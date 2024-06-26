// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity 0.8.21;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// internal
import { CollarEngine } from "./implementations/CollarEngine.sol";
import { BaseGovernedNFT } from "./base/BaseGovernedNFT.sol";
import { IProviderPositionNFT } from "./interfaces/IProviderPositionNFT.sol";

contract ProviderPositionNFT is IProviderPositionNFT, BaseGovernedNFT {
    using SafeERC20 for IERC20;

    uint internal constant BIPS_BASE = 10_000;
    uint public constant MIN_CALL_STRIKE_BIPS = BIPS_BASE; // 1x or 100%
    uint public constant MAX_CALL_STRIKE_BIPS = 10 * BIPS_BASE; // 10x or 1000%
    uint public constant MAX_PUT_STRIKE_BIPS = BIPS_BASE;

    string public constant VERSION = "0.1.0"; // allow checking version on-chain

    // ----- IMMUTABLES ----- //
    CollarEngine public immutable engine;
    IERC20 public immutable cashAsset;
    IERC20 public immutable collateralAsset;
    address public immutable borrowPositionContract;

    // ----- STATE ----- //
    uint public nextOfferId; // non transferrable, @dev this is NOT the NFT id
    mapping(uint positionId => ProviderPosition) internal positions;
    mapping(uint offerId => LiquidityOffer) internal liquidityOffers;

    constructor(
        address initialOwner,
        CollarEngine _engine,
        IERC20 _cashAsset,
        IERC20 _collateralAsset,
        address _borrowPositionContract,
        string memory _name,
        string memory _symbol
    )
        BaseGovernedNFT(initialOwner, _name, _symbol)
    {
        engine = _engine;
        cashAsset = _cashAsset;
        collateralAsset = _collateralAsset;
        borrowPositionContract = _borrowPositionContract;
        // check params are supported
        _validateAssetsSupported();
    }

    modifier onlyTrustedBorrowContract() {
        require(engine.isBorrowNFT(borrowPositionContract), "unsupported borrow contract");
        require(msg.sender == borrowPositionContract, "unauthorized borrow contract");
        _;
    }

    // ----- VIEWS ----- //

    function nextPositionId() external view returns (uint) {
        return nextTokenId;
    }

    // @dev return memory struct (the default getter returns tuple)
    function getPosition(uint positionId) external view returns (ProviderPosition memory) {
        return positions[positionId];
    }

    // @dev return memory struct (the default getter returns tuple)
    function getOffer(uint offerId) external view returns (LiquidityOffer memory) {
        return liquidityOffers[offerId];
    }

    // ----- MUTATIVE ----- //

    // ----- Liquidity actions ----- //

    function createOffer(
        uint callStrikeDeviation, // up to the provider
        uint amount, // up to the provider
        uint putStrikeDeviation, // validated vs. engine
        uint duration // validated vs. engine
    )
        external
        whenNotPaused
        returns (uint offerId)
    {
        _validateOfferParamsSupported(putStrikeDeviation, duration);
        require(callStrikeDeviation > MIN_CALL_STRIKE_BIPS, "strike deviation too low");
        require(callStrikeDeviation <= MAX_CALL_STRIKE_BIPS, "strike deviation too high");
        // TODO validate provider can receive NFTs (via the same check that's in _safeMint)
        offerId = nextOfferId++;
        liquidityOffers[offerId] = LiquidityOffer({
            provider: msg.sender,
            available: amount,
            putStrikeDeviation: putStrikeDeviation,
            callStrikeDeviation: callStrikeDeviation,
            duration: duration
        });
        cashAsset.safeTransferFrom(msg.sender, address(this), amount);
        emit OfferCreated(msg.sender, putStrikeDeviation, duration, callStrikeDeviation, amount, offerId);
    }

    function updateOfferAmount(uint offerId, uint newAmount) public whenNotPaused {
        require(msg.sender == liquidityOffers[offerId].provider, "not offer provider");
        uint previousAmount = liquidityOffers[offerId].available;

        if (newAmount > previousAmount) {
            // deposit more
            uint toAdd = newAmount - previousAmount;
            liquidityOffers[offerId].available += toAdd;
            cashAsset.safeTransferFrom(msg.sender, address(this), toAdd);
        } else if (newAmount < previousAmount) {
            // withdraw
            uint toRemove = previousAmount - newAmount;
            liquidityOffers[offerId].available -= toRemove;
            cashAsset.safeTransfer(msg.sender, toRemove);
        } else {
            // no change
        }
        emit OfferUpdated(offerId, msg.sender, previousAmount, newAmount);
    }

    // ----- Position actions ----- //

    // ----- actions through borrow NFT ----- //

    function mintPositionFromOffer(
        uint offerId,
        uint amount
    )
        external
        onlyTrustedBorrowContract
        whenNotPaused
        returns (uint positionId, ProviderPosition memory position)
    {
        LiquidityOffer storage offer = liquidityOffers[offerId];

        // check params are still supported
        _validateOfferParamsSupported(offer.putStrikeDeviation, offer.duration);

        // update liquidity
        require(amount <= offer.available, "amount too high");
        offer.available -= amount;

        // create position
        position = ProviderPosition({
            openedAt: block.timestamp,
            expiration: block.timestamp + offer.duration,
            principal: amount,
            putStrikeDeviation: offer.putStrikeDeviation,
            callStrikeDeviation: offer.callStrikeDeviation,
            settled: false,
            withdrawable: 0
        });

        positionId = nextTokenId++;
        // store position data
        positions[positionId] = position;
        // mint the NFT to the provider
        // @dev does not use _safeMint to avoid reentrancy
        _mint(offer.provider, positionId);

        emit OfferUpdated(offerId, msg.sender, offer.available + amount, offer.available);
        emit PositionCreated(
            positionId,
            position.putStrikeDeviation,
            offer.duration,
            position.callStrikeDeviation,
            amount,
            offerId
        );
    }

    function settlePosition(
        uint positionId,
        int positionChange
    )
        external
        onlyTrustedBorrowContract
        whenNotPaused
    {
        ProviderPosition storage position = positions[positionId];

        require(block.timestamp >= position.expiration, "not expired");
        require(!position.settled, "already settled");

        position.settled = true; // done here as this also acts as reentrancy protection

        uint withdrawable = position.principal;
        if (positionChange < 0) {
            uint toRemove = uint(-positionChange);
            /// @dev will revert if too much is requested
            require(toRemove <= withdrawable, "loss is too high");
            withdrawable -= toRemove;
            // we owe the borrower some tokens
            cashAsset.safeTransfer(borrowPositionContract, toRemove);
        } else if (positionChange > 0) {
            uint toAdd = uint(positionChange);
            withdrawable += toAdd;
            // the borrower owes us some tokens, requires approval
            cashAsset.safeTransferFrom(borrowPositionContract, address(this), toAdd);
        } else {
            // no change
        }

        // store the updated state
        position.withdrawable = withdrawable;

        emit PositionSettled(positionId, positionChange, withdrawable);
    }

    /// @dev for unwinds / rolls when the borrow contract is also the owner of this NFT
    /// callable through borrow position because only it is receiver of funds
    function cancelAndWithdraw(
        uint positionId,
        address recipient
    )
        external
        onlyTrustedBorrowContract
        whenNotPaused
    {
        require(msg.sender == ownerOf(positionId), "caller does not own token");

        ProviderPosition storage position = positions[positionId];

        require(!position.settled, "already settled");
        position.settled = true; // done here as this also acts as reentrancy protection

        // burn token
        _burn(positionId);

        cashAsset.safeTransfer(recipient, position.principal);

        emit PositionCanceled(positionId, recipient, position.principal, position.expiration);
    }

    // ----- actions by position owner ----- //

    function withdrawFromSettled(uint positionId, address recipient) external whenNotPaused {
        require(msg.sender == ownerOf(positionId), "not position owner");

        ProviderPosition storage position = positions[positionId];
        require(position.settled, "not settled");

        uint withdrawable = position.withdrawable;
        // zero out withdrawable
        position.withdrawable = 0;
        // burn token
        _burn(positionId);
        // transfer tokens
        cashAsset.safeTransfer(recipient, withdrawable);

        emit WithdrawalFromSettled(positionId, recipient, withdrawable);
    }

    // ----- INTERNAL MUTATIVE ----- //

    // ----- INTERNAL VIEWS ----- //

    function _validateAssetsSupported() internal view {
        require(engine.isSupportedCashAsset(address(cashAsset)), "unsupported asset");
        require(engine.isSupportedCollateralAsset(address(collateralAsset)), "unsupported asset");
    }

    function _validateOfferParamsSupported(uint putStrikeDeviation, uint duration) internal view {
        _validateAssetsSupported();
        require(putStrikeDeviation < MAX_PUT_STRIKE_BIPS, "invalid put strike deviation"); // check LTV is in
            // expected range
        uint ltv = putStrikeDeviation; // assumed to be always equal
        require(engine.isValidLTV(ltv), "unsupported LTV");
        require(engine.isValidCollarDuration(duration), "unsupported duration");
    }
}
