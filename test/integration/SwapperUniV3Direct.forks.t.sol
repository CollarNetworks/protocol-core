// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

import "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SwapperUniV3Direct } from "../../src/SwapperUniV3Direct.sol";

contract SwapperUniV3Direct_USDCWETH_ForkTest is Test {
    SwapperUniV3Direct public swapper;

    address router = 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;
    uint24 feeTier = 500;

    address tokenIn;
    address tokenOut;
    uint amountIn;
    uint expectedAmountOut;

    function setUp() public virtual {
        vm.createSelectFork(vm.envString("ARBITRUM_MAINNET_RPC"), 242_273_401);
        _setUp();
        deal(tokenIn, address(this), amountIn);
        swapper = new SwapperUniV3Direct(router, feeTier);
    }

    function _setUp() internal virtual {
        tokenIn = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1; // WETH
        tokenOut = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831; // USDC
        amountIn = 1 ether;
        expectedAmountOut = 2_712_591_287;
    }

    function test_constructor() public {
        swapper = new SwapperUniV3Direct(router, feeTier);
        assertEq(swapper.VERSION(), "0.2.0");
        assertEq(address(swapper.uniV3SwapRouter()), router);
        assertEq(swapper.swapFeeTier(), feeTier);
    }

    function test_swap() public {
        IERC20(tokenIn).approve(address(swapper), amountIn);

        uint amountOut = swapper.swap(IERC20(tokenIn), IERC20(tokenOut), amountIn, expectedAmountOut, "");

        assertEq(amountOut, expectedAmountOut);
    }

    function test_swap_slippage() public {
        IERC20(tokenIn).approve(address(swapper), amountIn);

        // this revert is from Uniswap Router - not from swapper
        vm.expectRevert("Too little received");
        swapper.swap(IERC20(tokenIn), IERC20(tokenOut), amountIn, expectedAmountOut + 1, "");
    }
}

contract SwapperUniV3Direct_WETHUSDC_ForkTest is SwapperUniV3Direct_USDCWETH_ForkTest {
    function _setUp() internal override {
        super._setUp();
        (tokenIn, tokenOut) = (tokenOut, tokenIn); // Swap USDC and WETH
        amountIn = 2_712_591_287; // 1 ETH worth of USDC
        expectedAmountOut = 998_961_362_164_977_913; // 0.998 ETH
    }
}
