// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity 0.8.22;

import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { SignedMath } from "@openzeppelin/contracts/utils/math/SignedMath.sol";

import { CollarTakerNFT, ShortProviderNFT } from "./CollarTakerNFT.sol";
import { BaseEmergencyAdmin } from "./base/BaseEmergencyAdmin.sol";
import { IRolls } from "./interfaces/IRolls.sol";

/**
 * @title Rolls
 * @dev This contract manages the "rolling" of existing collar positions before expiry to new strikes and
 * expiry.
 *
 * Main Functionality:
 * 1. Allows providers to create roll offers for existing positions.
 * 2. Handles the cancellation of created roll offers.
 * 3. Executes rolls, cancelling (settling) existing positions and creating new ones with updated terms.
 * 4. Manages the transfer of funds between takers and providers during rolls.
 *
 * Role in the Protocol:
 * Allows for the extension or modification of existing positions prior to expiry if both parties agree.
 *
 * Key Assumptions and Prerequisites:
 * 1. The CollarTakerNFT and ShortProviderNFT contracts are correctly implemented and authorized.
 * 2. The cash asset (ERC-20) used is standard compliant (non-rebasing, no transfer fees, no callbacks).
 * 3. Providers must approve this contract to transfer their ShortProviderNFTs and cash when creating
 * an offer. The NFT is transferred on offer creation, and cash will be transferred on execution, if
 * and when the user accepts the offer.
 * 4. Takers must approve this contract to transfer their CollarTakerNFTs and any cash that's needed
 * to be pulled.
 *
 * Design Considerations:
 * 1. Offers are made by providers, and accepted (and executed) by takers.
 * 2. Implements pausability for emergency situations.
 * 3. Calculates fees based on price changes to allow correct fee pricing when asset price moves.
 * 4. Settles existing positions and creates new ones atomically to ensure consistency.
 *
 * Security Considerations:
 * 1. Does not hold cash (only during execution), but will have approvals to spend cash.
 * 2. Signed integers are used for many input and output values, and proper care should be
 * taken in understanding the semantics of the positive and negative values.
 */
