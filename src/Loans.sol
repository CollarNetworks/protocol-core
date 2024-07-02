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

contract Loans is Ownable, Pausable {
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
    struct Loan {
        uint collateralAmount;
        uint loanAmount;
        address keeperAllowedBy;
        bool closed;
    }

    mapping(uint takerId => Loan) internal loans;

    // keeper for closing set by contract owner
    address public settlementKeeper;

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

    modifier onlyNFTOwner(uint takerId) {
        /// @dev will also revert on non-existent (unminted / burned) taker ID
        require(msg.sender == takerNFT.ownerOf(takerId), "not taker NFT owner");
        _;
    }

    modifier onlyNFTOwnerOrKeeper(uint takerId) {
        /// @dev will also revert on non-existent (unminted / burned) taker ID
        address currentTakerNFTOwner = takerNFT.ownerOf(takerId);
        bool isOwner = msg.sender == currentTakerNFTOwner;
        bool isKeeper = msg.sender == settlementKeeper;
        // if owner has changed since keeper was allowed by the owner, the allowance is disabled
        // to avoid selling an NFT with a keeper allowance, allowing keeper triggering for new buyer
        bool keeperAllowed = loans[takerId].keeperAllowedBy == currentTakerNFTOwner;
        require(isOwner || (isKeeper && keeperAllowed), "not taker NFT owner or allowed settlement keeper");
        _;
    }

    // ----- VIEW FUNCTIONS ----- //

    // @dev return memory struct (the default getter returns tuple)
    function getLoan(uint takerId) external view returns (Loan memory) {
        return loans[takerId];
    }

    // ----- STATE CHANGING FUNCTIONS ----- //

    function createLoan(
        uint collateralAmount,
        uint minLoanAmount,
        uint minSwapCash, // slippage control
        ProviderPositionNFT providerNFT,
        uint offerId // @dev implies specific provider, put & call deviations, duration
    )
        external
        whenNotPaused
        returns (uint takerId, uint providerId, uint loanAmount)
    {
        // pull collateral
        collateralAsset.safeTransferFrom(msg.sender, address(this), collateralAmount);

        // swap collateral
        // reentrancy assumptions: router is trusted + swap path is direct (not through multiple pools)
        uint cashFromSwap = _swapFromCollateral(collateralAmount, minSwapCash);

        uint putLockedCash;
        (loanAmount, putLockedCash) = _splitSwappedCash(cashFromSwap, providerNFT, offerId);
        require(loanAmount >= minLoanAmount, "loan amount too low");

        // approve the taker contract
        cashAsset.forceApprove(address(takerNFT), putLockedCash);

        // stores, mints, calls providerNFT and mints there, emits the event
        (takerId, providerId) = takerNFT.openPairedPosition(putLockedCash, providerNFT, offerId);

        // store the loan opening data
        loans[takerId] = Loan({
            collateralAmount: collateralAmount,
            loanAmount: loanAmount,
            keeperAllowedBy: address(0),
            closed: false
        });

        // transfer the full loan amount on open
        cashAsset.safeTransfer(msg.sender, loanAmount);

        // transfer the taker NFT to the user
        takerNFT.transferFrom(address(this), msg.sender, takerId);

        // TODO: event
    }

    /// @dev this stores the original sender, to avoid a hanging allowance for an NFT that
    /// has changed owners (was sold) exposing the new owner's approvals to the keeper
    /// @dev a user that sets this allowance has to also grant NFT and cash approvals to this contract
    function setKeeperAllowedBy(uint takerId, bool enabled) external onlyNFTOwner(takerId) {
        Loan storage loan = loans[takerId];
        _requireValidLoan(loan);
        loan.keeperAllowedBy = enabled ? msg.sender : address(0);
        // TODO: event
    }

    function closeLoan(
        uint takerId,
        uint minCollateralAmount
    )
        external
        onlyNFTOwnerOrKeeper(takerId)
        returns (uint collateralReturned)
    {
        // @dev user is the NFT owner, since msg.sender can be a keeper
        // If called by keeper, the user must trust them because:
        // - call pulls user funds (for repayment)
        // - call pulls the NFT (for settlement) from user
        // - call sends the final funds to the user
        // - keeper sets the slippage parameter
        address user = takerNFT.ownerOf(takerId);

        Loan storage loan = loans[takerId];
        _requireValidLoan(loan);
        loan.closed = true; // set here to add reentrancy protection

        // @dev assumes approval
        cashAsset.safeTransferFrom(user, address(this), loan.loanAmount);

        // set cashAmount to the loan that was repaid now
        uint cashAmount = loan.loanAmount;

        cashAmount += _settleAndWithdraw(takerId, user);

        collateralReturned = _swapCashToCollateral(cashAmount, minCollateralAmount);

        collateralAsset.safeTransfer(user, collateralReturned);

        // TODO: event
    }

    function setKeeper(address keeper) external onlyOwner {
        settlementKeeper = keeper;
        // TODO: event
    }

    // ----- INTERNAL MUTATIVE ----- //

    function _swapFromCollateral(
        uint collateralAmount,
        uint minCashAmount
    )
        internal
        returns (uint cashFromSwap)
    {
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
        _checkSwapPrice(cashFromSwap, collateralAmount);
    }

    function _swapCashToCollateral(
        uint cashAmount,
        uint minCollateralAmount
    )
        internal
        returns (uint collateralFromSwap)
    {
        // approve the dex router so we can swap the collateral to cash
        cashAsset.forceApprove(engine.univ3SwapRouter(), cashAmount);

        // build the swap transaction
        IV3SwapRouter.ExactInputSingleParams memory swapParams = IV3SwapRouter.ExactInputSingleParams({
            tokenIn: address(cashAsset),
            tokenOut: address(collateralAsset),
            fee: FEE_TIER_30_BIPS,
            recipient: address(this),
            amountIn: cashAmount,
            amountOutMinimum: minCollateralAmount,
            sqrtPriceLimitX96: 0
        });

        uint balanceBefore = collateralAsset.balanceOf(address(this));
        // reentrancy assumptions: router is trusted + swap path is direct (not through multiple pools)
        uint amountOutRouter = IV3SwapRouter(payable(engine.univ3SwapRouter())).exactInputSingle(swapParams);
        // Calculate the actual amount of cash received
        collateralFromSwap = collateralAsset.balanceOf(address(this)) - balanceBefore;
        // check balance is updated as expected and as reported by router (no other balance changes)
        // collateral-asset cannot be fee-on-transfer or rebasing (e.g., internal shares accounting)
        require(collateralFromSwap == amountOutRouter, "balance update mismatch");
        // check amount is as expected by user
        require(collateralFromSwap >= minCollateralAmount, "slippage exceeded");
    }

    function _settleAndWithdraw(uint takerId, address from) internal returns (uint withdrawnAmount) {
        // transfer the NFT to this contract so it can settle and withdraw
        // @dev owner must have approved the token ID to this contract to use it for settlement
        takerNFT.transferFrom(from, address(this), takerId);

        // position could have been settled by user or provider already
        CollarTakerNFT.TakerPosition memory takerPosition = takerNFT.getPosition(takerId);
        if (!takerPosition.settled) {
            /// @dev this will revert on:
            ///     not owner, too early, no position, calculation issues, ...
            takerNFT.settlePairedPosition(takerId);
            // update position struct
            takerPosition = takerNFT.getPosition(takerId);
        }

        /// @dev this should not be optional, since otherwise there is no point to the entire call
        /// (and the position NFT would be burned already, so would not belong to sender)
        withdrawnAmount = takerNFT.withdrawFromSettled(takerId, address(this));
    }

    // ----- INTERNAL VIEWS ----- //

    function _requireValidLoan(Loan storage loan) internal view {
        // no loan taken. Note that loanAmount 0 can happen for 0 putStrikePrice
        // so only collateral should be checked
        require(loan.collateralAmount != 0, "0 collateral amount");
        require(!loan.closed, "already closed");
    }

    /// The swap price is only used for "pot sizing", but not for payouts division on expiry.
    /// Due to this, price manipulation *should* NOT leak value from provider / protocol.
    /// The caller (user) is protected via a slippage parameter, and SHOULD use it to avoid MEV (if present).
    /// So, this check is just extra precaution and avoidance of manipulation edge-cases.
    function _checkSwapPrice(uint cashFromSwap, uint collateralAmount) internal view {
        uint twapPrice = _getTWAPPrice(block.timestamp);
        uint swapPrice = cashFromSwap * engine.TWAP_BASE_TOKEN_AMOUNT() / collateralAmount;
        uint diff = swapPrice > twapPrice ? swapPrice - twapPrice : twapPrice - swapPrice;
        uint deviation = diff * BIPS_BASE / twapPrice;
        require(deviation <= MAX_SWAP_TWAP_DEVIATION_BIPS, "swap and twap price too different");
    }

    function _getTWAPPrice(uint twapEndTime) internal view returns (uint price) {
        return engine.getHistoricalAssetPriceViaTWAP(
            address(collateralAsset), address(cashAsset), uint32(twapEndTime), TWAP_LENGTH
        );
    }

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
