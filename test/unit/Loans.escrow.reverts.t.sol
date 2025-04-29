// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

import { LoansBasicRevertsTest, ILoansNFT, EscrowSupplierNFT } from "./Loans.basic.reverts.t.sol";

contract LoansEscrowRevertsTest is LoansBasicRevertsTest {
    function setUp() public virtual override {
        super.setUp();
        openEscrowLoan = true;
    }

    // repeat all reverts tests (open, close) from super, but with escrow

    // common reverts with openLoans are tested in test_revert_openLoan_params
    // this tests additional reverting branches for escrow
    function test_revert_openEscrowLoan_params() public {
        maybeCreateEscrowOffer();

        vm.startPrank(user1);
        prepareDefaultSwapToCash();

        // not enough approval for fee
        vm.startPrank(user1);
        underlying.approve(address(loans), underlyingAmount + escrowFees - 1);
        expectRevertERC20Allowance(
            address(loans), underlyingAmount + escrowFees - 1, underlyingAmount + escrowFees
        );
        openLoan(underlyingAmount, minLoanAmount, 0, 0);

        // fix allowance
        underlying.approve(address(loans), underlyingAmount + escrowFees);

        // unsupported escrow
        setCanOpenSingle(address(escrowNFT), false);
        vm.startPrank(user1);
        vm.expectRevert("loans: unsupported escrow");
        openLoan(underlyingAmount, 0, 0, 0);

        // bad escrow offer
        setCanOpenSingle(address(escrowNFT), true);
        vm.startPrank(user1);
        escrowOfferId = 999; // invalid escrow offer
        vm.expectRevert("escrow: invalid offer");
        openLoan(underlyingAmount, minLoanAmount, 0, 0);

        // test escrow asset mismatch
        EscrowSupplierNFT invalidEscrow = new EscrowSupplierNFT(configHub, cashAsset, "", "");
        setCanOpenSingle(address(invalidEscrow), true);
        vm.startPrank(user1);
        escrowNFT = invalidEscrow;
        vm.expectRevert("loans: escrow asset mismatch");
        openLoan(underlyingAmount, 0, 0, 0);
    }

    function test_revert_openEscrowLoan_escrowValidations() public {
        maybeCreateEscrowOffer();

        vm.startPrank(owner);
        configHub.setCollarDurationRange(duration, duration + 1);
        // different durations between escrow and collar
        duration += 1;

        // provider offer has different duration
        uint providerOffer = createProviderOffer();

        vm.startPrank(user1);
        prepareDefaultSwapToCash();
        underlying.approve(address(loans), underlyingAmount + escrowFees);
        vm.expectRevert("loans: duration mismatch");
        openLoan(underlyingAmount, minLoanAmount, 0, providerOffer);

        // loanId mismatch escrow
        vm.mockCall(
            address(takerNFT),
            abi.encodeCall(takerNFT.nextPositionId, ()),
            abi.encode(takerNFT.nextPositionId() - 1)
        );
        vm.expectRevert("loans: unexpected loanId");
        openLoan(underlyingAmount, minLoanAmount, 0, providerOffer);
    }

    function test_revert_seizeEscrow_timingAndAuthorization() public {
        (uint loanId,,) = createAndCheckLoan();
        ILoansNFT.Loan memory loan = loans.getLoan(loanId);

        // seize before settlement
        vm.startPrank(supplier);
        vm.expectRevert("escrow: grace period not elapsed");
        escrowNFT.seizeEscrow(loan.escrowId);

        // settle
        skip(duration);
        updatePrice();
        takerNFT.settlePairedPosition(loanId);

        // at the end of grace period
        skip(gracePeriod);
        vm.expectRevert("escrow: grace period not elapsed");
        escrowNFT.seizeEscrow(loan.escrowId);

        // seize from an unauthorized address
        vm.startPrank(user1);
        vm.expectRevert("escrow: not escrow owner");
        escrowNFT.seizeEscrow(loan.escrowId);

        // seize now
        skip(1);

        // escrow can be seized
        vm.startPrank(supplier);
        escrowNFT.seizeEscrow(loan.escrowId);
    }

    function test_revert_seizeEscrow_invalidLoanStates() public {
        // seize a non-existent loan
        uint nonExistentEscrowId = 999;
        expectRevertERC721Nonexistent(nonExistentEscrowId);
        escrowNFT.seizeEscrow(nonExistentEscrowId);

        // create and cancel a loan
        (uint loanId,, uint loanAmount) = createAndCheckLoan();
        uint escrowId = loans.getLoan(loanId).escrowId;

        uint checkpoint = vm.snapshotState();
        vm.startPrank(user1);
        loans.unwrapAndCancelLoan(loanId);
        vm.startPrank(supplier);
        vm.expectRevert("escrow: already released");
        escrowNFT.seizeEscrow(escrowId);

        vm.revertToState(checkpoint);
        vm.startPrank(user1);
        skip(duration);
        updatePrice();
        cashAsset.approve(address(loans), loanAmount);
        loans.closeLoan(loanId, defaultSwapParams(0));
        vm.startPrank(supplier);
        vm.expectRevert("escrow: already released");
        escrowNFT.seizeEscrow(escrowId);
    }
}
