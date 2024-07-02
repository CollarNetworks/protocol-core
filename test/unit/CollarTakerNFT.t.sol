// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity 0.8.22;

import "forge-std/Test.sol";
import { TestERC20 } from "../utils/TestERC20.sol";
import { MockEngine } from "../../test/utils/MockEngine.sol";
import { CollarTakerNFT } from "../../src/CollarTakerNFT.sol";
import { ICollarTakerNFT } from "../../src/interfaces/ICollarTakerNFT.sol";
import { ProviderPositionNFT } from "../../src/ProviderPositionNFT.sol";
import { IProviderPositionNFT } from "../../src/interfaces/IProviderPositionNFT.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";

contract CollarTakerNFTTest is Test {
    TestERC20 cashAsset;
    TestERC20 collateralAsset;
    MockEngine engine;
    CollarTakerNFT takerNFT;
    ProviderPositionNFT providerNFT;
    address user1 = makeAddr("user1");
    address provider = makeAddr("provider");
    address owner = makeAddr("owner");
    uint amountToUse = 10_000 ether;
    uint ltvToUse = 9000;
    uint durationToUse = 300;
    uint putLockedCashToUse = 1000 ether;
    uint callLockedCashToUse = 2000 ether;
    uint priceToUse = 1 ether;
    uint callStrikePrice = 1.2 ether; // 120% of the price
    uint pastCallStrikePrice = 1.25 ether; // 125% of the price | to use when price goes over call strike
        // price
    uint putStrikePrice = 0.9 ether; // 90% of the price corresponding to 9000 LTV
    uint pastPutStrikePrice = 0.8 ether; // 80% of the price | to use when price goes under put strike price
    uint callStrikeDeviationToUse = 12_000;
    uint amountToProvide = 100_000 ether;

    function setUp() public {
        cashAsset = new TestERC20("TestCash", "TestCash");
        collateralAsset = new TestERC20("TestCollat", "TestCollat");
        cashAsset.mint(provider, 100_000_000 ether);
        vm.label(address(cashAsset), "TestCash");
        vm.label(address(collateralAsset), "TestCollat");
        engine = setupMockEngine();
        vm.label(address(engine), "CollarEngine");
        engine.addSupportedCashAsset(address(cashAsset));
        engine.addSupportedCollateralAsset(address(collateralAsset));
        takerNFT = new CollarTakerNFT(owner, engine, cashAsset, collateralAsset, "CollarTakerNFT", "BRWTST");
        providerNFT = new ProviderPositionNFT(
            owner, engine, cashAsset, collateralAsset, address(takerNFT), "CollarTakerNFT", "BRWTST"
        );
        engine.setCollarTakerContractAuth(address(takerNFT), true);
        engine.setProviderContractAuth(address(providerNFT), true);
        vm.label(address(takerNFT), "CollarTakerNFT");
        vm.label(address(providerNFT), "ProviderPositionNFT");
    }

    function setupMockEngine() public returns (MockEngine mockEngine) {
        mockEngine = new MockEngine(address(0));
        mockEngine.addLTV(ltvToUse);
        mockEngine.addCollarDuration(durationToUse);
    }

    function setPricesAtTimestamp(MockEngine engineToUse, uint timestamp, uint price) internal {
        engineToUse.setHistoricalAssetPrice(address(collateralAsset), timestamp, price);
        engineToUse.setHistoricalAssetPrice(address(cashAsset), timestamp, price);
    }

    function mintTokensToUserandApproveNFT() internal {
        cashAsset.mint(user1, amountToUse);
        cashAsset.approve(address(takerNFT), amountToUse);
    }

    function createOfferAsProvider(
        uint callStrike,
        uint putStrikeDeviation,
        ProviderPositionNFT providerNFTToUse
    )
        internal
        returns (uint offerId)
    {
        startHoax(provider);
        cashAsset.approve(address(providerNFTToUse), 1_000_000 ether);

        uint expectedOfferId = providerNFTToUse.nextPositionId();
        vm.expectEmit(address(providerNFTToUse));
        emit IProviderPositionNFT.OfferCreated(
            provider, putStrikeDeviation, durationToUse, callStrike, amountToProvide, expectedOfferId
        );
        offerId = providerNFTToUse.createOffer(callStrike, amountToProvide, putStrikeDeviation, durationToUse);
        ProviderPositionNFT.LiquidityOffer memory offer = providerNFTToUse.getOffer(offerId);
        assertEq(offer.callStrikeDeviation, callStrike);
        assertEq(offer.available, amountToProvide);
        assertEq(offer.provider, provider);
        assertEq(offer.duration, durationToUse);
        assertEq(offer.callStrikeDeviation, callStrike);
        assertEq(offer.putStrikeDeviation, putStrikeDeviation);
    }

    function createTakerPositionAsUser(
        uint offerId,
        CollarTakerNFT takerNFTToUse,
        ProviderPositionNFT providerNFTToUse
    )
        internal
        returns (uint takerId, uint providerNFTId)
    {
        startHoax(user1);
        cashAsset.approve(address(takerNFT), putLockedCashToUse);
        (takerId, providerNFTId) =
            takerNFTToUse.openPairedPosition(putLockedCashToUse, providerNFTToUse, offerId);
        checkTakerPosition();
        checkProviderPosition();
    }

    function createOfferMintTouserAndSetPrice() internal {
        createOfferAsProvider(callStrikeDeviationToUse, ltvToUse, providerNFT);
        mintTokensToUserandApproveNFT();
        setPricesAtTimestamp(engine, 1, priceToUse);
    }

    function checkTakerPosition() internal view {
        CollarTakerNFT.TakerPosition memory position = takerNFT.getPosition(0);
        assertEq(position.callStrikePrice, callStrikePrice);
        assertEq(position.putLockedCash, putLockedCashToUse);
        assertEq(position.callLockedCash, callLockedCashToUse);
        assertEq(position.settled, false);
        assertEq(position.withdrawable, 0);
    }

    function checkProviderPosition() internal view {
        ProviderPositionNFT.ProviderPosition memory position = providerNFT.getPosition(0);
        assertEq(position.expiration, 301);
        assertEq(position.principal, callLockedCashToUse);
        assertEq(position.putStrikeDeviation, ltvToUse);
        assertEq(position.callStrikeDeviation, callStrikeDeviationToUse);
        assertEq(position.settled, false);
        assertEq(position.withdrawable, 0);
    }

    function createAndSettlePositionOnPrice(
        uint priceToSettleAt,
        uint expectedTakerWithdrawable,
        uint expectedProviderWithdrawable,
        int expectedProviderChange
    )
        internal
        returns (uint takerId, uint providerNFTId)
    {
        createOfferMintTouserAndSetPrice();
        (takerId, providerNFTId) = createTakerPositionAsUser(0, takerNFT, providerNFT);
        skip(301);
        setPricesAtTimestamp(engine, 301, priceToSettleAt);

        startHoax(user1);
        vm.expectEmit(address(providerNFT));
        emit IProviderPositionNFT.PositionSettled(
            providerNFTId, expectedProviderChange, expectedProviderWithdrawable
        );
        vm.expectEmit(address(takerNFT));
        emit ICollarTakerNFT.PairedPositionSettled(
            takerId,
            address(providerNFT),
            providerNFTId,
            priceToSettleAt,
            expectedTakerWithdrawable,
            expectedProviderChange
        );
        takerNFT.settlePairedPosition(takerId);
    }

    function test_constructor() public {
        CollarTakerNFT newTakerNFT =
            new CollarTakerNFT(owner, engine, cashAsset, collateralAsset, "NewCollarTakerNFT", "NBPNFT");

        assertEq(address(newTakerNFT.engine()), address(engine));
        assertEq(address(newTakerNFT.cashAsset()), address(cashAsset));
        assertEq(address(newTakerNFT.collateralAsset()), address(collateralAsset));
        assertEq(newTakerNFT.name(), "NewCollarTakerNFT");
        assertEq(newTakerNFT.symbol(), "NBPNFT");
    }

    /**
     * Test methods that are inherited from other contracts
     */

    /**
     * Pausable
     */
    function test_pause() public {
        startHoax(owner);
        takerNFT.pause();
        assertTrue(takerNFT.paused());

        // Try to open a position while paused
        vm.expectRevert(Pausable.EnforcedPause.selector);
        takerNFT.openPairedPosition(putLockedCashToUse, providerNFT, 0);
        // Try to settle a position while paused
        vm.expectRevert(Pausable.EnforcedPause.selector);
        takerNFT.settlePairedPosition(0);

        // Try to withdraw from settled while paused
        vm.expectRevert(Pausable.EnforcedPause.selector);
        takerNFT.withdrawFromSettled(0, address(this));

        // Try to cancel a paired position while paused
        vm.expectRevert(Pausable.EnforcedPause.selector);
        takerNFT.cancelPairedPosition(0, address(this));
    }

    function test_unpause() public {
        startHoax(owner);
        takerNFT.pause();
        takerNFT.unpause();
        assertFalse(takerNFT.paused());

        // Should be able to open a position after unpausing
        createOfferMintTouserAndSetPrice();
        createTakerPositionAsUser(0, takerNFT, providerNFT);
    }

    /**
     * ERC721
     */
    function test_supportsInterface() public view {
        bool supportsERC721 = takerNFT.supportsInterface(0x80ac58cd); // ERC721 interface id
        bool supportsERC165 = takerNFT.supportsInterface(0x01ffc9a7); // ERC165 interface id

        assertTrue(supportsERC721);
        assertTrue(supportsERC165);

        // Test for an unsupported interface
        bool supportsUnsupported = takerNFT.supportsInterface(0xffffffff);
        assertFalse(supportsUnsupported);
    }

    /**
     * view functions
     */
    function test_cashAsset() public view {
        assertEq(address(takerNFT.cashAsset()), address(cashAsset));
    }

    function test_collateralAsset() public view {
        assertEq(address(takerNFT.collateralAsset()), address(collateralAsset));
    }

    function test_engine() public view {
        assertEq(address(takerNFT.engine()), address(engine));
    }

    function test_nextPositionId() public view {
        assertEq(takerNFT.nextPositionId(), 0);
    }

    function test_getPosition() public view {
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
        createOfferMintTouserAndSetPrice();
        uint userBalanceBefore = cashAsset.balanceOf(user1);
        (uint takerId, uint providerNFTId) = createTakerPositionAsUser(0, takerNFT, providerNFT);
        assertEq(takerId, 0);
        assertEq(providerNFTId, 0);
        assertEq(cashAsset.balanceOf(user1), userBalanceBefore - putLockedCashToUse);
    }

    /**
     * openPaired validation errors:
     *  "invalid put strike deviation" // cant get this since it checks that putStrike deviation is < 10000
     * and create offer doesnt allow you to put a put strike deviation > 10000
     */
    function test_openPairedPositionUnsupportedCashAsset() public {
        createOfferMintTouserAndSetPrice();
        vm.stopPrank();
        engine.removeSupportedCashAsset(address(cashAsset));
        startHoax(user1);
        vm.expectRevert("unsupported asset");
        takerNFT.openPairedPosition(putLockedCashToUse, providerNFT, 0);
    }

    function test_openPairedPositionUnsupportedCollateralAsset() public {
        createOfferMintTouserAndSetPrice();
        vm.stopPrank();
        engine.removeSupportedCollateralAsset(address(collateralAsset));
        startHoax(user1);
        vm.expectRevert("unsupported asset");
        takerNFT.openPairedPosition(putLockedCashToUse, providerNFT, 0);
    }

    function test_openPairedPositionUnsupportedTakerContract() public {
        createOfferMintTouserAndSetPrice();
        vm.stopPrank();
        engine.setCollarTakerContractAuth(address(takerNFT), false);
        startHoax(user1);
        vm.expectRevert("unsupported taker contract");
        takerNFT.openPairedPosition(putLockedCashToUse, providerNFT, 0);
    }

    function test_openPairedPositionUnsupportedProviderContract() public {
        createOfferMintTouserAndSetPrice();
        vm.stopPrank();
        engine.setProviderContractAuth(address(providerNFT), false);
        startHoax(user1);
        vm.expectRevert("unsupported provider contract");
        takerNFT.openPairedPosition(putLockedCashToUse, providerNFT, 0);
    }

    function test_openPairedPositionBadCashAssetMismatch() public {
        createOfferMintTouserAndSetPrice();
        vm.stopPrank();
        engine.addSupportedCashAsset(address(collateralAsset));
        ProviderPositionNFT providerNFTBad = new ProviderPositionNFT(
            owner,
            engine,
            collateralAsset,
            collateralAsset,
            address(takerNFT),
            "CollarTakerNFTBad",
            "BRWTSTBAD"
        );
        engine.setProviderContractAuth(address(providerNFTBad), true);
        startHoax(user1);
        cashAsset.approve(address(takerNFT), putLockedCashToUse);
        vm.expectRevert("asset mismatch");
        takerNFT.openPairedPosition(putLockedCashToUse, providerNFTBad, 0);
    }

    function test_openPairedPositionBadCollateralAssetMismatch() public {
        createOfferMintTouserAndSetPrice();
        vm.stopPrank();
        engine.addSupportedCollateralAsset(address(cashAsset));
        ProviderPositionNFT providerNFTBad = new ProviderPositionNFT(
            owner, engine, cashAsset, cashAsset, address(takerNFT), "CollarTakerNFTBad", "BRWTSTBAD"
        );
        engine.setProviderContractAuth(address(providerNFTBad), true);
        startHoax(user1);
        cashAsset.approve(address(takerNFT), putLockedCashToUse);
        vm.expectRevert("asset mismatch");
        takerNFT.openPairedPosition(putLockedCashToUse, providerNFTBad, 0);
    }

    function test_openPairedPositionStrikePricesArentDifferent() public {
        engine.addLTV(9990);
        uint badOfferId = createOfferAsProvider(10_010, 9990, providerNFT);
        mintTokensToUserandApproveNFT();
        setPricesAtTimestamp(engine, 1, 991);
        startHoax(user1);
        cashAsset.approve(address(takerNFT), putLockedCashToUse);
        vm.expectRevert("strike prices aren't different");
        takerNFT.openPairedPosition(priceToUse, providerNFT, badOfferId);
    }

    function test_settlePairedPositionPriceUp() public {
        uint takerContractCashBalanceBefore = cashAsset.balanceOf(address(takerNFT));
        uint providerContractCashBalanceBefore = cashAsset.balanceOf(address(providerNFT));

        (uint takerId, uint providerNFTId) = createAndSettlePositionOnPrice(
            pastCallStrikePrice, putLockedCashToUse + callLockedCashToUse, 0, -int(callLockedCashToUse)
        );

        uint providerContractCashBalanceAfter = cashAsset.balanceOf(address(providerNFT));
        uint takerContractCashBalanceAfter = cashAsset.balanceOf(address(takerNFT));

        assertEq(
            providerContractCashBalanceAfter - providerContractCashBalanceBefore,
            amountToProvide - callLockedCashToUse
        );
        assertEq(
            takerContractCashBalanceAfter - takerContractCashBalanceBefore,
            putLockedCashToUse + callLockedCashToUse
        );

        CollarTakerNFT.TakerPosition memory position = takerNFT.getPosition(takerId);
        assertEq(position.settled, true);
        assertEq(position.withdrawable, putLockedCashToUse + callLockedCashToUse);

        ProviderPositionNFT.ProviderPosition memory providerPosition = providerNFT.getPosition(providerNFTId);
        assertEq(providerPosition.settled, true);
    }

    function test_settlePairedPositionNoPriceChange() public {
        uint takerContractCashBalanceBefore = cashAsset.balanceOf(address(takerNFT));
        uint providerContractCashBalanceBefore = cashAsset.balanceOf(address(providerNFT));

        (uint takerId, uint providerNFTId) =
            createAndSettlePositionOnPrice(priceToUse, putLockedCashToUse, callLockedCashToUse, 0);

        uint providerContractCashBalanceAfter = cashAsset.balanceOf(address(providerNFT));
        uint takerContractCashBalanceAfter = cashAsset.balanceOf(address(takerNFT));

        assertEq(providerContractCashBalanceAfter - providerContractCashBalanceBefore, amountToProvide);
        assertEq(takerContractCashBalanceAfter - takerContractCashBalanceBefore, putLockedCashToUse);

        CollarTakerNFT.TakerPosition memory position = takerNFT.getPosition(takerId);
        assertEq(position.settled, true);
        assertEq(position.withdrawable, putLockedCashToUse);

        ProviderPositionNFT.ProviderPosition memory providerPosition = providerNFT.getPosition(providerNFTId);
        assertEq(providerPosition.settled, true);
    }

    function test_settlePairedPositionPriceDown() public {
        uint takerContractCashBalanceBefore = cashAsset.balanceOf(address(takerNFT));
        uint providerContractCashBalanceBefore = cashAsset.balanceOf(address(providerNFT));

        (uint takerId, uint providerNFTId) = createAndSettlePositionOnPrice(
            pastPutStrikePrice, 0, callLockedCashToUse + putLockedCashToUse, int(putLockedCashToUse)
        );

        uint providerContractCashBalanceAfter = cashAsset.balanceOf(address(providerNFT));
        uint takerContractCashBalanceAfter = cashAsset.balanceOf(address(takerNFT));

        assertEq(
            providerContractCashBalanceAfter - providerContractCashBalanceBefore,
            amountToProvide + putLockedCashToUse
        );
        assertEq(takerContractCashBalanceAfter, takerContractCashBalanceBefore);

        CollarTakerNFT.TakerPosition memory position = takerNFT.getPosition(takerId);
        assertEq(position.settled, true);
        assertEq(position.withdrawable, 0);

        ProviderPositionNFT.ProviderPosition memory providerPosition = providerNFT.getPosition(providerNFTId);
        assertEq(providerPosition.settled, true);
    }

    function test_settlePairedPosition_NonExistentPosition() public {
        vm.expectRevert("position doesn't exist");
        takerNFT.settlePairedPosition(999); // Use a position ID that doesn't exist
    }

    function test_settlePairedPosition_NotOwner() public {
        createOfferMintTouserAndSetPrice();
        (uint takerId,) = createTakerPositionAsUser(0, takerNFT, providerNFT);

        // Try to settle with a different address
        startHoax(address(0xdead));
        vm.expectRevert("not owner of either position");
        takerNFT.settlePairedPosition(takerId);
    }

    function test_settlePairedPosition_NotExpired() public {
        createOfferMintTouserAndSetPrice();
        (uint takerId,) = createTakerPositionAsUser(0, takerNFT, providerNFT);

        // Try to settle before expiration
        startHoax(user1);
        vm.expectRevert("not expired");
        takerNFT.settlePairedPosition(takerId);
    }

    function test_settlePairedPosition_AlreadySettled() public {
        createOfferMintTouserAndSetPrice();
        (uint takerId,) = createTakerPositionAsUser(0, takerNFT, providerNFT);

        // Settle the position
        skip(301);
        startHoax(user1);
        takerNFT.settlePairedPosition(takerId);

        // Try to settle again
        vm.expectRevert("already settled");
        takerNFT.settlePairedPosition(takerId);
    }

    function test_withdrawFromSettled() public {
        (uint takerId,) = createAndSettlePositionOnPrice(
            pastCallStrikePrice, putLockedCashToUse + callLockedCashToUse, 0, -int(callLockedCashToUse)
        );
        uint cashBalanceBefore = cashAsset.balanceOf(user1);
        takerNFT.withdrawFromSettled(takerId, user1);
        // price went up past call strike (120%) so the balance after withdrawing should be
        // userLocked + providerLocked
        assertEq(cashAsset.balanceOf(user1), cashBalanceBefore + putLockedCashToUse + callLockedCashToUse);
        CollarTakerNFT.TakerPosition memory position = takerNFT.getPosition(takerId);
        assertEq(position.withdrawable, 0);
    }

    function test_withdrawFromSettled_NotOwner() public {
        createOfferMintTouserAndSetPrice();
        (uint takerId,) = createTakerPositionAsUser(0, takerNFT, providerNFT);

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
        createOfferMintTouserAndSetPrice();
        (uint takerId,) = createTakerPositionAsUser(0, takerNFT, providerNFT);

        // Try to withdraw before settling
        startHoax(user1);
        vm.expectRevert("not settled");
        takerNFT.withdrawFromSettled(takerId, user1);
    }

    function test_cancelPairedPosition() public {
        createOfferMintTouserAndSetPrice();
        uint userCashBalanceBefore = cashAsset.balanceOf(user1);
        uint providerCashBalanceBefore = cashAsset.balanceOf(provider);
        (uint takerId, uint providerNFTId) = createTakerPositionAsUser(0, takerNFT, providerNFT);
        startHoax(user1);
        takerNFT.safeTransferFrom(user1, provider, takerId);
        startHoax(provider);
        takerNFT.approve(address(takerNFT), takerId);
        providerNFT.approve(address(takerNFT), providerNFTId);
        takerNFT.cancelPairedPosition(takerId, user1);
        CollarTakerNFT.TakerPosition memory position = takerNFT.getPosition(takerId);
        assertEq(position.settled, true);
        assertEq(position.withdrawable, 0);
        uint providerCashBalanceAfter = cashAsset.balanceOf(provider);
        uint userCashBalanceAfter = cashAsset.balanceOf(user1);
        uint userCashBalanceDiff = userCashBalanceAfter - userCashBalanceBefore;
        // we set the user1 address at recipient so both the putLockedCash and the callLockedCash should be
        // returned to user1  putLockedCash + callLockedCash
        uint shouldBeDiff = callLockedCashToUse;
        assertEq(userCashBalanceDiff, shouldBeDiff);

        uint providerCashBalanceDiff = providerCashBalanceAfter - providerCashBalanceBefore;
        assertEq(providerCashBalanceDiff, 0);
    }

    function test_cancelPairedPosition_NotOwnerOfTakerID() public {
        createOfferMintTouserAndSetPrice();
        (uint takerId,) = createTakerPositionAsUser(0, takerNFT, providerNFT);

        // Try to cancel with a different address
        startHoax(address(0xdead));
        vm.expectRevert("not owner of taker ID");
        takerNFT.cancelPairedPosition(takerId, address(0xdead));
    }

    function test_cancelPairedPosition_NotOwnerOfProviderID() public {
        createOfferMintTouserAndSetPrice();
        (uint takerId,) = createTakerPositionAsUser(0, takerNFT, providerNFT);

        // Transfer the taker NFT to another address, but not the provider NFT
        startHoax(user1);
        takerNFT.transferFrom(user1, address(0xbeef), takerId);

        // Try to cancel with the new taker NFT owner
        startHoax(address(0xbeef));
        vm.expectRevert("not owner of provider ID");
        takerNFT.cancelPairedPosition(takerId, address(0xbeef));
    }

    function test_cancelPairedPosition_AlreadySettled() public {
        createOfferMintTouserAndSetPrice();
        (uint takerId,) = createTakerPositionAsUser(0, takerNFT, providerNFT);

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
}
