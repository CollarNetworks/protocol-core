// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

import { LoansBasicEffectsTest, ILoansNFT } from "./Loans.basic.effects.t.sol";
import { IEscrowSupplierNFT } from "../../src/LoansNFT.sol";

contract LoansEscrowEffectsTest is LoansBasicEffectsTest {
    function setUp() public virtual override {
        super.setUp();
        openEscrowLoan = true;
    }

    function expectedGracePeriod(uint loanId, uint swapPrice) internal view returns (uint) {
        uint cashAvailable = takerNFT.getPosition({ takerId: loanId }).withdrawable;
        uint underlyingAmt = chainlinkOracle.convertToBaseAmount(cashAvailable, swapPrice);
        return escrowNFT.cappedGracePeriod(loans.getLoan(loanId).escrowId, underlyingAmt);
    }

    function checkForecloseLoan(uint settlePrice, uint currentPrice, uint skipAfterGrace, address caller)
        internal
        returns (EscrowReleaseAmounts memory released, uint estimatedGracePeriod)
    {
        (uint loanId,,) = createAndCheckLoan();

        skip(duration);
        updatePrice(settlePrice);
        // settle
        takerNFT.settlePairedPosition(loanId);

        // update to currentPrice price
        updatePrice(currentPrice);
        // estimate the length of grace period
        estimatedGracePeriod = loans.escrowGracePeriod(loanId);

        // skip past grace period
        skip(estimatedGracePeriod + skipAfterGrace);
        updatePrice(currentPrice);

        uint swapOut = prepareSwapToUnderlyingAtOraclePrice();

        // calculate expected escrow release values
        uint escrowId = loans.getLoan(loanId).escrowId;
        released = getEscrowReleaseValues(escrowId, swapOut);
        uint expectedToUser = released.fromEscrow + released.leftOver;
        uint userBalance = underlying.balanceOf(user1);
        uint escrowBalance = underlying.balanceOf(address(escrowNFT));

        // check late fee and grace period values
        assertGe(estimatedGracePeriod, escrowNFT.MIN_GRACE_PERIOD());
        assertLe(estimatedGracePeriod, maxGracePeriod);
        assertEq(released.lateFee, expectedLateFees(estimatedGracePeriod + skipAfterGrace));

        // foreclose
        vm.startPrank(caller);
        vm.expectEmit(address(loans));
        emit ILoansNFT.EscrowSettled(
            escrowId, released.lateFee, released.toEscrow, released.fromEscrow, released.leftOver
        );
        vm.expectEmit(address(loans));
        emit ILoansNFT.LoanForeclosed(loanId, escrowId, swapOut, expectedToUser);
        loans.forecloseLoan(loanId, defaultSwapParams(0));

        // balances
        assertEq(underlying.balanceOf(user1), userBalance + expectedToUser);
        assertEq(
            underlying.balanceOf(address(escrowNFT)), escrowBalance + released.toEscrow - released.fromEscrow
        );

        // struct
        IEscrowSupplierNFT.Escrow memory escrow = escrowNFT.getEscrow(escrowId);
        assertTrue(escrow.released);
        assertEq(escrow.withdrawable, escrow.escrowed + escrow.interestHeld + swapOut - expectedToUser);

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

    function test_escrowGracePeriod_afterExpiry() public {
        (uint loanId,,) = createAndCheckLoan();

        skip(duration);
        updatePrice();
        takerNFT.settlePairedPosition(loanId);
        // current price is different from settlement
        oraclePrice = oraclePrice * 11 / 10;
        updatePrice();
        uint expected = expectedGracePeriod(loanId, oraclePrice);

        // after expiry, keeps using correct price
        skip(1);
        updatePrice();
        assertEq(loans.escrowGracePeriod(loanId), expected);

        // After min grace period
        skip(escrowNFT.MIN_GRACE_PERIOD() - 1);
        updatePrice();
        assertEq(loans.escrowGracePeriod(loanId), expected);

        // After max grace period
        skip(escrowNFT.MAX_GRACE_PERIOD());
        updatePrice();
        assertEq(loans.escrowGracePeriod(loanId), expected);
    }

    function test_escrowGracePeriod_priceChanges() public {
        (uint loanId,,) = createAndCheckLoan();

        skip(duration); // at expiry
        updatePrice();
        takerNFT.settlePairedPosition(loanId);

        // Price increase
        uint highPrice = oraclePrice * 2;
        updatePrice(highPrice);
        assertEq(loans.escrowGracePeriod(loanId), expectedGracePeriod(loanId, highPrice));

        // Price decrease
        uint lowPrice = oraclePrice / 2;
        updatePrice(lowPrice);
        assertEq(loans.escrowGracePeriod(loanId), expectedGracePeriod(loanId, lowPrice));

        // min grace period (for very high price), very high price means cash is worth 0 underlying
        updatePrice(type(uint128).max);
        assertEq(loans.escrowGracePeriod(loanId), escrowNFT.MIN_GRACE_PERIOD());

        // max grace period (for very low price), because user swap will return a lot of underlying
        uint minPrice = 1;
        updatePrice(minPrice);
        assertEq(loans.escrowGracePeriod(loanId), maxGracePeriod);

        // worthless position
        (loanId,,) = createAndCheckLoan();
        skip(duration); // at expiry
        updatePrice(minPrice);
        takerNFT.settlePairedPosition(loanId);
        // position is worth 0 cash, so low underlying price doesn't matter
        assertEq(loans.escrowGracePeriod(loanId), escrowNFT.MIN_GRACE_PERIOD());
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

    function test_forecloseLoan_byKeeper() public {
        // Set the keeper
        vm.startPrank(owner);
        loans.setKeeper(keeper);

        // Supplier allows the keeper to foreclose
        vm.startPrank(supplier);
        loans.setKeeperApproved(true);

        // by keeper
        checkForecloseLoan(oraclePrice, oraclePrice, 1, keeper);
    }
}
