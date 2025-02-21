// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

import "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { TestERC20 } from "../utils/TestERC20.sol";

import { SwapperUniV3, IPeripheryImmutableState } from "../../src/SwapperUniV3.sol";
import { MockSwapperRouter } from "../utils/MockSwapRouter.sol";

contract SwapperUniV3Test is Test {
    SwapperUniV3 public swapper;
    MockSwapperRouter public mockRouter;

    uint24 feeTier = 3000;

    TestERC20 tokenIn;
    TestERC20 tokenOut;

    uint amountIn = 1000;
    uint amountOut = 900;
    uint minAmountOut = 800;

    function setUp() public {
        mockRouter = new MockSwapperRouter();
        swapper = new SwapperUniV3(address(mockRouter), feeTier);

        tokenIn = new TestERC20("Mock Token In", "MTI", 18);
        tokenOut = new TestERC20("Mock Token Out", "MTO", 18);
    }

    function setupSwap(uint _amountIn, uint _amountOut) internal {
        tokenIn.mint(address(this), _amountIn);
        tokenOut.mint(address(mockRouter), _amountOut);
        tokenIn.approve(address(swapper), _amountIn);
        mockRouter.setupSwap(_amountOut, _amountOut);
    }

    // effects

    function test_constructor() public {
        swapper = new SwapperUniV3(address(mockRouter), feeTier);
        assertEq(swapper.VERSION(), "0.2.0");
        assertEq(address(swapper.uniV3SwapRouter()), address(mockRouter));
        assertEq(swapper.swapFeeTier(), feeTier);

        // all supported fee tiers
        new SwapperUniV3(address(mockRouter), 100);
        new SwapperUniV3(address(mockRouter), 500);
        new SwapperUniV3(address(mockRouter), 3000);
        new SwapperUniV3(address(mockRouter), 10_000);
    }

    function test_swap() public {
        setupSwap(amountIn, amountOut);
        uint balanceInBefore = tokenIn.balanceOf(address(this));
        uint balanceOutBefore = tokenOut.balanceOf(address(this));
        uint returnedAmount = swapper.swap(tokenIn, tokenOut, amountIn, minAmountOut, "");
        assertEq(returnedAmount, amountOut);
        assertEq(tokenOut.balanceOf(address(this)) - balanceOutBefore, amountOut);
        assertEq(balanceInBefore - tokenIn.balanceOf(address(this)), amountIn);
    }

    // reverts

    function test_revert_constructor() public {
        vm.expectRevert(new bytes(0));
        new SwapperUniV3(address(0), feeTier);

        // invalid 0 address return
        vm.mockCall(
            address(mockRouter),
            abi.encodeCall(IPeripheryImmutableState.factory, ()),
            abi.encode(address(0)) // zero
        );
        vm.expectRevert("invalid router");
        new SwapperUniV3(address(mockRouter), feeTier);
        vm.clearMockedCalls();

        vm.expectRevert("invalid fee tier");
        new SwapperUniV3(address(mockRouter), 1234);
    }

    function test_revert_swap_slippageExceeded() public {
        setupSwap(amountIn, minAmountOut);
        vm.expectRevert("SwapperUniV3: slippage exceeded");
        swapper.swap(tokenIn, tokenOut, amountIn, minAmountOut + 1, "");
    }

    function test_revert_swap_balanceUpdateMismatch() public {
        setupSwap(amountIn, amountOut);
        mockRouter.setupSwap(amountOut, amountOut - 1); // Simulate a balance mismatch

        vm.expectRevert("SwapperUniV3: balance update mismatch");
        swapper.swap(tokenIn, tokenOut, amountIn, minAmountOut, "");
    }
}
