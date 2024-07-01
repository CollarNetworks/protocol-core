// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity 0.8.22;

import "forge-std/Test.sol";
import { TestERC20 } from "../utils/TestERC20.sol";
import { MockUniRouter } from "../utils/MockUniRouter.sol";
import { MockEngine } from "../../test/utils/MockEngine.sol";
import { BorrowPositionNFT } from "../../src/BorrowPositionNFT.sol";
import { IBorrowPositionNFT } from "../../src/interfaces/IBorrowPositionNFT.sol";
import { ProviderPositionNFT } from "../../src/ProviderPositionNFT.sol";
import { IProviderPositionNFT } from "../../src/interfaces/IProviderPositionNFT.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";

contract BorrowPositionNFTTest is Test {
    TestERC20 cashAsset;
    TestERC20 collateralAsset;
    MockUniRouter router;
    MockEngine engine;
    BorrowPositionNFT borrowNFT;
    ProviderPositionNFT providerNFT;
    address user1 = makeAddr("user1");
    address provider = makeAddr("provider");
    address owner = makeAddr("owner");
    uint amountToUse = 10_000 ether;
    uint loanAmount = 9000 ether;
    uint ltvToUse = 9000;
    uint durationToUse = 300;
    uint putLockedCashToUse = 1000 ether;
    uint callLockedCashToUse = 2000 ether;
    uint priceToUse = 1 ether;
    uint callStrikePrice = 1.2 ether; // 120% of the price
    uint pastCallStrikePrice = 1.25 ether; // 125% of the price | to use when price goes over call strike price
    uint putStrikePrice = 0.9 ether; // 90% of the price corresponding to 9000 LTV
    uint pastPutStrikePrice = 0.8 ether; // 80% of the price | to use when price goes under put strike price
    uint callStrikeDeviationToUse = 12_000;
    uint amountToProvide = 100_000 ether;

    function setUp() public {
        cashAsset = new TestERC20("Test1", "TST1");
        collateralAsset = new TestERC20("Test2", "TST2");
        router = new MockUniRouter();
        cashAsset.mint(address(router), 100_000 ether);
        collateralAsset.mint(address(router), 100_000 ether);
        cashAsset.mint(provider, 100_000_000 ether);
        collateralAsset.mint(user1, 100_000_000 ether);
        vm.label(address(cashAsset), "Test Token 1 // Pool Cash Token");
        vm.label(address(collateralAsset), "Test Token 2 // Collateral");
        engine = setupMockEngine();
        vm.label(address(engine), "CollarEngine");
        engine.addSupportedCashAsset(address(cashAsset));
        engine.addSupportedCollateralAsset(address(collateralAsset));
        borrowNFT =
            new BorrowPositionNFT(owner, engine, cashAsset, collateralAsset, "BorrowPositionNFT", "BRWTST");
        providerNFT = new ProviderPositionNFT(
            owner, engine, cashAsset, collateralAsset, address(borrowNFT), "BorrowPositionNFT", "BRWTST"
        );
        engine.setBorrowContractAuth(address(borrowNFT), true);
        engine.setProviderContractAuth(address(providerNFT), true);
        vm.label(address(borrowNFT), "BorrowPositionNFT");
        vm.label(address(providerNFT), "ProviderPositionNFT");
    }

    function setupMockEngine() public returns (MockEngine mockEngine) {
        mockEngine = new MockEngine(address(router));
        mockEngine.addLTV(ltvToUse);
        mockEngine.addCollarDuration(durationToUse);
    }

    function setPricesAtTimestamp(MockEngine engineToUse, uint timestamp, uint price) internal {
        engineToUse.setHistoricalAssetPrice(address(collateralAsset), timestamp, price);
        engineToUse.setHistoricalAssetPrice(address(cashAsset), timestamp, price);
    }

    function mintTokensToUserandApproveNFT() internal {
        cashAsset.mint(user1, amountToUse);
        cashAsset.approve(address(borrowNFT), amountToUse);
        collateralAsset.mint(user1, amountToUse);
        collateralAsset.approve(address(borrowNFT), amountToUse);
    }

    function createOfferAsProvider(
        uint callStrike,
        uint putStrikeDeviation,
        ProviderPositionNFT providerNFTToUse
    ) internal returns (uint offerId) {
        startHoax(provider);
        cashAsset.approve(address(providerNFTToUse), 1_000_000 ether);

        uint expectedOfferId = providerNFTToUse.nextPositionId();
        console.log("expectedOfferId", expectedOfferId);
        vm.expectEmit(true, true, true, true);
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

    function createBorrowPositionAsUser(
        uint offerId,
        BorrowPositionNFT borrowNFTToUse,
        ProviderPositionNFT providerNFTToUse
    ) internal returns (uint borrowId, uint providerNFTId, uint amountLoaned) {
        startHoax(user1);
        collateralAsset.approve(address(borrowNFT), amountToUse);
        (borrowId, providerNFTId, amountLoaned) =
            borrowNFTToUse.openPairedPosition(amountToUse, amountToUse, providerNFTToUse, offerId);
        checkBorrowPosition();
        checkProviderPosition();
    }

    function createOfferMintTouserAndSetPrice() internal {
        createOfferAsProvider(callStrikeDeviationToUse, ltvToUse, providerNFT);
        mintTokensToUserandApproveNFT();
        setPricesAtTimestamp(engine, 1, priceToUse);
    }

    function checkBorrowPosition() internal view {
        BorrowPositionNFT.BorrowPosition memory position = borrowNFT.getPosition(0);
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
        uint expectedBorrowWithdrawable,
        uint expectedProviderWithdrawable,
        int expectedProviderChange
    ) internal returns (uint borrowId, uint providerNFTId, uint amountLoaned) {
        createOfferMintTouserAndSetPrice();
        (borrowId, providerNFTId, amountLoaned) = createBorrowPositionAsUser(0, borrowNFT, providerNFT);
        skip(301);
        setPricesAtTimestamp(engine, 301, priceToSettleAt);

        startHoax(user1);
        vm.expectEmit(true, true, true, true, address(providerNFT));
        emit IProviderPositionNFT.PositionSettled(
            providerNFTId, expectedProviderChange, expectedProviderWithdrawable
        );
        vm.expectEmit(true, true, true, true, address(borrowNFT));
        emit IBorrowPositionNFT.PairedPositionSettled(
            borrowId,
            address(providerNFT),
            providerNFTId,
            priceToSettleAt,
            expectedBorrowWithdrawable,
            expectedProviderChange
        );
        borrowNFT.settlePairedPosition(borrowId);
    }

    function test_constructor() public {
        BorrowPositionNFT newBorrowNFT =
            new BorrowPositionNFT(owner, engine, cashAsset, collateralAsset, "NewBorrowPositionNFT", "NBPNFT");

        assertEq(address(newBorrowNFT.engine()), address(engine));
        assertEq(address(newBorrowNFT.cashAsset()), address(cashAsset));
        assertEq(address(newBorrowNFT.collateralAsset()), address(collateralAsset));
        assertEq(newBorrowNFT.name(), "NewBorrowPositionNFT");
        assertEq(newBorrowNFT.symbol(), "NBPNFT");
    }

    /**
     * Test methods that are inherited from other contracts
     */

    /**
     * Pausable
     */
    function test_pause() public {
        startHoax(owner);
        borrowNFT.pause();
        assertTrue(borrowNFT.paused());

        // Try to open a position while paused
        vm.expectRevert(Pausable.EnforcedPause.selector);
        borrowNFT.openPairedPosition(amountToUse, amountToUse, providerNFT, 0);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        borrowNFT.openPairedPositionWithoutSwap(putLockedCashToUse, providerNFT, 0);
        // Try to settle a position while paused
        vm.expectRevert(Pausable.EnforcedPause.selector);
        borrowNFT.settlePairedPosition(0);

        // Try to withdraw from settled while paused
        vm.expectRevert(Pausable.EnforcedPause.selector);
        borrowNFT.withdrawFromSettled(0, address(this));

        // Try to cancel a paired position while paused
        vm.expectRevert(Pausable.EnforcedPause.selector);
        borrowNFT.cancelPairedPosition(0, address(this));
    }

    function test_unpause() public {
        startHoax(owner);
        borrowNFT.pause();
        borrowNFT.unpause();
        assertFalse(borrowNFT.paused());

        // Should be able to open a position after unpausing
        createOfferMintTouserAndSetPrice();
        createBorrowPositionAsUser(0, borrowNFT, providerNFT);
    }

    /**
     * ERC721
     */
    function test_supportsInterface() public view {
        bool supportsERC721 = borrowNFT.supportsInterface(0x80ac58cd); // ERC721 interface id
        bool supportsERC165 = borrowNFT.supportsInterface(0x01ffc9a7); // ERC165 interface id

        assertTrue(supportsERC721);
        assertTrue(supportsERC165);

        // Test for an unsupported interface
        bool supportsUnsupported = borrowNFT.supportsInterface(0xffffffff);
        assertFalse(supportsUnsupported);
    }

    /**
     * view functions
     */
    function test_cashAsset() public view {
        assertEq(address(borrowNFT.cashAsset()), address(cashAsset));
    }

    function test_collateralAsset() public view {
        assertEq(address(borrowNFT.collateralAsset()), address(collateralAsset));
    }

    function test_engine() public view {
        assertEq(address(borrowNFT.engine()), address(engine));
    }

    function test_nextPositionId() public view {
        assertEq(borrowNFT.nextPositionId(), 0);
    }

    function test_getPosition() public view {
        BorrowPositionNFT.BorrowPosition memory position = borrowNFT.getPosition(0);
        assertEq(position.callStrikePrice, 0);
        assertEq(position.putLockedCash, 0);
        assertEq(position.callLockedCash, 0);

        assertEq(position.settled, false);
        assertEq(position.withdrawable, 0);
    }

    /**
     * mutative functions
     * function cancelPairedPosition(uint borrowId, address recipient) external;
     */
    function test_openPairedPosition() public {
        createOfferMintTouserAndSetPrice();
        uint userBalanceBefore = cashAsset.balanceOf(user1);
        (uint borrowId, uint providerNFTId, uint amountLoaned) =
            createBorrowPositionAsUser(0, borrowNFT, providerNFT);
        uint userBalanceAfter = cashAsset.balanceOf(user1);
        assertEq(borrowId, 0);
        assertEq(providerNFTId, 0);
        assertGt(userBalanceAfter, userBalanceBefore);
        uint balanceDiff = userBalanceAfter - userBalanceBefore;
        assertEq(balanceDiff, amountLoaned);
    }

    /**
     * openPaired validation errors:
     *  "invalid put strike deviation" // cant get this since it checks that putStrike deviation is < 10000 and create offer doesnt allow you to put a put strike deviation > 10000
     */
    function test_openPairedPositionUnsupportedCashAsset() public {
        createOfferMintTouserAndSetPrice();
        vm.stopPrank();
        engine.removeSupportedCashAsset(address(cashAsset));
        startHoax(user1);
        collateralAsset.approve(address(borrowNFT), amountToUse);
        vm.expectRevert("unsupported asset");
        borrowNFT.openPairedPosition(amountToUse, amountToUse, providerNFT, 0);
    }

    function test_openPairedPositionUnsupportedCollateralAsset() public {
        createOfferMintTouserAndSetPrice();
        vm.stopPrank();
        engine.removeSupportedCollateralAsset(address(collateralAsset));
        startHoax(user1);
        collateralAsset.approve(address(borrowNFT), amountToUse);
        vm.expectRevert("unsupported asset");
        borrowNFT.openPairedPosition(amountToUse, amountToUse, providerNFT, 0);
    }

    function test_openPairedPositionUnsupportedBorrowContract() public {
        createOfferMintTouserAndSetPrice();
        vm.stopPrank();
        engine.setBorrowContractAuth(address(borrowNFT), false);
        startHoax(user1);
        collateralAsset.approve(address(borrowNFT), amountToUse);
        vm.expectRevert("unsupported borrow contract");
        borrowNFT.openPairedPosition(amountToUse, amountToUse, providerNFT, 0);
    }

    function test_openPairedPositionUnsupportedProviderContract() public {
        createOfferMintTouserAndSetPrice();
        vm.stopPrank();
        engine.setProviderContractAuth(address(providerNFT), false);
        startHoax(user1);
        collateralAsset.approve(address(borrowNFT), amountToUse);
        vm.expectRevert("unsupported provider contract");
        borrowNFT.openPairedPosition(amountToUse, amountToUse, providerNFT, 0);
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
            address(borrowNFT),
            "BorrowPositionNFTBad",
            "BRWTSTBAD"
        );
        engine.setProviderContractAuth(address(providerNFTBad), true);
        startHoax(user1);
        collateralAsset.approve(address(borrowNFT), amountToUse);
        vm.expectRevert("asset mismatch");
        borrowNFT.openPairedPosition(amountToUse, amountToUse, providerNFTBad, 0);
    }

    function test_openPairedPositionBadCollateralAssetMismatch() public {
        createOfferMintTouserAndSetPrice();
        vm.stopPrank();
        engine.addSupportedCollateralAsset(address(cashAsset));
        ProviderPositionNFT providerNFTBad = new ProviderPositionNFT(
            owner, engine, cashAsset, cashAsset, address(borrowNFT), "BorrowPositionNFTBad", "BRWTSTBAD"
        );
        engine.setProviderContractAuth(address(providerNFTBad), true);
        startHoax(user1);
        collateralAsset.approve(address(borrowNFT), amountToUse);
        vm.expectRevert("asset mismatch");
        borrowNFT.openPairedPosition(amountToUse, amountToUse, providerNFTBad, 0);
    }

    function test_openPairedPositionSlippageExceeded() public {
        createOfferMintTouserAndSetPrice();
        vm.stopPrank();
        startHoax(user1);
        collateralAsset.approve(address(borrowNFT), amountToUse);
        router.setTransferAmount(amountToUse - 100);
        router.setAmountToReturn(amountToUse - 100);
        vm.expectRevert("slippage exceeded");
        borrowNFT.openPairedPosition(amountToUse, amountToUse, providerNFT, 0);
    }

    function test_openPairedPositionBalanceMismatch() public {
        createOfferMintTouserAndSetPrice();
        startHoax(user1);
        collateralAsset.approve(address(borrowNFT), amountToUse);
        router.setTransferAmount(amountToUse / 2);
        vm.expectRevert("balance update mismatch");
        borrowNFT.openPairedPosition(amountToUse, amountToUse, providerNFT, 0);
    }

    function test_openPairedPositionSwapAndTwapPriceTooDifferent() public {
        uint badOfferId = createOfferAsProvider(11_000, ltvToUse, providerNFT);
        mintTokensToUserandApproveNFT();
        setPricesAtTimestamp(engine, 1, 1);
        router.setTransferAmount(1);
        router.setAmountToReturn(1);
        startHoax(user1);
        collateralAsset.approve(address(borrowNFT), amountToUse);
        vm.expectRevert("swap and twap price too different");
        borrowNFT.openPairedPosition(amountToUse, 1, providerNFT, badOfferId);
    }

    function test_openPairedPositionStrikePricesArentDifferent() public {
        engine.addLTV(9990);
        uint badOfferId = createOfferAsProvider(10_010, 9990, providerNFT);
        mintTokensToUserandApproveNFT();
        setPricesAtTimestamp(engine, 1, 991);
        router.setTransferAmount(991);
        router.setAmountToReturn(991);
        startHoax(user1);
        collateralAsset.approve(address(borrowNFT), amountToUse);
        vm.expectRevert("strike prices aren't different");
        borrowNFT.openPairedPosition(priceToUse, 1, providerNFT, badOfferId);
    }

    function test_openPairedPositionWithoutSwap() public {
        createOfferMintTouserAndSetPrice();
        uint userBalanceBefore = cashAsset.balanceOf(user1);
        startHoax(user1);
        cashAsset.approve(address(borrowNFT), amountToUse);
        (uint borrowId, uint providerNFTId) =
            borrowNFT.openPairedPositionWithoutSwap(loanAmount, providerNFT, 0);
        uint userBalanceAfter = cashAsset.balanceOf(user1);
        assertEq(borrowId, 0);
        assertEq(providerNFTId, 0);
        assertGt(userBalanceBefore, userBalanceAfter);
        // there's no loan so the balance just goes down because of the locked cash amount
        uint balanceDiff = userBalanceBefore - userBalanceAfter;
        assertEq(balanceDiff, loanAmount);
    }

    function test_openPairedPosition_InvalidParameters() public {
        createOfferMintTouserAndSetPrice();
        router.setAmountToReturn(amountToUse);
        router.setTransferAmount(amountToUse);
        startHoax(user1);
        collateralAsset.approve(address(borrowNFT), amountToUse);
        // Test with zero collateral amount
        vm.expectRevert("zero collateral");
        borrowNFT.openPairedPosition(0, amountToUse, providerNFT, 0);
        // Test with invalid offerId
        vm.expectRevert("invalid put strike deviation");
        borrowNFT.openPairedPosition(amountToUse, amountToUse, providerNFT, 999);
    }

    function test_settlePairedPositionPriceUp() public {
        uint borrowContractCashBalanceBefore = cashAsset.balanceOf(address(borrowNFT));
        uint providerContractCashBalanceBefore = cashAsset.balanceOf(address(providerNFT));

        (uint borrowId, uint providerNFTId,) = createAndSettlePositionOnPrice(
            pastCallStrikePrice, putLockedCashToUse + callLockedCashToUse, 0, -int(callLockedCashToUse)
        );

        uint providerContractCashBalanceAfter = cashAsset.balanceOf(address(providerNFT));
        uint borrowContractCashBalanceAfter = cashAsset.balanceOf(address(borrowNFT));

        assertEq(
            providerContractCashBalanceAfter - providerContractCashBalanceBefore,
            amountToProvide - callLockedCashToUse
        );
        assertEq(
            borrowContractCashBalanceAfter - borrowContractCashBalanceBefore,
            putLockedCashToUse + callLockedCashToUse
        );

        BorrowPositionNFT.BorrowPosition memory position = borrowNFT.getPosition(borrowId);
        assertEq(position.settled, true);
        assertEq(position.withdrawable, putLockedCashToUse + callLockedCashToUse);

        ProviderPositionNFT.ProviderPosition memory providerPosition = providerNFT.getPosition(providerNFTId);
        assertEq(providerPosition.settled, true);
    }

    function test_settlePairedPositionNoPriceChange() public {
        uint borrowContractCashBalanceBefore = cashAsset.balanceOf(address(borrowNFT));
        uint providerContractCashBalanceBefore = cashAsset.balanceOf(address(providerNFT));

        (uint borrowId, uint providerNFTId,) =
            createAndSettlePositionOnPrice(priceToUse, putLockedCashToUse, callLockedCashToUse, 0);

        uint providerContractCashBalanceAfter = cashAsset.balanceOf(address(providerNFT));
        uint borrowContractCashBalanceAfter = cashAsset.balanceOf(address(borrowNFT));

        assertEq(providerContractCashBalanceAfter - providerContractCashBalanceBefore, amountToProvide);
        assertEq(borrowContractCashBalanceAfter - borrowContractCashBalanceBefore, putLockedCashToUse);

        BorrowPositionNFT.BorrowPosition memory position = borrowNFT.getPosition(borrowId);
        assertEq(position.settled, true);
        assertEq(position.withdrawable, putLockedCashToUse);

        ProviderPositionNFT.ProviderPosition memory providerPosition = providerNFT.getPosition(providerNFTId);
        assertEq(providerPosition.settled, true);
    }

    function test_settlePairedPositionPriceDown() public {
        uint borrowContractCashBalanceBefore = cashAsset.balanceOf(address(borrowNFT));
        uint providerContractCashBalanceBefore = cashAsset.balanceOf(address(providerNFT));

        (uint borrowId, uint providerNFTId,) = createAndSettlePositionOnPrice(
            pastPutStrikePrice, 0, callLockedCashToUse + putLockedCashToUse, int(putLockedCashToUse)
        );

        uint providerContractCashBalanceAfter = cashAsset.balanceOf(address(providerNFT));
        uint borrowContractCashBalanceAfter = cashAsset.balanceOf(address(borrowNFT));

        assertEq(
            providerContractCashBalanceAfter - providerContractCashBalanceBefore,
            amountToProvide + putLockedCashToUse
        );
        assertEq(borrowContractCashBalanceAfter, borrowContractCashBalanceBefore);

        BorrowPositionNFT.BorrowPosition memory position = borrowNFT.getPosition(borrowId);
        assertEq(position.settled, true);
        assertEq(position.withdrawable, 0);

        ProviderPositionNFT.ProviderPosition memory providerPosition = providerNFT.getPosition(providerNFTId);
        assertEq(providerPosition.settled, true);
    }

    function test_settlePairedPosition_NonExistentPosition() public {
        vm.expectRevert("position doesn't exist");
        borrowNFT.settlePairedPosition(999); // Use a position ID that doesn't exist
    }

    function test_settlePairedPosition_NotOwner() public {
        createOfferMintTouserAndSetPrice();
        (uint borrowId,,) = createBorrowPositionAsUser(0, borrowNFT, providerNFT);

        // Try to settle with a different address
        startHoax(address(0xdead));
        vm.expectRevert("not owner of either position");
        borrowNFT.settlePairedPosition(borrowId);
    }

    function test_settlePairedPosition_NotExpired() public {
        createOfferMintTouserAndSetPrice();
        (uint borrowId,,) = createBorrowPositionAsUser(0, borrowNFT, providerNFT);

        // Try to settle before expiration
        startHoax(user1);
        vm.expectRevert("not expired");
        borrowNFT.settlePairedPosition(borrowId);
    }

    function test_settlePairedPosition_AlreadySettled() public {
        createOfferMintTouserAndSetPrice();
        (uint borrowId,,) = createBorrowPositionAsUser(0, borrowNFT, providerNFT);

        // Settle the position
        skip(301);
        startHoax(user1);
        borrowNFT.settlePairedPosition(borrowId);

        // Try to settle again
        vm.expectRevert("already settled");
        borrowNFT.settlePairedPosition(borrowId);
    }

    function test_withdrawFromSettled() public {
        uint cashBalanceBefore = cashAsset.balanceOf(user1);
        (uint borrowId,,) = createAndSettlePositionOnPrice(
            pastCallStrikePrice, putLockedCashToUse + callLockedCashToUse, 0, -int(callLockedCashToUse)
        );
        borrowNFT.withdrawFromSettled(borrowId, user1);
        uint cashBalanceAfter = cashAsset.balanceOf(user1);
        uint cashBalanceDiff = cashBalanceAfter - cashBalanceBefore;
        // price went up past call strike (120%) so the balance after withdrawing should be  mint  + loan + userLocked + providerLocked
        uint shouldBeDiff = amountToUse + loanAmount + putLockedCashToUse + callLockedCashToUse;
        assertEq(cashBalanceDiff, shouldBeDiff);
        BorrowPositionNFT.BorrowPosition memory position = borrowNFT.getPosition(borrowId);
        assertEq(position.withdrawable, 0);
    }

    function test_withdrawFromSettled_NotOwner() public {
        createOfferMintTouserAndSetPrice();
        (uint borrowId,,) = createBorrowPositionAsUser(0, borrowNFT, providerNFT);

        // Settle the position
        skip(301);
        startHoax(user1);
        borrowNFT.settlePairedPosition(borrowId);

        // Try to withdraw with a different address
        startHoax(address(0xdead));
        vm.expectRevert("not position owner");
        borrowNFT.withdrawFromSettled(borrowId, address(0xdead));
    }

    function test_withdrawFromSettled_NotSettled() public {
        createOfferMintTouserAndSetPrice();
        (uint borrowId,,) = createBorrowPositionAsUser(0, borrowNFT, providerNFT);

        // Try to withdraw before settling
        startHoax(user1);
        vm.expectRevert("not settled");
        borrowNFT.withdrawFromSettled(borrowId, user1);
    }

    function test_cancelPairedPosition() public {
        createOfferMintTouserAndSetPrice();
        uint userCashBalanceBefore = cashAsset.balanceOf(user1);
        uint providerCashBalanceBefore = cashAsset.balanceOf(provider);
        (uint borrowId, uint providerNFTId,) = createBorrowPositionAsUser(0, borrowNFT, providerNFT);
        startHoax(user1);
        borrowNFT.safeTransferFrom(user1, provider, borrowId);
        startHoax(provider);
        borrowNFT.approve(address(borrowNFT), borrowId);
        providerNFT.approve(address(borrowNFT), providerNFTId);
        borrowNFT.cancelPairedPosition(borrowId, user1);
        BorrowPositionNFT.BorrowPosition memory position = borrowNFT.getPosition(borrowId);
        assertEq(position.settled, true);
        assertEq(position.withdrawable, 0);
        uint providerCashBalanceAfter = cashAsset.balanceOf(provider);
        uint userCashBalanceAfter = cashAsset.balanceOf(user1);
        uint userCashBalanceDiff = userCashBalanceAfter - userCashBalanceBefore;
        // we set the user1 address at recipient so both the putLockedCash and the callLockedCash should be returned to user1  loanAmount + putLockedCash + callLockedCash
        uint shouldBeDiff = loanAmount + putLockedCashToUse + callLockedCashToUse;
        assertEq(userCashBalanceDiff, shouldBeDiff);

        uint providerCashBalanceDiff = providerCashBalanceAfter - providerCashBalanceBefore;
        assertEq(providerCashBalanceDiff, 0);
    }

    function test_cancelPairedPosition_NotOwnerOfBorrowID() public {
        createOfferMintTouserAndSetPrice();
        (uint borrowId,,) = createBorrowPositionAsUser(0, borrowNFT, providerNFT);

        // Try to cancel with a different address
        startHoax(address(0xdead));
        vm.expectRevert("not owner of borrow ID");
        borrowNFT.cancelPairedPosition(borrowId, address(0xdead));
    }

    function test_cancelPairedPosition_NotOwnerOfProviderID() public {
        createOfferMintTouserAndSetPrice();
        (uint borrowId,,) = createBorrowPositionAsUser(0, borrowNFT, providerNFT);

        // Transfer the borrow NFT to another address, but not the provider NFT
        startHoax(user1);
        borrowNFT.transferFrom(user1, address(0xbeef), borrowId);

        // Try to cancel with the new borrow NFT owner
        startHoax(address(0xbeef));
        vm.expectRevert("not owner of provider ID");
        borrowNFT.cancelPairedPosition(borrowId, address(0xbeef));
    }

    function test_cancelPairedPosition_AlreadySettled() public {
        createOfferMintTouserAndSetPrice();
        (uint borrowId,,) = createBorrowPositionAsUser(0, borrowNFT, providerNFT);

        // Settle the position
        skip(301);
        startHoax(user1);
        borrowNFT.settlePairedPosition(borrowId);
        // Try to cancel the settled position
        borrowNFT.safeTransferFrom(user1, provider, borrowId);
        startHoax(provider);
        vm.expectRevert("already settled");
        borrowNFT.cancelPairedPosition(borrowId, user1);
    }
}
