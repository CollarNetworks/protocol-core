// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity 0.8.22;

import "forge-std/Test.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { TestERC20 } from "../utils/TestERC20.sol";

import { BaseAssetPairTestSetup, MockOracleUniV3TWAP } from "./BaseAssetPairTestSetup.sol";

import { CollarTakerNFT, ICollarTakerNFT } from "../../src/CollarTakerNFT.sol";
import { ICollarTakerNFT } from "../../src/interfaces/ICollarTakerNFT.sol";
import { ShortProviderNFT } from "../../src/ShortProviderNFT.sol";
import { IShortProviderNFT } from "../../src/interfaces/IShortProviderNFT.sol";

contract CollarTakerNFTTest is BaseAssetPairTestSetup {
    uint putLocked = 1000 ether;
    uint callLocked = 2000 ether;
    uint callStrikePrice = 1200 ether; // 120% of the price
    uint putStrikePrice = 900 ether; // 90% of the price corresponding to 9000 LTV

    uint offerId = 999; // stores latest ID, init to invalid

    function createOffer() internal {
        startHoax(provider);
        cashAsset.approve(address(providerNFT), largeAmount);

        uint expectedOfferId = providerNFT.nextPositionId();
        vm.expectEmit(address(providerNFT));
        emit IShortProviderNFT.OfferCreated(
            provider, ltv, duration, callStrikeDeviation, largeAmount, expectedOfferId
        );
        offerId = providerNFT.createOffer(callStrikeDeviation, largeAmount, ltv, duration);
        ShortProviderNFT.LiquidityOffer memory offer = providerNFT.getOffer(offerId);
        assertEq(offer.callStrikeDeviation, callStrikeDeviation);
        assertEq(offer.available, largeAmount);
        assertEq(offer.provider, provider);
        assertEq(offer.duration, duration);
        assertEq(offer.callStrikeDeviation, callStrikeDeviation);
        assertEq(offer.putStrikeDeviation, ltv);
    }

    function checkOpenPairedPosition() internal returns (uint takerId, uint providerNFTId) {
        createOffer();

        startHoax(user1);
        cashAsset.approve(address(takerNFT), putLocked);

        // expected values
        uint expectedTakerId = takerNFT.nextPositionId();
        uint expectedProviderId = providerNFT.nextPositionId();
        uint _callLocked = checkCalculateProviderLocked(putLocked, ltv, callStrikeDeviation);

        ICollarTakerNFT.TakerPosition memory expectedTakerPos = ICollarTakerNFT.TakerPosition({
            providerNFT: providerNFT,
            providerPositionId: expectedProviderId,
            duration: duration,
            expiration: block.timestamp + duration,
            initialPrice: twapPrice,
            putStrikePrice: putStrikePrice,
            callStrikePrice: callStrikePrice,
            putLockedCash: putLocked,
            callLockedCash: _callLocked,
            settled: false,
            withdrawable: 0
        });
        vm.expectEmit(address(takerNFT));
        emit ICollarTakerNFT.PairedPositionOpened(
            expectedTakerId, address(providerNFT), expectedProviderId, offerId, expectedTakerPos
        );
        (takerId, providerNFTId) = takerNFT.openPairedPosition(putLocked, providerNFT, offerId);
        // return values
        assertEq(takerId, expectedTakerId);
        assertEq(providerNFTId, expectedProviderId);

        // position view
        CollarTakerNFT.TakerPosition memory takerPos = takerNFT.getPosition(takerId);
        assertEq(abi.encode(takerPos), abi.encode(expectedTakerPos));

        // provider position
        ShortProviderNFT.ProviderPosition memory providerPos = providerNFT.getPosition(providerNFTId);
        assertEq(providerPos.expiration, block.timestamp + duration);
        assertEq(providerPos.principal, callLocked);
        assertEq(providerPos.putStrikeDeviation, ltv);
        assertEq(providerPos.callStrikeDeviation, callStrikeDeviation);
        assertEq(providerPos.settled, false);
        assertEq(providerPos.withdrawable, 0);
    }

    function checkCalculateProviderLocked(uint _putLocked, uint putStrike, uint callStrike)
        internal
        view
        returns (uint _callLocked)
    {
        // calculate
        uint putRange = BIPS_100PCT - putStrike;
        uint callRange = callStrike - BIPS_100PCT;
        _callLocked = callRange * _putLocked / putRange;
        // check view agrees
        assertEq(_callLocked, takerNFT.calculateProviderLocked(_putLocked, putStrike, callStrike));
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
        uint providerNFTId = takerPos.providerPositionId;
        uint expectedTakerOut = uint(int(putLocked) - expectedProviderChange);
        uint expectedProviderOut = uint(int(callLocked) + expectedProviderChange);

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
        emit IShortProviderNFT.PositionSettled(providerNFTId, expectedProviderChange, expectedProviderOut);
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

        ShortProviderNFT.ProviderPosition memory providerPosAfter = providerNFT.getPosition(providerNFTId);
        assertEq(providerPosAfter.settled, true);
        assertEq(providerPosAfter.withdrawable, expectedProviderOut);
    }

    function checkWithdrawFromSettled(uint takerId, uint expectedTakerOut) public {
        uint cashBalanceBefore = cashAsset.balanceOf(user1);
        vm.expectEmit(address(takerNFT));
        emit ICollarTakerNFT.WithdrawalFromSettled(takerId, user1, expectedTakerOut);
        uint withdrawal = takerNFT.withdrawFromSettled(takerId, user1);
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
            address(cashAsset), address(collateralAsset), address(mockOracle)
        );
        CollarTakerNFT takerNFT = new CollarTakerNFT(
            owner, configHub, cashAsset, collateralAsset, mockOracle, "NewCollarTakerNFT", "NBPNFT"
        );

        assertEq(takerNFT.owner(), owner);
        assertEq(takerNFT.pendingOwner(), address(0));
        assertEq(address(takerNFT.configHub()), address(configHub));
        assertEq(address(takerNFT.cashAsset()), address(cashAsset));
        assertEq(address(takerNFT.collateralAsset()), address(collateralAsset));
        assertEq(address(takerNFT.oracle()), address(mockOracle));
        assertEq(takerNFT.VERSION(), "0.2.0");
        assertEq(takerNFT.name(), "NewCollarTakerNFT");
        assertEq(takerNFT.symbol(), "NBPNFT");
        assertEq(takerNFT.nextPositionId(), 0);
    }

    function test_revert_constructor() public {
        // Create an oracle with mismatched assets
        MockOracleUniV3TWAP invalidOracle =
            new MockOracleUniV3TWAP(address(cashAsset), address(collateralAsset));
        vm.expectRevert("oracle asset mismatch");
        new CollarTakerNFT(
            owner, configHub, cashAsset, collateralAsset, invalidOracle, "NewCollarTakerNFT", "NBPNFT"
        );

        invalidOracle = new MockOracleUniV3TWAP(address(cashAsset), address(cashAsset));
        vm.expectRevert("oracle asset mismatch");
        new CollarTakerNFT(
            owner, configHub, cashAsset, collateralAsset, invalidOracle, "NewCollarTakerNFT", "NBPNFT"
        );

        invalidOracle = new MockOracleUniV3TWAP(address(collateralAsset), address(collateralAsset));
        vm.expectRevert("oracle asset mismatch");
        new CollarTakerNFT(
            owner, configHub, cashAsset, collateralAsset, invalidOracle, "NewCollarTakerNFT", "NBPNFT"
        );

        invalidOracle = new MockOracleUniV3TWAP(address(collateralAsset), address(0));
        vm.expectRevert("oracle asset mismatch");
        new CollarTakerNFT(
            owner, configHub, cashAsset, collateralAsset, invalidOracle, "NewCollarTakerNFT", "NBPNFT"
        );

        MockOracleUniV3TWAP newOracle = new MockOracleUniV3TWAP(address(collateralAsset), address(cashAsset));
        newOracle.setHistoricalAssetPrice(block.timestamp, 0);
        vm.expectRevert("invalid price");
        new CollarTakerNFT(
            owner, configHub, cashAsset, collateralAsset, newOracle, "NewCollarTakerNFT", "NBPNFT"
        );
    }

    function test_pausableMethods() public {
        // create a position
        (uint takerId,) = checkOpenPairedPosition();

        startHoax(owner);
        takerNFT.pause();
        assertTrue(takerNFT.paused());

        // Try to open a position while paused
        vm.expectRevert(Pausable.EnforcedPause.selector);
        takerNFT.openPairedPosition(putLocked, providerNFT, 0);
        // Try to settle a position while paused
        vm.expectRevert(Pausable.EnforcedPause.selector);
        takerNFT.settlePairedPosition(0);

        // Try to withdraw from settled while paused
        vm.expectRevert(Pausable.EnforcedPause.selector);
        takerNFT.withdrawFromSettled(0, address(this));

        // Try to cancel a paired position while paused
        vm.expectRevert(Pausable.EnforcedPause.selector);
        takerNFT.cancelPairedPosition(0, address(this));

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

    function test_getPosition_empty() public view {
        CollarTakerNFT.TakerPosition memory position = takerNFT.getPosition(0);
        assertEq(position.callStrikePrice, 0);
        assertEq(position.putLockedCash, 0);
        assertEq(position.callLockedCash, 0);
        assertEq(position.settled, false);
        assertEq(position.withdrawable, 0);
    }

    /**
     * mutative functions
     * function cancelPairedPosition(uint takerId, address recipient) external;
     */
    function test_openPairedPosition() public {
        uint userBalanceBefore = cashAsset.balanceOf(user1);
        (uint takerId, uint providerNFTId) = checkOpenPairedPosition();
        assertEq(takerId, 0);
        assertEq(providerNFTId, 0);
        assertEq(cashAsset.balanceOf(user1), userBalanceBefore - putLocked);
    }

    /**
     * openPaired validation errors:
     *  "invalid put strike deviation" // cant get this since it checks that putStrike deviation is < 10000
     * and create offer doesnt allow you to put a put strike deviation > 10000
     */
    function test_openPairedPositionUnsupportedCashAsset() public {
        createOffer();
        vm.startPrank(owner);
        configHub.setCashAssetSupport(address(cashAsset), false);
        startHoax(user1);
        vm.expectRevert("unsupported asset");
        takerNFT.openPairedPosition(putLocked, providerNFT, 0);
    }

    function test_openPairedPositionUnsupportedCollateralAsset() public {
        createOffer();
        vm.startPrank(owner);
        configHub.setCollateralAssetSupport(address(collateralAsset), false);
        startHoax(user1);
        vm.expectRevert("unsupported asset");
        takerNFT.openPairedPosition(putLocked, providerNFT, 0);
    }

    function test_openPairedPositionUnsupportedTakerContract() public {
        createOffer();
        vm.startPrank(owner);
        configHub.setCanOpen(address(takerNFT), false);
        startHoax(user1);
        vm.expectRevert("unsupported taker contract");
        takerNFT.openPairedPosition(putLocked, providerNFT, 0);
    }

    function test_openPairedPositionUnsupportedProviderContract() public {
        createOffer();
        vm.startPrank(owner);
        configHub.setCanOpen(address(providerNFT), false);
        startHoax(user1);
        vm.expectRevert("unsupported provider contract");
        takerNFT.openPairedPosition(putLocked, providerNFT, 0);
    }

    function test_openPairedPosition_badOfferId() public {
        createOffer();
        startHoax(user1);
        cashAsset.approve(address(takerNFT), putLocked);
        vm.expectRevert("invalid offer");
        takerNFT.openPairedPosition(putLocked, providerNFT, 1000);
    }

    function test_openPairedPositionBadCashAssetMismatch() public {
        createOffer();
        vm.startPrank(owner);
        configHub.setCashAssetSupport(address(collateralAsset), true);
        ShortProviderNFT providerNFTBad = new ShortProviderNFT(
            owner,
            configHub,
            collateralAsset,
            collateralAsset,
            address(takerNFT),
            "CollarTakerNFTBad",
            "BRWTSTBAD"
        );
        configHub.setCanOpen(address(providerNFTBad), true);
        startHoax(user1);
        cashAsset.approve(address(takerNFT), putLocked);
        vm.expectRevert("asset mismatch");
        takerNFT.openPairedPosition(putLocked, providerNFTBad, 0);
    }

    function test_openPairedPositionBadCollateralAssetMismatch() public {
        createOffer();
        vm.startPrank(owner);
        configHub.setCollateralAssetSupport(address(cashAsset), true);
        ShortProviderNFT providerNFTBad = new ShortProviderNFT(
            owner, configHub, cashAsset, cashAsset, address(takerNFT), "CollarTakerNFTBad", "BRWTSTBAD"
        );
        configHub.setCanOpen(address(providerNFTBad), true);
        startHoax(user1);
        cashAsset.approve(address(takerNFT), putLocked);
        vm.expectRevert("asset mismatch");
        takerNFT.openPairedPosition(putLocked, providerNFTBad, 0);
    }

    function test_openPairedPositionStrikePricesArentDifferent() public {
        vm.startPrank(owner);
        configHub.setLTVRange(9990, 9990);
        callStrikeDeviation = 10_010;
        ltv = 9990;
        createOffer();
        updatePrice(991);
        startHoax(user1);
        cashAsset.approve(address(takerNFT), putLocked);
        vm.expectRevert("strike prices aren't different");
        takerNFT.openPairedPosition(putLocked, providerNFT, offerId);
    }

    function test_openPairedPosition_unexpectedTakerId() public {
        createOffer();
        startHoax(user1);
        cashAsset.approve(address(takerNFT), putLocked);
        uint expectedId = takerNFT.nextPositionId();
        vm.mockCall(
            address(providerNFT),
            abi.encodeCall(providerNFT.mintFromOffer, (offerId, callLocked, expectedId)),
            abi.encode(
                0,
                IShortProviderNFT.ProviderPosition({
                    takerId: expectedId + 1, // wrong ID
                    expiration: 0,
                    principal: 0,
                    putStrikeDeviation: 0,
                    callStrikeDeviation: 2 * BIPS_100PCT,
                    settled: false,
                    withdrawable: 0
                })
            )
        );
        vm.expectRevert("unexpected takerId");
        takerNFT.openPairedPosition(putLocked, providerNFT, offerId);
    }

    function test_settleAndWIthdrawNoChange() public {
        uint takerId = createAndSettlePosition(twapPrice, 0);
        checkWithdrawFromSettled(takerId, putLocked);
    }

    function test_settleAndWIthdrawPriceAboveCall() public {
        uint newPrice = callStrikePrice * 11 / 10;
        uint takerId = createAndSettlePosition(newPrice, -int(callLocked));
        checkWithdrawFromSettled(takerId, putLocked + callLocked);
    }

    function test_settleAndWIthdrawPriceUp() public {
        uint newPrice = twapPrice * 110 / 100;
        uint takerId = createAndSettlePosition(newPrice, -int(callLocked / 2));
        checkWithdrawFromSettled(takerId, putLocked + callLocked / 2);
    }

    function test_settleAndWIthdrawPriceBelowPut() public {
        uint newPrice = putStrikePrice * 9 / 10;
        uint takerId = createAndSettlePosition(newPrice, int(putLocked));
        checkWithdrawFromSettled(takerId, 0);
    }

    function test_settleAndWIthdrawPriceDown() public {
        uint newPrice = twapPrice * 95 / 100;
        uint takerId = createAndSettlePosition(newPrice, int(putLocked / 2));
        checkWithdrawFromSettled(takerId, putLocked / 2);
    }

    function test_settleAndWIthdrawHistoricalPrice() public {
        uint expiryPice = twapPrice * 110 / 100;
        uint currentPrice = twapPrice * 120 / 100;

        mockOracle.setHistoricalAssetPrice(block.timestamp + duration, expiryPice);
        mockOracle.setHistoricalAssetPrice(block.timestamp + 10 * duration, currentPrice);

        (uint takerId,) = checkOpenPairedPosition();
        skip(10 * duration);
        assertEq(takerNFT.currentOraclePrice(), currentPrice);
        // settled at historical price and got 50% of callLocked
        checkSettlePosition(takerId, expiryPice, -int(callLocked / 2), true);
        checkWithdrawFromSettled(takerId, putLocked + callLocked / 2);
    }

    function test_settleAndWIthdrawFallbackToCurrent_MockOracle() public {
        uint currentPrice = twapPrice * 120 / 100;

        (uint takerId,) = checkOpenPairedPosition();

        // nock the pastPriceWithFallback view used by TakerNFT
        vm.mockCall(
            address(mockOracle),
            abi.encodeCall(mockOracle.pastPriceWithFallback, (uint32(block.timestamp + duration))),
            abi.encode(currentPrice, false)
        );
        mockOracle.setHistoricalAssetPrice(block.timestamp + 10 * duration, currentPrice);

        skip(10 * duration);
        assertEq(takerNFT.currentOraclePrice(), currentPrice);
        // settled at historical price and got 100% of callLocked
        checkSettlePosition(takerId, currentPrice, -int(callLocked), false);
        checkWithdrawFromSettled(takerId, putLocked + callLocked);
    }

    function test_settleAndWIthdrawFallbackToCurrent_MockInternalRevert() public {
        uint currentPrice = twapPrice * 120 / 100;

        (uint takerId,) = checkOpenPairedPosition();

        // nock revert the pastPrice view used by Oracle internally
        vm.mockCallRevert(
            address(mockOracle),
            abi.encodeCall(mockOracle.pastPrice, (uint32(block.timestamp + duration))),
            ""
        );
        mockOracle.setHistoricalAssetPrice(block.timestamp + 10 * duration, currentPrice);

        skip(10 * duration);
        assertEq(takerNFT.currentOraclePrice(), currentPrice);
        // settled at historical price and got 100% of callLocked
        checkSettlePosition(takerId, currentPrice, -int(callLocked), false);
        checkWithdrawFromSettled(takerId, putLocked + callLocked);
    }

    function test_withdrawRecipient() public {
        uint expectedTakerOut = putLocked;
        uint takerId = createAndSettlePosition(twapPrice, 0);
        // non owner recipient
        address recipient = address(0x123);
        uint cashBalanceBefore = cashAsset.balanceOf(recipient);
        uint cashBalanceUserBefore = cashAsset.balanceOf(user1);
        vm.expectEmit(address(takerNFT));
        emit ICollarTakerNFT.WithdrawalFromSettled(takerId, recipient, expectedTakerOut);
        uint withdrawal = takerNFT.withdrawFromSettled(takerId, recipient);
        assertEq(withdrawal, expectedTakerOut);
        assertEq(cashAsset.balanceOf(recipient), cashBalanceBefore + expectedTakerOut);
        assertEq(cashAsset.balanceOf(user1), cashBalanceUserBefore);
        CollarTakerNFT.TakerPosition memory position = takerNFT.getPosition(takerId);
        assertEq(position.withdrawable, 0);
    }

    function test_settlePairedPosition_NonExistentPosition() public {
        vm.expectRevert("position doesn't exist");
        takerNFT.settlePairedPosition(999); // Use a position ID that doesn't exist
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
        takerNFT.withdrawFromSettled(takerId, address(0xdead));
    }

    function test_withdrawFromSettled_NotSettled() public {
        (uint takerId,) = checkOpenPairedPosition();

        // Try to withdraw before settling
        startHoax(user1);
        vm.expectRevert("not settled");
        takerNFT.withdrawFromSettled(takerId, user1);
    }

    function test_cancelPairedPosition() public {
        (uint takerId, uint providerNFTId) = checkOpenPairedPosition();

        address recipient = address(123);

        uint userCashBefore = cashAsset.balanceOf(user1);
        uint providerCashBefore = cashAsset.balanceOf(provider);
        uint recipientCashBefore = cashAsset.balanceOf(recipient);

        startHoax(user1);
        takerNFT.safeTransferFrom(user1, provider, takerId);
        startHoax(provider);
        takerNFT.approve(address(takerNFT), takerId);
        providerNFT.approve(address(takerNFT), providerNFTId);
        vm.expectEmit(address(takerNFT));
        emit ICollarTakerNFT.PairedPositionCanceled(
            takerId, address(providerNFT), providerNFTId, recipient, putLocked, block.timestamp + duration
        );
        takerNFT.cancelPairedPosition(takerId, recipient);

        // view
        CollarTakerNFT.TakerPosition memory position = takerNFT.getPosition(takerId);
        assertEq(position.settled, true);
        assertEq(position.withdrawable, 0);

        // balances
        assertEq(cashAsset.balanceOf(recipient), recipientCashBefore + putLocked + callLocked);
        assertEq(cashAsset.balanceOf(user1), userCashBefore);
        assertEq(cashAsset.balanceOf(provider), providerCashBefore);
    }

    function test_cancelPairedPosition_NotOwnerOfTakerID() public {
        (uint takerId,) = checkOpenPairedPosition();

        // Try to cancel with a different address
        startHoax(address(0xdead));
        vm.expectRevert("not owner of taker ID");
        takerNFT.cancelPairedPosition(takerId, address(0xdead));
    }

    function test_cancelPairedPosition_NotOwnerOfProviderID() public {
        (uint takerId,) = checkOpenPairedPosition();

        // Transfer the taker NFT to another address, but not the provider NFT
        startHoax(user1);
        takerNFT.transferFrom(user1, address(0xbeef), takerId);

        // Try to cancel with the new taker NFT owner
        startHoax(address(0xbeef));
        vm.expectRevert("not owner of provider ID");
        takerNFT.cancelPairedPosition(takerId, address(0xbeef));
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
        takerNFT.cancelPairedPosition(takerId, user1);
    }

    function test_calculateProviderLocked_revert() public {
        uint putLockedCash = 1000 ether;
        uint putStrikeDeviation = 10_000; // This will cause a division by zero
        uint callStrikeDeviation = 12_000;

        vm.expectRevert("invalid put strike deviation");
        takerNFT.calculateProviderLocked(putLockedCash, putStrikeDeviation, callStrikeDeviation);
    }

    function test_setOracle() public {
        // new oracle
        MockOracleUniV3TWAP newOracle = new MockOracleUniV3TWAP(address(collateralAsset), address(cashAsset));

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
        MockOracleUniV3TWAP invalidOracle =
            new MockOracleUniV3TWAP(address(cashAsset), address(collateralAsset));
        vm.expectRevert("oracle asset mismatch");
        takerNFT.setOracle(invalidOracle);

        invalidOracle = new MockOracleUniV3TWAP(address(cashAsset), address(cashAsset));
        vm.expectRevert("oracle asset mismatch");
        takerNFT.setOracle(invalidOracle);

        invalidOracle = new MockOracleUniV3TWAP(address(collateralAsset), address(collateralAsset));
        vm.expectRevert("oracle asset mismatch");
        takerNFT.setOracle(invalidOracle);

        invalidOracle = new MockOracleUniV3TWAP(address(collateralAsset), address(0));
        vm.expectRevert("oracle asset mismatch");
        takerNFT.setOracle(invalidOracle);

        MockOracleUniV3TWAP newOracle = new MockOracleUniV3TWAP(address(collateralAsset), address(cashAsset));
        newOracle.setHistoricalAssetPrice(block.timestamp, 0);
        vm.expectRevert("invalid price");
        takerNFT.setOracle(newOracle);
    }
}
