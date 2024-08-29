// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity 0.8.22;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
// internal
import { ConfigHub } from "./ConfigHub.sol";
import { BaseEmergencyAdminNFT } from "./base/BaseEmergencyAdminNFT.sol";
import { IShortProviderNFT } from "./interfaces/IShortProviderNFT.sol";

/**
 * @title ShortProviderNFT
 *
 * Main Functionality:
 * 1. Allows liquidity providers to create and manage offers for a specific Taker contract.
 * 2. Mints NFTs representing provider positions when offers are taken allowing a secondary market
 *    for unexpired positions, cancellations, and rolls.
 * 3. Handles settlement and cancellation of positions.
 * 4. Manages withdrawals of settled positions.
 *
 * Role in the Protocol:
 * This contract acts as the interface for liquidity providers in the Collar Protocol.
 * It works in tandem with a corresponding CollarTakerNFT contract, which is trusted by this contract
 * to manage the taker side of position, as well as calculating the positions' payouts.
 *
 * Key Assumptions and Prerequisites:
 * 1. Liquidity providers must be able to receive ERC-721 tokens and withdraw offers or earnings
 *    from this contract.
 * 2. The associated taker contract is trusted and properly implemented.
 * 3. The ConfigHub contract correctly manages protocol parameters and authorization.
 * 4. Put strike deviation is assumed to always equal the Loan-to-Value (LTV) ratio.
 * 5. Asset (ERC-20) contracts are simple (non rebasing) and do not allow reentrancy.
 *
 * Design Considerations:
 * 1. Uses NFTs to represent positions, allowing for the necessary secondary market for
 *    cancellations and rolls, and for usage with third-party marketplaces and contracts.
 * 2. Implements pausability and asset recovery for emergency situations via BaseEmergencyAdminNFT.
 *
 * Security Notes:
 * 1. Critical functions are only callable by the trusted taker contract.
 * 2. Offer and position parameters are validated against the configHub's configurations.
 */
