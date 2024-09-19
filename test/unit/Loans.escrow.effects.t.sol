// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

import { LoansBasicEffectsTest, ILoansNFT } from "./Loans.basic.effects.t.sol";

contract LoansEscrowEffectsTest is LoansBasicEffectsTest {
    function setUp() public virtual override {
        super.setUp();
        openEscrowLoan = true;
    }

    // repeat all effects tests (open, close) from super, but with escrow

    function test_unwrapAndCancelLoan_beforeExpiry() public {
        (uint loanId,,) = createAndCheckLoan();
        uint takerId = loanId;
        assertEq(takerNFT.ownerOf(takerId), address(loans));

        // check that escrow unreleased
        uint escrowId = loans.getLoan(loanId).escrowId;
        assertEq(escrowNFT.ownerOf(escrowId), supplier);
        assertEq(escrowNFT.getEscrow(escrowId).released, false);
        // user balance
        uint balanceBefore = collateralAsset.balanceOf(user1);

        // release after half duration to get refund
        skip(duration / 2);

        // cancel
        vm.expectEmit(address(loans));
        emit ILoansNFT.LoanCancelled(loanId, address(user1));
        loans.unwrapAndCancelLoan(loanId);

        // NFT burned
        expectRevertERC721Nonexistent(loanId);
        loans.ownerOf(loanId);

        // taker NFT unwrapped
        assertEq(takerNFT.ownerOf(takerId), user1);

        // cannot cancel again
        expectRevertERC721Nonexistent(loanId);
        loans.unwrapAndCancelLoan(loanId);

        // escrow released
        assertEq(escrowNFT.getEscrow(escrowId).released, true);

        // received refund for half a duration
        uint refund = escrowNFT.getEscrow(escrowId).interestHeld / 2;
        assertEq(collateralAsset.balanceOf(user1), balanceBefore + refund);
    }

    function test_unwrapAndCancelLoan_releasedEscrow() public {
        (uint loanId,,) = createAndCheckLoan();
        uint takerId = loanId;
        assertEq(takerNFT.ownerOf(takerId), address(loans));

        // check that escrow unreleased
        uint escrowId = loans.getLoan(loanId).escrowId;
        assertEq(escrowNFT.ownerOf(escrowId), supplier);
        assertEq(escrowNFT.getEscrow(escrowId).released, false);

        // user balance
        uint balanceBefore = collateralAsset.balanceOf(user1);

        // after expiry
        skip(duration + 1);

        // cannot release
        vm.expectRevert("loan expired");
        loans.unwrapAndCancelLoan(loanId);

        // release escrow via some other way without closing the loan
        // can be lastResortSeizeEscrow if after full grace period
        vm.startPrank(address(loans));
        escrowNFT.endEscrow(escrowId, 0);
        assertEq(escrowNFT.getEscrow(escrowId).released, true);

        // now try to unwrap
        vm.startPrank(user1);
        vm.expectEmit(address(loans));
        emit ILoansNFT.LoanCancelled(loanId, address(user1));
        loans.unwrapAndCancelLoan(loanId);

        // NFT burned
        expectRevertERC721Nonexistent(loanId);
        loans.ownerOf(loanId);

        // taker NFT unwrapped
        assertEq(takerNFT.ownerOf(takerId), user1);

        // cannot cancel again
        expectRevertERC721Nonexistent(loanId);
        loans.unwrapAndCancelLoan(loanId);

        // nothing received
        assertEq(collateralAsset.balanceOf(user1), balanceBefore);
    }
}
