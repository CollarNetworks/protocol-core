// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

import { LoansBasicRevertsTest } from "./Loans.basic.reverts.t.sol";

contract LoansEscrowRevertsTest is LoansBasicRevertsTest {
    function setUp() public virtual override {
        super.setUp();
        useEscrow = true;
    }

    // repeat all reverts tests (open, close) from super, but with escrow

    // common reverts with openLoans are tested in test_revert_openLoan_params
    // this tests additional reverting branches for escrow
    function test_revert_openEscrowLoan_params() public {
        maybeCreateEscrowOffer();

        vm.startPrank(user1);
        prepareSwapToCashAtTWAPPrice();

        // not enough approval for fee
        vm.startPrank(user1);
        collateralAsset.approve(address(loans), collateralAmount + escrowFee - 1);
        vm.expectRevert("insufficient allowance for escrow fee");
        openLoan(collateralAmount, minLoanAmount, 0, 0);

        // unset escrow
        vm.startPrank(owner);
        loans.setContracts(rolls, providerNFT, NO_ESCROW);
        vm.startPrank(user1);
        vm.expectRevert("escrow contract unset");
        openLoan(0, 0, 0, 0);

        // unsupported provider
        vm.startPrank(owner);
        loans.setContracts(rolls, providerNFT, escrowNFT);
        configHub.setCanOpen(address(escrowNFT), false);
        vm.startPrank(user1);
        vm.expectRevert("unsupported escrow contract");
        openLoan(collateralAmount, 0, 0, 0);

        // bad escrow offer
        vm.startPrank(owner);
        configHub.setCanOpen(address(escrowNFT), true);
        vm.startPrank(user1);
        collateralAsset.approve(address(loans), collateralAmount + escrowFee);
        escrowOfferId = 999; // invalid escrow offer
        vm.expectRevert("invalid offer");
        openLoan(collateralAmount, minLoanAmount, 0, 0);
    }
}
