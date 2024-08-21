// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

import "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { TestERC20 } from "../utils/TestERC20.sol";

import { SwapperUniV3Direct, IPeripheryImmutableState } from "../../src/SwapperUniV3Direct.sol";
import { MockSwapRouter } from "../utils/MockSwapRouter.sol";

contract SwapperUniV3DirectTest is Test {
    SwapperUniV3Direct public swapper;
    MockSwapRouter public mockRouter;

    uint24 feeTier = 3000;

    TestERC20 tokenIn;
    TestERC20 tokenOut;

    uint amountIn = 1000;
    uint amountOut = 900;
    uint minAmountOut = 800;

    function setUp() public {
        mockRouter = new MockSwapRouter();
        swapper = new SwapperUniV3Direct(address(mockRouter), feeTier);

        tokenIn = new TestERC20("Mock Token In", "MTI");
        tokenOut = new TestERC20("Mock Token Out", "MTO");
    }

    function setupSwap(uint _amountIn, uint _amountOut) internal {
        tokenIn.mint(address(this), _amountIn);
        tokenOut.mint(address(mockRouter), _amountOut);

        tokenIn.approve(address(swapper), _amountIn);

        mockRouter.setAmountToReturn(_amountOut);
        mockRouter.setTransferAmount(_amountOut);
    }

    // effects

    function test_constructor() public {
        swapper = new SwapperUniV3Direct(address(mockRouter), feeTier);
        assertEq(swapper.VERSION(), "0.2.0");
        assertEq(address(swapper.uniV3SwapRouter()), address(mockRouter));
        assertEq(swapper.swapFeeTier(), feeTier);

        // all supported fee tiers
        new SwapperUniV3Direct(address(mockRouter), 100);
        new SwapperUniV3Direct(address(mockRouter), 500);
        new SwapperUniV3Direct(address(mockRouter), 3000);
        new SwapperUniV3Direct(address(mockRouter), 10_000);
    }

    function test_swap() public {
        setupSwap(amountIn, amountOut);
        uint returnedAmount = swapper.swap(tokenIn, tokenOut, amountIn, minAmountOut, "");
        assertEq(returnedAmount, amountOut);

        // min amount
        setupSwap(amountIn, amountOut);
        returnedAmount = swapper.swap(tokenIn, tokenOut, amountIn, minAmountOut, "");
        assertEq(returnedAmount, amountOut);
    }

    // reverts

    function test_revert_constructor() public {
        vm.expectRevert(new bytes(0));
        new SwapperUniV3Direct(address(0), feeTier);

        // invalid 0 address return
        vm.mockCall(
            address(mockRouter),
            abi.encodeCall(IPeripheryImmutableState.factory, ()),
            abi.encode(address(0)) // zero
        );
        vm.expectRevert("invalid router");
        new SwapperUniV3Direct(address(mockRouter), feeTier);
        vm.clearMockedCalls();

        vm.expectRevert("invalid fee tier");
        new SwapperUniV3Direct(address(mockRouter), 1234);
    }

    function test_revert_swap_slippageExceeded() public {
        setupSwap(amountIn, minAmountOut);
        vm.expectRevert("slippage exceeded");
        swapper.swap(tokenIn, tokenOut, amountIn, minAmountOut + 1, "");
    }

    function test_revert_swap_balanceUpdateMismatch() public {
        setupSwap(amountIn, amountOut);
        mockRouter.setTransferAmount(amountOut - 1); // Simulate a balance mismatch

        vm.expectRevert("balance update mismatch");
        swapper.swap(tokenIn, tokenOut, amountIn, minAmountOut, "");
    }
}
