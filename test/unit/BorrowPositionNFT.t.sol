// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity 0.8.21;

import "forge-std/Test.sol";
import { TestERC20 } from "../utils/TestERC20.sol";
import { MockUniRouter } from "../utils/MockUniRouter.sol";
import { MockBadUniRouter } from "../utils/MockBadUniRouter.sol";
import { MockEngine } from "../../test/utils/MockEngine.sol";
import { BorrowPositionNFT } from "../../src/BorrowPositionNFT.sol";
import { ProviderPositionNFT } from "../../src/ProviderPositionNFT.sol";

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
        mockEngine.addLTV(9000);
        mockEngine.addCollarDuration(300);
    }

    function setPricesAtTimestamp(MockEngine engineToUse, uint timestamp, uint price) internal {
        engineToUse.setHistoricalAssetPrice(address(collateralAsset), timestamp, price);
        engineToUse.setHistoricalAssetPrice(address(cashAsset), timestamp, price);
    }

    function mintTokensToUserandApproveNFT() internal {
        cashAsset.mint(user1, 10_000 ether);
        cashAsset.approve(address(borrowNFT), 10_000 ether);
        collateralAsset.mint(user1, 10_000 ether);
        collateralAsset.approve(address(borrowNFT), 10_000 ether);
    }

    function createOfferAsProvider(uint callStrike, ProviderPositionNFT providerNFTToUse) internal {
        startHoax(provider);
        cashAsset.approve(address(providerNFTToUse), 1_000_000 ether);
        uint offerid = providerNFTToUse.createOffer(callStrike, 100_000 ether, 9000, 300);
        assertEq(offerid, 0);
        ProviderPositionNFT.LiquidityOffer memory offer = providerNFTToUse.getOffer(0);
        assertEq(offer.callStrikeDeviation, callStrike);
        assertEq(offer.available, 100_000 ether);
    }

    function createBorrowPositionAsUser(
        uint offerId,
        BorrowPositionNFT borrowNFTToUse,
        ProviderPositionNFT providerNFTToUse
    ) internal returns (uint borrowId, uint providerNFTId, uint amountLoaned) {
        startHoax(user1);
        collateralAsset.approve(address(borrowNFT), 10_000 ether);
        (borrowId, providerNFTId, amountLoaned) =
            borrowNFTToUse.openPairedPosition(10_000 ether, 10_000 ether, providerNFTToUse, offerId);
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
        assertEq(position.collateralAmount, 0);
        assertEq(position.loanAmount, 0);
        assertEq(position.settled, false);
        assertEq(position.withdrawable, 0);
    }

    /**
     * mutative functions
     * function cancelPairedPosition(uint borrowId, address recipient) external;
     */
    function test_openPairedPosition() public {
        createOfferAsProvider(12_000, providerNFT);
        setPricesAtTimestamp(engine, 1, 1 ether);
        mintTokensToUserandApproveNFT();
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
     * TODO openPaired validation errors:
     *  "balance update mismatch");
     *  "slippage exceeded");
     *  "strike prices aren't different"
     *  "invalid put strike deviation"
     */
    function test_openPairedPositionUnsupportedCashAsset() public {
        createOfferAsProvider(12_000, providerNFT);
        setPricesAtTimestamp(engine, 1, 1 ether);
        mintTokensToUserandApproveNFT();
        startHoax(address(this));
        engine.removeSupportedCashAsset(address(cashAsset));
        startHoax(user1);
        collateralAsset.approve(address(borrowNFT), 10_000 ether);
        vm.expectRevert("unsupported asset");
        borrowNFT.openPairedPosition(10_000 ether, 10_000 ether, providerNFT, 0);
    }

    function test_openPairedPositionUnsupportedCollateralAsset() public {
        createOfferAsProvider(12_000, providerNFT);
        setPricesAtTimestamp(engine, 1, 1 ether);
        mintTokensToUserandApproveNFT();
        startHoax(address(this));
        engine.removeSupportedCollateralAsset(address(collateralAsset));
        startHoax(user1);
        collateralAsset.approve(address(borrowNFT), 10_000 ether);
        vm.expectRevert("unsupported asset");
        borrowNFT.openPairedPosition(10_000 ether, 10_000 ether, providerNFT, 0);
    }

    function test_openPairedPositionUnsupportedBorrowContract() public {
        createOfferAsProvider(12_000, providerNFT);
        setPricesAtTimestamp(engine, 1, 1 ether);
        mintTokensToUserandApproveNFT();
        startHoax(address(this));
        engine.setBorrowContractAuth(address(borrowNFT), false);
        startHoax(user1);
        collateralAsset.approve(address(borrowNFT), 10_000 ether);
        vm.expectRevert("unsupported borrow contract");
        borrowNFT.openPairedPosition(10_000 ether, 10_000 ether, providerNFT, 0);
    }

    function test_openPairedPositionUnsupportedProviderContract() public {
        createOfferAsProvider(12_000, providerNFT);
        setPricesAtTimestamp(engine, 1, 1 ether);
        mintTokensToUserandApproveNFT();
        startHoax(address(this));
        engine.setProviderContractAuth(address(providerNFT), false);
        startHoax(user1);
        collateralAsset.approve(address(borrowNFT), 10_000 ether);
        vm.expectRevert("unsupported provider contract");
        borrowNFT.openPairedPosition(10_000 ether, 10_000 ether, providerNFT, 0);
    }

    function test_openPairedPositionBadCashAssetMismatch() public {
        createOfferAsProvider(12_000, providerNFT);
        setPricesAtTimestamp(engine, 1, 1 ether);
        mintTokensToUserandApproveNFT();
        startHoax(address(this));
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
        collateralAsset.approve(address(borrowNFT), 10_000 ether);
        vm.expectRevert("asset mismatch");
        borrowNFT.openPairedPosition(10_000 ether, 10_000 ether, providerNFTBad, 0);
    }

    function test_openPairedPositionBadCollateralAssetMismatch() public {
        createOfferAsProvider(12_000, providerNFT);
        setPricesAtTimestamp(engine, 1, 1 ether);
        mintTokensToUserandApproveNFT();
        startHoax(address(this));
        engine.addSupportedCollateralAsset(address(cashAsset));
        ProviderPositionNFT providerNFTBad = new ProviderPositionNFT(
            owner, engine, cashAsset, cashAsset, address(borrowNFT), "BorrowPositionNFTBad", "BRWTSTBAD"
        );
        engine.setProviderContractAuth(address(providerNFTBad), true);
        startHoax(user1);
        collateralAsset.approve(address(borrowNFT), 10_000 ether);
        vm.expectRevert("asset mismatch");
        borrowNFT.openPairedPosition(10_000 ether, 10_000 ether, providerNFTBad, 0);
    }

    function test_openPairedPositionWithoutSwap() public {
        createOfferAsProvider(12_000, providerNFT);
        setPricesAtTimestamp(engine, 1, 1 ether);
        mintTokensToUserandApproveNFT();
        uint userBalanceBefore = cashAsset.balanceOf(user1);
        startHoax(user1);
        cashAsset.approve(address(borrowNFT), 10_000 ether);
        (uint borrowId, uint providerNFTId) =
            borrowNFT.openPairedPositionWithoutSwap(9000 ether, providerNFT, 0);
        uint userBalanceAfter = cashAsset.balanceOf(user1);
        assertEq(borrowId, 0);
        assertEq(providerNFTId, 0);
        assertGt(userBalanceBefore, userBalanceAfter);
        // there's no loan so the balance just goes down because of the locked cash amount
        uint balanceDiff = userBalanceBefore - userBalanceAfter;
        assertEq(balanceDiff, 9000 ether);
    }

    /**
     * TODO settlePairedPosition revert branches
     *     "position doesn't exist"
     *     "not owner of either position"
     *     "not expired"
     *     "already settled"
     */
    function test_settlePairedPosition() public {
        createOfferAsProvider(12_000, providerNFT);
        mintTokensToUserandApproveNFT();
        setPricesAtTimestamp(engine, 1, 1 ether);
        (uint borrowId, uint providerNFTId,) = createBorrowPositionAsUser(0, borrowNFT, providerNFT);
        skip(301);
        setPricesAtTimestamp(engine, 301, 1.25 ether);
        startHoax(user1);
        borrowNFT.settlePairedPosition(borrowId);
        BorrowPositionNFT.BorrowPosition memory position = borrowNFT.getPosition(borrowId);
        assertEq(position.settled, true);
        // price went up past call strike (120%) so the withdrawable amount should be locked (1000) + provider locked (2000)
        assertEq(position.withdrawable, 3000 ether);
        ProviderPositionNFT.ProviderPosition memory providerPosition = providerNFT.getPosition(providerNFTId);
        assertEq(providerPosition.settled, true);
    }

    /**
     * TODO withdrawFromSettled revert branches
     *         "not position owner"
     *         "not settled"
     */
    function test_withdrawFromSettled() public {
        createOfferAsProvider(12_000, providerNFT);
        mintTokensToUserandApproveNFT();
        setPricesAtTimestamp(engine, 1, 1 ether);
        uint cashBalanceBefore = cashAsset.balanceOf(user1);
        (uint borrowId,,) = createBorrowPositionAsUser(0, borrowNFT, providerNFT);
        skip(301);
        setPricesAtTimestamp(engine, 301, 1.25 ether);
        startHoax(user1);
        borrowNFT.settlePairedPosition(borrowId);
        borrowNFT.withdrawFromSettled(borrowId, user1);
        uint cashBalanceAfter = cashAsset.balanceOf(user1);
        uint cashBalanceDiff = cashBalanceAfter - cashBalanceBefore;
        // price went up past call strike (120%) so the balance after withdrawing should be previous balance + loan + userLocked + providerLocked
        assertEq(cashBalanceDiff, 12_000 ether);
        BorrowPositionNFT.BorrowPosition memory position = borrowNFT.getPosition(borrowId);
        assertEq(position.withdrawable, 0);
    }

    /**
     * TODO * cancelPairedPosition revert branches
     *         "not owner of borrow ID"
     *         "not owner of provider ID"
     *         "already settled"
     */
    function test_cancelPairedPosition() public {
        createOfferAsProvider(12_000, providerNFT);
        mintTokensToUserandApproveNFT();
        setPricesAtTimestamp(engine, 1, 1 ether);
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
        assertEq(userCashBalanceDiff, 12_000 ether);

        uint providerCashBalanceDiff = providerCashBalanceAfter - providerCashBalanceBefore;
        assertEq(providerCashBalanceDiff, 0);
    }
}
