// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test} from "@forge-std/Test.sol";
import {UniswapV3Mocks} from "../mocks/MockUniV3.sol";
import {IERC20} from "@oz-v4.9.3/token/ERC20/IERC20.sol";
import {console2} from "@forge-std/console2.sol";
import {UniswapV3Math} from "../libs/UniswapV3Lib.sol";
import {UniswapV3Utils} from "../libs/UniswapV3Lib.sol";
import {TestERC20} from "../mocks/TestERC20.sol";

contract UniswapUtilsTest is Test, UniswapV3Mocks {
    UniswapV3Mocks mocks;

    function setUp() public {
        mocks = new UniswapV3Mocks();
    }

    function test_PoolAddresses() public {
        address _computed_a_b_pool = UniswapV3Math.getComputedMediumFeePoolAddress(mocks.tokenA(), mocks.tokenB(), mocks.factory());
        address _computed_a_weth_pool = UniswapV3Math.getComputedMediumFeePoolAddress(mocks.tokenA(), mocks.weth(), mocks.factory());
        address _computed_b_weth_pool = UniswapV3Math.getComputedMediumFeePoolAddress(mocks.tokenB(), mocks.weth(), mocks.factory());

        assertEq(_computed_a_b_pool, mocks.pool_a_b_med_fee());
        assertEq(_computed_a_weth_pool, mocks.pool_a_weth_med_fee());
        assertEq(_computed_b_weth_pool, mocks.pool_b_weth_med_fee());
    }

    function test_exactInputSwaps() public {
        address _uniTest1 = makeAddr("UniTest1");

        uint256 amountIn = 1 ether;

        startHoax(_uniTest1);

        TestERC20(mocks.tokenA()).mint(100 ether);
        TestERC20(mocks.tokenB()).mint(100 ether);

        IERC20(mocks.tokenA()).approve(mocks.router(), 100_000 ether);
        IERC20(mocks.tokenB()).approve(mocks.router(), 100_000 ether);
        IERC20(mocks.weth()).approve(mocks.router(), 100_000 ether);

        uint256 balanceABefore = TestERC20(mocks.tokenA()).balanceOf(_uniTest1);
        uint256 balanceBBefore = TestERC20(mocks.tokenB()).balanceOf(_uniTest1);

        uint256 amountOut = UniswapV3Utils.swap(mocks.tokenA(), mocks.tokenB(), amountIn, mocks.router(), _uniTest1, UniswapV3Math.FEE_MEDIUM, true);

        uint256 balanceAAfter = TestERC20(mocks.tokenA()).balanceOf(_uniTest1);
        uint256 balanceBAfter = TestERC20(mocks.tokenB()).balanceOf(_uniTest1);

        assertEq(balanceABefore - balanceAAfter, amountIn, "amountIn (token a) incorrect");
        assertEq(balanceBAfter, balanceBBefore + amountOut, "amountOut (token b) incorrect");
    }
}
