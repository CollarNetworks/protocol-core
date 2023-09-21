// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import {CollarEngine} from "../src/CollarEngine.sol";
import {IERC20} from "../src/interfaces/external/IERC20.sol";

contract CollarEngineTest is Test {
    CollarEngine engine;

    uint256 rake;
    address owner;
    address feeWallet;
    address marketMakerMike;
    address averageJoe;
    address usdc;
    address testDex;
    address ethUSDOracle;
    address weth;

    uint256 constant testQTY = 0.1 ether;
    uint256 constant testLTV = 85;
    uint256 constant maturityTimestamp = 1670337200;

    function setUp() public {
        rake = 3;

        owner = makeAddr("owner");
        feeWallet = makeAddr("fee");
        marketMakerMike = makeAddr("mike");
        averageJoe = makeAddr("joe");
        usdc = makeAddr("usdc");
        testDex = makeAddr("dex");
        ethUSDOracle = makeAddr("oracle");
        weth = makeAddr("weth");

        hoax(owner);

        engine = new CollarEngine(
            rake,
            feeWallet,
            marketMakerMike,
            usdc,
            testDex,
            ethUSDOracle,
            weth
        );

        vm.label(address(engine), "CollarEngine");
    }

    function test_initialDeployAndValues() public {
        assertEq(engine.getAdmin(), owner);
        assertEq(engine.getDexRouter(), testDex);
        assertEq(engine.getMarketmaker(), marketMakerMike);
        assertEq(engine.getFeewallet(), feeWallet);
        assertEq(engine.getLendAsset(), usdc);
        assertEq(engine.getFeerate(), rake);
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
        assertEq(currentRFQId, 0);

        startHoax(averageJoe);

        engine.requestPrice(testQTY, testLTV, maturityTimestamp, "");

        currentRFQId = engine.getCurrRfqid();
        assertEq(currentRFQId, 1);

        CollarEngine.Pricing memory joePrice = engine.getPricingByClient(averageJoe);

        assertEq(joePrice.rfqid, 0);
        assertEq(joePrice.lendAsset, usdc);
        assertEq(joePrice.marketmaker, marketMakerMike);
        assertEq(joePrice.client, averageJoe);
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

        hoax(averageJoe);
        engine.requestPrice(testQTY, testLTV, maturityTimestamp, "");
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
        engine.requestPrice(testQTY, testLTV, maturityTimestamp, "");

        startHoax(marketMakerMike);
        engine.ackPrice(averageJoe);

        joeState = engine.getStateByClient(averageJoe);
        assertTrue(joeState == CollarEngine.PxState.ACKD);

        engine.showPrice(averageJoe, 110);

        joeState = engine.getStateByClient(averageJoe);
        assertTrue(joeState == CollarEngine.PxState.PXD);
    }

    function test_pullPrice() public {
        CollarEngine.PxState joeState;

        hoax(averageJoe);
        engine.requestPrice(testQTY, testLTV, maturityTimestamp, "");

        startHoax(marketMakerMike);
        engine.ackPrice(averageJoe);
        engine.showPrice(averageJoe, 110);

        joeState = engine.getStateByClient(averageJoe);
        assertTrue(joeState == CollarEngine.PxState.PXD);

        engine.pullPrice(averageJoe);

        joeState = engine.getStateByClient(averageJoe);
        assertTrue(joeState == CollarEngine.PxState.OFF);
    }

    function test_clientGiveOrder() public {
        CollarEngine.PxState joeState;

        hoax(averageJoe);
        engine.requestPrice(testQTY, testLTV, maturityTimestamp, "");

        startHoax(marketMakerMike);
        engine.ackPrice(averageJoe);
        engine.showPrice(averageJoe, 110);

        joeState = engine.getStateByClient(averageJoe);
        assertTrue(joeState == CollarEngine.PxState.PXD);

        changePrank(averageJoe);
        engine.clientGiveOrder{value: testQTY}();
        joeState = engine.getStateByClient(averageJoe);
        assertTrue(joeState == CollarEngine.PxState.DONE);
    }

    function test_executeTrade() public {
        CollarEngine.PxState joeState;

        hoax(averageJoe);
        engine.requestPrice(testQTY, testLTV, maturityTimestamp, "");

        startHoax(marketMakerMike);
        engine.ackPrice(averageJoe);
        engine.showPrice(averageJoe, 110);

        changePrank(averageJoe);
        engine.clientGiveOrder{value: testQTY}();

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
        assertEq(feeRate, 3);

        hoax(owner);
        engine.updateFeeRatePct(5);

        feeRate = engine.getFeerate();
        assertEq(feeRate, 5);
    }

    function test_clientPullOrder() public {
        CollarEngine.PxState joeState;

        hoax(averageJoe);
        engine.requestPrice(testQTY, testLTV, maturityTimestamp, "");

        startHoax(marketMakerMike);
        engine.ackPrice(averageJoe);
        engine.showPrice(averageJoe, 110);

        changePrank(averageJoe);
        uint256 joeBalancePre = address(averageJoe).balance;
        engine.clientGiveOrder{value: testQTY}();
        uint256 joeBalanceMid = address(averageJoe).balance;

        uint256 joeEscrow = engine.getClientEscrow(averageJoe);
        assertEq(joeEscrow, 0.1 ether);

        engine.clientPullOrder();
        uint256 joeBalancePost = address(averageJoe).balance;

        assertApproxEqRel(joeBalancePre, joeBalancePost, 1);
        assertApproxEqRel(joeBalancePre - joeBalanceMid, testQTY, 1);
    }

    function test_rejectOrder() public {
        CollarEngine.PxState joeState;

        hoax(averageJoe);
        engine.requestPrice(testQTY, testLTV, maturityTimestamp, "");

        startHoax(marketMakerMike);
        engine.ackPrice(averageJoe);
        engine.showPrice(averageJoe, 110);

        changePrank(averageJoe);
        uint256 joeBalancePre = address(averageJoe).balance;
        engine.clientGiveOrder{value: testQTY}();
        uint256 joeBalanceMid = address(averageJoe).balance;

        uint256 joeEscrow = engine.getClientEscrow(averageJoe);
        assertEq(joeEscrow, 0.1 ether);

        changePrank(marketMakerMike);
        engine.rejectOrder(averageJoe, "mkt moved");

        uint256 joeBalancePost = address(averageJoe).balance;

        joeEscrow = engine.getClientEscrow(averageJoe);
        assertEq(joeEscrow, 0);

        assertApproxEqRel(joeBalancePre, joeBalancePost, 1);
        assertApproxEqRel(joeBalancePre - joeBalanceMid, testQTY, 1);
    }
}
