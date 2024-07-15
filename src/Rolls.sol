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
import { IRolls } from "./interfaces/IRolls.sol";
import { CollarTakerNFT } from "./CollarTakerNFT.sol";
import { ProviderPositionNFT } from "./ProviderPositionNFT.sol";

contract Rolls is IRolls, Ownable, Pausable {
    using SafeERC20 for IERC20;
    using SafeCast for uint;

    uint internal constant BIPS_BASE = 10_000;

    string public constant VERSION = "0.2.0";

    // ----- IMMUTABLES ----- //
    CollarTakerNFT public immutable takerNFT;
    IERC20 public immutable cashAsset;

    // ----- STATE VARIABLES ----- //

    uint public nextRollId;

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

    function calculateTransferAmounts(uint rollId, uint price)
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

    // ----- MUTATIVE FUNCTIONS ----- //

    // @dev if the provider will need to provide cash on execution, they must approve the contract to pull that
    // cash when submitting the offer (and have those funds available), so that it is executable.
    // If offer is unexecutable becomes of insufficient provider cash approval or balance it should ideally be
    // filtered out by the FE as not executable (and show as unexecutable for the provider).
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

        ProviderPositionNFT providerNFT = takerPos.providerNFT;
        uint providerId = takerPos.providerPositionId;
        // caller is owner
        require(msg.sender == providerNFT.ownerOf(providerId), "not provider ID owner");

        // sanity check bounds
        require(minPrice < maxPrice, "max price not higher than min price");
        require(_abs(rollFeeDeltaFactorBIPS) <= BIPS_BASE, "invalid fee delta change");
        require(deadline >= block.timestamp, "deadline passed");

        // pull the NFT
        providerNFT.transferFrom(msg.sender, address(this), providerId);

        // @dev if provider expects to pay, check that they have granted sufficient balance and approvals already
        // according to their max payment expectation
        if (minToProvider < 0) {
            uint maxFromProvider = uint(-minToProvider);
            // @dev provider may still have insufficient allowance or balance when user will try to accept
            // but this check makes it a tiny bit harder to spoof offers, and reduces chance of errors.
            // Depositing the funds for each roll offer is avoided because it's capital inefficient, since
            // each offer is for a specific position.
            require(cashAsset.balanceOf(msg.sender) >= maxFromProvider, "insufficient cash balance");
            require(
                cashAsset.allowance(msg.sender, address(this)) >= maxFromProvider,
                "insufficient cash allowance"
            );
        }

        // store the offer
        rollId = nextRollId++;
        rollOffers[rollId] = RollOffer({
            takerId: takerId,
            rollFeeAmount: rollFeeAmount,
            rollFeeDeltaFactorBIPS: rollFeeDeltaFactorBIPS,
            rollFeeReferencePrice: getCurrentPrice(), // the roll offer fees are for current price
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
        emit OfferCancelled(rollId, offer.takerId, offer.provider);
    }

    function executeRoll(
        uint rollId,
        int minToUser // signed "slippage", user protection
    ) external whenNotPaused returns (uint newTakerId, uint newProviderId, int toTaker, int toProvider) {
        RollOffer storage offer = rollOffers[rollId];
        // auth, will revert if takerId was burned already
        require(msg.sender == takerNFT.ownerOf(offer.takerId), "not taker ID owner");

        // position is not settled yet. it must exist still (otherwise ownerOf would revert)
        CollarTakerNFT.TakerPosition memory takerPos = takerNFT.getPosition(offer.takerId);
        require(!takerPos.settled, "taker position settled");

        // offer is within its terms
        uint currentPrice = getCurrentPrice();
        require(currentPrice <= offer.maxPrice, "price too high");
        require(currentPrice >= offer.minPrice, "price too low");
        require(offer.deadline <= block.timestamp, "deadline passed");

        // offer was cancelled (if taken tokens would be burned)
        require(offer.active, "invalid offer");
        // store the inactive state before external calls as extra reentrancy precaution
        // @dev this writes to storage
        offer.active = false;

        (newTakerId, newProviderId, toTaker, toProvider) = _executeRoll(rollId, currentPrice, takerPos);

        // check transfers are sufficient / or pulls are not excessive
        require(toTaker >= minToUser, "taker transfer slippage");
        require(toProvider >= offer.minToProvider, "provider transfer slippage");
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

    function _executeRoll(uint rollId, uint currentPrice, CollarTakerNFT.TakerPosition memory takerPos)
        internal
        returns (uint newTakerId, uint newProviderId, int toTaker, int toProvider)
    {
        // @dev this is memory, not storage
        RollOffer memory offer = rollOffers[rollId];
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
        // what would the taker and provider get from a settlement of the old position at current price
        (uint takerSettled, int providerChange) = takerNFT.previewSettlement(takerPos, newPrice);
        int providerSettled = takerPos.callLockedCash.toInt256() + providerChange;

        // what are the new locked amounts as they will be calculated when opening the new positions
        (uint newPutLocked, uint newCallLocked) = _newLockedAmounts({
            startPrice: startPrice,
            newPrice: newPrice,
            putLocked: takerPos.putLockedCash,
            putDeviation: providerPos.putStrikeDeviation,
            callDeviation: providerPos.callStrikeDeviation
        });

        // The taker and provider external balances (before fee) should be updated according to
        // their PNL: the money released from their settled position minus the cost of opening the new position.
        // The roll-fee is applied, and can represent any arbitrary adjustment to this (that's expressed by the offer).
        toTaker = takerSettled.toInt256() - newPutLocked.toInt256() - rollFeeAmount;
        toProvider = providerSettled - newCallLocked.toInt256() + rollFeeAmount;

        /*
            Does this balance out? After settlement (aligned to see what cancels out):

            The contract balance    = takerSettled + providerSettled

            The contract receives / pays:
                1. toPairedPosition =                                  newPutLocked + newCallLocked
                2. toTaker          = takerSettled                   - newPutLocked                 - fee
                3. toProvider       =                providerSettled                - newCallLocked + fee

            All payments summed     = takerSettled + providerSettled

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
        newPutLocked = putLocked * newPrice / startPrice;
        // use the method that CollarTakerNFT will use to calculate the provider part
        newCallLocked = takerNFT.calculateProviderLocked(newPutLocked, putDeviation, callDeviation);
    }
}
