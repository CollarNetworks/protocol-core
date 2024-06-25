// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity 0.8.21;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { IV3SwapRouter } from "@uniswap/swap-router-contracts/contracts/interfaces/IV3SwapRouter.sol";
// internal imports
import { LiquidityPositionNFT } from "./LiquidityPositionNFT.sol";
import { BaseGovernedNFT } from "./base/BaseGovernedNFT.sol";
import { CollarEngine } from "./implementations/CollarEngine.sol";
import { TickCalculations } from "./libs/TickCalculations.sol";

contract BorrowPositionNFT is BaseGovernedNFT {
    using SafeERC20 for IERC20;
    using SafeCast for uint;

    uint24 internal constant FEE_TIER_30_BIPS = 3000;
    uint internal constant BIPS_BASE = 10_000;

    uint32 public constant TWAP_LENGTH = 15 minutes;
    uint public constant MAX_SWAP_TWAP_DEVIATION_BIPS = 100;

    // ----- IMMUTABLES ----- //
    CollarEngine public immutable engine;
    IERC20 public immutable cashAsset;
    IERC20 public immutable collateralAsset;

    // ----- STATE VARIABLES ----- //
    // TODO: Consider trimming down this struct, since some of the fields aren't needed on-chain,
    //      and are stored for FE / usability since the assumption is that this is used on L2.
    struct BorrowPosition {
        LiquidityPositionNFT providerContract;
        uint providerPositionId;
        uint openedAt;
        uint expiration;
        uint initialPrice;
        uint putStrikePrice;
        uint callStrikePrice;
        uint collateralAmount;
        uint loanAmount;
        uint putLockedCash;
        uint callLockedCash;
        // withdrawal
        bool settled;
        uint withdrawable;
    }

    mapping(uint positionId => BorrowPosition) public positions;

    // ----- CONSTRUCTOR ----- //

    constructor(
        address initialOwner,
        CollarEngine _engine,
        IERC20 _cashAsset,
        IERC20 _collateralAsset,
        string memory _name,
        string memory _symbol
    )
        BaseGovernedNFT(initialOwner, _name, _symbol)
    {
        engine = _engine;
        cashAsset = _cashAsset;
        collateralAsset = _collateralAsset;
        // check params are supported
        validateConfig();
    }

    /// @dev used by openPosition, and can be used externally to check this is available
    function validateConfig() public view {
        require(engine.isSupportedCashAsset(address(cashAsset)), "unsupported asset");
        require(engine.isSupportedCollateralAsset(address(collateralAsset)), "unsupported asset");
    }

    // ----- VIEW FUNCTIONS ----- //

    // ----- STATE CHANGING FUNCTIONS ----- //
    function openPairedPosition(
        uint collateralAmount,
        uint minCashAmount, // slippage control
        LiquidityPositionNFT providerContract, // @dev implies ltv & put deviation, duration
        uint offerId // @dev imply specific offer with provider and strike price
            // TODO: optional user validation struct for ltv, expiry, put, call deviation
    )
        external
        whenNotPaused
        returns (uint borrowPositionId, uint providerPositionId, BorrowPosition memory borrowPosition)
    {
        _openPositionValidations(providerContract);

        // get TWAP price
        uint twapPrice = _getTWAPPrice(block.timestamp);

        // transfer and swap collateral first to handle reentrancy
        // TODO: double-check this actually handles it, or add a reentrancy guard
        uint cashFromSwap = _pullAndSwap(msg.sender, collateralAmount, minCashAmount);

        // @dev note that TWAP price is used for payout decision later, and swap price should
        // only affect the "pot sizing" (so does not affect the provider, only the borrower)
        _checkSwapPrice(twapPrice, cashFromSwap, collateralAmount);

        (borrowPosition, providerPositionId) =
            _openPositionInternal(twapPrice, collateralAmount, cashFromSwap, providerContract, offerId);

        borrowPositionId = nextTokenId++;
        // store position data
        positions[borrowPositionId] = borrowPosition;
        // mint the NFT to the sender
        // @dev does not use _safeMint to avoid reentrancy
        _mint(msg.sender, borrowPositionId);

        // transfer the full loan amount on open
        cashAsset.safeTransfer(msg.sender, borrowPosition.loanAmount);

        // TODO: event
    }

    function settlePairedPosition(uint borrowId) external whenNotPaused {
        BorrowPosition storage position = positions[borrowId];
        LiquidityPositionNFT providerNFT = position.providerContract;
        uint providerId = position.providerPositionId;

        require(position.openedAt != 0, "position doesn't exist");
        // access is restricted because NFT owners might want to cancel (unwind) instead
        require(
            msg.sender == ownerOf(borrowId) || msg.sender == providerNFT.ownerOf(providerId),
            "not owner of either position"
        );
        require(block.timestamp >= position.expiration, "not expired");
        require(!position.settled, "already settled");

        position.settled = true; // set here to prevent reentrancy

        // get settlement price
        uint endPrice = _getTWAPPrice(position.expiration);

        (uint withdrawable, int providerChange) = _settlementCalculations(position, endPrice);

        _settleProviderPosition(position, providerChange);

        // set withdrawable for user
        position.withdrawable = withdrawable;

        // TODO: event
    }

    function withdrawFromSettled(uint positionId, address recipient) external whenNotPaused {
        require(msg.sender == ownerOf(positionId), "not position owner");

        BorrowPosition storage position = positions[positionId];
        require(position.settled, "not settled");

        uint withdrawable = position.withdrawable;
        // zero out withdrawable
        position.withdrawable = 0;
        // burn token
        _burn(positionId);
        // transfer tokens
        cashAsset.safeTransfer(recipient, withdrawable);
        // TODO: emit event
    }

    function cancelPairedPosition(uint borrowId, address recipient) external whenNotPaused {
        require(msg.sender == ownerOf(borrowId), "not owner");

        BorrowPosition storage position = positions[borrowId];
        require(!position.settled, "already settled");
        position.settled = true; // set here to prevent reentrancy

        // burn token
        _burn(borrowId);

        // pull the provider NFT to this contract
        LiquidityPositionNFT providerNFT = position.providerContract;
        uint providerId = position.providerPositionId;
        // @dev msg.sender must be used (as always with transferFrom) to ensure token owner is calling,
        // otherwise broad (`..forAll`) approvals by providers can be used maliciously to cancel positions
        providerNFT.transferFrom(msg.sender, address(this), providerId);

        // now that this contract has provider NFT - cancel it and withdraw funds to sender
        providerNFT.cancelAndWithdraw(providerId, recipient);

        // transfer the tokens locked in this contract
        cashAsset.safeTransfer(recipient, position.putLockedCash);

        // TODO: emit event
    }

    // ----- INTERNAL MUTATIVE ----- //

    function _pullAndSwap(
        address sender,
        uint amountIn,
        uint minAmountOut
    )
        internal
        returns (uint amountReceived)
    {
        collateralAsset.safeTransferFrom(sender, address(this), amountIn);

        // approve the dex router so we can swap the collateral to cash
        collateralAsset.forceApprove(engine.dexRouter(), amountIn);

        // build the swap transaction
        IV3SwapRouter.ExactInputSingleParams memory swapParams = IV3SwapRouter.ExactInputSingleParams({
            tokenIn: address(collateralAsset),
            tokenOut: address(cashAsset),
            fee: FEE_TIER_30_BIPS,
            recipient: address(this),
            amountIn: amountIn,
            amountOutMinimum: minAmountOut,
            sqrtPriceLimitX96: 0
        });

        uint balanceBefore = cashAsset.balanceOf(address(this));
        uint amountOutRouter = IV3SwapRouter(payable(engine.dexRouter())).exactInputSingle(swapParams);
        // Calculate the actual amount of cash received
        amountReceived = cashAsset.balanceOf(address(this)) - balanceBefore;
        // check balance is updated as expected and as reported by router (no other balance changes)
        // cash-asset cannot be fee-on-transfer or rebasing (e.g., internal shares accounting)
        require(amountReceived == amountOutRouter, "balance update mismatch");
        // check amount is as expected by user
        require(amountReceived >= minAmountOut, "slippage exceeded");
    }

    function _openPositionInternal(
        uint twapPrice,
        uint collateralAmount,
        uint cashFromSwap,
        LiquidityPositionNFT providerContract,
        uint offerId
    )
        internal
        returns (BorrowPosition memory borrowPosition, uint providerPositionId)
    {
        uint loanAmount = cashFromSwap * providerContract.ltv() / BIPS_BASE;

        // open the provider position with duration and callLockedCash locked liquidity (reverts if can't)
        // and sends the provider NFT to the provider
        uint callStrikeDeviation = providerContract.getOffer(offerId).strikeDeviation;
        uint callLockedCash = (callStrikeDeviation - BIPS_BASE) * cashFromSwap / BIPS_BASE;
        (providerPositionId,) = providerContract.mintPositionFromOffer(offerId, callLockedCash);

        uint putStrikePrice = twapPrice * _putStrikeDeviation(providerContract) / BIPS_BASE;
        uint callStrikePrice = twapPrice * callStrikeDeviation / BIPS_BASE;
        // avoid boolean edge cases and division by zero when settling
        require(putStrikePrice < twapPrice && callStrikePrice > twapPrice, "strike prices aren't different");

        borrowPosition = BorrowPosition({
            providerContract: providerContract,
            providerPositionId: providerPositionId,
            openedAt: block.timestamp,
            expiration: providerContract.getPosition(providerPositionId).expiration,
            initialPrice: twapPrice,
            putStrikePrice: putStrikePrice,
            callStrikePrice: callStrikePrice,
            collateralAmount: collateralAmount,
            loanAmount: loanAmount,
            putLockedCash: cashFromSwap - loanAmount, // this assumes LTV === put strike price
            callLockedCash: callLockedCash,
            settled: false,
            withdrawable: 0
        });
    }

    function _settleProviderPosition(BorrowPosition storage position, int providerChange) internal {
        if (providerChange > 0) {
            cashAsset.forceApprove(address(position.providerContract), uint(providerChange));
        }

        position.providerContract.settlePosition(position.providerPositionId, providerChange);
    }

    // ----- INTERNAL VIEWS ----- //

    function _openPositionValidations(LiquidityPositionNFT providerContract) internal view {
        validateConfig();

        // check self (provider will check too)
        require(engine.isBorrowNFT(address(this)), "unsupported borrow contract");

        // check provider
        require(engine.isProviderNFT(address(providerContract)), "unsupported provider contract");
        // check assets match
        require(providerContract.collateralAsset() == collateralAsset, "asset mismatch");
        require(providerContract.cashAsset() == cashAsset, "asset mismatch");

        // checking LTV and duration (from provider contract) is redundant since provider contract
        // is trusted by user (passed in input), and trusted by engine (was checked vs. engine above)
    }

    function _getTWAPPrice(uint twapEndTime) internal view returns (uint price) {
        return engine.getHistoricalAssetPriceViaTWAP(
            address(collateralAsset), address(cashAsset), uint32(twapEndTime), TWAP_LENGTH
        );
    }

    /// TODO: establish if this is needed or not, since the swap price is only used for "pot sizing",
    ///     but not for pot division on expiry (initialPrice is twap price).
    ///     still makes sense as a precaution, as long as the deviation is not too restrictive.
    function _checkSwapPrice(uint twapPrice, uint cashFromSwap, uint collateralAmount) internal view {
        // TODO: sort out the mess with using or not using exact amounts / BASE_TOKEN_AMOUNT
        uint swapPrice = cashFromSwap * engine.BASE_TOKEN_AMOUNT() / collateralAmount;
        uint diff = swapPrice > twapPrice ? swapPrice - twapPrice : twapPrice - swapPrice;
        uint deviation = diff * BIPS_BASE / twapPrice;
        require(deviation <= MAX_SWAP_TWAP_DEVIATION_BIPS, "swap and twap price too different");
    }

    function _putStrikeDeviation(LiquidityPositionNFT providerContract) internal view returns (uint) {
        // LTV === put strike price currently (explicitly assigned here for clarity)
        return providerContract.ltv();
    }

    function _settlementCalculations(
        BorrowPosition storage position,
        uint endPrice
    )
        internal
        view
        returns (uint withdrawable, int providerChange)
    {
        uint startPrice = position.initialPrice;
        uint putPrice = position.putStrikePrice;
        uint callPrice = position.callStrikePrice;

        // restrict endPrice to put-call range
        endPrice = endPrice < putPrice ? putPrice : endPrice;
        endPrice = endPrice > callPrice ? callPrice : endPrice;

        withdrawable = position.putLockedCash;
        if (endPrice < startPrice) {
            // put range: divide between user and LP, call range: goes to LP
            uint lpPart = startPrice - endPrice;
            uint putRange = startPrice - putPrice;
            uint lpGain = position.putLockedCash * lpPart / putRange; // no div-zero ensured on open
            withdrawable -= lpGain;
            providerChange = lpGain.toInt256();
        } else {
            // put range: goes to user, call range: divide between user and LP
            uint userPart = endPrice - startPrice;
            uint callRange = callPrice - startPrice;
            uint userGain = position.callLockedCash * userPart / callRange; // no div-zero ensured on open
            withdrawable += userGain;
            providerChange = -userGain.toInt256();
        }
    }
}
