// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import {CollarEngine} from "../../src/CollarEngine.sol";
import {EngineUtils} from "../utils/EngineUtils.sol";
import {IERC20} from "../../src/interfaces/external/IERC20.sol";

contract CollarEngineTest is Test, EngineUtils {
    CollarEngine engine;

    uint256 constant testQTY = 0.1 ether;
    uint256 constant testLTV = 85;
    uint256 constant maturityTimestamp = 1670337200;

    function setUp() public {
        engine = deployEngine();
    }

    function test_initialDeployAndValues() public {
        assertEq(engine.getAdmin(), DEFAULT_ENGINE_PARAMS.owner);
        assertEq(engine.getDexRouter(), DEFAULT_ENGINE_PARAMS.testDex);
        assertEq(engine.getMarketmaker(), DEFAULT_ENGINE_PARAMS.marketMakerMike);
        assertEq(engine.getFeewallet(), DEFAULT_ENGINE_PARAMS.feeWallet);
        assertEq(engine.getLendAsset(), DEFAULT_ENGINE_PARAMS.usdc);
        assertEq(engine.getFeerate(), DEFAULT_ENGINE_PARAMS.rake);
    }

    function test_getOraclePrice() public {
        uint256 oraclePrice = engine.getOraclePrice();
        assertEq(oraclePrice, 1172275959820000000000);
    }

    function test_updateDexRouter() public {
        hoax(DEFAULT_ENGINE_PARAMS.owner);
        engine.updateDexRouter(0x0000000000000000000000000000000000000001);
        address newDexRouter = engine.getDexRouter();
        assertEq(newDexRouter, 0x0000000000000000000000000000000000000001);
    }

    function test_requestPrice() public {
        uint256 currentRFQId = engine.getCurrRfqid();
        assertEq(currentRFQId, 0);

        startHoax(DEFAULT_ENGINE_PARAMS.averageJoe);

        engine.requestPrice(testQTY, testLTV, maturityTimestamp, "");

        currentRFQId = engine.getCurrRfqid();
        assertEq(currentRFQId, 1);

        CollarEngine.Pricing memory joePrice = engine.getPricingByClient(DEFAULT_ENGINE_PARAMS.averageJoe);

        assertEq(joePrice.rfqid, 0);
        assertEq(joePrice.lendAsset, DEFAULT_ENGINE_PARAMS.usdc);
        assertEq(joePrice.marketmaker, DEFAULT_ENGINE_PARAMS.marketMakerMike);
        assertEq(joePrice.client, DEFAULT_ENGINE_PARAMS.averageJoe);
        assertEq(joePrice.structure, "Prepaid");
        assertEq(joePrice.underlier, "ETH");
        assertEq(joePrice.maturityTimestamp, maturityTimestamp);
        assertEq(joePrice.qty, testQTY);
        assertEq(joePrice.ltv, testLTV);
        assertEq(joePrice.putstrikePct, 88);
        assertEq(joePrice.callstrikePct, 0);
        assertEq(joePrice.notes, "");
    }

    // enum PxState{NEW, REQD, ACKD, PXD, OFF, REJ, DONE}
    //              0    1     2     3    4    5    6

    function test_ackPrice() public {
        CollarEngine.PxState joeState;

        hoax(DEFAULT_ENGINE_PARAMS.averageJoe);
        engine.requestPrice(testQTY, testLTV, maturityTimestamp, "");
        joeState = engine.getStateByClient(DEFAULT_ENGINE_PARAMS.averageJoe);
        assertTrue(joeState == CollarEngine.PxState.REQD);

        hoax(DEFAULT_ENGINE_PARAMS.marketMakerMike);
        engine.ackPrice(DEFAULT_ENGINE_PARAMS.averageJoe);
        joeState = engine.getStateByClient(DEFAULT_ENGINE_PARAMS.averageJoe);
        assertTrue(joeState == CollarEngine.PxState.ACKD);
    }

    function test_showPrice() public {
        CollarEngine.PxState joeState;

        hoax(DEFAULT_ENGINE_PARAMS.averageJoe);
        engine.requestPrice(testQTY, testLTV, maturityTimestamp, "");

        startHoax(DEFAULT_ENGINE_PARAMS.marketMakerMike);
        engine.ackPrice(DEFAULT_ENGINE_PARAMS.averageJoe);

        joeState = engine.getStateByClient(DEFAULT_ENGINE_PARAMS.averageJoe);
        assertTrue(joeState == CollarEngine.PxState.ACKD);

        engine.showPrice(DEFAULT_ENGINE_PARAMS.averageJoe, 110);

        joeState = engine.getStateByClient(DEFAULT_ENGINE_PARAMS.averageJoe);
        assertTrue(joeState == CollarEngine.PxState.PXD);
    }

    function test_pullPrice() public {
        CollarEngine.PxState joeState;

        hoax(DEFAULT_ENGINE_PARAMS.averageJoe);
        engine.requestPrice(testQTY, testLTV, maturityTimestamp, "");

        startHoax(DEFAULT_ENGINE_PARAMS.marketMakerMike);
        engine.ackPrice(DEFAULT_ENGINE_PARAMS.averageJoe);
        engine.showPrice(DEFAULT_ENGINE_PARAMS.averageJoe, 110);

        joeState = engine.getStateByClient(DEFAULT_ENGINE_PARAMS.averageJoe);
        assertTrue(joeState == CollarEngine.PxState.PXD);

        engine.pullPrice(DEFAULT_ENGINE_PARAMS.averageJoe);

        joeState = engine.getStateByClient(DEFAULT_ENGINE_PARAMS.averageJoe);
        assertTrue(joeState == CollarEngine.PxState.OFF);
    }

    function test_clientGiveOrder() public {
        CollarEngine.PxState joeState;

        hoax(DEFAULT_ENGINE_PARAMS.averageJoe);
        engine.requestPrice(testQTY, testLTV, maturityTimestamp, "");

        startHoax(DEFAULT_ENGINE_PARAMS.marketMakerMike);
        engine.ackPrice(DEFAULT_ENGINE_PARAMS.averageJoe);
        engine.showPrice(DEFAULT_ENGINE_PARAMS.averageJoe, 110);

        joeState = engine.getStateByClient(DEFAULT_ENGINE_PARAMS.averageJoe);
        assertTrue(joeState == CollarEngine.PxState.PXD);

        changePrank(DEFAULT_ENGINE_PARAMS.averageJoe);
        engine.clientGiveOrder{value: testQTY}();
        joeState = engine.getStateByClient(DEFAULT_ENGINE_PARAMS.averageJoe);
        assertTrue(joeState == CollarEngine.PxState.DONE);
    }

    function test_executeTrade() public {
        CollarEngine.PxState joeState;

        hoax(DEFAULT_ENGINE_PARAMS.averageJoe);
        engine.requestPrice(testQTY, testLTV, maturityTimestamp, "");

        startHoax(DEFAULT_ENGINE_PARAMS.marketMakerMike);
        engine.ackPrice(DEFAULT_ENGINE_PARAMS.averageJoe);
        engine.showPrice(DEFAULT_ENGINE_PARAMS.averageJoe, 110);

        changePrank(DEFAULT_ENGINE_PARAMS.averageJoe);
        engine.clientGiveOrder{value: testQTY}();

        changePrank(DEFAULT_ENGINE_PARAMS.marketMakerMike);
        IERC20(DEFAULT_ENGINE_PARAMS.usdc).approve(address(engine), 1e10);
        engine.executeTrade(DEFAULT_ENGINE_PARAMS.averageJoe);

        joeState = engine.getStateByClient(DEFAULT_ENGINE_PARAMS.averageJoe);
        assertTrue(joeState == CollarEngine.PxState.NEW);

        uint256 engineUSDCBalance = IERC20(DEFAULT_ENGINE_PARAMS.usdc).balanceOf(address(engine));
        assertLt(engineUSDCBalance, 10);
        uint256 engineETHBalance = address(engine).balance;
        assertEq(engineETHBalance, 0);
    }

    function test_updateFeeRatePct() public {
        uint256 feeRate;

        feeRate = engine.getFeerate();
        assertEq(feeRate, 3);

        hoax(DEFAULT_ENGINE_PARAMS.owner);
        engine.updateFeeRatePct(5);

        feeRate = engine.getFeerate();
        assertEq(feeRate, 5);
    }

    function test_clientPullOrder() public {
        hoax(DEFAULT_ENGINE_PARAMS.averageJoe);
        engine.requestPrice(testQTY, testLTV, maturityTimestamp, "");

        startHoax(DEFAULT_ENGINE_PARAMS.marketMakerMike);
        engine.ackPrice(DEFAULT_ENGINE_PARAMS.averageJoe);
        engine.showPrice(DEFAULT_ENGINE_PARAMS.averageJoe, 110);

        changePrank(DEFAULT_ENGINE_PARAMS.averageJoe);
        uint256 joeBalancePre = address(DEFAULT_ENGINE_PARAMS.averageJoe).balance;
        engine.clientGiveOrder{value: testQTY}();
        uint256 joeBalanceMid = address(DEFAULT_ENGINE_PARAMS.averageJoe).balance;

        uint256 joeEscrow = engine.getClientEscrow(DEFAULT_ENGINE_PARAMS.averageJoe);
        assertEq(joeEscrow, 0.1 ether);

        engine.clientPullOrder();
        uint256 joeBalancePost = address(DEFAULT_ENGINE_PARAMS.averageJoe).balance;

        assertApproxEqRel(joeBalancePre, joeBalancePost, 1);
        assertApproxEqRel(joeBalancePre - joeBalanceMid, testQTY, 1);
    }

    function test_rejectOrder() public {
        hoax(DEFAULT_ENGINE_PARAMS.averageJoe);
        engine.requestPrice(testQTY, testLTV, maturityTimestamp, "");

        startHoax(DEFAULT_ENGINE_PARAMS.marketMakerMike);
        engine.ackPrice(DEFAULT_ENGINE_PARAMS.averageJoe);
        engine.showPrice(DEFAULT_ENGINE_PARAMS.averageJoe, 110);

        changePrank(DEFAULT_ENGINE_PARAMS.averageJoe);
        uint256 joeBalancePre = address(DEFAULT_ENGINE_PARAMS.averageJoe).balance;
        engine.clientGiveOrder{value: testQTY}();
        uint256 joeBalanceMid = address(DEFAULT_ENGINE_PARAMS.averageJoe).balance;

        uint256 joeEscrow = engine.getClientEscrow(DEFAULT_ENGINE_PARAMS.averageJoe);
        assertEq(joeEscrow, 0.1 ether);

        changePrank(DEFAULT_ENGINE_PARAMS.marketMakerMike);
        engine.rejectOrder(DEFAULT_ENGINE_PARAMS.averageJoe, "mkt moved");

        uint256 joeBalancePost = address(DEFAULT_ENGINE_PARAMS.averageJoe).balance;

        joeEscrow = engine.getClientEscrow(DEFAULT_ENGINE_PARAMS.averageJoe);
        assertEq(joeEscrow, 0);

        assertApproxEqRel(joeBalancePre, joeBalancePost, 1);
        assertApproxEqRel(joeBalancePre - joeBalanceMid, testQTY, 1);
    }
}
