// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity 0.8.22;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// internal
import { CollarEngine } from "./implementations/CollarEngine.sol";
import { BaseGovernedNFT } from "./base/BaseGovernedNFT.sol";
import { IProviderPositionNFT } from "./interfaces/IProviderPositionNFT.sol";

/**
 * @title ProviderPositionNFT
 * @dev This contract manages liquidity provision for the Collar Protocol.
 *
 * Main Functionality:
 * 1. Allows liquidity providers to create and manage offers of cash assets.
 * 2. Mints NFTs representing provider positions when offers are taken allowing a secondary market
 *    for unexpired positions (for the benefit of full or partial cancellations, and term updates (rolls).
 * 3. Handles settlement and cancellation of positions.
 * 4. Manages withdrawals of settled positions.
 *
 * Role in the Protocol:
 * This contract acts as the interface for liquidity providers in the Collar Protocol.
 * It works in tandem with a corresponding CollarTakerNFT contract, which is trusted by this contract
 * to manage the borrower side of position, as well as calculating the positions' payouts.
 *
 * Key Assumptions and Prerequisites:
 * 1. Liquidity providers must be able to receive ERC-721 tokens and withdraw offers or earnings
 *    from this contract.
 * 2. The associated borrow contract is trusted and properly implemented.
 * 3. The CollarEngine contract correctly manages protocol parameters and authorization.
 * 4. Put strike deviation is assumed to always equal the Loan-to-Value (LTV) ratio.
 * 5. Asset (ERC-20) contracts are simple (non rebasing) and do not allow reentrancy.
 *
 * Design Considerations:
 * 1. Uses NFTs to represent positions, allowing for the necessary secondary market for
 *    cancellations and rolls using third-party marketplaces and contracts.
 * 2. Implements pausability for emergency situations.
 * 3. Separates offer creation and position minting to allow borrow contract to act as "taker".
 * 4. Implements basic reentrancy caution through state changes, but assets are assumed to be safe.
 *
 * Security Notes:
 * 1. Critical functions are only callable by the trusted borrow contract.
 * 2. Offer and position parameters are validated against the engine's configurations.
 * 3. Asset transfers use SafeERC20 to handle non-standard token implementations.
 */
