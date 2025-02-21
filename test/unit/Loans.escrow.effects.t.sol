// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

import { LoansBasicEffectsTest, ILoansNFT } from "./Loans.basic.effects.t.sol";
import { IEscrowSupplierNFT } from "../../src/LoansNFT.sol";

contract LoansEscrowEffectsTest is LoansBasicEffectsTest {
    function setUp() public virtual override {
        super.setUp();
        openEscrowLoan = true;
    }

    // tests

    // repeat all effects tests (open, close, unwrap) from super, but with escrow

    function test_unwrapAndCancelLoan_after_seizeEscrow() public {
        (uint loanId,,) = createAndCheckLoan();

        // check that escrow unreleased
        uint escrowId = loans.getLoan(loanId).escrowId;
        assertFalse(escrowNFT.getEscrow(escrowId).released);

        // after expiry
        skip(duration + gracePeriod + 1);

        // user balance
        uint userBalance = underlying.balanceOf(user1);
        uint loansBalance = underlying.balanceOf(address(loans));

        // release escrow via seizeEscrow
        vm.startPrank(supplier);
        escrowNFT.seizeEscrow(escrowId);
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
}
