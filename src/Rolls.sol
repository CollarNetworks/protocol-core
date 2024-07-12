// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity 0.8.22;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
// internal imports
import { CollarEngine } from "./implementations/CollarEngine.sol";
import { CollarTakerNFT } from "./CollarTakerNFT.sol";
import { ProviderPositionNFT } from "./ProviderPositionNFT.sol";

contract Rolls is Ownable, Pausable {
    using SafeERC20 for IERC20;
    using SafeCast for uint;

    uint internal constant BIPS_BASE = 10_000;

    // allow checking version in scripts / on-chain
    string public constant VERSION = "0.2.0";

    // ----- IMMUTABLES ----- //
    CollarTakerNFT public immutable takerNFT;
    IERC20 public immutable cashAsset;

    // ----- STATE VARIABLES ----- //

    uint public nextRollId;

    struct RollOffer {
        // terms
        uint takerId;
        int rollFeeAmount;
        int rollFeeDeltaFactorBIPS; // bips change of fee amount for delta (ratio) of price change
        uint rollFeeReferencePrice;
        uint minPrice;
        uint maxPrice;
        // somewhat redundant (since it comes from the taker ID), but safer for cancellations
        ProviderPositionNFT providerNFT;
        uint providerId;
        // state
        address provider;
        bool active;
    }

    mapping(uint rollId => RollOffer) internal rollOffers;

    constructor(address initialOwner, CollarTakerNFT _takerNFT, IERC20 _cashAsset) Ownable(initialOwner) {
        takerNFT = _takerNFT;
        cashAsset = _cashAsset;
    }

    // ----- VIEW FUNCTIONS ----- //

    /// @dev return memory struct (the default getter returns tuple)
    function getRollOffer(uint rollId) external view returns (RollOffer memory) {
        return rollOffers[rollId];
    }

    function calculateRollFee(RollOffer memory offer, uint currentPrice) public pure returns (int rollFee) {
        // original fee magnitude
        uint amount = _abs(offer.rollFeeAmount);
        // delta factor without its sign
        uint deltaFactor = _abs(offer.rollFeeDeltaFactorBIPS);
        // scale the fee magnitude by the delta (price change) multiplied by the factor
        // for deltaFactor of 100%, this results in linear scaling of the fee with price
        // so if factor is BIPS_BASE the amount moves with the price. E.g., 5% price increase, 5% fee increase
        // but if it's, e.g.,  50% the fee increases only 2.5% for a 5% price increase.
        uint change = amount * deltaFactor * currentPrice / offer.rollFeeReferencePrice / BIPS_BASE;
        // Apply the change depending on the sign of the delta (increase or decrease fee magnitude).
        // E.g., if the fee is -5, the sign of the factor specifies whether it's increased (+5% -> -5.25)
        // or decreased (-5% -> -4.75) with price change.
        uint newAmount = offer.rollFeeDeltaFactorBIPS > 0 ? amount + change : amount - change;
        int i_newAmount = newAmount.toInt256();
        // apply the original sign of the fee (increase of decrease provider's balance)
        rollFee = offer.rollFeeAmount > 0 ? i_newAmount : -i_newAmount;
    }

    function getCurrentPrice() public view returns (uint) {
        return takerNFT.getReferenceTWAPPrice(block.timestamp);
    }

    function previewRollTransfers(uint rollId, uint price)
        external
        view
        returns (int toTaker, int toProvider, int rollFee)
    {
        RollOffer memory offer = rollOffers[rollId];
        CollarTakerNFT.TakerPosition memory takerPos = takerNFT.getPosition(offer.takerId);
        rollFee = calculateRollFee(offer, price);
        (toTaker, toProvider) = _calculateTransferAmounts({
            startPrice: takerPos.initialPrice,
            newPrice: price,
            rollFeeAmount: rollFee,
            takerPos: takerPos,
            providerPos: takerPos.providerNFT.getPosition(takerPos.providerPositionId)
        });
    }

    // ----- STATE CHANGING FUNCTIONS ----- //

    // @dev if the provider will need to provide cash on execution, they must approve the contract to pull that
    // cash when submitting the offer (and have those funds available), so that it is executable.
    // If offer is unexecutable becomes of insufficient provider cash approval or balance it should ideally be
    // filtered out by the FE as not executable (and show as unexecutable for the provider).
    function createRollOffer(
        uint takerId,
        int rollFeeAmount,
        int rollFeeDeltaFactorBIPS,
        uint minPrice,
        uint maxPrice
    ) external whenNotPaused returns (uint rollId) {
        // taker position is valid
        CollarTakerNFT.TakerPosition memory takerPos = takerNFT.getPosition(takerId);
        require(takerPos.expiration != 0, "taker position doesn't exist");
        require(!takerPos.settled, "taker position settled");

        ProviderPositionNFT providerNFT = takerPos.providerNFT;
        uint providerId = takerPos.providerPositionId;
        // caller is owner
        require(msg.sender == providerNFT.ownerOf(providerId), "not provider ID owner");

        // sanity check bounds
        require(minPrice < maxPrice, "max price not higher than min price");
        require(_abs(rollFeeDeltaFactorBIPS) <= BIPS_BASE, "invalid fee delta change");

        // pull the NFT
        providerNFT.transferFrom(msg.sender, address(this), providerId);

        // store the offer
        rollId = nextRollId++;
        rollOffers[rollId] = RollOffer({
            takerId: takerId,
            rollFeeAmount: rollFeeAmount,
            rollFeeDeltaFactorBIPS: rollFeeDeltaFactorBIPS,
            rollFeeReferencePrice: getCurrentPrice(), // the roll offer fees are for current price
            minPrice: minPrice,
            maxPrice: maxPrice,
            providerNFT: providerNFT,
            providerId: providerId,
            provider: msg.sender,
            active: true
        });

        // TODO: event
    }

    /// @dev only cancel and no updating, to prevent frontrunning a user's accept.
    /// The risk of update is different here from providerNFT.updateOfferAmount because
    /// the most an update can cause there is a revert of taking the offer.
    function cancelOffer(uint rollId) external whenNotPaused {
        RollOffer storage offer = rollOffers[rollId];
        require(msg.sender == offer.provider, "not initial provider");
        // cancel offer
        offer.active = false;
        // return the NFT
        offer.providerNFT.transferFrom(address(this), msg.sender, offer.providerId);
        // TODO event
    }

    function executeRoll(
        uint rollId,
        int minToUser // signed "slippage", user protection
    ) external whenNotPaused returns (uint newTakerId, uint newProviderId, int toTaker, int toProvider) {
        // @dev this is memory, not storage, because we later pass it into _executeRoll, which
        // should use memory not storage. It would be possible to use storage here, and memory
        // there, but that's error prone, so memory is used in both places.
        RollOffer memory offerMemory = rollOffers[rollId];
        // auth, will revert if takerId was burned already
        require(msg.sender == takerNFT.ownerOf(offerMemory.takerId), "not taker ID owner");

        // position is not settled yet. it must exist still (otherwise ownerOf would revert)
        CollarTakerNFT.TakerPosition memory takerPos = takerNFT.getPosition(offerMemory.takerId);
        require(!takerPos.settled, "taker position settled");

        // prices are valid
        uint currentPrice = getCurrentPrice();
        require(currentPrice <= offerMemory.maxPrice, "price too high");
        require(currentPrice >= offerMemory.minPrice, "price too low");

        // offer was cancelled (if taken tokens would be burned)
        require(offerMemory.active, "invalid offer");
        // store the inactive state before external calls as extra reentrancy precaution
        // @dev this writes to storage, and so doesn't use memoryOffer (because it's in memory)
        rollOffers[rollId].active = false;

        (newTakerId, newProviderId, toTaker, toProvider) = _executeRoll(offerMemory, currentPrice, takerPos);

        // check transfer is sufficient / or pull is not excessive
        require(toTaker >= minToUser, "taker transfer slippage");
    }

    // admin mutative

    /// @notice Pauses the contract in an emergency, pausing all user callable mutative methods
    function pause() public onlyOwner {
        _pause();
    }

    /// @notice Unpauses the contract
    function unpause() public onlyOwner {
        _unpause();
    }

    // ----- INTERNAL MUTATIVE ----- //

    function _executeRoll(
        RollOffer memory offer, // @dev this is NOT storage
        uint currentPrice,
        CollarTakerNFT.TakerPosition memory takerPos
    ) internal returns (uint newTakerId, uint newProviderId, int toTaker, int toProvider) {
        // pull the taker NFT from the user (we already have the provider NFT)
        takerNFT.transferFrom(msg.sender, address(this), offer.takerId);
        // now that we have both NFTs, cancel the positions and withdraw
        _cancelPairedPositionAndWithdraw(offer.takerId, takerPos);

        ProviderPositionNFT providerNFT = takerPos.providerNFT;
        ProviderPositionNFT.ProviderPosition memory providerPos =
            providerNFT.getPosition(takerPos.providerPositionId);
        // calculate the transfer amounts
        int rollFee = calculateRollFee(offer, currentPrice);
        (toTaker, toProvider) = _calculateTransferAmounts({
            startPrice: takerPos.initialPrice,
            newPrice: currentPrice,
            rollFeeAmount: rollFee,
            takerPos: takerPos,
            providerPos: providerPos
        });

        // pull any needed cash
        if (toTaker < 0) {
            // assumes approval from the taker
            cashAsset.safeTransferFrom(msg.sender, address(this), uint(-toTaker));
        }
        if (toProvider < 0) {
            // @dev this requires the original owner of the providerId (stored in the offer) when
            // the roll offer was created to still allow this contract to pull their funds, and
            // still have sufficient balance for that.
            cashAsset.safeTransferFrom(offer.provider, address(this), uint(-toProvider));
        }

        // open the new positions
        (newTakerId, newProviderId) = _openNewPairedPosition(currentPrice, providerNFT, takerPos, providerPos);

        // we now own both of the NFT IDs, so send them out to their new proud owners
        takerNFT.transferFrom(address(this), msg.sender, newTakerId);
        providerNFT.transferFrom(address(this), offer.provider, newProviderId);

        // pay cash if needed
        if (toTaker > 0) {
            // pay the taker if needed
            cashAsset.safeTransfer(msg.sender, uint(toTaker));
        }
        if (toProvider > 0) {
            // pay the provider if needed
            cashAsset.safeTransfer(offer.provider, uint(toProvider));
        }

        // TODO: event
    }

    function _cancelPairedPositionAndWithdraw(uint takerId, CollarTakerNFT.TakerPosition memory takerPos)
        internal
    {
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
        ProviderPositionNFT providerNFT,
        CollarTakerNFT.TakerPosition memory takerPos,
        ProviderPositionNFT.ProviderPosition memory providerPos
    ) internal returns (uint newTakerId, uint newProviderId) {
        // calculate locked amounts for new positions
        (uint newPutLocked, uint newCallLocked) = _newLockedAmounts({
            startPrice: takerPos.initialPrice,
            newPrice: currentPrice,
            putLocked: takerPos.putLockedCash,
            putDeviation: providerPos.putStrikeDeviation,
            callDeviation: providerPos.callStrikeDeviation
        });

        // create a liquidity offer just for this roll
        cashAsset.forceApprove(address(providerNFT), newCallLocked);
        uint liquidityOfferId = providerNFT.createOffer({
            callStrikeDeviation: providerPos.callStrikeDeviation,
            amount: newCallLocked,
            putStrikeDeviation: providerPos.putStrikeDeviation,
            duration: takerPos.duration
        });

        // take the liquidity offer as taker
        cashAsset.forceApprove(address(takerNFT), newPutLocked);
        (newTakerId, newProviderId) = takerNFT.openPairedPosition(newPutLocked, providerNFT, liquidityOfferId);

        // withdraw any dust from the liquidity offer, in case of possible rounding in calculations.
        // should be 0 because the same calculation method is used
        providerNFT.updateOfferAmount(liquidityOfferId, 0);
    }

    // ----- INTERNAL VIEWS ----- //

    function _abs(int a) internal pure returns (uint) {
        return a > 0 ? uint(a) : uint(-a);
    }

    function _calculateTransferAmounts(
        uint startPrice,
        uint newPrice,
        int rollFeeAmount,
        CollarTakerNFT.TakerPosition memory takerPos,
        ProviderPositionNFT.ProviderPosition memory providerPos
    ) internal view returns (int toTaker, int toProvider) {
        // assign for readability
        uint putLocked = takerPos.putLockedCash;
        uint callLocked = takerPos.callLockedCash;
        uint putDeviation = providerPos.putStrikeDeviation;
        uint callDeviation = providerPos.callStrikeDeviation;

        // what would the taker get from a settlement of the old position at current price
        (uint takerSettled,) = takerNFT.previewSettlement(takerPos, newPrice);

        // what are the new locked amounts as they will be calculated when opening the new positions
        (uint newPutLocked, uint newCallLocked) = _newLockedAmounts({
            startPrice: startPrice,
            newPrice: newPrice,
            putLocked: putLocked,
            putDeviation: putDeviation,
            callDeviation: callDeviation
        });

        // The first invariant is that the new locked balance needs to be transferred out to be locked
        // in the new paired-position when opening it
        uint oldLocked = putLocked + callLocked; // the withdrawal from the cancelled old position
        int toPairedPosition = (newPutLocked + newCallLocked).toInt256() - oldLocked.toInt256();

        // The second invariant is that taker's external balance (before fee) should be updated according to
        // their PNL: the money released from their settled position minus the cost of opening the new position.
        // The roll-fee is deduced, and can represent any arbitrary adjustment to this (that's expressed by the offer).
        toTaker = takerSettled.toInt256() - newPutLocked.toInt256() - rollFeeAmount;

        // The third invariant is that the contract should be have no funds remaining after this, so
        // this means that the provider transfer balances out the other two transfers (taker and locked). So
        // provider pays (or receives) the difference to balance them out.
        // Since the roll-fee is already accounted for in toTaker, there is no need to account
        // for it again.
        toProvider = -toPairedPosition - toTaker;
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
        newPutLocked = putLocked * newPrice / startPrice;
        // use the method that CollarTakerNFT will use to calculate the provider part
        newCallLocked = takerNFT.calculateProviderLocked(newPutLocked, putDeviation, callDeviation);
    }
}
