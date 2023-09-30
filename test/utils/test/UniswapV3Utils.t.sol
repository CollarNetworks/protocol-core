// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test} from "@forge-std/Test.sol";
import {UniswapV3Mocks} from "../UniswapV3Utils.sol";
import {IERC20} from "@oz-v4.9.3/token/ERC20/IERC20.sol";
import {console2} from "@forge-std/console2.sol";

contract UniswapUtilsTest is Test, UniswapV3Mocks {
    function setUp() public override {
        super.setUp();
    }

    function test_PoolAddresses() public {
        address _computed_a_b_pool = getComputedPoolAddress(mockUni.tokenA, mockUni.tokenB, mockUni.factory);
        address _computed_a_weth_pool = getComputedPoolAddress(mockUni.tokenA, mockUni.weth, mockUni.factory);
        address _computed_b_weth_pool = getComputedPoolAddress(mockUni.tokenB, mockUni.weth, mockUni.factory);

        assertEq(_computed_a_b_pool, mockUni.pool_a_b);
        assertEq(_computed_a_weth_pool, mockUni.pool_a_weth);
        assertEq(_computed_b_weth_pool, mockUni.pool_b_weth);
    }

    function test_exactInputSwaps() public {
        address _uniTest1 = makeAddr("UniTest1");

        uint256 amountIn = 1 ether;

        startHoax(_uniTest1);

        deal(mockUni.tokenA, _uniTest1, 100 ether);
        deal(mockUni.tokenB, _uniTest1, 100 ether);

        IERC20(mockUni.tokenA).approve(mockUni.router, 100_000 ether);
        IERC20(mockUni.tokenB).approve(mockUni.router, 100_000 ether);
        IERC20(mockUni.weth).approve(mockUni.router, 100_000 ether);

        uint256 balanceABefore = IERC20(mockUni.tokenA).balanceOf(_uniTest1);
        uint256 balanceBBefore = IERC20(mockUni.tokenB).balanceOf(_uniTest1);

        uint256 amountOut = doExactInputSwap(mockUni.tokenA, mockUni.tokenB, amountIn, mockUni.router, _uniTest1);

        uint256 balanceAAfter = IERC20(mockUni.tokenA).balanceOf(_uniTest1);
        uint256 balanceBAfter = IERC20(mockUni.tokenB).balanceOf(_uniTest1);

        assertEq(balanceABefore - balanceAAfter, amountIn, "amountIn (token a) incorrect");
        assertEq(balanceBAfter, balanceBBefore + amountOut, "amountOut (token b) incorrect");
    }
}
