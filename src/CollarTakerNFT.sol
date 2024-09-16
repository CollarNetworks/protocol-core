// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity 0.8.22;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
// internal
import { ConfigHub, BaseNFT, ShortProviderNFT } from "./ShortProviderNFT.sol";
import { OracleUniV3TWAP } from "./OracleUniV3TWAP.sol";
import { ICollarTakerNFT } from "./interfaces/ICollarTakerNFT.sol";

contract CollarTakerNFT is ICollarTakerNFT, BaseNFT {
    using SafeERC20 for IERC20;
    using SafeCast for uint;

    uint internal constant BIPS_BASE = 10_000;

    string public constant VERSION = "0.2.0";

    // ----- IMMUTABLES ----- //
    IERC20 public immutable cashAsset;
    IERC20 public immutable collateralAsset;

    // ----- STATE VARIABLES ----- //
    OracleUniV3TWAP public oracle;
    mapping(uint positionId => TakerPosition) internal positions;

    constructor(
        address initialOwner,
        ConfigHub _configHub,
        IERC20 _cashAsset,
        IERC20 _collateralAsset,
        OracleUniV3TWAP _oracle,
        string memory _name,
        string memory _symbol
    ) BaseNFT(initialOwner, _name, _symbol) {
        cashAsset = _cashAsset;
        collateralAsset = _collateralAsset;
        _setConfigHub(_configHub);
        _setOracle(_oracle);
        emit CollarTakerNFTCreated(address(_cashAsset), address(_collateralAsset), address(_oracle));
    }

    // ----- VIEW FUNCTIONS ----- //

    /// @notice Returns the ID of the next taker position to be minted
    function nextPositionId() external view returns (uint) {
        return nextTokenId;
    }

    /// @notice Retrieves the details of a specific position (corresponds to the NFT token ID)
    /// @dev This is used instead of the default getter because the default getter returns a tuple
    function getPosition(uint takerId) external view returns (TakerPosition memory) {
        return positions[takerId];
    }

    /// @dev calculate the amount of cash the provider will lock for specific terms and taker
    /// locked amount
    function calculateProviderLocked(uint putLockedCash, uint putStrikeDeviation, uint callStrikeDeviation)
        public
        pure
        returns (uint)
    {
        uint putRange = BIPS_BASE - putStrikeDeviation;
        uint callRange = callStrikeDeviation - BIPS_BASE;
        require(putRange != 0, "invalid put strike deviation"); // avoid division by zero
        return callRange * putLockedCash / putRange; // proportionally scaled according to ranges
    }

    /// @dev TWAP price that's used in this contract for opening positions
    function currentOraclePrice() public view returns (uint price) {
        return oracle.currentPrice();
    }

    /// @dev preview the settlement calculation updates at a particular price
    /// @dev no validation, so may revert with division by zero for bad values
    function previewSettlement(uint takerId, uint endPrice)
        external
        view
        returns (uint takerBalance, int providerChange)
    {
        return _settlementCalculations(positions[takerId], endPrice);
    }

    // ----- STATE CHANGING FUNCTIONS ----- //

    function openPairedPosition(
        uint putLockedCash, // user portion of collar position
        ShortProviderNFT providerNFT,
        uint offerId // @dev implies specific provider, put & call deviations, duration
    ) external whenNotPaused returns (uint takerId, uint providerId) {
        // check assets allowed
        require(configHub.isSupportedCashAsset(address(cashAsset)), "unsupported asset");
        require(configHub.isSupportedCollateralAsset(address(collateralAsset)), "unsupported asset");
        // check self allowed
        require(configHub.canOpen(address(this)), "unsupported taker contract");
        // check provider allowed
        require(configHub.canOpen(address(providerNFT)), "unsupported provider contract");
        // check assets match
        require(providerNFT.collateralAsset() == collateralAsset, "asset mismatch");
        require(providerNFT.cashAsset() == cashAsset, "asset mismatch");

        // pull the user side of the locked cash
        cashAsset.safeTransferFrom(msg.sender, address(this), putLockedCash);

        // get TWAP price
        uint twapPrice = currentOraclePrice();

        // stores, mints, calls providerNFT and mints there, emits the event
        (takerId, providerId) = _openPairedPositionInternal(twapPrice, putLockedCash, providerNFT, offerId);
    }

    /// @dev this should be called as soon after expiry as possible, because if the expiry TWAP price becomes
    /// unavailable in the UniV3 oracle, the current price will be used instead of it.
    /// Both taker and providder should be incentivised to call this method, however it's possible that
    /// one side is not (e.g., due to being at max loss). For this reason a keeper should be run to
    /// prevent regular users with gains from neglecting to settle their positions on time.
    /// @dev To increase the timespan during which the price is available use
    /// `increaseCardinality` (or the pool's `increaseObservationCardinalityNext`).
    function settlePairedPosition(uint takerId) external whenNotPaused {
        TakerPosition storage position = positions[takerId];
        ShortProviderNFT providerNFT = position.providerNFT;
        uint providerId = position.providerPositionId;

        require(position.expiration != 0, "position doesn't exist");
        require(block.timestamp >= position.expiration, "not expired");
        require(!position.settled, "already settled");

        position.settled = true; // set here to prevent reentrancy

        // get settlement price. casting is safe since expiration was checked
        (uint endPrice, bool historical) = oracle.pastPriceWithFallback(uint32(position.expiration));

        (uint withdrawable, int providerChange) = _settlementCalculations(position, endPrice);

        _settleProviderPosition(position, providerChange);

        // set withdrawable for user
        position.withdrawable = withdrawable;

        emit PairedPositionSettled(
            takerId, address(providerNFT), providerId, endPrice, historical, withdrawable, providerChange
        );
    }

    function withdrawFromSettled(uint takerId, address recipient)
        external
        whenNotPaused
        returns (uint amount)
    {
        require(msg.sender == ownerOf(takerId), "not position owner");

        TakerPosition storage position = positions[takerId];
        require(position.settled, "not settled");

        amount = position.withdrawable;
        // zero out withdrawable
        position.withdrawable = 0;
        // burn token
        _burn(takerId);
        // transfer tokens
        cashAsset.safeTransfer(recipient, amount);

        emit WithdrawalFromSettled(takerId, recipient, amount);
    }

    function cancelPairedPosition(uint takerId, address recipient) external whenNotPaused {
        TakerPosition storage position = positions[takerId];
        ShortProviderNFT providerNFT = position.providerNFT;
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

    // ----- Owner Mutative ----- //

    function setOracle(OracleUniV3TWAP _oracleUniV3) external onlyOwner {
        _setOracle(_oracleUniV3);
    }

    // ----- INTERNAL MUTATIVE ----- //

    function _openPairedPositionInternal(
        uint twapPrice,
        uint putLockedCash,
        ShortProviderNFT providerNFT,
        uint offerId
    ) internal returns (uint takerId, uint providerId) {
        ShortProviderNFT.LiquidityOffer memory offer = providerNFT.getOffer(offerId);
        uint callLockedCash = _calculateProviderLocked(putLockedCash, offer);

        // open the provider position with duration and callLockedCash locked liquidity (reverts if can't)
        // and sends the provider NFT to the provider
        ShortProviderNFT.ProviderPosition memory providerPosition;
        (providerId, providerPosition) = providerNFT.mintFromOffer(offerId, callLockedCash, nextTokenId);
        uint putStrikePrice = twapPrice * providerPosition.putStrikeDeviation / BIPS_BASE;
        uint callStrikePrice = twapPrice * providerPosition.callStrikeDeviation / BIPS_BASE;
        // avoid boolean edge cases and division by zero when settling
        require(putStrikePrice < twapPrice && callStrikePrice > twapPrice, "strike prices aren't different");

        TakerPosition memory takerPosition = TakerPosition({
            providerNFT: providerNFT,
            providerPositionId: providerId,
            duration: offer.duration,
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

        // ensure taker ID is as expected (no reentrancy between nextTokenId use and incrementing)
        require(providerPosition.takerId == nextTokenId, "unexpected takerId");
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

    // internal owner

    function _setOracle(OracleUniV3TWAP _oracle) internal {
        require(_oracle.baseToken() == address(collateralAsset), "oracle asset mismatch");
        require(_oracle.quoteToken() == address(cashAsset), "oracle asset mismatch");
        // Ensure doesn't revert and returns a price at least right now.
        // Only a sanity check, since this doesn't ensure that it will work in the future,
        // since the observations buffer can be filled such that the required time window is not available.
        // @dev this means this contract can be temporarily DoSed unless the cardinality is set
        // to at least twap-window. For 5 minutes TWAP on Arbitrum this is 300 (obs. are set by timestamps)
        require(_oracle.currentPrice() != 0, "invalid price");
        emit OracleSet(oracle, _oracle); // emit before for the prev value
        oracle = _oracle;
    }

    // ----- INTERNAL VIEWS ----- //

    // calculations

    function _calculateProviderLocked(uint putLockedCash, ShortProviderNFT.LiquidityOffer memory offer)
        internal
        pure
        returns (uint)
    {
        require(offer.provider != address(0), "invalid offer");
        return calculateProviderLocked(putLockedCash, offer.putStrikeDeviation, offer.callStrikeDeviation);
    }

    function _settlementCalculations(TakerPosition memory position, uint endPrice)
        internal
        pure
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