contract ProviderPositionNFT is IProviderPositionNFT, BaseGovernedNFT {
    using SafeERC20 for IERC20;

    uint internal constant BIPS_BASE = 10_000;
    uint public constant MIN_CALL_STRIKE_BIPS = BIPS_BASE + 1; // 1x or 100%
    uint public constant MAX_CALL_STRIKE_BIPS = 10 * BIPS_BASE; // 10x or 1000%
    uint public constant MAX_PUT_STRIKE_BIPS = BIPS_BASE - 1;

    string public constant VERSION = "0.2.0"; // allow checking version on-chain

    // ----- IMMUTABLES ----- //
    CollarEngine public immutable engine;
    IERC20 public immutable cashAsset;
    IERC20 public immutable collateralAsset;
    address public immutable collarTakerContract;

    // ----- STATE ----- //
    uint public nextOfferId; // non transferrable, @dev this is NOT the NFT id
    mapping(uint positionId => ProviderPosition) internal positions;
    mapping(uint offerId => LiquidityOffer) internal liquidityOffers;

    constructor(
        address initialOwner,
        CollarEngine _engine,
        IERC20 _cashAsset,
        IERC20 _collateralAsset,
        address _collarTakerContract,
        string memory _name,
        string memory _symbol
    ) BaseGovernedNFT(initialOwner, _name, _symbol) {
        engine = _engine;
        cashAsset = _cashAsset;
        collateralAsset = _collateralAsset;
        collarTakerContract = _collarTakerContract;
        // check params are supported
        _validateAssetsSupported();
    }

    modifier onlyTrustedTakerContract() {
        require(engine.isCollarTakerNFT(collarTakerContract), "unsupported taker contract");
        require(msg.sender == collarTakerContract, "unauthorized taker contract");
        _;
    }

    // ----- VIEWS ----- //

    /// @notice Returns the ID of the next provider position to be minted
    function nextPositionId() external view returns (uint) {
        return nextTokenId;
    }

    /// @notice Retrieves the details of a specific position (corresponds to the NFT token ID)
    /// @dev This is used instead of the default getter because the default getter returns a tuple
    function getPosition(uint positionId) external view returns (ProviderPosition memory) {
        return positions[positionId];
    }

    /// @notice Retrieves the details of a specific non-transferrable offer.
    /// @dev This is used instead of the default getter because the default getter returns a tuple
    function getOffer(uint offerId) external view returns (LiquidityOffer memory) {
        return liquidityOffers[offerId];
    }

    // ----- MUTATIVE ----- //

    // ----- Liquidity actions ----- //

    /// @notice Creates a new non transferrable liquidity offer of cash asset, at specific parameters.
    /// The cash is held at the contract, but can be withdrawn at any time if unused.
    /// New positions that take the offer reduce the offer amount stored in the offer state.
    /// The caller MUST be able to handle ERC-721 and interact with this contract later.
    /// @param callStrikeDeviation The call strike deviation in basis points
    /// @param amount The amount of cash asset to offer
    /// @param putStrikeDeviation The put strike deviation in basis points
    /// @param duration The duration of the offer in seconds
    /// @return offerId The ID of the newly created offer
    function createOffer(
        uint callStrikeDeviation, // up to the provider
        uint amount, // up to the provider
        uint putStrikeDeviation, // validated vs. engine
        uint duration // validated vs. engine
    ) external whenNotPaused returns (uint offerId) {
        _validateOfferParamsSupported(putStrikeDeviation, duration);
        require(callStrikeDeviation > MIN_CALL_STRIKE_BIPS, "strike deviation too low");
        require(callStrikeDeviation <= MAX_CALL_STRIKE_BIPS, "strike deviation too high");
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

    /// @notice Updates the amount of an existing liquidity offer by either transferring from the offer
    /// owner into the contract (when the new amount is higher), or transferring to the owner from the
    /// contract when the new amount is lower. Only available to the original owner of the offer.
    /// @dev An offer is never deleted, so can always be reused if more cash is deposited into it.
    /// @param offerId The ID of the offer to update
    /// @param newAmount The new amount of cash asset for the offer
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

    // ----- actions through collar taker NFT ----- //

    /// @notice Mints a new position from an existing offer. Can ONLY be called through the
    /// borrowing contract, which is trusted to open and settle the offer according to the terms.
    /// Offer parameters are checked vs. the global config to ensure they are still supported.
    /// Offer amount is updated as well.
    /// The ERC-721 NFT token, representing ownership of the position, is minted to original
    /// provider of the offer.
    /// @param offerId The ID of the offer to mint from
    /// @param amount The amount of cash asset to use for the new position
    /// @return positionId The ID of the newly created position (NFT token ID)
    /// @return position The details of the newly created position
    function mintPositionFromOffer(uint offerId, uint amount)
        external
        whenNotPaused
        onlyTrustedTakerContract
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
        // emit creation before transfer
        emit PositionCreated(
            positionId,
            position.putStrikeDeviation,
            offer.duration,
            position.callStrikeDeviation,
            amount,
            offerId
        );
        // mint the NFT to the provider
        // @dev does not use _safeMint to avoid reentrancy
        _mint(offer.provider, positionId);

        emit OfferUpdated(offerId, msg.sender, offer.available + amount, offer.available);
    }

    /// @notice Settles an existing position. Can ONLY be called through the
    /// borrowing contract, which is trusted to open and settle the offer according to the terms.
    /// Cash assets are transferred between this contract and the borrowing according to the
    /// settlement logic. The assets earned by the position become withdrawable by the NFT owner.
    /// @dev note that settlement MUST NOT trigger a withdrawal to the provider. This is because
    /// this method is called via the borrowing contract (for example by the borrower).
    /// Allowing the a third-party caller to trigger transfer of funds on behalf of the provider
    /// introduces several risks: 1) if the provider is a contract it may have its own bookkeeping,
    /// 2) if the NFT is deposited in a NFT-market or an escrow - that contract cannot handle
    /// settlement funds correctly 3) the provider may want to choose the timing or destination
    /// of the withdrawal themselves
    /// @param positionId The ID of the position to settle (NFT token ID)
    /// @param positionChange The change in position value (positive or negative)
    function settlePosition(uint positionId, int positionChange)
        external
        whenNotPaused
        onlyTrustedTakerContract
    {
        ProviderPosition storage position = positions[positionId];

        require(block.timestamp >= position.expiration, "not expired");
        require(!position.settled, "already settled");

        position.settled = true; // done here as this also acts as reentrancy protection

        uint withdrawable = position.principal;
        if (positionChange < 0) {
            uint toRemove = uint(-positionChange);
            require(toRemove <= withdrawable, "loss is too high");
            withdrawable -= toRemove;
            // we owe the taker some tokens
            cashAsset.safeTransfer(collarTakerContract, toRemove);
        } else if (positionChange > 0) {
            uint toAdd = uint(positionChange);
            withdrawable += toAdd;
            // the taker owes us some tokens, requires approval
            cashAsset.safeTransferFrom(collarTakerContract, address(this), toAdd);
        } else {
            // no change
        }

        // store the updated state
        position.withdrawable = withdrawable;

        emit PositionSettled(positionId, positionChange, withdrawable);
    }

    /// @notice Cancels a position and withdraws the principal to a recipient. Burns the NFT.
    /// Can ONLY be called through the borrowing contract, which MUST be the owner of NFT
    /// when the call is made (so will have received it from the provider), and is trusted
    /// to cancel the other side of the position.
    /// @dev note that a withdrawal is triggerred (and the NFT is burned) because in contrast
    /// to settlement, during cancellation the caller MUST be the NFT owner (is the provider),
    /// so is assumed to specify the withdrawal correctly for their funds.
    /// @param positionId The ID of the position to cancel (NFT token ID)
    /// @param recipient The address to receive the withdrawn funds
    function cancelAndWithdraw(uint positionId, address recipient)
        external
        whenNotPaused
        onlyTrustedTakerContract
    {
        require(msg.sender == ownerOf(positionId), "caller does not own token");

        ProviderPosition storage position = positions[positionId];

        require(!position.settled, "already settled");
        position.settled = true; // done here as this also acts as reentrancy protection

        uint withdrawal = position.principal;

        // burn token
        _burn(positionId);

        cashAsset.safeTransfer(recipient, withdrawal);

        emit PositionCanceled(positionId, recipient, withdrawal, position.expiration);
    }

    // ----- actions by position owner ----- //

    /// @notice Withdraws funds from a settled position. Can only be called for a settled position
    /// (and not a cancelled one), and checks the ownernship of the NFT. Burns the NFT.
    /// @param positionId The ID of the settled position to withdraw from (NFT token ID).
    /// @param recipient The address to receive the withdrawn funds
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
        require(putStrikeDeviation <= MAX_PUT_STRIKE_BIPS, "invalid put strike deviation");
        uint ltv = putStrikeDeviation; // assumed to be always equal
        require(engine.isValidLTV(ltv), "unsupported LTV");
        require(engine.isValidCollarDuration(duration), "unsupported duration");
    }
}