contract Rolls is IRolls, BaseEmergencyAdmin {
    using SafeERC20 for IERC20;
    using SafeCast for uint;

    uint internal constant BIPS_BASE = 10_000;

    string public constant VERSION = "0.2.0";

    // ----- IMMUTABLES ----- //
    CollarTakerNFT public immutable takerNFT;
    IERC20 public immutable cashAsset;

    // ----- STATE VARIABLES ----- //

    uint public nextRollId = 1; // starts from 1 so that 0 ID is not used

    mapping(uint rollId => RollOffer) internal rollOffers;

    /// @dev Rolls needs BaseEmergencyAdmin for pausing since is approved by users, and holds NFTs.
    /// Does not need `canOpen` auth because its auth usage is set directly on Loans,
    /// and it has no long-lived functionality so doesn't need a close-only migration mode.
    constructor(address initialOwner, CollarTakerNFT _takerNFT) BaseEmergencyAdmin(initialOwner) {
        takerNFT = _takerNFT;
        cashAsset = _takerNFT.cashAsset();
        _setConfigHub(_takerNFT.configHub());
    }

    // ----- VIEW FUNCTIONS ----- //

    /// @dev return memory struct (the default getter returns tuple)
    function getRollOffer(uint rollId) external view returns (RollOffer memory) {
        return rollOffers[rollId];
    }

    /**
     * @notice Calculates the roll fee based on the price
     * @dev The fee changes based on the price change since the offer was created.
     * All three of - price change, roll fee, and delta-factor - can be negative. The fee is adjusted
     * such that positive `price-change x delta-factor` increase the fee (provider benefits), and decrease
     * the fee (taker benefits) if negative.
     * 0 delta-factor means the fee is constant, 100% delta-factor (10_000 in bips), means the price
     * linearly scales the fee (according to the sign logic)
     * @param offer The roll offer to calculate the fee for
     * @param currentPrice The current price to use for the calculation
     * @return rollFee The calculated roll fee (in cash amount)
     */
    function calculateRollFee(RollOffer memory offer, uint currentPrice) public pure returns (int rollFee) {
        int prevPrice = offer.rollFeeReferencePrice.toInt256();
        int priceChange = currentPrice.toInt256() - prevPrice;
        // Scaling the fee magnitude by the delta (price change) multiplied by the factor.
        // For deltaFactor of 100%, this results in linear scaling of the fee with price.
        // If factor is BIPS_BASE the amount moves with the price. E.g., 5% price increase, 5% fee increase.
        // If factor is, e.g., 50% the fee increases only 2.5% for a 5% price increase.
        int feeSize = SignedMath.abs(offer.rollFeeAmount).toInt256();
        int change = feeSize * offer.rollFeeDeltaFactorBIPS * priceChange / prevPrice / int(BIPS_BASE);
        // Apply the change depending on the sign of the delta * price-change.
        // Positive factor means provider gets more money with higher price.
        // Negative factor means user gets more money with higher price.
        // E.g., if the fee is -5, the sign of the factor specifies whether provider gains (+5% -> -4.75)
        // or user gains (+5% -> -5.25) with price increase.
        rollFee = offer.rollFeeAmount + change;
    }

    /**
     * @notice Calculates the amounts to be transferred during a roll execution at a specific price.
     * This does not check any of the execution validity conditions (deadline, price range, etc...).
     * @dev If validity is important, a staticcall to the executeRoll method should be used instead of
     * this view.
     * @param rollId The ID of the roll offer
     * @param price The price to use for the calculation
     * @return toTaker The amount that would be transferred to (or from, if negative) the taker
     * @return toProvider The amount that would be transferred to (or from, if negative) the provider
     * @return rollFee The roll fee that would be applied
     */
    function calculateTransferAmounts(uint rollId, uint price)
        external
        view
        returns (int toTaker, int toProvider, int rollFee)
    {
        RollOffer memory offer = rollOffers[rollId];
        CollarTakerNFT.TakerPosition memory takerPos = takerNFT.getPosition(offer.takerId);
        rollFee = calculateRollFee(offer, price);
        (toTaker, toProvider) = _calculateTransferAmounts({
            newPrice: price,
            rollFeeAmount: rollFee,
            takerId: offer.takerId,
            providerPos: takerPos.providerNFT.getPosition(takerPos.providerId)
        });
    }

    // ----- MUTATIVE FUNCTIONS ----- //

    /**
     * @notice Creates a new roll offer for an existing taker NFT position and pulls the provider NFT.
     * @dev The provider must own the ShortProviderNFT for the position to be rolled
     * @param takerId The ID of the CollarTakerNFT position to be rolled
     * @param rollFeeAmount The base fee for the roll, can be positive (paid by taker) or
     *     negative (paid by provider)
     * @param rollFeeDeltaFactorBIPS How much the fee changes with price, in basis points, can be
     *     negative. Positive means asset price increase benefits provider, and negative benefits user.
     * @param minPrice The minimum acceptable price for roll execution
     * @param maxPrice The maximum acceptable price for roll execution
     * @param minToProvider The minimum amount the provider is willing to receive, or maximum willing to pay
     *     if negative. The execution transfer (in or out) will be checked to be >= this value.
     * @param deadline The timestamp after which this offer can no longer be executed
     * @return rollId The ID of the newly created roll offer
     *
     * @dev if the provider will need to provide cash on execution, they must approve the contract to pull that
     * cash when submitting the offer (and have those funds available), so that it is executable.
     * If offer becomes unexecutable due to insufficient provider cash approval or balance it should ideally be
     * filtered out by the FE as not executable (and provider be made aware).
     */
    function createRollOffer(
        uint takerId,
        int rollFeeAmount,
        int rollFeeDeltaFactorBIPS,
        // provider protection
        uint minPrice,
        uint maxPrice,
        int minToProvider,
        uint deadline
    ) external whenNotPaused returns (uint rollId) {
        // taker position is valid
        CollarTakerNFT.TakerPosition memory takerPos = takerNFT.getPosition(takerId);
        require(takerPos.expiration != 0, "taker position doesn't exist");
        require(!takerPos.settled, "taker position settled");
        require(block.timestamp <= takerPos.expiration, "taker position expired");

        ShortProviderNFT providerNFT = takerPos.providerNFT;
        uint providerId = takerPos.providerId;
        // caller is owner
        require(msg.sender == providerNFT.ownerOf(providerId), "not provider ID owner");

        // sanity check bounds
        require(minPrice <= maxPrice, "max price lower than min price");
        require(SignedMath.abs(rollFeeDeltaFactorBIPS) <= BIPS_BASE, "invalid fee delta change");
        require(block.timestamp <= deadline, "deadline passed");

        // pull the NFT
        providerNFT.transferFrom(msg.sender, address(this), providerId);

        // store the offer
        rollId = nextRollId++;
        rollOffers[rollId] = RollOffer({
            takerId: takerId,
            rollFeeAmount: rollFeeAmount,
            rollFeeDeltaFactorBIPS: rollFeeDeltaFactorBIPS,
            rollFeeReferencePrice: takerNFT.currentOraclePrice(), // the roll offer fees are for current price
            minPrice: minPrice,
            maxPrice: maxPrice,
            minToProvider: minToProvider,
            deadline: deadline,
            providerNFT: providerNFT,
            providerId: providerId,
            provider: msg.sender,
            active: true
        });

        emit OfferCreated(takerId, msg.sender, providerNFT, providerId, rollFeeAmount, rollId);
    }

    /**
     * @notice Cancels an existing roll offer and returns the provider NFT to the sender.
     * @dev Can only be called by the original offer creator
     * @param rollId The ID of the roll offer to cancel
     *
     * @dev only cancel and no updating, to prevent frontrunning a user's acceptance
     * The risk of update is different here from providerNFT.updateOfferAmount because
     * the most an update can cause there is a revert of taking the offer.
     */
    function cancelOffer(uint rollId) external whenNotPaused {
        RollOffer storage offer = rollOffers[rollId];
        require(msg.sender == offer.provider, "not initial provider");
        require(offer.active, "offer not active");
        // cancel offer
        offer.active = false;
        // return the NFT
        offer.providerNFT.transferFrom(address(this), msg.sender, offer.providerId);
        emit OfferCancelled(rollId, offer.takerId, offer.provider);
    }

    /**
     * @notice Executes a roll, settling the existing paired position and creating a new one.
     * This pulls and distributes cash, pulls taker NFT, and sends out new taker and provider NFTs.
     * @dev The caller must be the owner of the CollarTakerNFT for the position being rolled,
     * and must have approved sufficient cash if cash needs to be paid (depends on offer and current price)
     * @param rollId The ID of the roll offer to execute
     * @param minToTaker The minimum amount the user (taker) is willing to receive, or maximum willing to
     *     pay if negative. The execution transfer (in or out) will be checked to be >= this value.
     * @return newTakerId The ID of the newly created CollarTakerNFT position
     * @return newProviderId The ID of the newly created ShortProviderNFT position
     * @return toTaker The amount transferred to (or from, if negative) the taker
     * @return toProvider The amount transferred to (or from, if negative) the provider
     */
    function executeRoll(
        uint rollId,
        int minToTaker // signed "slippage", user protection
    ) external whenNotPaused returns (uint newTakerId, uint newProviderId, int toTaker, int toProvider) {
        RollOffer storage offer = rollOffers[rollId];
        // offer was cancelled (if taken tokens would be burned)
        require(offer.active, "invalid offer");
        // store the inactive state before external calls as extra reentrancy precaution
        // @dev this writes to storage
        offer.active = false;

        // offer is within its terms
        uint newPrice = takerNFT.currentOraclePrice();
        require(newPrice <= offer.maxPrice, "price too high");
        require(newPrice >= offer.minPrice, "price too low");
        require(block.timestamp <= offer.deadline, "deadline passed");

        // auth, will revert if takerId was burned already
        require(msg.sender == takerNFT.ownerOf(offer.takerId), "not taker ID owner");

        // position is not settled yet. it must exist still (otherwise ownerOf would revert)
        CollarTakerNFT.TakerPosition memory takerPos = takerNFT.getPosition(offer.takerId);
        require(!takerPos.settled, "taker position settled");
        // @dev an expired position should settle at some past price, so if rolling after expiry is allowed,
        // a different price may be used in settlement calculations instead of current price.
        // This is prevented by this check, since supporting the complexity of such scenarios is not needed.
        require(block.timestamp <= takerPos.expiration, "taker position expired");

        (newTakerId, newProviderId, toTaker, toProvider) = _executeRoll(rollId, newPrice, takerPos);

        // check transfers are sufficient / or pulls are not excessive
        require(toTaker >= minToTaker, "taker transfer slippage");
        require(toProvider >= offer.minToProvider, "provider transfer slippage");
    }

    // ----- INTERNAL MUTATIVE ----- //

    function _executeRoll(uint rollId, uint newPrice, CollarTakerNFT.TakerPosition memory takerPos)
        internal
        returns (uint newTakerId, uint newProviderId, int toTaker, int toProvider)
    {
        // @dev this is memory, not storage
        RollOffer memory offer = rollOffers[rollId];

        ShortProviderNFT providerNFT = takerPos.providerNFT;
        ShortProviderNFT.ProviderPosition memory providerPos = providerNFT.getPosition(takerPos.providerId);
        // calculate the transfer amounts
        int rollFee = calculateRollFee(offer, newPrice);
        (toTaker, toProvider) = _calculateTransferAmounts({
            newPrice: newPrice,
            rollFeeAmount: rollFee,
            takerId: offer.takerId,
            providerPos: providerPos
        });

        // pull the taker NFT from the user (we already have the provider NFT)
        takerNFT.transferFrom(msg.sender, address(this), offer.takerId);
        // now that we have both NFTs, cancel the positions and withdraw
        _cancelPairedPositionAndWithdraw(offer.takerId, takerPos);

        // pull cash as needed
        _pullCash(toTaker, msg.sender, toProvider, offer.provider);

        // open the new positions
        (newTakerId, newProviderId) = _openNewPairedPosition(newPrice, providerNFT, takerPos, providerPos);

        // pay cash as needed
        _payCash(toTaker, msg.sender, toProvider, offer.provider);

        // we now own both of the NFT IDs, so send them out to their new proud owners
        takerNFT.transferFrom(address(this), msg.sender, newTakerId);
        providerNFT.transferFrom(address(this), offer.provider, newProviderId);

        emit OfferExecuted(
            rollId,
            offer.takerId,
            offer.providerNFT,
            offer.providerId,
            toTaker,
            toProvider,
            rollFee,
            newTakerId,
            newProviderId
        );
    }

    function _pullCash(int toTaker, address taker, int toProvider, address provider) internal {
        if (toTaker < 0) {
            // assumes approval from the taker, @dev reverts for type(int).min
            cashAsset.safeTransferFrom(taker, address(this), uint(-toTaker));
        }
        if (toProvider < 0) {
            // @dev this requires the original owner of the providerId (stored in the offer) when
            // the roll offer was created to still allow this contract to pull their funds, and
            // still have sufficient balance for that. Reverts for type(int).min
            cashAsset.safeTransferFrom(provider, address(this), uint(-toProvider));
        }
    }

    function _payCash(int toTaker, address taker, int toProvider, address provider) internal {
        if (toTaker > 0) {
            cashAsset.safeTransfer(taker, uint(toTaker));
        }
        if (toProvider > 0) {
            cashAsset.safeTransfer(provider, uint(toProvider));
        }
    }

    function _cancelPairedPositionAndWithdraw(uint takerId, CollarTakerNFT.TakerPosition memory takerPos)
        internal
    {
        // approve the takerNFT to pull the provider NFT, as both NFTs are needed for cancellation
        takerPos.providerNFT.approve(address(takerNFT), takerPos.providerId);
        // cancel and withdraw the cash from the existing paired position
        // @dev this relies on being the owner of both NFTs. it burns both NFTs, and withdraws
        // both put and locked cash to this contract
        uint balanceBefore = cashAsset.balanceOf(address(this));
        takerNFT.cancelPairedPosition(takerId, address(this));
        uint withdrawn = cashAsset.balanceOf(address(this)) - balanceBefore;
        // @dev if this changes, the calculations need to be updated
        uint expectedAmount = takerPos.putLockedCash + takerPos.callLockedCash;
        require(withdrawn == expectedAmount, "unexpected withdrawal amount");
    }

    function _openNewPairedPosition(
        uint currentPrice,
        ShortProviderNFT providerNFT,
        CollarTakerNFT.TakerPosition memory takerPos,
        ShortProviderNFT.ProviderPosition memory providerPos
    ) internal returns (uint newTakerId, uint newProviderId) {
        // calculate locked amounts for new positions
        (uint newPutLocked, uint newCallLocked) = _newLockedAmounts({
            startPrice: takerPos.initialPrice,
            newPrice: currentPrice,
            putLocked: takerPos.putLockedCash,
            putDeviation: providerPos.putStrikeDeviation,
            callDeviation: providerPos.callStrikeDeviation
        });

        // add the protocol fee that will be taken from the offer
        (uint protocolFee,) = providerNFT.protocolFee(newCallLocked, takerPos.duration);
        uint offerAmount = newCallLocked + protocolFee;

        // create a liquidity offer just for this roll
        cashAsset.forceApprove(address(providerNFT), offerAmount);
        uint liquidityOfferId = providerNFT.createOffer({
            callStrikeDeviation: providerPos.callStrikeDeviation,
            amount: offerAmount,
            putStrikeDeviation: providerPos.putStrikeDeviation,
            duration: takerPos.duration
        });

        // take the liquidity offer as taker
        cashAsset.forceApprove(address(takerNFT), newPutLocked);
        (newTakerId, newProviderId) = takerNFT.openPairedPosition(newPutLocked, providerNFT, liquidityOfferId);
    }

    // ----- INTERNAL VIEWS ----- //

    function _calculateTransferAmounts(
        uint newPrice,
        int rollFeeAmount,
        uint takerId,
        ShortProviderNFT.ProviderPosition memory providerPos
    ) internal view returns (int toTaker, int toProvider) {
        // what would the taker and provider get from a settlement of the old position at current settlement price
        (uint takerSettled, int providerChange) = takerNFT.previewSettlement(takerId, newPrice);
        CollarTakerNFT.TakerPosition memory takerPos = takerNFT.getPosition(takerId);
        int providerSettled = takerPos.callLockedCash.toInt256() + providerChange;

        // what are the new locked amounts as they will be calculated when opening the new positions
        (uint newPutLocked, uint newCallLocked) = _newLockedAmounts({
            startPrice: takerPos.initialPrice,
            newPrice: newPrice,
            putLocked: takerPos.putLockedCash,
            putDeviation: providerPos.putStrikeDeviation,
            callDeviation: providerPos.callStrikeDeviation
        });

        (uint protocolFee,) = takerPos.providerNFT.protocolFee(newCallLocked, takerPos.duration);

        // The taker and provider external balances (before fee) should be updated according to
        // their PNL: the money released from their settled position minus the cost of opening the new position.
        // The roll-fee is applied, and can represent any arbitrary adjustment to this (that's expressed by the offer).
        toTaker = takerSettled.toInt256() - newPutLocked.toInt256() - rollFeeAmount;
        toProvider = providerSettled - newCallLocked.toInt256() + rollFeeAmount - protocolFee.toInt256();

        /*  Does this balance out? Vars:
                Ts: takerSettled, Ps: providerSettled, put: newPutLocked,
                call: newCallLocked, rollFee: rollFee, proFee: protocolFee

            After settlement (after cancelling and withdrawing old position):
                Contract balance    = Ts + Ps

            Then contract receives / pays:
                1. toPairedPosition =           put + call
                2. toTaker          = Ts      - put        - rollFee
                3. toProvider       =      Ps       - call + rollFee - proFee
                4. toProtocol       =                                + proFee

            All payments summed     = Ts + Ps

            So the contract pays out everything it receives, and everyone gets their correct updates.
        */
    }

    // @dev the amounts needed for a new position given the old position
    function _newLockedAmounts(
        uint startPrice,
        uint newPrice,
        uint putLocked,
        uint putDeviation,
        uint callDeviation
    ) internal view returns (uint newPutLocked, uint newCallLocked) {
        // simply scale up using price. As the putLockedCash is the main input to CollarTakerNFT's
        // open, this determines the new funds needed.
        // The reason this needs to be scaled with price, instead of just using the previous amount
        // is that this can serve the loans use-case, where the "collateral" value (price exposure) is
        // maintained constant (instead of the dollar amount).
        newPutLocked = putLocked * newPrice / startPrice; // zero start price is invalid and will cause panic
        // use the method that CollarTakerNFT will use to calculate the provider part
        newCallLocked = takerNFT.calculateProviderLocked(newPutLocked, putDeviation, callDeviation);
    }
}
