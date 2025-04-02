// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "forge-std/Test.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { Strings } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

import { TestERC20 } from "../utils/TestERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { BaseAssetPairTestSetup, BaseTakerOracle } from "./BaseAssetPairTestSetup.sol";

import { CollarTakerNFT, ICollarTakerNFT, ReentrancyGuard } from "../../src/CollarTakerNFT.sol";
import { ICollarTakerNFT } from "../../src/interfaces/ICollarTakerNFT.sol";
import { CollarProviderNFT } from "../../src/CollarProviderNFT.sol";
import { ICollarProviderNFT } from "../../src/interfaces/ICollarProviderNFT.sol";
import { ITakerOracle } from "../../src/interfaces/ITakerOracle.sol";

contract CollarTakerNFTTest is BaseAssetPairTestSetup {
    uint takerLocked = cashUnits(1000);
    uint providerLocked = cashUnits(2000);
    uint callStrikePrice = cashUnits(1200); // 120% of the price
    uint putStrikePrice = cashUnits(900); // 90% of the price corresponding to 9000 LTV

    uint offerId = 999; // stores latest ID, init to invalid

    function createOffer() internal {
        startHoax(provider);
        cashAsset.approve(address(providerNFT), largeCash);

        uint expectedOfferId = providerNFT.nextPositionId();
        vm.expectEmit(address(providerNFT));
        emit ICollarProviderNFT.OfferCreated(
            provider, ltv, duration, callStrikePercent, largeCash, expectedOfferId, 0
        );
        offerId = providerNFT.createOffer(callStrikePercent, largeCash, ltv, duration, 0);
        CollarProviderNFT.LiquidityOffer memory offer = providerNFT.getOffer(offerId);
        assertEq(offer.callStrikePercent, callStrikePercent);
        assertEq(offer.available, largeCash);
        assertEq(offer.provider, provider);
        assertEq(offer.duration, duration);
        assertEq(offer.callStrikePercent, callStrikePercent);
        assertEq(offer.putStrikePercent, ltv);
    }

    function checkOpenPairedPosition() public returns (uint takerId, uint providerNFTId) {
        createOffer();

        startHoax(user1);
        cashAsset.approve(address(takerNFT), takerLocked);

        // expected values
        uint expectedTakerId = takerNFT.nextPositionId();
        uint expectedProviderId = providerNFT.nextPositionId();
        uint _providerLocked = checkCalculateProviderLocked(takerLocked, ltv, callStrikePercent);

        ICollarTakerNFT.TakerPosition memory expectedTakerPos = ICollarTakerNFT.TakerPosition({
            providerNFT: providerNFT,
            providerId: expectedProviderId,
            duration: duration,
            expiration: block.timestamp + duration,
            startPrice: oraclePrice,
            putStrikePercent: ltv,
            callStrikePercent: callStrikePercent,
            takerLocked: takerLocked,
            providerLocked: _providerLocked,
            settled: false,
            withdrawable: 0
        });
        vm.expectEmit(address(takerNFT));
        emit ICollarTakerNFT.PairedPositionOpened(
            expectedTakerId, address(providerNFT), expectedProviderId, offerId, takerLocked, oraclePrice
        );
        (takerId, providerNFTId) = takerNFT.openPairedPosition(takerLocked, providerNFT, offerId);
        // return values
        assertEq(takerId, expectedTakerId);
        assertEq(providerNFTId, expectedProviderId);

        // position view
        CollarTakerNFT.TakerPosition memory takerPos = takerNFT.getPosition(takerId);
        assertEq(abi.encode(takerPos), abi.encode(expectedTakerPos));
        (uint expiration, bool settled) = takerNFT.expirationAndSettled(takerId);
        assertEq(expiration, expectedTakerPos.expiration);
        assertEq(settled, expectedTakerPos.settled);

        // provider position
        CollarProviderNFT.ProviderPosition memory providerPos = providerNFT.getPosition(providerNFTId);
        assertEq(providerPos.duration, duration);
        assertEq(providerPos.expiration, block.timestamp + duration);
        assertEq(providerPos.providerLocked, _providerLocked);
        assertEq(providerPos.putStrikePercent, ltv);
        assertEq(providerPos.callStrikePercent, callStrikePercent);
        assertEq(providerPos.settled, false);
        assertEq(providerPos.withdrawable, 0);
    }

    function checkCalculateProviderLocked(uint _takerLocked, uint putStrike, uint callStrike)
        internal
        view
        returns (uint _providerLocked)
    {
        // calculate
        uint putRange = BIPS_100PCT - putStrike;
        uint callRange = callStrike - BIPS_100PCT;
        _providerLocked = callRange * _takerLocked / putRange;
        // check view agrees
        assertEq(_providerLocked, takerNFT.calculateProviderLocked(_takerLocked, putStrike, callStrike));
    }

    function createAndSettlePosition(uint priceToSettleAt, int expectedProviderChange)
        internal
        returns (uint takerId)
    {
        (takerId,) = checkOpenPairedPosition();
        skip(duration);
        // set settlement price
        updatePrice(priceToSettleAt);
        checkSettlePosition(takerId, priceToSettleAt, expectedProviderChange);
    }

    function checkSettlementCalculation(CollarTakerNFT.TakerPosition memory takerPos, uint endPrice)
        internal
        view
        returns (uint takerBalance, int providerDelta)
    {
        uint e = endPrice;
        uint s = takerPos.startPrice;

        // can be used to check (in fuzz test) if roundup affects results
        // uint p = (s * ltv - 1) / BIPS_100PCT + 1;
        uint p = s * ltv / BIPS_100PCT;
        uint c = s * callStrikePercent / BIPS_100PCT;

        e = e > c ? c : e;
        e = e < p ? p : e;

        if (e < s) {
            uint pGain = takerPos.takerLocked * (s - e) / (s - p);
            takerBalance = takerPos.takerLocked - pGain;
            providerDelta = int(pGain);
        } else {
            uint tGain = takerPos.providerLocked * (e - s) / (c - s);
            takerBalance = takerPos.takerLocked + tGain;
            providerDelta = -int(tGain);
        }

        (uint takerBalanceView, int providerDeltaView) = takerNFT.previewSettlement(takerPos, endPrice);

        assertEq(takerBalance, takerBalanceView);
        assertEq(providerDelta, providerDeltaView);
    }

    function checkSettlePosition(uint takerId, uint expectedSettlePrice, int expectedProviderChange)
        internal
    {
        CollarTakerNFT.TakerPosition memory takerPos = takerNFT.getPosition(takerId);
        uint providerNFTId = takerPos.providerId;
        uint expectedTakerOut = uint(int(takerLocked) - expectedProviderChange);
        uint expectedProviderOut = uint(int(providerLocked) + expectedProviderChange);

        // check the view
        {
            (uint takerBalanceView, int providerChangeView) =
                checkSettlementCalculation(takerPos, expectedSettlePrice);
            assertEq(takerBalanceView, expectedTakerOut);
            assertEq(providerChangeView, expectedProviderChange);
        }

        uint takerNFTBalanceBefore = cashAsset.balanceOf(address(takerNFT));
        uint providerNFTBalanceBefore = cashAsset.balanceOf(address(providerNFT));

        startHoax(user1);
        vm.expectEmit(address(providerNFT));
        emit ICollarProviderNFT.PositionSettled(providerNFTId, expectedProviderChange, expectedProviderOut);
        vm.expectEmit(address(takerNFT));
        emit ICollarTakerNFT.PairedPositionSettled(
            takerId,
            address(providerNFT),
            providerNFTId,
            expectedSettlePrice,
            expectedTakerOut,
            expectedProviderChange
        );
        takerNFT.settlePairedPosition(takerId);

        // balance changes
        assertEq(
            int(cashAsset.balanceOf(address(takerNFT))), int(takerNFTBalanceBefore) - expectedProviderChange
        );
        assertEq(
            int(cashAsset.balanceOf(address(providerNFT))),
            int(providerNFTBalanceBefore) + expectedProviderChange
        );

        // positions changes
        CollarTakerNFT.TakerPosition memory takerPosAfter = takerNFT.getPosition(takerId);
        assertEq(takerPosAfter.settled, true);
        assertEq(takerPosAfter.withdrawable, expectedTakerOut);
        (, bool settled) = takerNFT.expirationAndSettled(takerId);
        assertEq(settled, true);

        CollarProviderNFT.ProviderPosition memory providerPosAfter = providerNFT.getPosition(providerNFTId);
        assertEq(providerPosAfter.settled, true);
        assertEq(providerPosAfter.withdrawable, expectedProviderOut);
    }

    function checkSettleAsCancelled(uint takerId, address caller) internal {
        CollarTakerNFT.TakerPosition memory takerPos = takerNFT.getPosition(takerId);
        uint providerNFTId = takerPos.providerId;
        uint takerNFTBalanceBefore = cashAsset.balanceOf(address(takerNFT));
        uint providerNFTBalanceBefore = cashAsset.balanceOf(address(providerNFT));

        startHoax(caller);
        vm.expectEmit(address(providerNFT));
        emit ICollarProviderNFT.PositionSettled(providerNFTId, 0, providerLocked);
        vm.expectEmit(address(takerNFT));
        emit ICollarTakerNFT.PairedPositionSettled(
            takerId, address(providerNFT), providerNFTId, 0, takerLocked, 0
        );
        takerNFT.settleAsCancelled(takerId);

        // balance changes
        assertEq(cashAsset.balanceOf(address(takerNFT)), takerNFTBalanceBefore);
        assertEq(cashAsset.balanceOf(address(providerNFT)), providerNFTBalanceBefore);

        // positions changes
        CollarTakerNFT.TakerPosition memory takerPosAfter = takerNFT.getPosition(takerId);
        assertEq(takerPosAfter.settled, true);
        assertEq(takerPosAfter.withdrawable, takerLocked);
        (, bool settled) = takerNFT.expirationAndSettled(takerId);
        assertEq(settled, true);

        CollarProviderNFT.ProviderPosition memory providerPosAfter = providerNFT.getPosition(providerNFTId);
        assertEq(providerPosAfter.settled, true);
        assertEq(providerPosAfter.withdrawable, providerLocked);
    }

    function checkWithdrawFromSettled(uint takerId, uint expectedTakerOut) public {
        startHoax(user1);
        uint takerCashBefore = cashAsset.balanceOf(user1);
        vm.expectEmit(address(takerNFT));
        emit ICollarTakerNFT.WithdrawalFromSettled(takerId, expectedTakerOut);
        uint withdrawalTaker = takerNFT.withdrawFromSettled(takerId);
        assertEq(withdrawalTaker, expectedTakerOut);
        assertEq(cashAsset.balanceOf(user1), takerCashBefore + expectedTakerOut);
        assertEq(takerNFT.getPosition(takerId).withdrawable, 0);

        startHoax(provider);
        uint providerCashBefore = cashAsset.balanceOf(provider);
        uint providerId = takerNFT.getPosition(takerId).providerId;
        uint withdrawalProvider = providerNFT.withdrawFromSettled(providerId);
        uint expectedProviderOut = providerLocked + takerLocked - expectedTakerOut;
        assertEq(withdrawalProvider, expectedProviderOut);
        assertEq(cashAsset.balanceOf(provider), providerCashBefore + expectedProviderOut);
        assertEq(providerNFT.getPosition(providerId).withdrawable, 0);
    }

    // tests

    function test_constructor() public {
        CollarTakerNFT takerNFT = new CollarTakerNFT(
            configHub, cashAsset, underlying, chainlinkOracle, "NewCollarTakerNFT", "NBPNFT"
        );

        assertEq(takerNFT.configHubOwner(), owner);
        assertEq(address(takerNFT.configHub()), address(configHub));
        assertEq(address(takerNFT.cashAsset()), address(cashAsset));
        assertEq(address(takerNFT.underlying()), address(underlying));
        assertEq(address(takerNFT.oracle()), address(chainlinkOracle));
        assertEq(takerNFT.SETTLE_AS_CANCELLED_DELAY(), 1 weeks);
        assertEq(takerNFT.VERSION(), "0.3.0");
        assertEq(takerNFT.name(), "NewCollarTakerNFT");
        assertEq(takerNFT.symbol(), "NBPNFT");
        assertEq(takerNFT.nextPositionId(), 1);
    }

    function test_revert_constructor() public {
        // Create an oracle with mismatched assets
        BaseTakerOracle invalidOracle = createMockFeedOracle(address(cashAsset), address(underlying));
        vm.expectRevert("taker: oracle underlying mismatch");
        new CollarTakerNFT(configHub, cashAsset, underlying, invalidOracle, "NewCollarTakerNFT", "NBPNFT");

        invalidOracle = createMockFeedOracle(address(cashAsset), address(cashAsset));
        vm.expectRevert("taker: oracle underlying mismatch");
        new CollarTakerNFT(configHub, cashAsset, underlying, invalidOracle, "NewCollarTakerNFT", "NBPNFT");

        invalidOracle = createMockFeedOracle(address(underlying), address(underlying));
        vm.expectRevert("taker: oracle cashAsset mismatch");
        new CollarTakerNFT(configHub, cashAsset, underlying, invalidOracle, "NewCollarTakerNFT", "NBPNFT");

        vm.mockCall(address(100), abi.encodeCall(IERC20Metadata.decimals, ()), abi.encode(18));
        invalidOracle = createMockFeedOracle(address(underlying), address(100));
        vm.expectRevert("taker: oracle cashAsset mismatch");
        new CollarTakerNFT(configHub, cashAsset, underlying, invalidOracle, "NewCollarTakerNFT", "NBPNFT");

        BaseTakerOracle newOracle = createMockFeedOracle(address(underlying), address(cashAsset));
        vm.mockCall(address(newOracle), abi.encodeCall(ITakerOracle.currentPrice, ()), abi.encode(0));
        vm.expectRevert("taker: invalid current price");
        new CollarTakerNFT(configHub, cashAsset, underlying, newOracle, "NewCollarTakerNFT", "NBPNFT");
        vm.clearMockedCalls();

        updatePrice(1);
        // 0 conversion view
        vm.mockCall(address(newOracle), abi.encodeCall(newOracle.convertToBaseAmount, (1, 1)), abi.encode(0));
        vm.expectRevert("taker: invalid convertToBaseAmount");
        new CollarTakerNFT(configHub, cashAsset, underlying, newOracle, "NewCollarTakerNFT", "NBPNFT");
        vm.clearMockedCalls();

        // reverting conversion view
        vm.mockCallRevert(address(newOracle), abi.encodeCall(newOracle.convertToBaseAmount, (1, 1)), "mocked");
        vm.expectRevert("mocked");
        new CollarTakerNFT(configHub, cashAsset, underlying, newOracle, "NewCollarTakerNFT", "NBPNFT");
    }

    function test_supportsInterface() public view {
        bool supportsERC721 = takerNFT.supportsInterface(0x80ac58cd); // ERC721 interface id
        bool supportsERC165 = takerNFT.supportsInterface(0x01ffc9a7); // ERC165 interface id

        assertTrue(supportsERC721);
        assertTrue(supportsERC165);

        // Test for an unsupported interface
        bool supportsUnsupported = takerNFT.supportsInterface(0xffffffff);
        assertFalse(supportsUnsupported);
    }

    function test_revert_nonExistentID() public {
        vm.expectRevert("taker: position does not exist");
        takerNFT.getPosition(1000);

        vm.expectRevert("taker: position does not exist");
        takerNFT.settlePairedPosition(1000);
    }

    function test_openPairedPosition() public {
        uint nextTakertId = takerNFT.nextPositionId();
        uint nextProviderId = providerNFT.nextPositionId();
        uint userBalanceBefore = cashAsset.balanceOf(user1);
        (uint takerId, uint providerNFTId) = checkOpenPairedPosition();
        assertEq(takerId, nextTakertId);
        assertEq(providerNFTId, nextProviderId);
        assertEq(cashAsset.balanceOf(user1), userBalanceBefore - takerLocked);
    }

    function test_tokenURI() public {
        (uint takerId,) = checkOpenPairedPosition();
        string memory expected = string.concat(
            "https://services.collarprotocol.xyz/metadata/",
            Strings.toString(block.chainid),
            "/",
            Strings.toHexString(address(takerNFT)),
            "/",
            Strings.toString(takerId)
        );
        assertEq(takerNFT.tokenURI(takerId), expected);
    }

    function test_openPairedPositionUnsupportedTakerContract() public {
        createOffer();
        setCanOpen(address(takerNFT), false);
        startHoax(user1);
        vm.expectRevert("taker: unsupported taker");
        takerNFT.openPairedPosition(takerLocked, providerNFT, 0);
        // allowed for different assets, still reverts
        vm.startPrank(owner);
        configHub.setCanOpenPair(address(cashAsset), address(underlying), address(takerNFT), true);
        vm.startPrank(user1);
        vm.expectRevert("taker: unsupported taker");
        takerNFT.openPairedPosition(takerLocked, providerNFT, 0);
    }

    function test_openPairedPositionUnsupportedProviderContract() public {
        createOffer();
        setCanOpen(address(providerNFT), false);
        startHoax(user1);
        vm.expectRevert("taker: unsupported provider");
        takerNFT.openPairedPosition(takerLocked, providerNFT, 0);
        // allowed for different assets, still reverts
        vm.startPrank(owner);
        configHub.setCanOpenPair(address(cashAsset), address(underlying), address(providerNFT), true);
        vm.startPrank(user1);
        vm.expectRevert("taker: unsupported provider");
        takerNFT.openPairedPosition(takerLocked, providerNFT, 0);
    }

    function test_openPairedPosition_badOfferId() public {
        createOffer();
        startHoax(user1);
        cashAsset.approve(address(takerNFT), takerLocked);
        vm.expectRevert("taker: invalid offer");
        takerNFT.openPairedPosition(takerLocked, providerNFT, 1000);
    }

    function test_openPairedPosition_expirationMistmatch() public {
        createOffer();
        startHoax(user1);
        uint badExpiration = block.timestamp + duration + 1;
        vm.mockCall(
            address(providerNFT),
            abi.encodeCall(providerNFT.expiration, (providerNFT.nextPositionId())),
            abi.encode(badExpiration)
        );
        vm.expectRevert("taker: expiration mismatch");
        takerNFT.openPairedPosition(takerLocked, providerNFT, offerId);
    }

    function test_nonReentrant_methods() public {
        createOffer();
        vm.startPrank(user1);
        bytes memory reentrantRevert =
            abi.encodeWithSelector(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);

        // set up reentrancy
        ReentrantAttacker attacker = new ReentrantAttacker();
        cashAsset.setAttacker(address(attacker));

        // attack open open
        attacker.setCall(address(takerNFT), abi.encodeCall(takerNFT.openPairedPosition, (0, providerNFT, 0)));
        vm.expectRevert(reentrantRevert);
        takerNFT.openPairedPosition(takerLocked, providerNFT, offerId);

        // attack open settle
        attacker.setCall(address(takerNFT), abi.encodeCall(takerNFT.settlePairedPosition, (0)));
        vm.expectRevert(reentrantRevert);
        takerNFT.openPairedPosition(takerLocked, providerNFT, offerId);

        // attack open cancel
        attacker.setCall(address(takerNFT), abi.encodeCall(takerNFT.cancelPairedPosition, (0)));
        vm.expectRevert(reentrantRevert);
        takerNFT.openPairedPosition(takerLocked, providerNFT, offerId);

        // attack open withdraw
        attacker.setCall(address(takerNFT), abi.encodeCall(takerNFT.withdrawFromSettled, (0)));
        vm.expectRevert(reentrantRevert);
        takerNFT.openPairedPosition(takerLocked, providerNFT, offerId);

        // below cases use settle entry point, but are mostly redundant since removing
        // nonReentrant from any of the methods would fail one of the above cases

        // open position
        cashAsset.setAttacker(address(0));
        cashAsset.approve(address(takerNFT), takerLocked);
        (uint takerId,) = takerNFT.openPairedPosition(takerLocked, providerNFT, offerId);
        skip(duration);
        cashAsset.setAttacker(address(attacker));

        // attack settle open
        attacker.setCall(address(takerNFT), abi.encodeCall(takerNFT.openPairedPosition, (0, providerNFT, 0)));
        vm.expectRevert(reentrantRevert);
        takerNFT.settlePairedPosition(takerId);

        // attack settle settle
        attacker.setCall(address(takerNFT), abi.encodeCall(takerNFT.settlePairedPosition, (0)));
        vm.expectRevert(reentrantRevert);
        takerNFT.settlePairedPosition(takerId);
    }

    function test_openPairedPosition_providerConfigMismatch() public {
        createOffer();

        // cash mismatch
        CollarProviderNFT providerNFTBad = new CollarProviderNFT(
            configHub, underlying, underlying, address(takerNFT), "CollarTakerNFTBad", "BRWTSTBAD"
        );
        setCanOpen(address(providerNFTBad), true);
        startHoax(user1);
        cashAsset.approve(address(takerNFT), takerLocked);
        vm.expectRevert("taker: cashAsset mismatch");
        takerNFT.openPairedPosition(takerLocked, providerNFTBad, 0);

        // underlying mismatch
        providerNFTBad = new CollarProviderNFT(
            configHub, cashAsset, cashAsset, address(takerNFT), "CollarTakerNFTBad", "BRWTSTBAD"
        );
        setCanOpen(address(providerNFTBad), true);
        startHoax(user1);
        cashAsset.approve(address(takerNFT), takerLocked);
        vm.expectRevert("taker: underlying mismatch");
        takerNFT.openPairedPosition(takerLocked, providerNFTBad, 0);

        // taker mismatch
        providerNFTBad = new CollarProviderNFT(
            configHub, cashAsset, underlying, address(providerNFT2), "CollarTakerNFTBad", "BRWTSTBAD"
        );
        setCanOpen(address(providerNFTBad), true);
        startHoax(user1);
        cashAsset.approve(address(takerNFT), takerLocked);
        vm.expectRevert("taker: taker mismatch");
        takerNFT.openPairedPosition(takerLocked, providerNFTBad, 0);
    }

    function test_openPairedPositionStrikePricesArentDifferent() public {
        vm.startPrank(owner);
        configHub.setLTVRange(9990, 9990);
        callStrikePercent = 10_010;
        ltv = 9990;
        createOffer();
        updatePrice(991);
        startHoax(user1);
        cashAsset.approve(address(takerNFT), takerLocked);
        vm.expectRevert("taker: strike prices not different");
        takerNFT.openPairedPosition(takerLocked, providerNFT, offerId);
    }

    function test_settleAndWIthdrawNoChange() public {
        uint takerId = createAndSettlePosition(oraclePrice, 0);
        checkWithdrawFromSettled(takerId, takerLocked);
    }

    /// forge-config: default.fuzz.runs = 100
    function test_settleCalculation_fuzz(
        uint startPrice,
        uint endPrice,
        uint pStrike,
        uint cStrike,
        uint tLocked
    ) public {
        // price must be at least BIPS_100PCT so that 1 bip strike results in different strike prices
        oraclePrice = bound(startPrice, BIPS_100PCT, oraclePrice * pow10(18 - cashDecimals));
        endPrice = bound(endPrice, oraclePrice / 100, oraclePrice * 100);
        ltv = bound(pStrike, 1000, 9999);
        callStrikePercent = bound(cStrike, 10_001, 12_000);
        takerLocked = bound(tLocked, 0, takerLocked);
        updatePrice();
        vm.startPrank(owner);
        configHub.setLTVRange(ltv, ltv);
        vm.assumeNoRevert();
        // using "this." so that assumeNoRevert covers the whole setup phase
        (uint takerId,) = this.checkOpenPairedPosition();
        CollarTakerNFT.TakerPosition memory takerPos = takerNFT.getPosition(takerId);
        checkSettlementCalculation(takerPos, endPrice);
    }

    // test case that can show roundup direction difference for price calculations
    // when rounding is done differently in checkSettlementCalculation from contract
    // part of validating finding #467 from the contest
    function test_rounding_contest_467() public {
        oraclePrice = 99_990_909;
        updatePrice();
        takerLocked = 1e9;
        ltv = 9999;
        callStrikePercent = 10_002;
        uint newPrice = 99_980_910;
        vm.startPrank(owner);
        configHub.setLTVRange(ltv, ltv);
        (uint takerId,) = checkOpenPairedPosition();
        CollarTakerNFT.TakerPosition memory takerPos = takerNFT.getPosition(takerId);
        checkSettlementCalculation(takerPos, newPrice);
    }

    function test_settleAndWIthdrawPriceAboveCall() public {
        uint newPrice = callStrikePrice * 11 / 10;
        uint takerId = createAndSettlePosition(newPrice, -int(providerLocked));
        checkWithdrawFromSettled(takerId, takerLocked + providerLocked);
    }

    function test_settleAndWIthdrawPriceUp() public {
        uint newPrice = oraclePrice * 110 / 100;
        uint takerId = createAndSettlePosition(newPrice, -int(providerLocked / 2));
        checkWithdrawFromSettled(takerId, takerLocked + providerLocked / 2);
    }

    function test_settleAndWIthdrawPriceBelowPut() public {
        uint newPrice = putStrikePrice * 9 / 10;
        uint takerId = createAndSettlePosition(newPrice, int(takerLocked));
        checkWithdrawFromSettled(takerId, 0);
    }

    function test_settleAndWIthdrawPriceDown() public {
        uint newPrice = oraclePrice * 95 / 100;
        uint takerId = createAndSettlePosition(newPrice, int(takerLocked / 2));
        checkWithdrawFromSettled(takerId, takerLocked / 2);
    }

    function test_settleAndWIthdrawLate_usesCurrentPrice() public {
        uint currentPrice = oraclePrice * 120 / 100;

        (uint takerId,) = checkOpenPairedPosition();
        skip(10 * duration);
        updatePrice(currentPrice);
        assertEq(takerNFT.currentOraclePrice(), currentPrice);
        // settled at current price and got 100% of providerLocked
        checkSettlePosition(takerId, currentPrice, -int(providerLocked));
        checkWithdrawFromSettled(takerId, takerLocked + providerLocked);
    }

    function test_settlePairedPosition_NotExpired() public {
        (uint takerId,) = checkOpenPairedPosition();

        // Try to settle before expiration
        startHoax(user1);
        vm.expectRevert("taker: not expired");
        takerNFT.settlePairedPosition(takerId);
    }

    function test_settlePairedPosition_AlreadySettled() public {
        (uint takerId,) = checkOpenPairedPosition();

        // Settle the position
        skip(301);
        startHoax(user1);
        takerNFT.settlePairedPosition(takerId);

        // Try to settle again
        vm.expectRevert("taker: already settled");
        takerNFT.settlePairedPosition(takerId);
    }

    function test_settlePairedPosition_balanceMismatch() public {
        (uint takerId, uint providerId) = checkOpenPairedPosition();
        skip(duration);
        // expect to get paid
        updatePrice(oraclePrice * 2);
        // no transfer, but update is -providerLocked
        vm.mockCall(
            address(providerNFT),
            abi.encodeCall(providerNFT.settlePosition, (providerId, -int(providerLocked))),
            ""
        );
        vm.startPrank(user1);
        // try to settle
        vm.expectRevert("taker: settle balance mismatch");
        takerNFT.settlePairedPosition(takerId);

        // expect funds to be pulled
        updatePrice();
        (takerId, providerId) = checkOpenPairedPosition();
        skip(duration);
        // expect to get paid
        updatePrice(oraclePrice / 2);
        // no transfer, but update is +takerLocked
        vm.mockCall(
            address(providerNFT),
            abi.encodeCall(providerNFT.settlePosition, (providerId, int(takerLocked))),
            ""
        );
        // try to settle
        vm.expectRevert("taker: settle balance mismatch");
        takerNFT.settlePairedPosition(takerId);
    }

    function test_settleAsCancelled() public {
        (uint takerId,) = checkOpenPairedPosition();
        skip(duration + takerNFT.SETTLE_AS_CANCELLED_DELAY());
        // oracle reverts now
        vm.mockCallRevert(address(takerNFT.oracle()), abi.encodeCall(takerNFT.oracle().currentPrice, ()), "");
        // check that it reverts
        vm.expectRevert(new bytes(0));
        takerNFT.currentOraclePrice();

        uint snapshot = vm.snapshotState();
        // settled at starting price and get takerLocked back
        checkSettleAsCancelled(takerId, user1);
        checkWithdrawFromSettled(takerId, takerLocked);

        vm.revertToState(snapshot);
        // check provider can call too
        checkSettleAsCancelled(takerId, provider);
        checkWithdrawFromSettled(takerId, takerLocked);

        vm.revertToState(snapshot);
        // check someone else can call too
        checkSettleAsCancelled(takerId, keeper);
        checkWithdrawFromSettled(takerId, takerLocked);
    }

    function test_settleAsCancelled_NotYet() public {
        (uint takerId,) = checkOpenPairedPosition();

        // Try to settle before expiration + delay
        skip(duration + takerNFT.SETTLE_AS_CANCELLED_DELAY() - 1);
        startHoax(user1);
        vm.expectRevert("taker: cannot be settled as cancelled yet");
        takerNFT.settleAsCancelled(takerId);
    }

    function test_settleAsCancelled_AlreadySettled() public {
        (uint takerId,) = checkOpenPairedPosition();

        // Settle the position
        skip(duration + takerNFT.SETTLE_AS_CANCELLED_DELAY());
        startHoax(user1);
        updatePrice();
        takerNFT.settlePairedPosition(takerId);

        // Try to settle again
        vm.expectRevert("taker: already settled");
        takerNFT.settleAsCancelled(takerId);
    }

    function test_settleAsCancelled_balanceMismatch() public {
        (uint takerId, uint providerId) = checkOpenPairedPosition();
        skip(duration + takerNFT.SETTLE_AS_CANCELLED_DELAY());
        DonatingProvider donatingProvider = new DonatingProvider(cashAsset);
        deal(address(cashAsset), address(donatingProvider), 1);
        // also mock getPosition with actual's getPosition data because it's called inside settleAsCancelled
        // for some reason this needs to be mocked before the call to etch (doesn't work the other way around)
        vm.mockCall(
            address(providerNFT),
            abi.encodeCall(providerNFT.getPosition, (providerId)),
            abi.encode(providerNFT.getPosition(providerId))
        );
        // switch implementation to one that sends funds
        vm.etch(address(providerNFT), address(donatingProvider).code);

        vm.startPrank(user1);
        // try to settle
        vm.expectRevert("taker: settle balance mismatch");
        takerNFT.settleAsCancelled(takerId);
    }

    function test_withdrawFromSettled_NotOwner() public {
        (uint takerId,) = checkOpenPairedPosition();

        // Settle the position
        skip(301);
        startHoax(user1);
        takerNFT.settlePairedPosition(takerId);

        // Try to withdraw with a different address
        startHoax(address(0xdead));
        vm.expectRevert("taker: not position owner");
        takerNFT.withdrawFromSettled(takerId);
    }

    function test_withdrawFromSettled_NotSettled() public {
        (uint takerId,) = checkOpenPairedPosition();

        // Try to withdraw before settling
        startHoax(user1);
        vm.expectRevert("taker: not settled");
        takerNFT.withdrawFromSettled(takerId);
    }

    function test_cancelPairedPosition() public {
        (uint takerId, uint providerNFTId) = checkOpenPairedPosition();

        uint userCashBefore = cashAsset.balanceOf(user1);
        uint providerCashBefore = cashAsset.balanceOf(provider);

        uint expectedWithdrawal = takerLocked + providerLocked;

        startHoax(user1);
        takerNFT.safeTransferFrom(user1, provider, takerId);
        startHoax(provider);
        takerNFT.approve(address(takerNFT), takerId);
        providerNFT.approve(address(takerNFT), providerNFTId);
        vm.expectEmit(address(takerNFT));
        emit ICollarTakerNFT.PairedPositionCanceled(
            takerId, address(providerNFT), providerNFTId, expectedWithdrawal, block.timestamp + duration
        );
        uint withdrawal = takerNFT.cancelPairedPosition(takerId);

        assertEq(withdrawal, expectedWithdrawal);

        // view
        CollarTakerNFT.TakerPosition memory position = takerNFT.getPosition(takerId);
        assertEq(position.settled, true);
        assertEq(position.withdrawable, 0);
        (, bool settled) = takerNFT.expirationAndSettled(takerId);
        assertEq(settled, true);

        // balances
        assertEq(cashAsset.balanceOf(user1), userCashBefore);
        assertEq(cashAsset.balanceOf(provider), providerCashBefore + expectedWithdrawal);
    }

    function test_cancelIfBrokenOracle() public {
        // exit cases when the oracle is broken or if it reverts due to sequencer checks
        (uint takerId, uint providerNFTId) = checkOpenPairedPosition();

        // disable oracle
        vm.startPrank(owner);
        mockCLFeed.setReverts(true);
        vm.expectRevert("oracle reverts");
        takerNFT.currentOraclePrice();

        // cancel works
        vm.startPrank(provider);
        providerNFT.transferFrom(provider, user1, providerNFTId);
        vm.startPrank(user1);
        providerNFT.approve(address(takerNFT), providerNFTId);
        takerNFT.cancelPairedPosition(takerId);
    }

    function test_cancelPairedPosition_NotOwnerOfTakerID() public {
        (uint takerId,) = checkOpenPairedPosition();

        // Try to cancel with a different address
        startHoax(address(0xdead));
        vm.expectRevert("taker: not owner of ID");
        takerNFT.cancelPairedPosition(takerId);
    }

    function test_cancelPairedPosition_NotOwnerOfProviderID() public {
        (uint takerId,) = checkOpenPairedPosition();

        // Transfer the taker NFT to another address, but not the provider NFT
        startHoax(user1);
        takerNFT.transferFrom(user1, address(0xbeef), takerId);

        // Try to cancel with the new taker NFT owner
        startHoax(address(0xbeef));
        vm.expectRevert("taker: not owner of provider ID");
        takerNFT.cancelPairedPosition(takerId);
    }

    function test_cancelPairedPosition_AlreadySettled() public {
        (uint takerId,) = checkOpenPairedPosition();

        // Settle the position
        skip(301);
        startHoax(user1);
        takerNFT.settlePairedPosition(takerId);
        // Try to cancel the settled position
        takerNFT.safeTransferFrom(user1, provider, takerId);
        startHoax(provider);
        vm.expectRevert("taker: already settled");
        takerNFT.cancelPairedPosition(takerId);
    }

    function test_cancelPairedPosition_balanceMismatch() public {
        (uint takerId, uint providerId) = checkOpenPairedPosition();

        skip(duration);
        vm.startPrank(provider);
        providerNFT.transferFrom(provider, user1, providerId);
        // one wei transfer expected, but doesn't happen
        vm.mockCall(
            address(providerNFT), abi.encodeCall(providerNFT.cancelAndWithdraw, (providerId)), abi.encode(1)
        );
        vm.startPrank(user1);
        vm.expectRevert("taker: cancel balance mismatch");
        takerNFT.cancelPairedPosition(takerId);
    }
}

contract ReentrantAttacker {
    address public to;
    bytes public data;

    function setCall(address _to, bytes memory _data) external {
        to = _to;
        data = _data;
    }

    fallback() external {
        (bool success, bytes memory retdata) = to.call(data);
        // bubble up the revert reason
        if (!success) {
            assembly {
                revert(add(retdata, 0x20), mload(retdata))
            }
        }
    }
}

contract DonatingProvider {
    TestERC20 public immutable cashAsset;

    constructor(TestERC20 _cashAsset) {
        cashAsset = _cashAsset;
    }

    function settlePosition(uint, int) external {
        cashAsset.transfer(msg.sender, 1);
    }
}
