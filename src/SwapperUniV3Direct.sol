// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity 0.8.22;

import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IV3SwapRouter } from "@uniswap/swap-router-contracts/contracts/interfaces/IV3SwapRouter.sol";
import { BaseEmergencyAdmin, ConfigHub } from "./base/BaseEmergencyAdmin.sol";
import { ISwapper } from "./interfaces/ISwapper.sol";

contract SwapperUniV3Direct is BaseEmergencyAdmin, ISwapper {
    using SafeERC20 for IERC20;

    uint24 internal constant INITIAL_FEE_TIER = 500;

    string public constant VERSION = "0.2.0";

    // ----- State ----- //
    uint24 public swapFeeTier = INITIAL_FEE_TIER;

    // ----- Events ----- //
    event SwapFeeTierUpdated(uint24 indexed previousFeeTier, uint24 indexed newFeeTier);

    /// @dev BaseEmergencyAdmin is used for it's ownable, token rescue, and configHub features.
    constructor(address initialOwner, ConfigHub _configHub) BaseEmergencyAdmin(initialOwner) {
        _setConfigHub(_configHub);
        // assumes that 500 is supported b Uniswap V3 which is a safe assumption (see setSwapFeeTier())
        swapFeeTier = INITIAL_FEE_TIER;
    }

    // ----- Owner mutative ----- //

    /// @notice Sets the fee tier to use for swaps
    /// @dev only owner
    function setSwapFeeTier(uint24 newFeeTier) external onlyOwner {
        // @dev The most precise check would be to check via factory's feeAmountTickSpacing():
        //      require(IUniswapV3Factory(factory).feeAmountTickSpacing(newFeeTier) != 0, .. );
        // KISS is fine here: known tiers aren't likely to change, and swappers can easily be replaced.
        require(
            newFeeTier == 100 || newFeeTier == 500 || newFeeTier == 3000 || newFeeTier == 10_000,
            "invalid fee tier"
        );
        emit SwapFeeTierUpdated(swapFeeTier, newFeeTier);
        swapFeeTier = newFeeTier;
    }

    // ----- Mutative ----- //

    // TODO: docs
    function swap(IERC20 assetIn, IERC20 assetOut, uint amountIn, uint minAmountOut, bytes calldata extraData)
        external
        whenNotPaused
        returns (uint amountOut)
    {
        // unused in this swapper
        // extraData should be used in swappers which expect more off-chain input, such as routes
        extraData;

        assetIn.safeTransferFrom(msg.sender, address(this), amountIn);

        uint balanceBefore = assetOut.balanceOf(address(this));

        IV3SwapRouter uniV3SwapRouter = IV3SwapRouter(payable(configHub.uniV3SwapRouter()));

        // approve router
        assetIn.forceApprove(address(uniV3SwapRouter), amountIn);

        // reentrancy assumptions: router is trusted + swap path is direct (not through multiple pools).
        // @dev This swapper is safe from reentrancy under the assumption of trusted router and tokens.
        // However, in general a multi-hop swap route (via more flexible routers) can allow reentrancy via
        // malicious tokens in the route path. Therefore, this direct router is safer to allow-list than
        // more flexible routers.
        uint amountOutRouter = uniV3SwapRouter.exactInputSingle(
            IV3SwapRouter.ExactInputSingleParams({
                tokenIn: address(assetIn),
                tokenOut: address(assetOut),
                fee: swapFeeTier,
                recipient: address(this),
                amountIn: amountIn,
                amountOutMinimum: minAmountOut,
                sqrtPriceLimitX96: 0
            })
        );

        // Calculate the actual amount received
        amountOut = assetOut.balanceOf(address(this)) - balanceBefore;
        // check balance is updated as expected and as reported by router (no other balance changes)
        // asset cannot be fee-on-transfer or rebasing (e.g., internal shares accounting)
        require(amountOut == amountOutRouter, "balance update mismatch");
        // check amount is as expected by caller
        require(amountOut >= minAmountOut, "slippage exceeded");

        assetOut.safeTransfer(msg.sender, amountOut);
    }
}
