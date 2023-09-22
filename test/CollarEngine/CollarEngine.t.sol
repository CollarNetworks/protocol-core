// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import {CollarEngine} from "../../src/CollarEngine.sol";
import {EngineUtils} from "../utils/EngineUtils.sol";
import {IERC20} from "../../src/interfaces/external/IERC20.sol";

contract CollarEngineTest is Test, EngineUtils {
    CollarEngine engine;

    uint256 constant maturityTimestamp = 1670337200;

    function setUp() public {
        engine = deployEngine();
    }

    function test_initialDeployAndValues() public {
        assertEq(engine.getAdmin(), owner);
        assertEq(engine.getDexRouter(), testDex);
        assertEq(engine.getMarketmaker(), marketMakerMike);
        assertEq(engine.getFeewallet(), feeWallet);
        assertEq(engine.getLendAsset(), usdc);
        assertEq(engine.getFeerate(), DEFAULT_RAKE);
    }

    function test_getOraclePrice() public {
        uint256 oraclePrice = engine.getOraclePrice();
        assertEq(oraclePrice, 1172275959820000000000);
    }

    function test_updateDexRouter() public {
        hoax(owner);
        engine.updateDexRouter(0x0000000000000000000000000000000000000001);
        address newDexRouter = engine.getDexRouter();
        assertEq(newDexRouter, 0x0000000000000000000000000000000000000001);
    }

    function test_requestPrice() public {
        uint256 currentRFQId = engine.getCurrRfqid();
        assertEq(currentRFQId, DEFAULT_RFQID);

        startHoax(averageJoe);

        engine.requestPrice(DEFAULT_QTY, DEFAULT_LTV, maturityTimestamp, "");

        currentRFQId = engine.getCurrRfqid();
        assertEq(currentRFQId, DEFAULT_RFQID + 1);

        CollarEngine.Pricing memory joePrice = engine.getPricingByClient(averageJoe);

        assertEq(joePrice.rfqid, DEFAULT_RFQID);
        assertEq(joePrice.lendAsset, usdc);
        assertEq(joePrice.marketmaker, marketMakerMike);
        assertEq(joePrice.client, averageJoe);
        assertEq(joePrice.structure, "Prepaid");
        assertEq(joePrice.underlier, "ETH");
        assertEq(joePrice.maturityTimestamp, maturityTimestamp);
        assertEq(joePrice.qty, DEFAULT_QTY);
        assertEq(joePrice.ltv, DEFAULT_LTV);
        assertEq(joePrice.putstrikePct, DEFAULT_PUT_STRIKE_PCT);
        assertEq(joePrice.callstrikePct, 0);
        assertEq(joePrice.notes, "");
    }

    // enum PxState{NEW, REQD, ACKD, PXD, OFF, REJ, DONE}
    //              0    1     2     3    4    5    6

    function test_ackPrice() public {
        CollarEngine.PxState joeState;

        hoax(averageJoe);
        engine.requestPrice(DEFAULT_QTY, DEFAULT_LTV, maturityTimestamp, "");
        joeState = engine.getStateByClient(averageJoe);
        assertTrue(joeState == CollarEngine.PxState.REQD);

        hoax(marketMakerMike);
        engine.ackPrice(averageJoe);
        joeState = engine.getStateByClient(averageJoe);
        assertTrue(joeState == CollarEngine.PxState.ACKD);
    }

    function test_showPrice() public {
        CollarEngine.PxState joeState;

        hoax(averageJoe);
        engine.requestPrice(DEFAULT_QTY, DEFAULT_LTV, maturityTimestamp, "");

        startHoax(marketMakerMike);
        engine.ackPrice(averageJoe);

        joeState = engine.getStateByClient(averageJoe);
        assertTrue(joeState == CollarEngine.PxState.ACKD);

        engine.showPrice(averageJoe, DEFAULT_CALL_STRIKE_PCT);

        joeState = engine.getStateByClient(averageJoe);
        assertTrue(joeState == CollarEngine.PxState.PXD);
    }

    function test_pullPrice() public {
        CollarEngine.PxState joeState;

        hoax(averageJoe);
        engine.requestPrice(DEFAULT_QTY, DEFAULT_LTV, maturityTimestamp, "");

        startHoax(marketMakerMike);
        engine.ackPrice(averageJoe);
        engine.showPrice(averageJoe, DEFAULT_CALL_STRIKE_PCT);

        joeState = engine.getStateByClient(averageJoe);
        assertTrue(joeState == CollarEngine.PxState.PXD);

        engine.pullPrice(averageJoe);

        joeState = engine.getStateByClient(averageJoe);
        assertTrue(joeState == CollarEngine.PxState.OFF);
    }

    function test_clientGiveOrder() public {
        CollarEngine.PxState joeState;

        hoax(averageJoe);
        engine.requestPrice(DEFAULT_QTY, DEFAULT_LTV, maturityTimestamp, "");

        startHoax(marketMakerMike);
        engine.ackPrice(averageJoe);
        engine.showPrice(averageJoe, DEFAULT_CALL_STRIKE_PCT);

        joeState = engine.getStateByClient(averageJoe);
        assertTrue(joeState == CollarEngine.PxState.PXD);

        changePrank(averageJoe);
        engine.clientGiveOrder{value: DEFAULT_QTY}();
        joeState = engine.getStateByClient(averageJoe);
        assertTrue(joeState == CollarEngine.PxState.DONE);
    }

    function test_executeTrade() public {
        CollarEngine.PxState joeState;

        hoax(averageJoe);
        engine.requestPrice(DEFAULT_QTY, DEFAULT_LTV, maturityTimestamp, "");

        startHoax(marketMakerMike);
        engine.ackPrice(averageJoe);
        engine.showPrice(averageJoe, DEFAULT_CALL_STRIKE_PCT);

        changePrank(averageJoe);
        engine.clientGiveOrder{value: DEFAULT_QTY}();

        changePrank(marketMakerMike);
        IERC20(usdc).approve(address(engine), 1e10);
        engine.executeTrade(averageJoe);

        joeState = engine.getStateByClient(averageJoe);
        assertTrue(joeState == CollarEngine.PxState.NEW);

        uint256 engineUSDCBalance = IERC20(usdc).balanceOf(address(engine));
        assertLt(engineUSDCBalance, 10);
        uint256 engineETHBalance = address(engine).balance;
        assertEq(engineETHBalance, 0);
    }

    function test_updateFeeRatePct() public {
        uint256 feeRate;

        feeRate = engine.getFeerate();
        assertEq(feeRate, DEFAULT_RAKE);

        hoax(owner);
        engine.updateFeeRatePct(5);

        feeRate = engine.getFeerate();
        assertEq(feeRate, 5);
    }

    function test_clientPullOrder() public {
        hoax(averageJoe);
        engine.requestPrice(DEFAULT_QTY, DEFAULT_LTV, maturityTimestamp, "");

        startHoax(marketMakerMike);
        engine.ackPrice(averageJoe);
        engine.showPrice(averageJoe, DEFAULT_CALL_STRIKE_PCT);

        changePrank(averageJoe);
        uint256 joeBalancePre = address(averageJoe).balance;
        engine.clientGiveOrder{value: DEFAULT_QTY}();
        uint256 joeBalanceMid = address(averageJoe).balance;

        uint256 joeEscrow = engine.getClientEscrow(averageJoe);
        assertEq(joeEscrow, DEFAULT_QTY);

        engine.clientPullOrder();
        uint256 joeBalancePost = address(averageJoe).balance;

        assertApproxEqRel(joeBalancePre, joeBalancePost, 1);
        assertApproxEqRel(joeBalancePre - joeBalanceMid, DEFAULT_QTY, 1);
    }

    function test_rejectOrder() public {
        hoax(averageJoe);
        engine.requestPrice(DEFAULT_QTY, DEFAULT_LTV, maturityTimestamp, "");

        startHoax(marketMakerMike);
        engine.ackPrice(averageJoe);
        engine.showPrice(averageJoe, DEFAULT_CALL_STRIKE_PCT);

        changePrank(averageJoe);
        uint256 joeBalancePre = address(averageJoe).balance;
        engine.clientGiveOrder{value: DEFAULT_QTY}();
        uint256 joeBalanceMid = address(averageJoe).balance;

        uint256 joeEscrow = engine.getClientEscrow(averageJoe);
        assertEq(joeEscrow, DEFAULT_QTY);

        changePrank(marketMakerMike);
        engine.rejectOrder(averageJoe, "mkt moved");

        uint256 joeBalancePost = address(averageJoe).balance;

        joeEscrow = engine.getClientEscrow(averageJoe);
        assertEq(joeEscrow, 0);

        assertApproxEqRel(joeBalancePre, joeBalancePost, 1);
        assertApproxEqRel(joeBalancePre - joeBalanceMid, DEFAULT_QTY, 1);
    }
}