contract ShortProviderNFT is IShortProviderNFT, BaseEmergencyAdminNFT {
    using SafeERC20 for IERC20;

    uint internal constant BIPS_BASE = 10_000;
    uint public constant MIN_CALL_STRIKE_BIPS = BIPS_BASE + 1; // 1x or 100%
    uint public constant MAX_CALL_STRIKE_BIPS = 10 * BIPS_BASE; // 10x or 1000%
    uint public constant MAX_PUT_STRIKE_BIPS = BIPS_BASE - 1;

    string public constant VERSION = "0.2.0";

    // ----- IMMUTABLES ----- //
    IERC20 public immutable cashAsset;
    IERC20 public immutable collateralAsset;
    // the trusted CollarTakerNFT contract. no interface is assumed because calls are only inbound
    address public immutable taker;

    // ----- STATE ----- //
    uint public nextOfferId; // @dev this is NOT the NFT id, this is separate ID
    // offerId is non transferrable
    mapping(uint offerId => LiquidityOffer) internal liquidityOffers;
    // positionId is the NFT token ID (tracked in BaseEmergencyAdminNFT)
    mapping(uint positionId => ProviderPosition) internal positions;

    constructor(
        address initialOwner,
        ConfigHub _configHub,
        IERC20 _cashAsset,
        IERC20 _collateralAsset,
        address _taker,
        string memory _name,
        string memory _symbol
    ) BaseEmergencyAdminNFT(initialOwner, _configHub, _name, _symbol) {
        cashAsset = _cashAsset;
        collateralAsset = _collateralAsset;
        taker = _taker;
    }

    modifier onlyTaker() {
        require(msg.sender == taker, "unauthorized taker contract");
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

    /// @notice Calculates the protocol fee charged from offers on position creation.
    /// @dev fee is set to 0 if recipient is zero because no transfer will be done
    function protocolFee(uint providerLocked, uint duration) public view returns (uint fee, address to) {
        to = configHub.feeRecipient();
        fee = to == address(0)
            ? 0
            // @dev rounds up to prevent avoiding fee using many small positions.
            : _divUp(providerLocked * configHub.protocolFeeAPR() * duration, BIPS_BASE * 365 days);
    }

    // ----- MUTATIVE ----- //

    // ----- Liquidity actions ----- //

    /// @notice Creates a new non transferrable liquidity offer of cash asset, for specific terms.
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
        uint putStrikeDeviation, // validated vs. configHub
        uint duration // validated vs. configHub
    ) external whenNotPaused returns (uint offerId) {
        // sanity checks
        require(callStrikeDeviation >= MIN_CALL_STRIKE_BIPS, "strike deviation too low");
        require(callStrikeDeviation <= MAX_CALL_STRIKE_BIPS, "strike deviation too high");
        require(putStrikeDeviation <= MAX_PUT_STRIKE_BIPS, "invalid put strike deviation");
        // config hub allows values
        _configHubValidations(putStrikeDeviation, duration);

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
    function updateOfferAmount(uint offerId, uint newAmount) external whenNotPaused {
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
        } else { } // no change
        emit OfferUpdated(offerId, msg.sender, previousAmount, newAmount);
    }

    // ----- Position actions ----- //

    // ----- actions through collar taker NFT ----- //

    /// @notice Mints a new position from an existing offer. Can ONLY be called through the
    /// taker contract, which is trusted to open and settle the offer according to the terms.
    /// Offer parameters are checked vs. the global config to ensure they are still supported.
    /// Protocol fee (based on the provider amount and duration) is deducted from offer, and sent
    /// to fee recipient. Offer amount is updated as well.
    /// The NFT representing ownership of the position, is minted to original provider of the offer.
    /// @param offerId The ID of the offer to mint from
    /// @param amount The amount of cash asset to use for the new position
    /// @param takerId The ID of the taker position for which this position is minted
    /// @return positionId The ID of the newly created position (NFT token ID)
    /// @return position The details of the newly created position
    function mintFromOffer(uint offerId, uint amount, uint takerId)
        external
        whenNotPaused
        onlyTaker
        returns (uint positionId, ProviderPosition memory position)
    {
        // @dev only checked on open, not checked later on settle / cancel to allow withdraw-only mode
        require(configHub.canOpen(msg.sender), "unsupported taker contract");
        require(configHub.canOpen(address(this)), "unsupported provider contract");

        LiquidityOffer storage offer = liquidityOffers[offerId];

        // check params are still supported
        _configHubValidations(offer.putStrikeDeviation, offer.duration);

        // calc protocol fee to subtract from offer (on top of amount)
        (uint fee, address feeRecipient) = protocolFee(amount, offer.duration);

        // check amount
        uint prevOfferAmount = offer.available;
        require(amount + fee <= prevOfferAmount, "amount too high");

        // storage updates
        offer.available = prevOfferAmount - amount - fee;
        positionId = nextTokenId++;
        position = ProviderPosition({
            takerId: takerId,
            expiration: block.timestamp + offer.duration,
            principal: amount,
            putStrikeDeviation: offer.putStrikeDeviation,
            callStrikeDeviation: offer.callStrikeDeviation,
            settled: false,
            withdrawable: 0
        });
        positions[positionId] = position;

        // emit creation before transfer. No need to emit takerId, because it's emitted by the taker event
        emit PositionCreated(
            positionId,
            position.putStrikeDeviation,
            offer.duration,
            position.callStrikeDeviation,
            amount,
            offerId,
            fee
        );
        // mint the NFT to the provider
        // @dev does not use _safeMint to avoid reentrancy
        _mint(offer.provider, positionId);

        // non-zero fee for zero-recipient is prevented in protocolFee() view and in ConfigHub setter
        if (feeRecipient != address(0)) {
            cashAsset.safeTransfer(feeRecipient, fee);
        }

        emit OfferUpdated(offerId, msg.sender, prevOfferAmount, offer.available);
    }

    /// @notice Settles an existing position. Can ONLY be called through the
    /// taker contract, which is trusted to open and settle the offer according to the terms.
    /// Cash assets are transferred between this contract and the taker contract according to the
    /// settlement logic. The assets earned by the position become withdrawable by the NFT owner.
    /// @dev note that settlement MUST NOT trigger a withdrawal to the provider. This is because
    /// this method is called via the taker contract and can be called by anyone.
    /// Allowing a third-party caller to trigger transfer of funds on behalf of the provider
    /// introduces several risks: 1) if the provider is a contract it may have its own bookkeeping,
    /// 2) if the NFT is traded on a NFT-market or in an escrow - that contract cannot handle
    /// settlement funds correctly 3) the provider may want to choose the timing or destination
    /// of the withdrawal themselves 4) In the NFT-market case, this can be used to front-run an order
    /// because it changes the underlying value of the NFT. Conversely, withdrawal (later) must burn the NFT
    /// to prevent the last issue.
    /// The funds that are transferred here are between the two contracts, and don't change the value
    /// of the NFT abruptly (only preventing settlement at future price).
    /// @param positionId The ID of the position to settle (NFT token ID)
    /// @param positionChange The change in position value (positive or negative)
    function settlePosition(uint positionId, int positionChange) external whenNotPaused onlyTaker {
        ProviderPosition storage position = positions[positionId];

        require(block.timestamp >= position.expiration, "not expired");
        require(!position.settled, "already settled");

        position.settled = true; // done here as this also acts as partial-reentrancy protection

        uint withdrawable = position.principal;
        if (positionChange < 0) {
            uint toRemove = uint(-positionChange); // will revert for type(int).min
            require(toRemove <= withdrawable, "loss is too high");
            withdrawable -= toRemove;
            // we owe the taker some tokens
            cashAsset.safeTransfer(taker, toRemove);
        } else if (positionChange > 0) {
            uint toAdd = uint(positionChange);
            withdrawable += toAdd;
            // the taker owes us some tokens, requires approval
            cashAsset.safeTransferFrom(taker, address(this), toAdd);
        } else { } // no change

        // store the updated state
        position.withdrawable = withdrawable;

        emit PositionSettled(positionId, positionChange, withdrawable);
    }

    /// @notice Cancels a position and withdraws the principal to a recipient. Burns the NFT.
    /// Can ONLY be called through the taker contract, which MUST be the owner of NFT
    /// when the call is made (so will have received it from the provider), and is trusted
    /// to cancel the other side of the position.
    /// @dev note that a withdrawal is triggerred (and the NFT is burned) because in contrast
    /// to settlement, during cancellation the caller MUST be the NFT owner (is the provider),
    /// so is assumed to specify the withdrawal correctly for their funds.
    /// @param positionId The ID of the position to cancel (NFT token ID)
    /// @param recipient The address to receive the withdrawn funds
    function cancelAndWithdraw(uint positionId, address recipient) external whenNotPaused onlyTaker {
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

    function _configHubValidations(uint putStrikeDeviation, uint duration) internal view {
        // assets
        require(configHub.isSupportedCashAsset(address(cashAsset)), "unsupported asset");
        require(configHub.isSupportedCollateralAsset(address(collateralAsset)), "unsupported asset");
        // terms
        uint ltv = putStrikeDeviation; // assumed to be always equal
        require(configHub.isValidLTV(ltv), "unsupported LTV");
        require(configHub.isValidCollarDuration(duration), "unsupported duration");
    }

    function _divUp(uint x, uint y) internal pure returns (uint) {
        return (x == 0) ? 0 : ((x - 1) / y) + 1; // divUp(x,y) = (x-1 / y) + 1
    }
}
