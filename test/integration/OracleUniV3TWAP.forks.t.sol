// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

import "forge-std/Test.sol";

import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import { IUniswapV3Factory } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import { INonfungiblePositionManager } from
    "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";

import { CollarOwnedERC20 } from "../utils/CollarOwnedERC20.sol";

import { OracleUniV3TWAP } from "../../src/OracleUniV3TWAP.sol";

contract OracleUniV3TWAP_USDCWETH_ForkTest is Test {
    OracleUniV3TWAP public oracle;

    address router = 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;
    address factory = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    uint24 feeTier = 500;

    uint32 twapWindow = 300;

    // setup for particular test class
    address baseToken;
    address quoteToken;
    address pool;

    // test values
    uint expectedCurPrice;
    uint expectedPriceTwapWindowAgo;
    uint16 expectedCardinality;

    // old factory, so reverts with require(, 'OLD') instead of custom error as in newer implementations
    // https://arbiscan.io/address/0xC6962004f452bE9203591991D15f6b388e09E8D0#code#F9#L226
    bytes revertBytesOLD = bytes("OLD");

    function setUp() public {
        vm.createSelectFork(vm.envString("ARBITRUM_MAINNET_RPC"), 242_273_401);
        _setUp();
        oracle = new OracleUniV3TWAP(baseToken, quoteToken, feeTier, twapWindow, router);
    }

    function _setUp() internal virtual {
        baseToken = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1; // WETH
        quoteToken = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831; // USDC
        pool = 0xC6962004f452bE9203591991D15f6b388e09E8D0;

        expectedCardinality = 8000;
        expectedCurPrice = 2_713_263_289; // 2713 USDC per 1 ETH
        expectedPriceTwapWindowAgo = 2_720_326_598;
    }

    // effects tests

    function test_constructor() public {
        oracle = new OracleUniV3TWAP(baseToken, quoteToken, feeTier, twapWindow, router);
        assertEq(oracle.VERSION(), "0.2.0");
        assertEq(oracle.MIN_TWAP_WINDOW(), 300);
        assertEq(oracle.baseToken(), baseToken);
        assertEq(oracle.quoteToken(), quoteToken);
        assertEq(oracle.feeTier(), feeTier);
        assertEq(oracle.twapWindow(), twapWindow);
        assertEq(address(oracle.pool()), pool);
    }

    function test_currentCardinality() public view {
        assertEq(oracle.currentCardinality(), expectedCardinality);
    }

    function test_currentPrice() public view {
        assertEq(oracle.currentPrice(), expectedCurPrice);
    }

    function test_pastPrice() public view {
        uint32 pastTimestamp = uint32(block.timestamp) - twapWindow;
        assertEq(oracle.pastPrice(pastTimestamp), expectedPriceTwapWindowAgo);
    }

    function test_pastPriceWithFallback() public view {
        uint32 pastTimestamp = uint32(block.timestamp) - twapWindow;
        (uint price, bool pastPriceOk) = oracle.pastPriceWithFallback(pastTimestamp);
        assertEq(price, expectedPriceTwapWindowAgo);
        assertTrue(pastPriceOk);
    }

    function test_pastPriceWithFallback_unavailableHistorical() public {
        uint32 ago = 30 * 86_400; // 30 days, adjust up if flaky
        uint32 pastTimestamp = uint32(block.timestamp) - ago;

        // past price should revert
        vm.expectRevert(revertBytesOLD);
        oracle.pastPrice(pastTimestamp);

        // fallback should succeed
        (uint price, bool pastPriceOk) = oracle.pastPriceWithFallback(pastTimestamp);

        assertEq(price, expectedCurPrice);
        assertFalse(pastPriceOk);
    }

    function test_increaseCardinality() public {
        uint16 toAdd = 100;
        oracle.increaseCardinality(toAdd);

        assertEq(oracle.currentCardinality(), expectedCardinality + toAdd);
    }
}

contract OracleUniV3TWAP_WETHUSDC_ForkTest is OracleUniV3TWAP_USDCWETH_ForkTest {
    function _setUp() internal override {
        super._setUp();
        baseToken = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831; // USDC
        quoteToken = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1; // WETH

        // 368M ETH (= 1 trillion / 2713) for 1e18 USDC (1 trillion USDC)
        expectedCurPrice = 368_559_882_855_728_784_761_983_870;
        expectedPriceTwapWindowAgo = 367_602_919_598_965_378_923_333_340;
    }
}

contract OracleUniV3TWAP_NewPool_ForkTest is OracleUniV3TWAP_USDCWETH_ForkTest {
    uint initialAmount = 10 ether;

    function _setUp() internal virtual override {
        super._setUp();

        baseToken = address(new CollarOwnedERC20(address(this), "Test Collateral", "Test Collateral"));
        quoteToken = address(new CollarOwnedERC20(address(this), "Test Cash", "Test Cash"));
        pool = 0xf882c5F7DF30928E8D70E95f3b305013C9D1d56C;

        expectedCardinality = uint16(twapWindow);

        _setupNewPool(expectedCardinality, 2 * twapWindow); // twice the window for testing pastPrice

        expectedCurPrice = 1 ether;
        expectedPriceTwapWindowAgo = expectedCurPrice;
    }

    function _setupNewPool(uint16 cardinality, uint32 initialObservationsSpan) internal {
        address newPool = IUniswapV3Factory(factory).createPool(baseToken, quoteToken, feeTier);

        // price 1:1, because otherwise liquidity amounts calc is a bit much
        //  if another initial price and liquidity are needed use this: https://uniswapv3book.com/milestone_1/calculating-liquidity.html
        uint160 sqrtPriceX96Tick0 = 79_228_162_514_264_337_593_543_950_336;
        IUniswapV3Pool(newPool).initialize(sqrtPriceX96Tick0);

        _provideAmount1to1(initialAmount);

        // set the cardinality to what is needed
        IUniswapV3Pool(newPool).increaseObservationCardinalityNext(cardinality);

        for (uint i; i < initialObservationsSpan / 60; ++i) {
            skip(60); // skip 1 minute
            _provideAmount1to1(1); // provide 1 wei to record an observation
        }
    }

    function _provideAmount1to1(uint amount) internal {
        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            // token order is inverted because depends on addresses
            token0: quoteToken,
            token1: baseToken,
            fee: feeTier,
            tickLower: -10,
            tickUpper: 10,
            amount0Desired: amount,
            amount1Desired: amount,
            amount0Min: 0,
            amount1Min: 0,
            recipient: address(this),
            deadline: block.timestamp
        });

        address positionManager = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;

        CollarOwnedERC20(baseToken).mint(address(this), amount);
        CollarOwnedERC20(quoteToken).mint(address(this), amount);

        CollarOwnedERC20(baseToken).approve(address(positionManager), amount);
        CollarOwnedERC20(quoteToken).approve(address(positionManager), amount);

        INonfungiblePositionManager(positionManager).mint(params);
    }
}
