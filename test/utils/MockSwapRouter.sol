// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IV3SwapRouter } from "@uniswap/swap-router-contracts/contracts/interfaces/IV3SwapRouter.sol";

// mock for either a Router, or a Swapper
contract MockSwapperRouter {
    // mocking
    uint toReturn;
    uint toTransfer;

    function setupSwap(uint _toReturn, uint _toTransfer) external {
        toReturn = _toReturn;
        toTransfer = _toTransfer;
    }

    // mock router
    address public factory = address(1); // not zero, router interface

    function exactInputSingle(IV3SwapRouter.ExactInputSingleParams memory params)
        external
        returns (uint amountOut)
    {
        IERC20(params.tokenIn).transferFrom(msg.sender, address(this), params.amountIn);
        amountOut = toReturn;
        IERC20(params.tokenOut).transfer(params.recipient, toTransfer);
    }

    // mock swapper
    string public VERSION = "mock"; // swapper interface

    function swap(IERC20 assetIn, IERC20 assetOut, uint amountIn, uint minAmountOut, bytes calldata extraData)
        external
        returns (uint amountOut)
    {
        extraData;
        minAmountOut;
        assetIn.transferFrom(msg.sender, address(this), amountIn);
        amountOut = toReturn;
        assetOut.transfer(msg.sender, toTransfer);
    }
}
