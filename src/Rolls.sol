// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity 0.8.22;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
// internal imports
import { CollarEngine } from "./implementations/CollarEngine.sol";
import { CollarTakerNFT } from "./CollarTakerNFT.sol";
import { ProviderPositionNFT } from "./ProviderPositionNFT.sol";

contract Rolls is Ownable, Pausable {
    using SafeERC20 for IERC20;

    uint internal constant BIPS_BASE = 10_000;
    uint public constant MAX_FEE_PERCENT_BIPS = BIPS_BASE / 10; // 10%

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
        uint maxPrice;
        uint feePercent;
        // somewhat redundant (since it comes from the taker ID), but safer for cancellations
        ProviderPositionNFT providerNFT;
        uint providerId;
        // state
        address provider;
        bool active;
    }

    mapping(uint rollId => RollOffer) internal rollOffers;

    constructor(
        address initialOwner,
        CollarTakerNFT _takerNFT,
        IERC20 _cashAsset
    )
        Ownable(initialOwner)
    {
        takerNFT = _takerNFT;
        cashAsset = _cashAsset;
    }

    // ----- VIEW FUNCTIONS ----- //

    /// @dev return memory struct (the default getter returns tuple)
    function getRollOffer(uint rollId) external view returns (RollOffer memory) {
        return rollOffers[rollId];
    }

    // ----- STATE CHANGING FUNCTIONS ----- //

    function createRollOffer(
        uint takerId,
        uint maxPrice,
        uint feePercent
    )
        external
        whenNotPaused
        returns (uint rollId)
    {
        // taker position is valid
        CollarTakerNFT.TakerPosition memory takerPos = takerNFT.getPosition(takerId);
        require(takerPos.expiration != 0, "taker position doesn't exist");
        require(!takerPos.settled, "taker position settled");

        ProviderPositionNFT providerNFT = takerPos.providerNFT;
        uint providerId = takerPos.providerPositionId;
        // caller is owner
        require(msg.sender == providerNFT.ownerOf(providerId), "not provider ID owner");
        // fee is valid
        require(feePercent <= MAX_FEE_PERCENT_BIPS, "fee percent too high");

        // prices are valid
        uint currentPrice = takerNFT.getReferenceTWAPPrice(block.timestamp);
        require(currentPrice >= takerPos.initialPrice, "price is lower than initial");
        require(maxPrice >= takerPos.initialPrice, "max price lower than initial");
        // @dev maxPrice can be lower than currentPrice

        ProviderPositionNFT.ProviderPosition memory providerPos = providerNFT.getPosition(providerId);
        // calculate the max amount of cash that may be needed to be pulled from the provider
        (uint maxProviderTransfer,,) = _calculateTransferAmounts({
            startPrice: takerPos.initialPrice,
            newPrice: maxPrice,
            feePercent: feePercent,
            takerPos: takerPos,
            providerPos: providerPos
        });

        // check allowance and balance to reduce chances of unfillable offers
        // @dev provider may still have insufficient allowance or balance when user will try to accept
        // but this check makes it harder to spoof offers, and reduces chance of provider errors.
        // Note that depositing the funds for each roll offer can be highly capital inefficient, since
        // each offer is for a specific position.
        uint providerAllowance = cashAsset.allowance(msg.sender, address(this));
        require(cashAsset.balanceOf(msg.sender) >= maxProviderTransfer, "insufficient cash balance");
        require(providerAllowance >= maxProviderTransfer, "insufficient cash allowance");

        // pull the NFT
        providerNFT.transferFrom(msg.sender, address(this), providerId);

        // store the offer
        rollId = nextRollId++;
        rollOffers[rollId] = RollOffer({
            takerId: takerId,
            maxPrice: maxPrice,
            feePercent: feePercent,
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
        uint minCashTransfer // "slippage", extra user protection (e.g, from price changes)
    )
        external
        whenNotPaused
        returns (uint newTakerId, uint newProviderId, uint takerTransfer)
    {
        RollOffer memory offerMemory = rollOffers[rollId]; // @dev memory, not storage
        // auth, will revert if takerId was burned already
        require(msg.sender == takerNFT.ownerOf(offerMemory.takerId), "not taker ID owner");

        // position is valid
        CollarTakerNFT.TakerPosition memory takerPos = takerNFT.getPosition(offerMemory.takerId);
        require(!takerPos.settled, "taker position settled");

        // prices are valid
        uint currentPrice = takerNFT.getReferenceTWAPPrice(block.timestamp);
        require(currentPrice >= takerPos.initialPrice, "price too low");
        require(currentPrice <= offerMemory.maxPrice, "price too high");

        require(offerMemory.active, "invalid offer");
        // store the inactive state before external calls as extra reentrancy precaution
        // @dev this writes to storage, and so doesn't use memoryOffer (because it's in memory)
        rollOffers[rollId].active = false;

        // track our balance
        uint balanceBefore = cashAsset.balanceOf(address(this));

        (newTakerId, newProviderId, takerTransfer) = _executeRoll(offerMemory, currentPrice, takerPos);

        // check transfer is sufficient
        require(takerTransfer >= minCashTransfer, "taker transfer too small");

        // refund any remaining dust or excess
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
    )
        internal
        returns (uint newTakerId, uint newProviderId, uint takerTransfer)
    {
        // pull the taker NFT from the user (we already have the provider NFT)
        takerNFT.transferFrom(msg.sender, address(this), offer.takerId);
        // now that we have both NFTs, cancel the positions and withdraw
        _cancelPairedPositionAndWithdraw(offer.takerId, takerPos);

        ProviderPositionNFT providerNFT = takerPos.providerNFT;
        ProviderPositionNFT.ProviderPosition memory providerPos =
            providerNFT.getPosition(takerPos.providerPositionId);
        // calculate the transfer amounts
        uint providerTransferIn;
        uint fee;
        (providerTransferIn, takerTransfer, fee) = _calculateTransferAmounts({
            startPrice: takerPos.initialPrice,
            newPrice: currentPrice,
            feePercent: offer.feePercent,
            takerPos: takerPos,
            providerPos: providerPos
        });

        // pull the additional cash needed from the original provider who made the roll offer
        // @dev this requires the original owner of the providerId (stored in the offer) when
        // the roll offer was created to still allow this contract to pull their funds, and
        // still have sufficient balance for that.
        cashAsset.safeTransferFrom(offer.provider, address(this), providerTransferIn);

        // open the new positions
        (newTakerId, newProviderId) = _openNewPairedPosition(currentPrice, providerNFT, takerPos, providerPos);

        // we now own both of the NFT IDs, so send them out to their new proud owners
        takerNFT.transferFrom(address(this), msg.sender, newTakerId);
        providerNFT.transferFrom(address(this), offer.provider, newProviderId);

        // send the cash for the delta (price exposure difference, equivalent to the loan increase)
        // to the taker
        cashAsset.safeTransfer(msg.sender, takerTransfer);

        // TODO: event
    }

    function _cancelPairedPositionAndWithdraw(
        uint takerId,
        CollarTakerNFT.TakerPosition memory takerPos
    )
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
    )
        internal
        returns (uint newTakerId, uint newProviderId)
    {
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

    function _calculateTransferAmounts(
        uint startPrice,
        uint newPrice,
        uint feePercent,
        CollarTakerNFT.TakerPosition memory takerPos,
        ProviderPositionNFT.ProviderPosition memory providerPos
    )
        internal
        view
        returns (uint providerTransferIn, uint takerTransferOut, uint fee)
    {
        // assign for readability
        uint putLocked = takerPos.putLockedCash;
        uint putDeviation = providerPos.putStrikeDeviation;
        uint callDeviation = providerPos.callStrikeDeviation;

        // new locked amounts, as they will be calculated when opening the new positions
        (uint newPutLocked, uint newCallLocked) = _newLockedAmounts({
            startPrice: startPrice,
            newPrice: newPrice,
            putLocked: putLocked,
            putDeviation: putDeviation,
            callDeviation: callDeviation
        });

        // 1. provider needs to pay for total difference in pot, which is scaled by the price change
        // which the provider is exposed to (on behalf of the user, acting as "collateral")
        uint potIncrease = (newPutLocked + newCallLocked) - (putLocked + takerPos.callLockedCash);

        // 2. provider needs to pay for the difference in the put option (the loan) that the user
        // was exposed to (and that now has a higher strike price), and is scaled by the price change
        uint takerDelta = _calculateTakerDelta(startPrice, newPrice, putLocked, putDeviation);

        // feePercent is in BIPs, and is taken out of tre taker's transfer.
        // this fee, compared to the "fair" (neutral) repricing above is why the provider is willing
        // to even do the roll, compared to the original position which had lower call-strikm
        // so was more inherently profitable to the provider.
        fee = takerDelta * feePercent / BIPS_BASE;

        // take the fee out
        takerTransferOut = takerDelta - fee;

        // sum parts 1 + 2: position locked value increase + the taker's put value increase
        providerTransferIn = potIncrease + takerTransferOut;
    }

    // @dev the amounts needed for a new position given the old position
    function _newLockedAmounts(
        uint startPrice,
        uint newPrice,
        uint putLocked,
        uint putDeviation,
        uint callDeviation
    )
        internal
        view
        returns (uint newPutLocked, uint newCallLocked)
    {
        // simple scale up using price. As the putLockedCash is the main input to CollarTakerNFT's
        // open, this determines the new funds needed.
        newPutLocked = putLocked * newPrice / startPrice;
        // use the method that CollarTakerNFT will use to calculate the provider part
        newCallLocked = takerNFT.calculateProviderLocked(newPutLocked, putDeviation, callDeviation);
    }

    function _calculateTakerDelta(
        uint startPrice,
        uint newPrice,
        uint putLocked,
        uint putDeviation
    )
        internal
        pure
        returns (uint takerDelta)
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
            2. 900 = "loan value" = 90% * 100;
        Combining the two steps results in the same.
        */
        uint initialPutValue = putLocked * putDeviation / putRange;

        /*
        To get to the new value we scale by price. But because the previous value is the result
        of division, and to avoid mul-after-div precision loss, we substitute the previous formula:
            1. initialPutValue = putLocked * putDeviation / putRange;
        into the new one:
            2. newPutValue = initialPutValue * newPrice / startPrice;
        resulting in after rearranging:
            newPutValue = putLocked * putDeviation * newPrice / startPrice / putRange;
        */
        uint newPutValue = putLocked * putDeviation * newPrice / startPrice / putRange;

        // the difference between the two is what the taker should be paid (before fees)
        takerDelta = newPutValue - initialPutValue;
    }
}
