// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

import { LoansBasicRevertsTest, ILoansNFT } from "./Loans.basic.reverts.t.sol";

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

        // unsupported escrow
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

    function test_revert_openEscrowLoan_escrowValidations() public {
        maybeCreateEscrowOffer();

        vm.startPrank(owner);
        configHub.setCollarDurationRange(duration, duration + 1);
        // different durations between escrow and collar
        duration += 1;

        // provider offer has different duration
        uint shortOffer = createProviderOffer();

        vm.startPrank(user1);
        prepareSwapToCashAtTWAPPrice();
        collateralAsset.approve(address(loans), collateralAmount + escrowFee);
        vm.expectRevert("duration mismatch");
        openLoan(collateralAmount, minLoanAmount, 0, shortOffer);

        // loanId mismatch escrow
        vm.mockCall(
            address(takerNFT),
            abi.encodeCall(takerNFT.nextPositionId, ()),
            abi.encode(takerNFT.nextPositionId() - 1)
        );
        vm.expectRevert("unexpected loanId");
        openLoan(collateralAmount, minLoanAmount, 0, shortOffer);
    }

    function test_revert_unwrapAndCancelLoan_timing() public {
        (uint loanId,,) = createAndCheckLoan();
        // after expiry
        skip(duration + 1);
        // cannot unwrap
        vm.expectRevert("loan expired");
        loans.unwrapAndCancelLoan(loanId);
    }

    function test_revert_forecloseLoan_timingAndAuthorization() public {
        (uint loanId,,) = createAndCheckLoan();

        uint gracePeriodEnd = loans.escrowGracePeriodEnd(loanId);

        // foreclose before grace period ends
        vm.startPrank(supplier);
        vm.expectRevert("cannot foreclose yet");
        loans.forecloseLoan(loanId, defaultSwapParams(0));

        // at the end of grace period
        skip(gracePeriodEnd - block.timestamp);
        updatePrice();
        prepareSwapToCollateralAtTWAPPrice();
        mockOracle.setRequirePriceSet(true);
        vm.expectRevert("cannot foreclose yet");
        loans.forecloseLoan(loanId, defaultSwapParams(0));

        // foreclose from an unauthorized address
        vm.startPrank(user1);
        vm.expectRevert("not escrow owner or allowed keeper");
        loans.forecloseLoan(loanId, defaultSwapParams(0));

        // Set the keeper
        vm.startPrank(owner);
        loans.setKeeper(keeper);

        // keeper not authorized by supplier
        vm.startPrank(keeper);
        vm.expectRevert("not escrow owner or allowed keeper");
        loans.forecloseLoan(loanId, defaultSwapParams(0));

        // keeper authorized by user but not supplier
        vm.startPrank(user1);
        loans.setKeeperAllowed(true);
        vm.startPrank(keeper);
        vm.expectRevert("not escrow owner or allowed keeper");
        loans.forecloseLoan(loanId, defaultSwapParams(0));

        // Allow keeper
        vm.startPrank(supplier);
        loans.setKeeperAllowed(true);

        // foreclosable now
        skip(1);
        updatePrice();
        prepareSwapToCollateralAtTWAPPrice();

        // Keeper can now foreclose
        vm.startPrank(keeper);
        loans.forecloseLoan(loanId, defaultSwapParams(0));
    }

    function test_revert_forecloseLoan_invalidLoanStates() public {
        // foreclose a non-existent loan
        uint nonExistentLoanId = 999;
        vm.expectRevert("not an escrowed loan");
        loans.forecloseLoan(nonExistentLoanId, defaultSwapParams(0));

        // Create and cancel a loan
        (uint loanId,,) = createAndCheckLoan();
        vm.startPrank(user1);
        loans.unwrapAndCancelLoan(loanId);
        vm.startPrank(supplier);
        expectRevertERC721Nonexistent(loanId);
        loans.forecloseLoan(loanId, defaultSwapParams(0));

        // Create a non-escrow loan
        openEscrowLoan = false;
        (uint nonEscrowLoanId,,) = createAndCheckLoan();
        openEscrowLoan = true;

        // Skip to after what would be the grace period
        skip(duration + gracePeriod + 1);
        vm.startPrank(supplier);
        vm.expectRevert("not an escrowed loan");
        loans.forecloseLoan(nonEscrowLoanId, defaultSwapParams(0));
    }

    function test_revert_forecloseLoan_invalidParameters() public {
        (uint loanId,,) = createAndCheckLoan();

        // after grace period
        skip(duration + gracePeriod + 1);
        updatePrice();
        mockOracle.setRequirePriceSet(true);
        uint swapOut = prepareSwapToCollateralAtTWAPPrice();

        // foreclose with an invalid swapper
        vm.startPrank(supplier);
        vm.expectRevert("swapper not allowed");
        loans.forecloseLoan(loanId, ILoansNFT.SwapParams(0, address(0x123), ""));

        // slippage
        vm.expectRevert("slippage exceeded");
        loans.forecloseLoan(loanId, ILoansNFT.SwapParams(swapOut + 1, defaultSwapper, ""));
    }
}
