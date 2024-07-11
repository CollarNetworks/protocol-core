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
        uint change = amount * deltaFactor * currentPrice / offer.rollFeeReferencePrice / BIPS_BASE;
        // apply the change depending on the sign of the delta (increase or decrease fee magnitude)
        uint newAmount = offer.rollFeeDeltaFactorBIPS > 0 ? amount + change : amount - change;
        int i_newAmount = newAmount.toInt256();
        // apply the original sign of the fee (increase of decrease provider's balance)
        rollFee = offer.rollFeeAmount > 0 ? i_newAmount : -i_newAmount;
    }

    function getCurrentPrice() public view returns (uint) {
        return takerNFT.getReferenceTWAPPrice(block.timestamp);
    }

    // ----- STATE CHANGING FUNCTIONS ----- //

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

        ProviderPositionNFT.ProviderPosition memory providerPos = providerNFT.getPosition(providerId);
        // calculate the approximate amount of cash that may be needed to be pulled from the provider
        // @dev it's likely that actual max amount can be somewhat different due to fees, but this
        // is a close enough approximation, since it's only used for sanity checking the cash
        // made available now. This doesn't need to be exact because provider may not have enough
        // cash anyway when execution is triggered, and calculating the max fees (depending on factor
        // signs) is unnecessary complexity
        (, int toProvider) = _calculateTransferAmounts({
            startPrice: takerPos.initialPrice,
            newPrice: maxPrice, // at maxPrice, the provider needs to provide the max amount of new funds
            rollFeeAmount: rollFeeAmount,
            takerPos: takerPos,
            providerPos: providerPos
        });
        // how much should be pulled from provider. 0 if push is expected
        uint maxFromProvider = toProvider < 0 ? uint(-toProvider) : 0;

        if (maxFromProvider > 0) {
            // check allowance and balance to reduce chances of unfillable offers
            // @dev provider may still have insufficient allowance or balance when user will try to accept
            // but this check makes it a tiny bit harder to spoof offers, and reduces chance of errors.
            // Depositing the funds for each roll offer is avoided because it's capital inefficient, since
            // each offer is for a specific position. The offer must specific, because each taker's initial
            // price may be different, so may or may not be attractive (or require different fee) for a
            // provider.
            uint providerAllowance = cashAsset.allowance(msg.sender, address(this));
            require(cashAsset.balanceOf(msg.sender) >= maxFromProvider, "insufficient cash balance");
            require(providerAllowance >= maxFromProvider, "insufficient cash allowance");
        }

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

        // track our balance
        uint balanceBefore = cashAsset.balanceOf(address(this));

        (newTakerId, newProviderId, toTaker, toProvider) = _executeRoll(offerMemory, currentPrice, takerPos);

        // check transfer is sufficient / or pull is not excessive
        require(toTaker >= minToUser, "taker transfer slippage");

        // refund any remaining dust or excess to provider
        uint providerRefund = cashAsset.balanceOf(address(this)) - balanceBefore;
        cashAsset.safeTransfer(offerMemory.provider, providerRefund);
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

        // account for the difference in the put option (the loan) that the user
        // was exposed to (and that now has a different strike price), and is scaled by the price change
        (uint initialUnlocked, uint newUnlocked) =
            _calculatePutValues(startPrice, newPrice, putLocked, putDeviation);

        // new locked amounts, as they will be calculated when opening the new positions
        (uint newPutLocked, uint newCallLocked) = _newLockedAmounts({
            startPrice: startPrice,
            newPrice: newPrice,
            putLocked: putLocked,
            putDeviation: putDeviation,
            callDeviation: callDeviation
        });

        // The first invariant is that taker's external balance (adjusted for roll-fee) should
        // reflect the new position's put value.
        // Taker should either get paid OR repay the difference in "loan" (put value), adjusted by roll fee.
        toTaker = newUnlocked.toInt256() - initialUnlocked.toInt256() - rollFeeAmount;
        uint lockedBalance = putLocked + callLocked;
        // The second invariant is that the new locked balance needs to be present in the contract
        // when opening the new position regardless of where it comes from.
        int lockedChange = (newPutLocked + newCallLocked).toInt256() - lockedBalance.toInt256();
        // The result is that provider "needs" to pay (or receive) the difference needed for these
        // invariant to be satisfied: locked adjustment and taker's adjustment.
        // since the roll-fee is already accounted for in the takerTransfer, there is no need to account
        // for it again.
        // Thus, if new cash needs to be provided into the system (e.g, due to increase in price), it's
        // the position calculations force taker and locked changes, and the difference is via the provider
        // and the roll-fee adjustment.
        toProvider = -lockedChange - toTaker;
    }

    // @dev the amounts needed for a new position given the old position
    function _newLockedAmounts(
        uint startPrice,
        uint newPrice,
        uint putLocked,
        uint putDeviation,
        uint callDeviation
    ) internal view returns (uint newPutLocked, uint newCallLocked) {
        // simple scale up using price. As the putLockedCash is the main input to CollarTakerNFT's
        // open, this determines the new funds needed.
        newPutLocked = putLocked * newPrice / startPrice;
        // use the method that CollarTakerNFT will use to calculate the provider part
        newCallLocked = takerNFT.calculateProviderLocked(newPutLocked, putDeviation, callDeviation);
    }

    function _calculatePutValues(uint startPrice, uint newPrice, uint putLocked, uint putDeviation)
        internal
        pure
        returns (uint initialPutValue, uint newPutValue)
    {
        // the deviation range of the put. e.g., 10% = 100% - 90%
        uint putRange = BIPS_BASE - putDeviation;
        /*
        To calculate the initial put's value (equivalent to the loan), we use the putLocked
        amount (e.g. 100 tokens), which represent its range (e.g., 10%), to get to what
        the 90% (the put) would be worth:
            putValue = putLocked * BIPS_BASE / putRange;
            900 = 100 * 90% / 10%;
        Another way to get to the same is in two steps:
            1. 1000 = "full collateral value" = 100 * 100% / 10%;
            2. 900 = "loan value" = 90% * 1000;
        Combining the two steps results in the same.
        */
        initialPutValue = putLocked * putDeviation / putRange;

        /*
        To get to the new value we scale by price. But because the previous value is the result
        of division, and to avoid mul-after-div precision loss, we substitute the previous formula:
            1. initialPutValue = putLocked * putDeviation / putRange;
        into the new one:
            2. newPutValue = initialPutValue * newPrice / startPrice;
        resulting in, after rearranging:
            newPutValue = putLocked * putDeviation * newPrice / startPrice / putRange;
        */
        newPutValue = putLocked * putDeviation * newPrice / startPrice / putRange;
    }
}
