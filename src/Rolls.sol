// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity 0.8.22;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IV3SwapRouter } from "@uniswap/swap-router-contracts/contracts/interfaces/IV3SwapRouter.sol";
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
    CollarEngine public immutable engine;
    CollarTakerNFT public immutable takerNFT;
    IERC20 public immutable cashAsset;
    IERC20 public immutable collateralAsset;

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
        CollarEngine _engine,
        CollarTakerNFT _takerNFT,
        IERC20 _cashAsset,
        IERC20 _collateralAsset
    )
        Ownable(initialOwner)
    {
        engine = _engine;
        takerNFT = _takerNFT;
        cashAsset = _cashAsset;
        collateralAsset = _collateralAsset;
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

    function acceptOffer(uint rollId, uint minCashTransfer) external whenNotPaused returns (uint amount) {
        RollOffer storage offer = rollOffers[rollId];
        // auth, will revert if takerId was burned already
        require(msg.sender == takerNFT.ownerOf(offer.takerId), "not taker ID owner");

        // position is valid
        uint takerId = offer.takerId;
        CollarTakerNFT.TakerPosition memory takerPos = takerNFT.getPosition(takerId);
        require(!takerPos.settled, "taker position settled");

        // prices are valid
        uint currentPrice = takerNFT.getReferenceTWAPPrice(block.timestamp);
        require(currentPrice >= takerPos.initialPrice, "price too low");
        require(currentPrice <= offer.maxPrice, "price too high");

        ProviderPositionNFT providerNFT = takerPos.providerNFT;
        uint providerId = takerPos.providerPositionId;
        ProviderPositionNFT.ProviderPosition memory providerPos = providerNFT.getPosition(providerId);
        // calculate the transfer amounts
        (uint providerTransferIn, uint takerTransferOut,) = _calculateTransferAmounts({
            startPrice: takerPos.initialPrice,
            newPrice: currentPrice,
            feePercent: offer.feePercent,
            takerPos: takerPos,
            providerPos: providerPos
        });

        // deactivate before external calls as reentrancy precaution
        offer.active = false;

        // pull the taker NFT from the user (we already have the provider NFT)
        takerNFT.transferFrom(msg.sender, address(this), takerId);

        // cancel and withdraw the cash from the existing paired position
        // @dev this relies on being the owner of both NFTs. it burns both NFTs, and withdraws
        // both put and locked cash to this contract
        uint balanceBefore = cashAsset.balanceOf(address(this));
        takerNFT.cancelPairedPosition(takerId, address(this));
        uint withdrawn = cashAsset.balanceOf(address(this)) - balanceBefore;
        uint expectedAmount = takerPos.putLockedCash + takerPos.callLockedCash;
        require(withdrawn == expectedAmount, "unexpected withdrawal amount");

        // pull the cash needed from the original provider who made the roll offer
        // @dev this requires the original owner of the providerId (stored in the offer) when
        // the roll offer was created to still allow this contract to pull their funds, and
        // still have sufficient balance on that account.
        cashAsset.safeTransferFrom(offer.provider, address(this), providerTransferIn);

        // calculate locked amounts for new positions
        (uint newPutLocked, uint newCallLocked) = _newLockedAmounts({
            startPrice : takerPos.initialPrice,
            newPrice : currentPrice,
            putLocked : takerPos.putLockedCash,
            putDeviation : providerPos.putStrikeDeviation,
            callDeviation : providerPos.callStrikeDeviation
        });

        // create a liquidity offer just for this roll
        cashAsset.forceApprove(address(providerNFT), newCallLocked);
        uint liquidityOfferId = providerNFT.createOffer(providerPos.callStrikeDeviation, newCallLocked, providerPos.putStrikeDeviation, takerPos.duration);

        // take the liquidity offer as taker
        cashAsset.forceApprove(address(takerNFT), newPutLocked);
        (uint newTakerId, uint newProviderId) = takerNFT.openPairedPosition(newPutLocked, providerNFT, liquidityOfferId);

        // send the cash for the delta (price exposure difference, equivalent to the loan increase)
        // to the taker
        cashAsset.safeTransfer(msg.sender, takerTransferOut);

        // we now own both of the NFT IDs, so send them out to their new proud owners
        takerNFT.transferFrom(address(this), msg.sender, newTakerId);
        providerNFT.transferFrom(address(this), offer.provider, newProviderId);

        // TODO: event
    }

    /// @notice Pauses the contract in an emergency, pausing all user callable mutative methods
    function pause() public onlyOwner {
        _pause();
    }

    /// @notice Unpauses the contract
    function unpause() public onlyOwner {
        _unpause();
    }

    // ----- INTERNAL MUTATIVE ----- //

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
        uint putLocked = takerPos.putLockedCash;
        uint putDeviation = providerPos.putStrikeDeviation;
        uint callDeviation = providerPos.callStrikeDeviation;

        (uint newPutLocked, uint newCallLocked) =
            _newLockedAmounts(startPrice, newPrice, putLocked, putDeviation, callDeviation);

        uint potIncrease = (newPutLocked + newCallLocked) - (putLocked + takerPos.callLockedCash);

        uint takerDelta = _calculateTakerDelta(startPrice, newPrice, putLocked, putDeviation);

        // fee is always smaller than taker delta
        fee = takerDelta * feePercent / BIPS_BASE;

        takerTransferOut = takerDelta - fee;

        providerTransferIn = potIncrease + takerTransferOut;
    }

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
        newPutLocked = putLocked * newPrice / startPrice;
        // use the method that will be used by taker NFT when opening
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
        uint putRange = BIPS_BASE - putDeviation;
        //        initialNotional = putLocked * BIPS_BASE / putRange;
        //        initialLoan = initialNotional * putDeviation / BIPS_BASE;
        uint initialLoan = putLocked * putDeviation / putRange;

        //        uint newLoan = initialLoan * newPrice / initialPrice;
        uint newLoan = putLocked * putDeviation * newPrice / startPrice / putRange;

        takerDelta = newLoan - initialLoan;
    }
}
