// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IV3SwapRouter } from "@uniswap/swap-router-contracts/contracts/interfaces/IV3SwapRouter.sol";
import { IPeripheryImmutableState } from
    "@uniswap/v3-periphery/contracts/interfaces/IPeripheryImmutableState.sol";
import { ISwapper } from "./interfaces/ISwapper.sol";

/**
 * @notice Unowned simple contract that swaps tokens in a direct route via UniswapV3.
 * @custom:security-contact security@collarprotocol.xyz
 *
 * Post-Deployment Configuration:
 * - LoansNFT: Add to allowed swappers if asset pair's liquidity for this fee tier is adequate
 */
contract SwapperUniV3 is ISwapper {
    using SafeERC20 for IERC20;

    string public constant VERSION = "0.2.0";

    IV3SwapRouter public immutable uniV3SwapRouter;
    uint24 public immutable swapFeeTier;

    /**
     * @param _uniV3SwapRouter The address of the Uniswap V3 router.
     * @param _feeTier The fee tier to be used for swaps. Must be one of 100, 500, 3000, or 10000.
     * Note that 100 may not be supported on all networks.
     */
    constructor(address _uniV3SwapRouter, uint24 _feeTier) {
        // sanity check router
        require(IPeripheryImmutableState(_uniV3SwapRouter).factory() != address(0), "invalid router");
        // @dev The most precise check would be to check via factory's feeAmountTickSpacing():
        //      require(IUniswapV3Factory(factory).feeAmountTickSpacing(newFeeTier) != 0, .. );
        // KISS is fine here: known tiers aren't likely to change, and swappers can easily be replaced.
        // Note that additional fee tiers are available on some chains (e.g., on Base).
        require(
            _feeTier == 100 || _feeTier == 500 || _feeTier == 3000 || _feeTier == 10_000, "invalid fee tier"
        );
        uniV3SwapRouter = IV3SwapRouter(payable(_uniV3SwapRouter));
        swapFeeTier = _feeTier;
    }

    /**
     * @notice Swaps a specified amount of one token for another via a direct Uniswap V3 route with
     * the configured fee tier using `exactInputSingle`.
     * @dev This function assumes that as long as the swap router and the two tokens involved
     * are non-malicious and don't allow reentrancy, reentrancy is not possible, because the route is direct.
     * Additional checks:
     *  - The output of the router is checked to correspond exactly to the balance change.
     *  - A slippage check vs. minAmountOut.
     * @param assetIn ERC20 token being swapped from.
     * @param assetOut ERC20 token being swapped to.
     * @param amountIn The amount of `assetIn` to swap. @dev Must not be 0, otherwise will revert.
     * @param minAmountOut The minimum amount of `assetOut` to accept, limiting slippage.
     * @param extraData Arbitrary bytes data (unused in this contract) that are part of ISwapper interface
     * for more complex integrations in other implementations.
     * @return amountOut The actual amount of `assetOut` received from the swap.
     */
    function swap(IERC20 assetIn, IERC20 assetOut, uint amountIn, uint minAmountOut, bytes calldata extraData)
        external
        returns (uint amountOut)
    {
        // unused in this swapper
        // extraData should be used in swappers which expect more off-chain input, such as routes.
        // While `extraData` can be used to pass swapFeeTier, this implementation is intended to be
        // maximally constrained, to reduce the surface area for user and keeper mistakes
        extraData;

        // pull funds (assumes approval from caller)
        assetIn.safeTransferFrom(msg.sender, address(this), amountIn);
        // approve router to pull.
        // @dev dangling approval (and balance) can remain if assetIn is WETH and router has ETH balance
        assetIn.forceApprove(address(uniV3SwapRouter), amountIn);

        // swap `recipient` is msg.sender, so its balance update is checked
        uint senderBalanceBefore = assetOut.balanceOf(msg.sender);
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
                recipient: msg.sender,
                amountIn: amountIn, // @dev must not be 0
                amountOutMinimum: minAmountOut,
                sqrtPriceLimitX96: 0
            })
        );
        // actual amount received by the sender (`recipient` in the swap params above)
        amountOut = assetOut.balanceOf(msg.sender) - senderBalanceBefore;

        // Check balance is updated as expected and as reported by router (no other balance changes)
        // asset cannot be fee-on-transfer or rebasing (e.g., internal shares accounting).
        // This also checks that router behaves as we expect, to prevent misconfiguration or
        // incorrect assumptions about its implementation
        require(amountOut == amountOutRouter, "SwapperUniV3: balance update mismatch");
        // check amount is as expected by caller
        require(amountOut >= minAmountOut, "SwapperUniV3: slippage exceeded");
    }
}
