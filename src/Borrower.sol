// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity 0.8.22;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IV3SwapRouter } from "@uniswap/swap-router-contracts/contracts/interfaces/IV3SwapRouter.sol";
// internal imports
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { CollarEngine } from "./implementations/CollarEngine.sol";
import { CollarTakerNFT } from "./CollarTakerNFT.sol";
import { ProviderPositionNFT } from "./ProviderPositionNFT.sol";

contract Borrower is Ownable, Pausable {
    using SafeERC20 for IERC20;

    uint24 internal constant FEE_TIER_30_BIPS = 3000;
    uint internal constant BIPS_BASE = 10_000;

    uint32 public constant TWAP_LENGTH = 15 minutes;
    /// should be set to not be overly restrictive since is mostly sanity-check
    uint public constant MAX_SWAP_TWAP_DEVIATION_BIPS = 100;

    string public constant VERSION = "0.2.0"; // allow checking version on-chain

    // ----- IMMUTABLES ----- //
    CollarEngine public immutable engine;
    CollarTakerNFT public immutable takerNFT;
    IERC20 public immutable cashAsset;
    IERC20 public immutable collateralAsset;

    // ----- STATE VARIABLES ----- //
    struct Borrow{
        uint collateralAmount;
        uint loanAmount;
    }
    mapping(uint takerId => Borrow) internal borrows;

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
        // check params are supported
        _validateConfigSupported();
    }

    // ----- VIEW FUNCTIONS ----- //

    // @dev return memory struct (the default getter returns tuple)
    function getBorrow(uint takerId) external view returns (Borrow memory) {
        return borrows[takerId];
    }

    function getOwner(uint takerId) public view returns (address) {
        return takerNFT.ownerOf(takerId);
    }

    // ----- STATE CHANGING FUNCTIONS ----- //

    function borrow(
        uint collateralAmount,
        uint minCashAmount, // slippage control
        ProviderPositionNFT providerNFT,
        uint offerId // @dev implies specific provider, put & call deviations, duration
    )
        external
        whenNotPaused
        returns (uint takerId, uint providerId, uint loanAmount)
    {
        uint twapPrice = _getTWAPPrice(block.timestamp);

        // transfer and swap collateral
        // reentrancy assumptions: router is trusted + swap path is direct (not through multiple pools)
        uint cashFromSwap = _pullAndSwap(msg.sender, collateralAmount, minCashAmount, twapPrice);

        uint putLockedCash;
        (loanAmount, putLockedCash) = _splitSwappedCash(cashFromSwap, providerNFT, offerId);

        // approve the taker contract
        cashAsset.forceApprove(address(takerNFT), putLockedCash);

        // stores, mints, calls providerNFT and mints there, emits the event
        (takerId, providerId) = takerNFT.openPairedPosition(putLockedCash, providerNFT, offerId);

        // store the borrow opening data
        borrows[takerId] = Borrow({
            collateralAmount : collateralAmount,
            loanAmount : loanAmount
        });

        // transfer the full loan amount on open
        cashAsset.safeTransfer(msg.sender, loanAmount);

        // transfer the taker NFT to the user
        takerNFT.transferFrom(address(this), msg.sender, takerId);

        // TODO: event
    }

    // ----- INTERNAL MUTATIVE ----- //

    function _pullAndSwap(
        address sender,
        uint collateralAmount,
        uint minCashAmount,
        uint twapPrice
    )
        internal
        returns (uint cashFromSwap)
    {
        collateralAsset.safeTransferFrom(sender, address(this), collateralAmount);

        // approve the dex router so we can swap the collateral to cash
        collateralAsset.forceApprove(engine.univ3SwapRouter(), collateralAmount);

        // build the swap transaction
        IV3SwapRouter.ExactInputSingleParams memory swapParams = IV3SwapRouter.ExactInputSingleParams({
            tokenIn: address(collateralAsset),
            tokenOut: address(cashAsset),
            fee: FEE_TIER_30_BIPS,
            recipient: address(this),
            amountIn: collateralAmount,
            amountOutMinimum: minCashAmount,
            sqrtPriceLimitX96: 0
        });

        uint balanceBefore = cashAsset.balanceOf(address(this));
        // reentrancy assumptions: router is trusted + swap path is direct (not through multiple pools)
        uint amountOutRouter = IV3SwapRouter(payable(engine.univ3SwapRouter())).exactInputSingle(swapParams);
        // Calculate the actual amount of cash received
        cashFromSwap = cashAsset.balanceOf(address(this)) - balanceBefore;
        // check balance is updated as expected and as reported by router (no other balance changes)
        // cash-asset cannot be fee-on-transfer or rebasing (e.g., internal shares accounting)
        require(cashFromSwap == amountOutRouter, "balance update mismatch");
        // check amount is as expected by user
        require(cashFromSwap >= minCashAmount, "slippage exceeded");

        // @dev note that only TWAP price is used for payout decision later, and swap price should
        // only affect the "pot sizing" (so does not affect the provider, only the taker)
        _checkSwapPrice(twapPrice, cashFromSwap, collateralAmount);
    }

    // ----- INTERNAL VIEWS ----- //

    function _validateConfigSupported() internal view {
        require(engine.isSupportedCashAsset(address(cashAsset)), "unsupported asset");
        require(engine.isSupportedCollateralAsset(address(collateralAsset)), "unsupported asset");
        require(engine.isCollarTakerNFT(address(takerNFT)), "unsupported taker NFT");
    }

    function _getTWAPPrice(uint twapEndTime) internal view returns (uint price) {
        return engine.getHistoricalAssetPriceViaTWAP(
            address(collateralAsset), address(cashAsset), uint32(twapEndTime), TWAP_LENGTH
        );
    }

    /// The swap price is only used for "pot sizing", but not for payouts division on expiry.
    /// Due to this, price manipulation *should* NOT leak value from provider / protocol.
    /// The caller (user) is protected via a slippage parameter, and SHOULD use it to avoid MEV (if present).
    /// So, this check is just extra precaution and avoidance of manipulation edge-cases.
    function _checkSwapPrice(uint twapPrice, uint cashFromSwap, uint collateralAmount) internal view {
        uint swapPrice = cashFromSwap * engine.TWAP_BASE_TOKEN_AMOUNT() / collateralAmount;
        uint diff = swapPrice > twapPrice ? swapPrice - twapPrice : twapPrice - swapPrice;
        uint deviation = diff * BIPS_BASE / twapPrice;
        require(deviation <= MAX_SWAP_TWAP_DEVIATION_BIPS, "swap and twap price too different");
    }

    // calculations

    function _splitSwappedCash(
        uint cashFromSwap,
        ProviderPositionNFT providerNFT,
        uint offerId
    )
        internal
        view
        returns (uint loanAmount, uint putLockedCash)
    {
        uint putStrikeDeviation = providerNFT.getOffer(offerId).putStrikeDeviation;
        // this assumes LTV === put strike price
        loanAmount = putStrikeDeviation * cashFromSwap / BIPS_BASE;
        // everything that remains is locked on the put side
        putLockedCash = cashFromSwap - loanAmount;
    }

}
