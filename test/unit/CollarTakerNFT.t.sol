// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "forge-std/Test.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { TestERC20 } from "../utils/TestERC20.sol";

import { BaseAssetPairTestSetup, MockOracleUniV3TWAP } from "./BaseAssetPairTestSetup.sol";

import { CollarTakerNFT, ICollarTakerNFT } from "../../src/CollarTakerNFT.sol";
import { ICollarTakerNFT } from "../../src/interfaces/ICollarTakerNFT.sol";
import { CollarProviderNFT } from "../../src/CollarProviderNFT.sol";
import { ICollarProviderNFT } from "../../src/interfaces/ICollarProviderNFT.sol";

contract CollarTakerNFTTest is BaseAssetPairTestSetup {
    uint takerLocked = 1000 ether;
    uint providerLocked = 2000 ether;
    uint callStrikePrice = 1200 ether; // 120% of the price
    uint putStrikePrice = 900 ether; // 90% of the price corresponding to 9000 LTV

    uint offerId = 999; // stores latest ID, init to invalid

    function createOffer() internal {
        startHoax(provider);
        cashAsset.approve(address(providerNFT), largeAmount);

        uint expectedOfferId = providerNFT.nextPositionId();
        vm.expectEmit(address(providerNFT));
        emit ICollarProviderNFT.OfferCreated(
            provider, ltv, duration, callStrikePercent, largeAmount, expectedOfferId
        );
        offerId = providerNFT.createOffer(callStrikePercent, largeAmount, ltv, duration);
        CollarProviderNFT.LiquidityOffer memory offer = providerNFT.getOffer(offerId);
        assertEq(offer.callStrikePercent, callStrikePercent);
        assertEq(offer.available, largeAmount);
        assertEq(offer.provider, provider);
        assertEq(offer.duration, duration);
        assertEq(offer.callStrikePercent, callStrikePercent);
        assertEq(offer.putStrikePercent, ltv);
    }

    function checkOpenPairedPosition() internal returns (uint takerId, uint providerNFTId) {
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
            startPrice: twapPrice,
            putStrikePrice: putStrikePrice,
            callStrikePrice: callStrikePrice,
            takerLocked: takerLocked,
            providerLocked: _providerLocked,
            settled: false,
            withdrawable: 0
        });
        vm.expectEmit(address(takerNFT));
        emit ICollarTakerNFT.PairedPositionOpened(
            expectedTakerId, address(providerNFT), expectedProviderId, offerId, takerLocked, twapPrice
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
        assertEq(providerPos.providerLocked, providerLocked);
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
        mockOracle.setHistoricalAssetPrice(block.timestamp, priceToSettleAt);
        checkSettlePosition(takerId, priceToSettleAt, expectedProviderChange, true);
    }

    function checkSettlePosition(
        uint takerId,
        uint expectedSettlePrice,
        int expectedProviderChange,
        bool historicalUsed
    ) internal {
        CollarTakerNFT.TakerPosition memory takerPos = takerNFT.getPosition(takerId);
        uint providerNFTId = takerPos.providerId;
        uint expectedTakerOut = uint(int(takerLocked) - expectedProviderChange);
        uint expectedProviderOut = uint(int(providerLocked) + expectedProviderChange);

        // check the view
        {
            (uint takerBalanceView, int providerChangeView) =
                takerNFT.previewSettlement(takerId, expectedSettlePrice);
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
            historicalUsed,
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

    function checkWithdrawFromSettled(uint takerId, uint expectedTakerOut) public {
        uint cashBalanceBefore = cashAsset.balanceOf(user1);
        vm.expectEmit(address(takerNFT));
        emit ICollarTakerNFT.WithdrawalFromSettled(takerId, expectedTakerOut);
        uint withdrawal = takerNFT.withdrawFromSettled(takerId);
        assertEq(withdrawal, expectedTakerOut);
        assertEq(cashAsset.balanceOf(user1), cashBalanceBefore + expectedTakerOut);
        CollarTakerNFT.TakerPosition memory position = takerNFT.getPosition(takerId);
        assertEq(position.withdrawable, 0);
    }

    // tests

    function test_constructor() public {
        vm.expectEmit();
        emit ICollarTakerNFT.OracleSet(MockOracleUniV3TWAP(address(0)), mockOracle);
        vm.expectEmit();
        emit ICollarTakerNFT.CollarTakerNFTCreated(
            address(cashAsset), address(underlying), address(mockOracle)
        );
        CollarTakerNFT takerNFT = new CollarTakerNFT(
            owner, configHub, cashAsset, underlying, mockOracle, "NewCollarTakerNFT", "NBPNFT"
        );

        assertEq(takerNFT.owner(), owner);
        assertEq(takerNFT.pendingOwner(), address(0));
        assertEq(address(takerNFT.configHub()), address(configHub));
        assertEq(address(takerNFT.cashAsset()), address(cashAsset));
        assertEq(takerNFT.underlying(), address(underlying));
        assertEq(address(takerNFT.oracle()), address(mockOracle));
        assertEq(takerNFT.VERSION(), "0.2.0");
        assertEq(takerNFT.name(), "NewCollarTakerNFT");
        assertEq(takerNFT.symbol(), "NBPNFT");
        assertEq(takerNFT.nextPositionId(), 1);
    }

    function test_revert_constructor() public {
        // Create an oracle with mismatched assets
        MockOracleUniV3TWAP invalidOracle = new MockOracleUniV3TWAP(address(cashAsset), address(underlying));
        vm.expectRevert("oracle asset mismatch");
        new CollarTakerNFT(
            owner, configHub, cashAsset, underlying, invalidOracle, "NewCollarTakerNFT", "NBPNFT"
        );

        invalidOracle = new MockOracleUniV3TWAP(address(cashAsset), address(cashAsset));
        vm.expectRevert("oracle asset mismatch");
        new CollarTakerNFT(
            owner, configHub, cashAsset, underlying, invalidOracle, "NewCollarTakerNFT", "NBPNFT"
        );

        invalidOracle = new MockOracleUniV3TWAP(address(underlying), address(underlying));
        vm.expectRevert("oracle asset mismatch");
        new CollarTakerNFT(
            owner, configHub, cashAsset, underlying, invalidOracle, "NewCollarTakerNFT", "NBPNFT"
        );

        invalidOracle = new MockOracleUniV3TWAP(address(underlying), address(0));
        vm.expectRevert("oracle asset mismatch");
        new CollarTakerNFT(
            owner, configHub, cashAsset, underlying, invalidOracle, "NewCollarTakerNFT", "NBPNFT"
        );

        MockOracleUniV3TWAP newOracle = new MockOracleUniV3TWAP(address(underlying), address(cashAsset));
        newOracle.setHistoricalAssetPrice(block.timestamp, 0);
        vm.expectRevert("invalid current price");
        new CollarTakerNFT(owner, configHub, cashAsset, underlying, newOracle, "NewCollarTakerNFT", "NBPNFT");

        newOracle.setHistoricalAssetPrice(block.timestamp, 1);
        vm.mockCallRevert(
            address(newOracle),
            abi.encodeCall(newOracle.pastPriceWithFallback, (uint32(block.timestamp))),
            "mocked"
        );
        vm.expectRevert("mocked");
        new CollarTakerNFT(owner, configHub, cashAsset, underlying, newOracle, "NewCollarTakerNFT", "NBPNFT");

        newOracle.setHistoricalAssetPrice(block.timestamp, 1);
        // 1 current price, but 0 historical price
        vm.mockCall(address(newOracle), abi.encodeCall(newOracle.currentPrice, ()), abi.encode(1));
        vm.mockCall(
            address(newOracle),
            abi.encodeCall(newOracle.pastPriceWithFallback, (uint32(block.timestamp))),
            abi.encode(0, false)
        );
        vm.expectRevert("invalid past price");
        new CollarTakerNFT(owner, configHub, cashAsset, underlying, newOracle, "NewCollarTakerNFT", "NBPNFT");
        vm.clearMockedCalls();

        // 0 conversion view
        vm.mockCall(address(newOracle), abi.encodeCall(newOracle.convertToBaseAmount, (1, 1)), abi.encode(0));
        vm.expectRevert("invalid convertToBaseAmount");
        new CollarTakerNFT(owner, configHub, cashAsset, underlying, newOracle, "NewCollarTakerNFT", "NBPNFT");
        vm.clearMockedCalls();

        // reverting conversion view
        vm.mockCallRevert(address(newOracle), abi.encodeCall(newOracle.convertToBaseAmount, (1, 1)), "mocked");
        vm.expectRevert("mocked");
        new CollarTakerNFT(owner, configHub, cashAsset, underlying, newOracle, "NewCollarTakerNFT", "NBPNFT");

        // reverting historical price
        vm.mockCallRevert(
            address(newOracle),
            abi.encodeCall(newOracle.pastPriceWithFallback, (uint32(block.timestamp))),
            "mocked"
        );
        vm.expectRevert("mocked");
        new CollarTakerNFT(owner, configHub, cashAsset, underlying, newOracle, "NewCollarTakerNFT", "NBPNFT");
        vm.clearMockedCalls();
    }

    function test_pausableMethods() public {
        // create a position
        (uint takerId,) = checkOpenPairedPosition();

        startHoax(owner);
        takerNFT.pause();
        assertTrue(takerNFT.paused());

        // Try to open a position while paused
        vm.expectRevert(Pausable.EnforcedPause.selector);
        takerNFT.openPairedPosition(takerLocked, providerNFT, 0);
        // Try to settle a position while paused
        vm.expectRevert(Pausable.EnforcedPause.selector);
        takerNFT.settlePairedPosition(0);

        // Try to withdraw from settled while paused
        vm.expectRevert(Pausable.EnforcedPause.selector);
        takerNFT.withdrawFromSettled(0);

        // Try to cancel a paired position while paused
        vm.expectRevert(Pausable.EnforcedPause.selector);
        takerNFT.cancelPairedPosition(0);

        // transfers are paused
        vm.startPrank(user1);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        takerNFT.transferFrom(user1, provider, takerId);
    }

    function test_unpause() public {
        startHoax(owner);
        takerNFT.pause();
        takerNFT.unpause();
        assertFalse(takerNFT.paused());
        // Should be able to open a position after unpausing
        checkOpenPairedPosition();
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
        vm.expectRevert("taker position does not exist");
        takerNFT.getPosition(1000);

        vm.expectRevert("taker position does not exist");
        takerNFT.previewSettlement(1000, 0);

        vm.expectRevert("taker position does not exist");
        takerNFT.settlePairedPosition(1000);
    }

    /**
     * mutative functions
     * function cancelPairedPosition(uint takerId, address recipient) external;
     */
    function test_openPairedPosition() public {
        uint userBalanceBefore = cashAsset.balanceOf(user1);
        (uint takerId, uint providerNFTId) = checkOpenPairedPosition();
        assertEq(takerId, 1);
        assertEq(providerNFTId, 1);
        assertEq(cashAsset.balanceOf(user1), userBalanceBefore - takerLocked);
    }

    /**
     * openPaired validation errors:
     * and create offer doesnt allow you to put a put strike percent > 10000
     */
    function test_openPairedPositionUnsupportedCashAsset() public {
        createOffer();
        vm.startPrank(owner);
        configHub.setCashAssetSupport(address(cashAsset), false);
        startHoax(user1);
        vm.expectRevert("unsupported asset");
        takerNFT.openPairedPosition(takerLocked, providerNFT, 0);
    }

    function test_openPairedPositionUnsupportedUnderlying() public {
        createOffer();
        vm.startPrank(owner);
        configHub.setUnderlyingSupport(address(underlying), false);
        startHoax(user1);
        vm.expectRevert("unsupported asset");
        takerNFT.openPairedPosition(takerLocked, providerNFT, 0);
    }

    function test_openPairedPositionUnsupportedTakerContract() public {
        createOffer();
        vm.startPrank(owner);
        configHub.setCanOpen(address(takerNFT), false);
        startHoax(user1);
        vm.expectRevert("unsupported taker contract");
        takerNFT.openPairedPosition(takerLocked, providerNFT, 0);
    }

    function test_openPairedPositionUnsupportedProviderContract() public {
        createOffer();
        vm.startPrank(owner);
        configHub.setCanOpen(address(providerNFT), false);
        startHoax(user1);
        vm.expectRevert("unsupported provider contract");
        takerNFT.openPairedPosition(takerLocked, providerNFT, 0);
    }

    function test_openPairedPosition_badOfferId() public {
        createOffer();
        startHoax(user1);
        cashAsset.approve(address(takerNFT), takerLocked);
        vm.expectRevert("invalid offer");
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
        vm.expectRevert("expiration mismatch");
        takerNFT.openPairedPosition(takerLocked, providerNFT, offerId);
    }

    function test_openPairedPositionBadCashAssetMismatch() public {
        createOffer();
        vm.startPrank(owner);
        configHub.setCashAssetSupport(address(underlying), true);
        CollarProviderNFT providerNFTBad = new CollarProviderNFT(
            owner, configHub, underlying, underlying, address(takerNFT), "CollarTakerNFTBad", "BRWTSTBAD"
        );
        configHub.setCanOpen(address(providerNFTBad), true);
        startHoax(user1);
        cashAsset.approve(address(takerNFT), takerLocked);
        vm.expectRevert("asset mismatch");
        takerNFT.openPairedPosition(takerLocked, providerNFTBad, 0);
    }

    function test_openPairedPositionBadUnderlyingMismatch() public {
        createOffer();
        vm.startPrank(owner);
        configHub.setUnderlyingSupport(address(cashAsset), true);
        CollarProviderNFT providerNFTBad = new CollarProviderNFT(
            owner, configHub, cashAsset, cashAsset, address(takerNFT), "CollarTakerNFTBad", "BRWTSTBAD"
        );
        configHub.setCanOpen(address(providerNFTBad), true);
        startHoax(user1);
        cashAsset.approve(address(takerNFT), takerLocked);
        vm.expectRevert("asset mismatch");
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
        vm.expectRevert("strike prices not different");
        takerNFT.openPairedPosition(takerLocked, providerNFT, offerId);
    }

    function test_settleAndWIthdrawNoChange() public {
        uint takerId = createAndSettlePosition(twapPrice, 0);
        checkWithdrawFromSettled(takerId, takerLocked);
    }

    function test_settleAndWIthdrawPriceAboveCall() public {
        uint newPrice = callStrikePrice * 11 / 10;
        uint takerId = createAndSettlePosition(newPrice, -int(providerLocked));
        checkWithdrawFromSettled(takerId, takerLocked + providerLocked);
    }

    function test_settleAndWIthdrawPriceUp() public {
        uint newPrice = twapPrice * 110 / 100;
        uint takerId = createAndSettlePosition(newPrice, -int(providerLocked / 2));
        checkWithdrawFromSettled(takerId, takerLocked + providerLocked / 2);
    }

    function test_settleAndWIthdrawPriceBelowPut() public {
        uint newPrice = putStrikePrice * 9 / 10;
        uint takerId = createAndSettlePosition(newPrice, int(takerLocked));
        checkWithdrawFromSettled(takerId, 0);
    }

    function test_settleAndWIthdrawPriceDown() public {
        uint newPrice = twapPrice * 95 / 100;
        uint takerId = createAndSettlePosition(newPrice, int(takerLocked / 2));
        checkWithdrawFromSettled(takerId, takerLocked / 2);
    }

    function test_settleAndWIthdrawHistoricalPrice() public {
        uint expiryPice = twapPrice * 110 / 100;
        uint currentPrice = twapPrice * 120 / 100;

        uint expiration = block.timestamp + duration;
        mockOracle.setHistoricalAssetPrice(expiration, expiryPice);
        mockOracle.setHistoricalAssetPrice(expiration + 10 * duration, currentPrice);

        (uint takerId,) = checkOpenPairedPosition();
        skip(11 * duration);
        assertEq(takerNFT.currentOraclePrice(), currentPrice);
        (uint historicalPrice, bool historical) = takerNFT.historicalOraclePrice(expiration);
        assertEq(historicalPrice, expiryPice);
        assertTrue(historical);
        // settled at historical price and got 50% of providerLocked
        checkSettlePosition(takerId, expiryPice, -int(providerLocked / 2), true);
        checkWithdrawFromSettled(takerId, takerLocked + providerLocked / 2);
    }

    function test_settleAndWIthdrawFallbackToCurrent_MockOracle() public {
        uint currentPrice = twapPrice * 120 / 100;

        (uint takerId,) = checkOpenPairedPosition();
        uint expiration = block.timestamp + duration;

        // nock the pastPriceWithFallback view used by TakerNFT
        vm.mockCall(
            address(mockOracle),
            abi.encodeCall(mockOracle.pastPriceWithFallback, (uint32(expiration))),
            abi.encode(currentPrice, false)
        );
        mockOracle.setHistoricalAssetPrice(expiration + 10 * duration, currentPrice);

        skip(11 * duration);
        assertEq(takerNFT.currentOraclePrice(), currentPrice);
        (uint historicalPrice, bool historical) = takerNFT.historicalOraclePrice(expiration);
        assertEq(historicalPrice, currentPrice);
        assertFalse(historical);
        // settled at historical price and got 100% of providerLocked
        checkSettlePosition(takerId, currentPrice, -int(providerLocked), false);
        checkWithdrawFromSettled(takerId, takerLocked + providerLocked);
    }

    function test_settleAndWIthdrawFallbackToCurrent_MockInternalRevert() public {
        uint currentPrice = twapPrice * 120 / 100;

        (uint takerId,) = checkOpenPairedPosition();
        uint expiration = block.timestamp + duration;

        // nock revert the pastPrice view used by Oracle internally
        vm.mockCallRevert(address(mockOracle), abi.encodeCall(mockOracle.pastPrice, (uint32(expiration))), "");
        mockOracle.setHistoricalAssetPrice(expiration + 10 * duration, currentPrice);

        skip(11 * duration);
        assertEq(takerNFT.currentOraclePrice(), currentPrice);
        (uint historicalPrice, bool historical) = takerNFT.historicalOraclePrice(expiration);
        assertEq(historicalPrice, currentPrice);
        assertFalse(historical);
        // settled at historical price and got 100% of providerLocked
        checkSettlePosition(takerId, currentPrice, -int(providerLocked), false);
        checkWithdrawFromSettled(takerId, takerLocked + providerLocked);
    }

    function test_settlePairedPosition_NotExpired() public {
        (uint takerId,) = checkOpenPairedPosition();

        // Try to settle before expiration
        startHoax(user1);
        vm.expectRevert("not expired");
        takerNFT.settlePairedPosition(takerId);
    }

    function test_settlePairedPosition_AlreadySettled() public {
        (uint takerId,) = checkOpenPairedPosition();

        // Settle the position
        skip(301);
        startHoax(user1);
        takerNFT.settlePairedPosition(takerId);

        // Try to settle again
        vm.expectRevert("already settled");
        takerNFT.settlePairedPosition(takerId);
    }

    function test_withdrawFromSettled_NotOwner() public {
        (uint takerId,) = checkOpenPairedPosition();

        // Settle the position
        skip(301);
        startHoax(user1);
        takerNFT.settlePairedPosition(takerId);

        // Try to withdraw with a different address
        startHoax(address(0xdead));
        vm.expectRevert("not position owner");
        takerNFT.withdrawFromSettled(takerId);
    }

    function test_withdrawFromSettled_NotSettled() public {
        (uint takerId,) = checkOpenPairedPosition();

        // Try to withdraw before settling
        startHoax(user1);
        vm.expectRevert("not settled");
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

    function test_cancelPairedPosition_NotOwnerOfTakerID() public {
        (uint takerId,) = checkOpenPairedPosition();

        // Try to cancel with a different address
        startHoax(address(0xdead));
        vm.expectRevert("not owner of taker ID");
        takerNFT.cancelPairedPosition(takerId);
    }

    function test_cancelPairedPosition_NotOwnerOfProviderID() public {
        (uint takerId,) = checkOpenPairedPosition();

        // Transfer the taker NFT to another address, but not the provider NFT
        startHoax(user1);
        takerNFT.transferFrom(user1, address(0xbeef), takerId);

        // Try to cancel with the new taker NFT owner
        startHoax(address(0xbeef));
        vm.expectRevert("not owner of provider ID");
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
        vm.expectRevert("already settled");
        takerNFT.cancelPairedPosition(takerId);
    }

    function test_setOracle() public {
        // new oracle
        MockOracleUniV3TWAP newOracle = new MockOracleUniV3TWAP(address(underlying), address(cashAsset));

        uint newPrice = 1500 ether;
        newOracle.setHistoricalAssetPrice(block.timestamp, newPrice);

        startHoax(owner);
        vm.expectEmit(address(takerNFT));
        emit ICollarTakerNFT.OracleSet(mockOracle, newOracle);
        takerNFT.setOracle(newOracle);

        assertEq(address(takerNFT.oracle()), address(newOracle));
        assertEq(takerNFT.currentOraclePrice(), newPrice);
    }

    function test_revert_setOracle() public {
        startHoax(user1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        takerNFT.setOracle(mockOracle);

        startHoax(owner);

        // Create an oracle with mismatched assets
        MockOracleUniV3TWAP invalidOracle = new MockOracleUniV3TWAP(address(cashAsset), address(underlying));
        vm.expectRevert("oracle asset mismatch");
        takerNFT.setOracle(invalidOracle);

        invalidOracle = new MockOracleUniV3TWAP(address(cashAsset), address(cashAsset));
        vm.expectRevert("oracle asset mismatch");
        takerNFT.setOracle(invalidOracle);

        invalidOracle = new MockOracleUniV3TWAP(address(underlying), address(underlying));
        vm.expectRevert("oracle asset mismatch");
        takerNFT.setOracle(invalidOracle);

        invalidOracle = new MockOracleUniV3TWAP(address(underlying), address(0));
        vm.expectRevert("oracle asset mismatch");
        takerNFT.setOracle(invalidOracle);

        MockOracleUniV3TWAP newOracle = new MockOracleUniV3TWAP(address(underlying), address(cashAsset));
        newOracle.setHistoricalAssetPrice(block.timestamp, 0);
        vm.expectRevert("invalid current price");
        takerNFT.setOracle(newOracle);

        newOracle.setHistoricalAssetPrice(block.timestamp, 1);
        // 1 current price, but 0 historical price
        vm.mockCall(address(newOracle), abi.encodeCall(newOracle.currentPrice, ()), abi.encode(1));
        vm.mockCall(
            address(newOracle),
            abi.encodeCall(newOracle.pastPriceWithFallback, (uint32(block.timestamp))),
            abi.encode(0, false)
        );
        vm.expectRevert("invalid past price");
        takerNFT.setOracle(newOracle);
        vm.clearMockedCalls();

        // 0 conversion view
        vm.mockCall(address(newOracle), abi.encodeCall(newOracle.convertToBaseAmount, (1, 1)), abi.encode(0));
        vm.expectRevert("invalid convertToBaseAmount");
        takerNFT.setOracle(newOracle);
        vm.clearMockedCalls();

        // reverting conversion view
        vm.mockCallRevert(address(newOracle), abi.encodeCall(newOracle.convertToBaseAmount, (1, 1)), "mocked");
        vm.expectRevert("mocked");
        takerNFT.setOracle(newOracle);
        vm.clearMockedCalls();

        // reverting historical price
        vm.mockCallRevert(
            address(newOracle),
            abi.encodeCall(newOracle.pastPriceWithFallback, (uint32(block.timestamp))),
            "mocked"
        );
        vm.expectRevert("mocked");
        takerNFT.setOracle(newOracle);
    }

    function test_revert_historicalOraclePrice_overflow() public {
        uint overflow32 = uint(type(uint32).max) + 1;
        vm.expectRevert(
            abi.encodeWithSelector(SafeCast.SafeCastOverflowedUintDowncast.selector, 32, overflow32)
        );
        takerNFT.historicalOraclePrice(overflow32);
    }
}
