// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

import { LoansBasicEffectsTest, ILoansNFT } from "./Loans.basic.effects.t.sol";
import { IEscrowSupplierNFT } from "../../src/LoansNFT.sol";

contract LoansEscrowEffectsTest is LoansBasicEffectsTest {
    function setUp() public virtual override {
        super.setUp();
        openEscrowLoan = true;
    }

    function expectedForeclosureValues(uint loanId, uint price)
        internal
        view
        returns (uint gracePeriod, uint cashAvailable, uint lateFeeCash)
    {
        cashAvailable = takerNFT.getPosition({ takerId: loanId }).withdrawable;
        (, uint lateFee) = escrowNFT.currentOwed(loans.getLoan(loanId).escrowId);
        uint underlyingAmt = chainlinkOracle.convertToBaseAmount(cashAvailable, price);
        gracePeriod = escrowNFT.cappedGracePeriod(loans.getLoan(loanId).escrowId, underlyingAmt);
        lateFeeCash = chainlinkOracle.convertToQuoteAmount(lateFee, price);
        lateFeeCash = lateFeeCash > cashAvailable ? cashAvailable : lateFeeCash;
    }

    function checkForecloseLoan(uint settlePrice, uint currentPrice, uint skipAfterGrace, address caller)
        internal
        returns (uint swapOut, uint expectedBorrowerRefund)
    {
        (uint loanId,,) = createAndCheckLoan();

        skip(duration);
        updatePrice(settlePrice);
        // settle
        takerNFT.settlePairedPosition(loanId);

        // update to currentPrice price
        updatePrice(currentPrice);
        // estimate the length of grace period
        (uint estimatedGracePeriod,) = loans.foreclosureValues(loanId);

        // skip past grace period
        skip(estimatedGracePeriod + skipAfterGrace);
        updatePrice(currentPrice);
        // estimate the cash for late fees
        (, uint lateFeeCash) = loans.foreclosureValues(loanId);

        uint takerCash = takerNFT.getPosition(loanId).withdrawable;
        swapOut = chainlinkOracle.convertToBaseAmount(lateFeeCash, currentPrice);
        prepareSwap(underlying, swapOut);

        // calculate expected escrow release values
        uint escrowId = loans.getLoan(loanId).escrowId;
        EscrowReleaseAmounts memory released = getEscrowReleaseValues(escrowId, swapOut);
        expectedBorrowerRefund = takerCash - lateFeeCash;
        uint userCashBalance = cashAsset.balanceOf(user1);
        uint escrowBalance = underlying.balanceOf(address(escrowNFT));

        // check late fee and grace period values
        assertGe(estimatedGracePeriod, escrowNFT.MIN_GRACE_PERIOD());
        assertLe(estimatedGracePeriod, maxGracePeriod);
        assertEq(released.lateFee, expectedLateFees(estimatedGracePeriod + skipAfterGrace));

        // foreclose
        vm.startPrank(caller);
        vm.expectEmit(address(loans));
        emit ILoansNFT.LoanForeclosed(loanId, escrowId, swapOut, expectedBorrowerRefund);
        loans.forecloseLoan(loanId, defaultSwapParams(0));

        // balances
        assertEq(cashAsset.balanceOf(user1), userCashBalance + expectedBorrowerRefund);
        assertEq(underlying.balanceOf(address(escrowNFT)), escrowBalance + swapOut);

        // struct
        IEscrowSupplierNFT.Escrow memory escrow = escrowNFT.getEscrow(escrowId);
        assertTrue(escrow.released);
        assertEq(escrow.withdrawable, escrow.escrowed + escrow.interestHeld + swapOut);

        // loan and taker NFTs burned
        expectRevertERC721Nonexistent(loanId);
        loans.ownerOf(loanId);
        expectRevertERC721Nonexistent(loanId);
        takerNFT.ownerOf({ tokenId: loanId });
    }

    // tests

    // repeat all effects tests (open, close, unwrap) from super, but with escrow

    function test_unwrapAndCancelLoan_releasedEscrow() public {
        (uint loanId,,) = createAndCheckLoan();

        // check that escrow unreleased
        uint escrowId = loans.getLoan(loanId).escrowId;
        assertFalse(escrowNFT.getEscrow(escrowId).released);

        // after expiry
        skip(duration + 1);

        // cannot release
        vm.expectRevert("loans: loan expired");
        loans.unwrapAndCancelLoan(loanId);

        // user balance
        uint userBalance = underlying.balanceOf(user1);
        uint loansBalance = underlying.balanceOf(address(loans));

        // release escrow via some other way without closing the loan
        // can be lastResortSeizeEscrow if after full grace period
        vm.startPrank(address(loans));
        escrowNFT.endEscrow(escrowId, 0);
        assertTrue(escrowNFT.getEscrow(escrowId).released);

        // now can unwrap
        vm.startPrank(user1);
        loans.unwrapAndCancelLoan(loanId);

        // no funds moved
        assertEq(underlying.balanceOf(user1), userBalance);
        assertEq(underlying.balanceOf(address(loans)), loansBalance);

        // NFT burned
        expectRevertERC721Nonexistent(loanId);
        loans.ownerOf(loanId);
        // taker NFT unwrapped
        assertEq(takerNFT.ownerOf({ tokenId: loanId }), user1);
        // cannot cancel again
        expectRevertERC721Nonexistent(loanId);
        loans.unwrapAndCancelLoan(loanId);
    }

    function test_foreclosureValues_afterExpiry() public {
        (uint loanId,,) = createAndCheckLoan();

        skip(duration);
        updatePrice();
        takerNFT.settlePairedPosition(loanId);
        // current price is different from settlement
        oraclePrice = oraclePrice * 11 / 10;
        updatePrice();
        (uint expectedPeriod,,) = expectedForeclosureValues(loanId, oraclePrice);

        // after expiry, keeps using correct price
        skip(1);
        updatePrice();
        (uint gracePeriod, uint lateFeeCash) = loans.foreclosureValues(loanId);
        assertEq(gracePeriod, expectedPeriod);
        assertEq(lateFeeCash, 0);

        // at last second of grace period
        skip(escrowNFT.MIN_GRACE_PERIOD() - 1);
        updatePrice();
        (gracePeriod, lateFeeCash) = loans.foreclosureValues(loanId);
        assertEq(gracePeriod, expectedPeriod);
        assertEq(lateFeeCash, 0);

        // After max grace period
        skip(escrowNFT.MAX_GRACE_PERIOD());
        updatePrice();
        // late fee cash changes with time due to late fee accumulating
        (,, uint expectedFeeCash) = expectedForeclosureValues(loanId, oraclePrice);
        (gracePeriod, lateFeeCash) = loans.foreclosureValues(loanId);
        assertEq(gracePeriod, expectedPeriod);
        assertEq(lateFeeCash, expectedFeeCash);
    }

    function test_foreclosureValues_priceChanges() public {
        (uint loanId,,) = createAndCheckLoan();

        skip(duration); // at expiry
        updatePrice();
        takerNFT.settlePairedPosition(loanId);
        // skip to max grace period for late fee accumulation
        skip(escrowNFT.MAX_GRACE_PERIOD());
        updatePrice();

        // Price increase
        uint highPrice = oraclePrice * 2;
        updatePrice(highPrice);
        (uint expectedPeriod, uint cashAvailable, uint expectedFeeCash) =
            expectedForeclosureValues(loanId, highPrice);
        (uint gracePeriod, uint lateFeeCash) = loans.foreclosureValues(loanId);
        assertEq(gracePeriod, expectedPeriod);
        assertEq(lateFeeCash, expectedFeeCash);

        // Price decrease
        uint lowPrice = oraclePrice / 2;
        updatePrice(lowPrice);
        (expectedPeriod,, expectedFeeCash) = expectedForeclosureValues(loanId, lowPrice);
        (gracePeriod, lateFeeCash) = loans.foreclosureValues(loanId);
        assertEq(gracePeriod, expectedPeriod);
        assertEq(lateFeeCash, expectedFeeCash);

        // min grace period (for very high price), very high price means cash is worth 0 underlying
        updatePrice(type(uint128).max);
        (gracePeriod, lateFeeCash) = loans.foreclosureValues(loanId);
        assertEq(gracePeriod, escrowNFT.MIN_GRACE_PERIOD());
        assertEq(lateFeeCash, cashAvailable);

        // max grace period (for very low price), because swap will return a lot of underlying
        uint minPrice = 1;
        updatePrice(minPrice);
        (,, expectedFeeCash) = expectedForeclosureValues(loanId, minPrice);
        (gracePeriod, lateFeeCash) = loans.foreclosureValues(loanId);
        assertEq(gracePeriod, maxGracePeriod);
        assertEq(lateFeeCash, expectedFeeCash);

        // worthless position
        (loanId,,) = createAndCheckLoan();
        skip(duration); // at expiry
        updatePrice(minPrice);
        takerNFT.settlePairedPosition(loanId);
        (gracePeriod, lateFeeCash) = loans.foreclosureValues(loanId);
        // position is worth 0 cash, so low underlying price doesn't matter
        assertEq(gracePeriod, escrowNFT.MIN_GRACE_PERIOD());
        assertEq(lateFeeCash, 0);
    }

    function test_forecloseLoan_prices() public {
        // just after grace period end
        checkForecloseLoan(oraclePrice, oraclePrice, 1, supplier);

        // long after max gracePeriod
        checkForecloseLoan(oraclePrice, oraclePrice, maxGracePeriod, supplier);

        // price increase
        checkForecloseLoan(type(uint128).max, type(uint128).max, maxGracePeriod, supplier);

        // price decrease
        checkForecloseLoan(1, 1, maxGracePeriod, supplier);

        // price increase, and decrease
        checkForecloseLoan(largeAmount, 1, maxGracePeriod, supplier);

        // price decrease, and increase
        checkForecloseLoan(1, largeAmount, maxGracePeriod, supplier);
    }

    function test_forecloseLoan_zero_amount_swap() public {
        (uint swapOut,) = checkForecloseLoan(1, 1, maxGracePeriod, supplier);
        assertEq(swapOut, 0);
    }

    function test_forecloseLoan_borrowerRefund() public {
        // price decrease during swap to get so that little cash is needed to cover late fees
        // and a large refund is left
        (, uint borrowerRefund) = checkForecloseLoan(oraclePrice, oraclePrice / 100, maxGracePeriod, supplier);
        // check borrower should have got something, exact amount is checked in checkForecloseLoan
        assertNotEq(borrowerRefund, 0);
    }

    function test_forecloseLoan_borrowerRefund_blockedTransfer() public {
        // blocked non-zero transfer breaks foreclosure
        (uint loanId,,) = createAndCheckLoan();
        skip(duration);
        updatePrice();
        takerNFT.settlePairedPosition(loanId);
        skip(maxGracePeriod + 1);
        updatePrice();

        // block transfer to user1
        cashAsset.setBlocked(user1, true);
        prepareSwap(underlying, underlyingAmount);
        // a lot of leftovers
        vm.startPrank(supplier);
        vm.expectRevert("blocked");
        loans.forecloseLoan(loanId, defaultSwapParams(0));

        // blocked 0 transfer works fine

        // update to high price such the cash now doesn't buy enough late fees, so all cash is used up
        updatePrice(type(uint128).max);
        loans.forecloseLoan(loanId, defaultSwapParams(0));
    }

    function test_forecloseLoan_byKeeper() public {
        // Set the keeper
        vm.startPrank(owner);
        loans.setKeeper(keeper);

        // Supplier allows the keeper to foreclose
        vm.startPrank(supplier);
        // approve keeper for next loan ID, since it will be created in the helper method
        loans.setKeeperApproved(takerNFT.nextPositionId(), true);

        // by keeper
        checkForecloseLoan(oraclePrice, oraclePrice, 1, keeper);
    }
}
