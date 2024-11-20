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
        prepareSwapToCashAtOraclePrice();

        // not enough approval for fee
        vm.startPrank(user1);
        underlying.approve(address(loans), underlyingAmount + escrowFee - 1);
        expectRevertERC20Allowance(
            address(loans), underlyingAmount + escrowFee - 1, underlyingAmount + escrowFee
        );
        openLoan(underlyingAmount, minLoanAmount, 0, 0);

        // fix allowance
        underlying.approve(address(loans), underlyingAmount + escrowFee);

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
        EscrowSupplierNFT invalidEscrow = new EscrowSupplierNFT(owner, configHub, cashAsset, "", "");
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
        prepareSwapToCashAtOraclePrice();
        underlying.approve(address(loans), underlyingAmount + escrowFee);
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

    function test_revert_unwrapAndCancelLoan_timing() public {
        (uint loanId,,) = createAndCheckLoan();
        // after expiry
        skip(duration + 1);
        // cannot unwrap
        vm.expectRevert("loans: loan expired");
        loans.unwrapAndCancelLoan(loanId);
    }

    function test_revert_forecloseLoan_timingAndAuthorization() public {
        (uint loanId,,) = createAndCheckLoan();

        // view reverts too escrowGracePeriod
        vm.expectRevert("loans: taker position not settled");
        loans.escrowGracePeriod(loanId);

        // foreclose before settlement
        vm.startPrank(supplier);
        vm.expectRevert("loans: taker position not settled");
        loans.forecloseLoan(loanId, defaultSwapParams(0));

        // settle
        skip(duration);
        updatePrice();
        takerNFT.settlePairedPosition(loanId);
        uint gracePeriod = loans.escrowGracePeriod(loanId);

        // at the end of grace period
        skip(gracePeriod);
        updatePrice();
        prepareSwapToUnderlyingAtOraclePrice();
        vm.expectRevert("loans: cannot foreclose yet");
        loans.forecloseLoan(loanId, defaultSwapParams(0));

        // foreclose from an unauthorized address
        vm.startPrank(user1);
        vm.expectRevert("loans: not escrow owner or allowed keeper");
        loans.forecloseLoan(loanId, defaultSwapParams(0));

        // set the keeper
        vm.startPrank(owner);
        loans.setKeeper(keeper);

        // keeper not authorized by supplier
        vm.startPrank(keeper);
        vm.expectRevert("loans: not escrow owner or allowed keeper");
        loans.forecloseLoan(loanId, defaultSwapParams(0));

        // keeper authorized by user but not supplier
        vm.startPrank(user1);
        loans.setKeeperApproved(true);
        vm.startPrank(keeper);
        vm.expectRevert("loans: not escrow owner or allowed keeper");
        loans.forecloseLoan(loanId, defaultSwapParams(0));

        // allow keeper
        vm.startPrank(supplier);
        loans.setKeeperApproved(true);

        // foreclosable now
        skip(1);
        updatePrice();
        prepareSwapToUnderlyingAtOraclePrice();

        // Keeper can now foreclose
        vm.startPrank(keeper);
        loans.forecloseLoan(loanId, defaultSwapParams(0));
    }

    function test_revert_forecloseLoan_invalidLoanStates() public {
        // foreclose a non-existent loan
        uint nonExistentLoanId = 999;
        expectRevertERC721Nonexistent(nonExistentLoanId);
        loans.forecloseLoan(nonExistentLoanId, defaultSwapParams(0));

        // create and cancel a loan
        (uint loanId,,) = createAndCheckLoan();
        vm.startPrank(user1);
        loans.unwrapAndCancelLoan(loanId);
        vm.startPrank(supplier);
        expectRevertERC721Nonexistent(loanId);
        loans.forecloseLoan(loanId, defaultSwapParams(0));

        // create a non-escrow loan
        openEscrowLoan = false;
        (uint nonEscrowLoanId,,) = createAndCheckLoan();
        vm.startPrank(supplier);
        vm.expectRevert("loans: not an escrowed loan");
        loans.forecloseLoan(nonEscrowLoanId, defaultSwapParams(0));
    }

    function test_revert_forecloseLoan_invalidParameters() public {
        (uint loanId,,) = createAndCheckLoan();

        // after grace period
        skip(duration + maxGracePeriod + 1);
        updatePrice();
        takerNFT.settlePairedPosition(loanId);
        uint swapOut = prepareSwapToUnderlyingAtOraclePrice();

        // foreclose with an invalid swapper
        vm.startPrank(supplier);
        vm.expectRevert("loans: swapper not allowed");
        loans.forecloseLoan(loanId, ILoansNFT.SwapParams(0, address(0x123), ""));

        // slippage
        vm.expectRevert("SwapperUniV3: slippage exceeded");
        loans.forecloseLoan(loanId, ILoansNFT.SwapParams(swapOut + 1, defaultSwapper, ""));
    }
}
