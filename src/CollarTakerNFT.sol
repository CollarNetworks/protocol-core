// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity 0.8.22;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
// internal imports
import { ProviderPositionNFT } from "./ProviderPositionNFT.sol";
import { BaseGovernedNFT } from "./base/BaseGovernedNFT.sol";
import { CollarEngine } from "./implementations/CollarEngine.sol";
import { ICollarTakerNFT } from "./interfaces/ICollarTakerNFT.sol";

contract CollarTakerNFT is ICollarTakerNFT, BaseGovernedNFT {
    using SafeERC20 for IERC20;
    using SafeCast for uint;

    uint internal constant BIPS_BASE = 10_000;

    uint32 public constant TWAP_LENGTH = 15 minutes;

    string public constant VERSION = "0.2.0"; // allow checking version on-chain

    // ----- IMMUTABLES ----- //
    CollarEngine public immutable engine;
    IERC20 public immutable cashAsset;
    IERC20 public immutable collateralAsset;

    // ----- STATE VARIABLES ----- //
    mapping(uint positionId => TakerPosition) internal positions;

    constructor(
        address initialOwner,
        CollarEngine _engine,
        IERC20 _cashAsset,
        IERC20 _collateralAsset,
        string memory _name,
        string memory _symbol
    ) BaseGovernedNFT(initialOwner, _name, _symbol) {
        engine = _engine;
        cashAsset = _cashAsset;
        collateralAsset = _collateralAsset;
        // check params are supported
        _validateAssetsSupported();
    }

    // ----- VIEW FUNCTIONS ----- //
    // @dev return memory struct (the default getter returns tuple)
    function getPosition(uint takerId) external view returns (TakerPosition memory) {
        return positions[takerId];
    }

    function nextPositionId() external view returns (uint) {
        return nextTokenId;
    }

    // ----- STATE CHANGING FUNCTIONS ----- //

    function openPairedPosition(
        uint putLockedCash, // user portion of collar position
        ProviderPositionNFT providerNFT,
        uint offerId // @dev implies specific provider, put & call deviations, duration
    )
        external
        whenNotPaused
        returns (uint takerId, uint providerId)
    {
        _openPositionValidations(providerNFT);

        // pull the user side of the locked cash
        cashAsset.safeTransferFrom(msg.sender, address(this), putLockedCash);

        // get TWAP price
        uint twapPrice = _getTWAPPrice(block.timestamp);

        // stores, mints, calls providerNFT and mints there, emits the event
        (takerId, providerId) = _openPairedPositionInternal(twapPrice, putLockedCash, providerNFT, offerId);
    }

    function settlePairedPosition(uint takerId) external whenNotPaused {
        TakerPosition storage position = positions[takerId];
        ProviderPositionNFT providerNFT = position.providerNFT;
        uint providerId = position.providerPositionId;

        require(position.openedAt != 0, "position doesn't exist");
        // access is restricted because NFT owners might want to cancel (unwind) instead
        require(
            msg.sender == ownerOf(takerId) || msg.sender == providerNFT.ownerOf(providerId),
            "not owner of either position"
        );
        require(block.timestamp >= position.expiration, "not expired");
        require(!position.settled, "already settled");

        position.settled = true; // set here to prevent reentrancy

        // get settlement price
        uint endPrice = _getTWAPPrice(position.expiration);

        (uint withdrawable, int providerChange) = _settlementCalculations(position, endPrice);

        _settleProviderPosition(position, providerChange);

        // set withdrawable for user
        position.withdrawable = withdrawable;

        emit PairedPositionSettled(
            takerId, address(providerNFT), providerId, endPrice, withdrawable, providerChange
        );
    }

    function withdrawFromSettled(uint takerId, address recipient) external whenNotPaused {
        require(msg.sender == ownerOf(takerId), "not position owner");

        TakerPosition storage position = positions[takerId];
        require(position.settled, "not settled");

        uint withdrawable = position.withdrawable;
        // zero out withdrawable
        position.withdrawable = 0;
        // burn token
        _burn(takerId);
        // transfer tokens
        cashAsset.safeTransfer(recipient, withdrawable);

        emit WithdrawalFromSettled(takerId, recipient, withdrawable);
    }

    function cancelPairedPosition(uint takerId, address recipient) external whenNotPaused {
        TakerPosition storage position = positions[takerId];
        ProviderPositionNFT providerNFT = position.providerNFT;
        uint providerId = position.providerPositionId;

        require(msg.sender == ownerOf(takerId), "not owner of taker ID");
        // this is redundant due to NFT transfer from msg.sender later, but is clearer.
        require(msg.sender == providerNFT.ownerOf(providerId), "not owner of provider ID");

        require(!position.settled, "already settled");
        position.settled = true; // set here to prevent reentrancy

        // burn token
        _burn(takerId);

        // pull the provider NFT to this contract
        providerNFT.transferFrom(msg.sender, address(this), providerId);

        // now that this contract has the provider NFT - cancel it and withdraw funds to sender
        providerNFT.cancelAndWithdraw(providerId, recipient);

        // transfer the tokens locked in this contract
        cashAsset.safeTransfer(recipient, position.putLockedCash);

        emit PairedPositionCanceled(
            takerId, address(providerNFT), providerId, recipient, position.putLockedCash, position.expiration
        );
    }

    // ----- INTERNAL MUTATIVE ----- //

    function _openPairedPositionInternal(
        uint twapPrice,
        uint putLockedCash,
        ProviderPositionNFT providerNFT,
        uint offerId
    )
        internal
        returns (uint takerId, uint providerId)
    {
        uint callLockedCash = _calculateProviderLocked(putLockedCash, providerNFT, offerId);

        // open the provider position with duration and callLockedCash locked liquidity (reverts if can't)
        // and sends the provider NFT to the provider
        ProviderPositionNFT.ProviderPosition memory providerPosition;
        (providerId, providerPosition) = providerNFT.mintPositionFromOffer(offerId, callLockedCash);

        // put and call deviations are assumed to be identical for offer and resulting position
        uint putStrikePrice = twapPrice * providerPosition.putStrikeDeviation / BIPS_BASE;
        uint callStrikePrice = twapPrice * providerPosition.callStrikeDeviation / BIPS_BASE;
        // avoid boolean edge cases and division by zero when settling
        require(putStrikePrice < twapPrice && callStrikePrice > twapPrice, "strike prices aren't different");

        TakerPosition memory takerPosition = TakerPosition({
            providerNFT: providerNFT,
            providerPositionId: providerId,
            openedAt: block.timestamp,
            expiration: providerPosition.expiration,
            initialPrice: twapPrice,
            putStrikePrice: putStrikePrice,
            callStrikePrice: callStrikePrice,
            putLockedCash: putLockedCash,
            callLockedCash: callLockedCash,
            // unset until settlement
            settled: false,
            withdrawable: 0
        });

        // increment ID
        takerId = nextTokenId++;
        // store position data
        positions[takerId] = takerPosition;
        // mint the NFT to the sender
        // @dev does not use _safeMint to avoid reentrancy
        _mint(msg.sender, takerId);

        emit PairedPositionOpened(takerId, address(providerNFT), providerId, offerId, takerPosition);
    }

    function _settleProviderPosition(TakerPosition storage position, int providerChange) internal {
        if (providerChange > 0) {
            cashAsset.forceApprove(address(position.providerNFT), uint(providerChange));
        }

        position.providerNFT.settlePosition(position.providerPositionId, providerChange);
    }

    // ----- INTERNAL VIEWS ----- //

    function _validateAssetsSupported() internal view {
        require(engine.isSupportedCashAsset(address(cashAsset)), "unsupported asset");
        require(engine.isSupportedCollateralAsset(address(collateralAsset)), "unsupported asset");
    }

    function _openPositionValidations(ProviderPositionNFT providerNFT) internal view {
        _validateAssetsSupported();

        // check self (provider will check too)
        require(engine.isCollarTakerNFT(address(this)), "unsupported taker contract");

        // check provider
        require(engine.isProviderNFT(address(providerNFT)), "unsupported provider contract");
        // check assets match
        require(providerNFT.collateralAsset() == collateralAsset, "asset mismatch");
        require(providerNFT.cashAsset() == cashAsset, "asset mismatch");

        // checking LTV and duration (from provider offer) is redundant since provider offer
        // is trusted by user (passed in input), and trusted by engine (was checked vs. engine above)
    }

    function _getTWAPPrice(uint twapEndTime) internal view returns (uint price) {
        return engine.getHistoricalAssetPriceViaTWAP(
            address(collateralAsset), address(cashAsset), uint32(twapEndTime), TWAP_LENGTH
        );
    }

    // calculations

    function _calculateProviderLocked(
        uint putLockedCash,
        ProviderPositionNFT providerNFT,
        uint offerId
    )
        internal
        view
        returns (uint)
    {
        ProviderPositionNFT.LiquidityOffer memory offer = providerNFT.getOffer(offerId);
        uint putRange = BIPS_BASE - offer.putStrikeDeviation;
        uint callRange = offer.callStrikeDeviation - BIPS_BASE;
        require(putRange != 0, "invalid put strike deviation"); // avoid division by zero
        return callRange * putLockedCash / putRange; // proportionally scaled according to ranges
    }

    function _settlementCalculations(
        TakerPosition storage position,
        uint endPrice
    )
        internal
        view
        returns (uint withdrawable, int providerChange)
    {
        uint startPrice = position.initialPrice;
        uint putPrice = position.putStrikePrice;
        uint callPrice = position.callStrikePrice;

        // restrict endPrice to put-call range
        endPrice = endPrice < putPrice ? putPrice : endPrice;
        endPrice = endPrice > callPrice ? callPrice : endPrice;

        withdrawable = position.putLockedCash;
        if (endPrice < startPrice) {
            // put range: divide between user and LP, call range: goes to LP
            uint lpPart = startPrice - endPrice;
            uint putRange = startPrice - putPrice;
            uint lpGain = position.putLockedCash * lpPart / putRange; // no div-zero ensured on open
            withdrawable -= lpGain;
            providerChange = lpGain.toInt256();
        } else {
            // put range: goes to user, call range: divide between user and LP
            uint userPart = endPrice - startPrice;
            uint callRange = callPrice - startPrice;
            uint userGain = position.callLockedCash * userPart / callRange; // no div-zero ensured on open
            withdrawable += userGain;
            providerChange = -userGain.toInt256();
        }
    }
}
