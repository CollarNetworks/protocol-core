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
        uint feePercent,
        ProviderPositionNFT providerNFT,
        uint providerId
    )
        external
        whenNotPaused
        returns (uint rollId)
    {
        // auth
        require(msg.sender == providerNFT.ownerOf(providerId), "not provider ID owner");
        // fee is valid
        require(feePercent <= MAX_FEE_PERCENT_BIPS, "fee percent too high");

        // position is valid
        CollarTakerNFT.TakerPosition memory takerPos = takerNFT.getPosition(takerId);
        require(takerPos.openedAt != 0, "taker position doesn't exist");
        require(!takerPos.settled, "taker position settled");

        // prices are valid
        uint currentPrice = takerNFT.getReferenceTWAPPrice(block.timestamp);
        require(currentPrice >= takerPos.initialPrice, "price is lower than initial");
        require(maxPrice >= takerPos.initialPrice, "max price lower than initial");

        ProviderPositionNFT.ProviderPosition memory providerPos =
            takerPos.providerNFT.getPosition(takerPos.providerPositionId);
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

    function cancelOffer(uint rollId) external whenNotPaused {
        RollOffer storage offer = rollOffers[rollId];
        require(msg.sender == offer.provider, "not initial provider");
        // cancel offer
        offer.active = false;
        // return the NFT
        offer.providerNFT.transferFrom(address(this), msg.sender, offer.providerId);
        // TODO event
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
        returns (uint providerTransfer, uint takerTransfer, uint fee)
    {
        uint putLocked = takerPos.putLockedCash;
        uint putDeviation = providerPos.putStrikeDeviation;
        uint callDeviation = providerPos.callStrikeDeviation;

        (uint newPutLocked, uint newCallLocked) =
            _newLockedAmounts(startPrice, newPrice, putLocked, putDeviation, callDeviation);

        uint potIncrease = (newPutLocked + newCallLocked) - (putLocked + takerPos.callLockedCash);

        takerTransfer = _calculateTakerTransfer(startPrice, newPrice, putLocked, putDeviation);

        fee = takerTransfer * feePercent / BIPS_BASE;

        providerTransfer = potIncrease + takerTransfer - fee;
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

    function _calculateTakerTransfer(
        uint startPrice,
        uint newPrice,
        uint putLocked,
        uint putDeviation
    )
        internal
        pure
        returns (uint takerTransfer)
    {
        uint putRange = BIPS_BASE - putDeviation;
        //        initialNotional = putLocked * BIPS_BASE / putRange;
        //        initialLoan = initialNotional * putDeviation / BIPS_BASE;
        uint initialLoan = putLocked * putDeviation / putRange;

        //        uint newLoan = initialLoan * newPrice / initialPrice;
        uint newLoan = putLocked * putDeviation * newPrice / startPrice / putRange;

        takerTransfer = newLoan - initialLoan;
    }
}
