// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "forge-std/Test.sol";
import "./DeploymentLoader.sol";
import { ILoansNFT } from "../../../src/interfaces/ILoansNFT.sol";
import { IRolls } from "../../../src/interfaces/IRolls.sol";
import { ArbitrumMainnetDeployer } from "../../../script/arbitrum-mainnet/deployer.sol";
import { DeploymentUtils } from "../../../script/utils/deployment-exporter.s.sol";

abstract contract LoansTestBase is Test, DeploymentLoader {
    function setUp() public virtual override {
        super.setUp();
    }

    function createProviderOffer(
        DeploymentHelper.AssetPairContracts memory pair,
        uint callStrikePercent,
        uint amount
    ) internal returns (uint offerId) {
        vm.startPrank(provider);
        uint cashBalance = pair.cashAsset.balanceOf(provider);
        console.log("Provider cash balance: %d", cashBalance);
        pair.cashAsset.approve(address(pair.providerNFT), amount);
        offerId = pair.providerNFT.createOffer(callStrikePercent, amount, pair.ltvs[0], pair.durations[0], 0);

        vm.stopPrank();
    }

    function openLoan(
        DeploymentHelper.AssetPairContracts memory pair,
        address user,
        uint underlyingAmount,
        uint minLoanAmount,
        uint offerId
    ) internal returns (uint loanId, uint providerId, uint loanAmount) {
        vm.startPrank(user);
        pair.underlying.approve(address(pair.loansContract), underlyingAmount);
        (loanId, providerId, loanAmount) = pair.loansContract.openLoan(
            underlyingAmount,
            minLoanAmount,
            ILoansNFT.SwapParams(0, address(pair.loansContract.defaultSwapper()), ""),
            ILoansNFT.ProviderOffer(pair.providerNFT, offerId)
        );
        vm.stopPrank();
    }

    function closeLoan(
        DeploymentHelper.AssetPairContracts memory pair,
        address user,
        uint loanId,
        uint minUnderlyingOut
    ) internal returns (uint underlyingOut) {
        vm.startPrank(user);
        ILoansNFT.Loan memory loan = pair.loansContract.getLoan(loanId);
        // approve repayment amount in cash asset to loans contract
        pair.cashAsset.approve(address(pair.loansContract), loan.loanAmount);
        underlyingOut = pair.loansContract.closeLoan(
            loanId, ILoansNFT.SwapParams(minUnderlyingOut, address(pair.loansContract.defaultSwapper()), "")
        );
        vm.stopPrank();
    }

    function createRollOffer(
        DeploymentHelper.AssetPairContracts memory pair,
        address provider,
        uint loanId,
        uint providerId,
        int rollFee,
        int rollDeltaFactor
    ) internal returns (uint rollOfferId) {
        vm.startPrank(provider);
        pair.cashAsset.approve(address(pair.rollsContract), type(uint).max);
        pair.providerNFT.approve(address(pair.rollsContract), providerId);
        uint currentPrice = pair.takerNFT.currentOraclePrice();
        uint takerId = loanId;
        rollOfferId = pair.rollsContract.createOffer(
            takerId,
            rollFee,
            rollDeltaFactor,
            currentPrice * 90 / 100,
            currentPrice * 110 / 100,
            0,
            block.timestamp + 1 hours
        );
        vm.stopPrank();
    }

    function rollLoan(
        DeploymentHelper.AssetPairContracts memory pair,
        address user,
        uint loanId,
        uint rollOfferId,
        int minToUser
    ) internal returns (uint newLoanId, uint newLoanAmount, int transferAmount) {
        vm.startPrank(user);
        pair.cashAsset.approve(address(pair.loansContract), type(uint).max);
        (newLoanId, newLoanAmount, transferAmount) = pair.loansContract.rollLoan(
            loanId, ILoansNFT.RollOffer(pair.rollsContract, rollOfferId), minToUser, 0, 0
        );
        vm.stopPrank();
    }
}

contract LoansForkTest is LoansTestBase {
    address constant cashAsset = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8; // USDC
    address constant underlying = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1; // WETH
    uint constant callstrikeToUse = 12_000;
    uint constant offerAmount = 100_000e6;
    uint constant underlyingAmount = 1 ether;
    int constant rollFee = 100e6;
    int constant rollDeltaFactor = 10_000;
    uint constant bigCashAmount = 1_000_000e6;
    uint constant bigUnderlyingAmount = 1000 ether;
    uint constant slippage = 1; // 1%
    uint constant BIPS_BASE = 10_000;

    //escrow related constants
    uint constant interestAPR = 500; // 5% APR
    uint constant maxGracePeriod = 7 days;
    uint constant lateFeeAPR = 10_000; // 100% APR

    // Protocol fee params
    uint constant feeAPR = 100; // 1% APR

    DeploymentHelper.AssetPairContracts internal pair;

    // Protocol fee values
    address feeRecipient;

    // escrow related values
    address escrowSupplier;

    function setUp() public virtual override {
        super.setUp();
        pair = getPairByAssets(address(cashAsset), address(underlying));
        require(address(pair.loansContract) != address(0), "Loans contract not deployed");

        // Setup protocol fee
        feeRecipient = makeAddr("feeRecipient");
        vm.startPrank(owner);
        configHub.setProtocolFeeParams(feeAPR, feeRecipient);
        vm.stopPrank();
        escrowSupplier = makeAddr("escrowSupplier");
        fundWallets();
    }

    function setForkId(uint _forkId) public {
        forkId = _forkId;
        forkSet = true;
    }

    function testOpenAndCloseLoan() public {
        uint providerBalanceBefore = pair.cashAsset.balanceOf(provider);
        uint offerId = createProviderOffer(pair, callstrikeToUse, offerAmount);
        assertEq(pair.cashAsset.balanceOf(provider), providerBalanceBefore - offerAmount);
        uint feeRecipientBalanceBefore = pair.cashAsset.balanceOf(feeRecipient);

        (uint loanId,, uint loanAmount) = openLoan(
            pair,
            user,
            underlyingAmount,
            0.3e6, // minLoanAmount
            offerId
        );
        // Verify fee taken and sent to recipient
        uint expectedFee = getProviderProtocolFeeByLoanAmount(loanAmount);
        assertEq(pair.cashAsset.balanceOf(feeRecipient) - feeRecipientBalanceBefore, expectedFee);
        /// @dev offerAmount change (offerAmount-providerLocked-fee) could be checked
        /// but would require a lot of precision due to slippage from swap on final providerLocked value
        assertGt(loanAmount, 0);
        skip(pair.durations[0]);
        closeAndCheckLoan(loanId, loanAmount, 0);
    }

    function testOpenEscrowLoan() public {
        (uint offerId, uint escrowOfferId) = createEscrowOffers();
        uint feeRecipientBalanceBefore = pair.cashAsset.balanceOf(feeRecipient);
        uint expectedProtocolFee = getProviderProtocolFeeByUnderlying();
        (uint loanId, uint providerId, uint loanAmount) = executeEscrowLoan(offerId, escrowOfferId);
        verifyEscrowLoan(
            loanId, providerId, loanAmount, escrowOfferId, feeRecipientBalanceBefore, expectedProtocolFee
        );
    }

    function testOpenAndCloseEscrowLoan() public {
        //  create provider and escrow offers
        (uint offerId, uint escrowOfferId) = createEscrowOffers();
        (uint loanId,, uint loanAmount) = executeEscrowLoan(offerId, escrowOfferId);
        ILoansNFT.Loan memory loanBefore = pair.loansContract.getLoan(loanId);

        uint escrowSupplierBefore = pair.underlying.balanceOf(escrowSupplier);
        uint interestFee = pair.escrowNFT.interestFee(escrowOfferId, underlyingAmount);

        // Skip to expiry
        skip(pair.durations[0]);

        closeAndCheckLoan(loanId, loanAmount, 0);

        // Check escrow position's withdrawable amount (underlying + interest)
        uint withdrawable = pair.escrowNFT.getEscrow(loanBefore.escrowId).withdrawable;
        assertEq(withdrawable, underlyingAmount + interestFee);

        // Execute withdrawal and verify balance change
        vm.startPrank(escrowSupplier);
        pair.escrowNFT.withdrawReleased(loanBefore.escrowId);
        vm.stopPrank();

        assertEq(
            pair.underlying.balanceOf(escrowSupplier) - escrowSupplierBefore, underlyingAmount + interestFee
        );
    }

    function testCloseEscrowLoanAfterGracePeriod() public {
        //  create provider and escrow offers
        (uint offerId, uint escrowOfferId) = createEscrowOffers();
        (uint loanId,, uint loanAmount) = executeEscrowLoan(offerId, escrowOfferId);

        ILoansNFT.Loan memory loanBefore = pair.loansContract.getLoan(loanId);
        uint escrowSupplierBefore = pair.underlying.balanceOf(escrowSupplier);
        uint interestFee = pair.escrowNFT.interestFee(escrowOfferId, underlyingAmount);

        // Skip past expiry AND grace period
        skip(pair.durations[0] + maxGracePeriod + 1);

        // Calculate expected late fee
        (, uint lateFee) = pair.escrowNFT.currentOwed(loanBefore.escrowId);
        assertGt(lateFee, 0);

        closeAndCheckLoan(loanId, loanAmount, lateFee);

        // Check escrow position's withdrawable (underlying + interest + late fee)
        uint withdrawable = pair.escrowNFT.getEscrow(loanBefore.escrowId).withdrawable;
        assertEq(withdrawable, underlyingAmount + interestFee + lateFee);

        // Execute withdrawal and verify balance
        vm.startPrank(escrowSupplier);
        pair.escrowNFT.withdrawReleased(loanBefore.escrowId);
        vm.stopPrank();

        assertEq(
            pair.underlying.balanceOf(escrowSupplier) - escrowSupplierBefore,
            underlyingAmount + interestFee + lateFee
        );
    }

    function testCloseEscrowLoanWithPartialLateFees() public {
        //  create provider and escrow offers
        (uint offerId, uint escrowOfferId) = createEscrowOffers();
        (uint loanId,, uint loanAmount) = executeEscrowLoan(offerId, escrowOfferId);

        ILoansNFT.Loan memory loanBefore = pair.loansContract.getLoan(loanId);
        uint escrowSupplierBefore = pair.underlying.balanceOf(escrowSupplier);
        uint interestFee = pair.escrowNFT.interestFee(escrowOfferId, underlyingAmount);

        // Skip past expiry but only halfway through grace period
        skip(pair.durations[0] + maxGracePeriod / 2);

        // Calculate expected partial late fee
        (, uint lateFee) = pair.escrowNFT.currentOwed(loanBefore.escrowId);
        assertGt(lateFee, 0);
        assertLt(lateFee, underlyingAmount * lateFeeAPR * maxGracePeriod / (BIPS_BASE * 365 days));

        closeAndCheckLoan(loanId, loanAmount, lateFee);

        // Check escrow position's withdrawable (underlying + interest + partial late fee)
        uint withdrawable = pair.escrowNFT.getEscrow(loanBefore.escrowId).withdrawable;
        assertEq(withdrawable, underlyingAmount + interestFee + lateFee);

        // Execute withdrawal and verify balance
        vm.startPrank(escrowSupplier);
        pair.escrowNFT.withdrawReleased(loanBefore.escrowId);
        vm.stopPrank();

        assertEq(
            pair.underlying.balanceOf(escrowSupplier) - escrowSupplierBefore,
            underlyingAmount + interestFee + lateFee
        );
    }

    function testRollEscrowLoanBetweenSuppliers() public {
        // Create first provider and escrow offers
        (uint offerId1, uint escrowOfferId1) = createEscrowOffers();
        uint interestFee1 = pair.escrowNFT.interestFee(escrowOfferId1, underlyingAmount);

        uint userUnderlyingBefore = pair.underlying.balanceOf(user);
        (uint loanId, uint providerId, uint loanAmount) = executeEscrowLoan(offerId1, escrowOfferId1);
        ILoansNFT.Loan memory loan = pair.loansContract.getLoan(loanId);
        // User has paid underlyingAmount + interestFee1 at this point
        assertEq(userUnderlyingBefore - pair.underlying.balanceOf(user), underlyingAmount + interestFee1);

        uint escrowSupplier1Before = pair.underlying.balanceOf(escrowSupplier);

        // Create second escrow supplier
        address escrowSupplier2 = makeAddr("escrowSupplier2");
        deal(address(underlying), escrowSupplier2, bigUnderlyingAmount);

        // Skip half the duration to test partial fees
        skip(pair.durations[0] / 2);

        // Get exact refund amount from contract
        (uint withdrawal, uint toLoans,) = pair.escrowNFT.previewRelease(loan.escrowId, 0);

        // Create second escrow supplier's offer
        vm.startPrank(escrowSupplier2);
        pair.underlying.approve(address(pair.escrowNFT), underlyingAmount);
        uint escrowOfferId2 = pair.escrowNFT.createOffer(
            underlyingAmount,
            pair.durations[0],
            interestAPR,
            maxGracePeriod,
            lateFeeAPR,
            0 // minEscrow
        );
        vm.stopPrank();

        // Create roll offer using existing provider position
        uint rollOfferId = createRollOffer(pair, provider, loanId, providerId, rollFee, rollDeltaFactor);

        uint newEscrowFee = pair.escrowNFT.interestFee(escrowOfferId2, underlyingAmount);
        uint userUnderlyingBeforeRoll = pair.underlying.balanceOf(user);

        vm.startPrank(user);
        pair.cashAsset.approve(address(pair.loansContract), uint(rollFee));
        pair.underlying.approve(address(pair.loansContract), newEscrowFee);
        (uint newLoanId, uint newLoanAmount,) = pair.loansContract.rollLoan(
            loanId,
            ILoansNFT.RollOffer(pair.rollsContract, rollOfferId),
            -1000e6,
            escrowOfferId2,
            newEscrowFee
        );
        vm.stopPrank();

        // Execute withdrawal for first supplier
        vm.startPrank(escrowSupplier);
        pair.escrowNFT.withdrawReleased(loanId);
        vm.stopPrank();

        // Verify first supplier got partial fees using exact toLoans amount
        // we use Ge because of rounding (seeing 1 wei difference 237823439879 != 237823439878)
        assertGe(pair.underlying.balanceOf(escrowSupplier) - escrowSupplier1Before, withdrawal);

        // Verify user paid new escrow fee and got refund from old escrow
        assertEq(userUnderlyingBeforeRoll - pair.underlying.balanceOf(user) + toLoans, newEscrowFee);

        // Skip to end of new loan term
        skip(pair.durations[0]);

        // Track second supplier balance before closing
        uint escrowSupplier2Before = pair.underlying.balanceOf(escrowSupplier2);

        closeAndCheckLoan(newLoanId, newLoanAmount, 0);

        // Execute withdrawal for second supplier
        vm.startPrank(escrowSupplier2);
        pair.escrowNFT.withdrawReleased(newLoanId);
        vm.stopPrank();

        // Verify second supplier got full amount + full fees
        assertEq(
            pair.underlying.balanceOf(escrowSupplier2) - escrowSupplier2Before,
            underlyingAmount + newEscrowFee
        );
    }

    function testRollLoan() public {
        uint offerId = createProviderOffer(pair, callstrikeToUse, offerAmount);
        (uint loanId, uint providerId, uint initialLoanAmount) = openLoan(
            pair,
            user,
            underlyingAmount,
            0.3e6, // minLoanAmount
            offerId
        );

        uint rollOfferId = createRollOffer(pair, provider, loanId, providerId, rollFee, rollDeltaFactor);

        // Calculate and verify protocol fee based on new position's provider locked amount
        uint newPositionPrice = pair.takerNFT.currentOraclePrice();
        IRolls.PreviewResults memory expectedResults =
            pair.rollsContract.previewRoll(rollOfferId, newPositionPrice);
        assertGt(expectedResults.protocolFee, 0);
        assertGt(expectedResults.toProvider, 0);

        uint providerBalanceBefore = pair.cashAsset.balanceOf(provider);
        uint feeRecipientBalanceBefore = pair.cashAsset.balanceOf(feeRecipient);
        (uint newLoanId, uint newLoanAmount, int transferAmount) = rollLoan(
            pair,
            user,
            loanId,
            rollOfferId,
            -1000e6 // Allow up to 1000 tokens to be paid by the user
        );

        // Verify fee taken and sent to recipient
        assertEq(
            pair.cashAsset.balanceOf(feeRecipient) - feeRecipientBalanceBefore, expectedResults.protocolFee
        );
        assertEq(int(pair.cashAsset.balanceOf(provider) - providerBalanceBefore), expectedResults.toProvider);
        assertGt(newLoanId, loanId);
        assertGe(int(newLoanAmount), int(initialLoanAmount) + transferAmount);
    }

    function testFullLoanLifecycle() public {
        uint feeRecipientBalanceBefore = pair.cashAsset.balanceOf(feeRecipient);

        uint offerId = createProviderOffer(pair, callstrikeToUse, offerAmount);

        (uint loanId, uint providerId, uint initialLoanAmount) =
            openLoan(pair, user, underlyingAmount, 0.3e6, offerId);
        uint initialFee = getProviderProtocolFeeByLoanAmount(initialLoanAmount);
        // Verify fee taken and sent to recipient
        assertEq(pair.cashAsset.balanceOf(feeRecipient) - feeRecipientBalanceBefore, initialFee);

        // Advance time
        skip(pair.durations[0] - 20);

        uint recipientBalanceAfterOpenLoan = pair.cashAsset.balanceOf(feeRecipient);
        uint rollOfferId = createRollOffer(pair, provider, loanId, providerId, rollFee, rollDeltaFactor);

        // Calculate roll protocol fee
        IRolls.PreviewResults memory expectedResults =
            pair.rollsContract.previewRoll(rollOfferId, pair.takerNFT.currentOraclePrice());
        assertGt(expectedResults.protocolFee, 0);
        (uint newLoanId, uint newLoanAmount, int transferAmount) =
            rollLoan(pair, user, loanId, rollOfferId, -1000e6);

        assertEq(
            pair.cashAsset.balanceOf(feeRecipient) - recipientBalanceAfterOpenLoan,
            expectedResults.protocolFee
        );

        // Advance time again
        skip(pair.durations[0]);

        closeAndCheckLoan(newLoanId, newLoanAmount, 0);
        assertGt(initialLoanAmount, 0);
        assertGe(int(newLoanAmount), int(initialLoanAmount) + transferAmount);

        // Verify total protocol fees collected
        assertEq(
            pair.cashAsset.balanceOf(feeRecipient) - feeRecipientBalanceBefore,
            initialFee + expectedResults.protocolFee
        );
    }

    function getProviderProtocolFeeByLoanAmount(uint loanAmount) internal view returns (uint protocolFee) {
        // Calculate protocol fee based on post-swap provider locked amount
        uint swapOut = loanAmount * BIPS_BASE / pair.ltvs[0];
        uint initProviderLocked = swapOut * (callstrikeToUse - BIPS_BASE) / BIPS_BASE;
        (protocolFee,) = pair.providerNFT.protocolFee(initProviderLocked, pair.durations[0]);
        assertGt(protocolFee, 0);
    }

    function getProviderProtocolFeeByUnderlying() internal view returns (uint protocolFee) {
        // Calculate protocol fee based on post-swap provider locked amount
        uint swapOut = underlyingAmount * pair.takerNFT.currentOraclePrice() / pair.oracle.baseUnitAmount();
        uint initProviderLocked = swapOut * (callstrikeToUse - BIPS_BASE) / BIPS_BASE;
        (protocolFee,) = pair.providerNFT.protocolFee(initProviderLocked, pair.durations[0]);
        assertGt(protocolFee, 0);
    }

    function closeAndCheckLoan(uint loanId, uint loanAmount, uint lateFee) internal {
        // Track balances before closing
        uint userCashBefore = pair.cashAsset.balanceOf(user);
        uint userUnderlyingBefore = pair.underlying.balanceOf(user);

        // no price change so underlying out should be underlying in minus slippage and minus late fees
        uint minUnderlyingOut = underlyingAmount;
        uint minUnderlyingOutWithSlippage = (minUnderlyingOut * (100 - slippage) / 100) - lateFee;
        uint underlyingOut = closeLoan(pair, user, loanId, minUnderlyingOutWithSlippage);
        assertGe(underlyingOut, minUnderlyingOutWithSlippage);
        // Verify balance changes
        assertEq(userCashBefore - pair.cashAsset.balanceOf(user), loanAmount);
        assertEq(pair.underlying.balanceOf(user) - userUnderlyingBefore, underlyingOut);
    }

    function createEscrowOffer(uint duration) internal returns (uint offerId) {
        vm.startPrank(escrowSupplier);
        pair.underlying.approve(address(pair.escrowNFT), underlyingAmount);
        offerId = pair.escrowNFT.createOffer(
            underlyingAmount,
            duration,
            interestAPR,
            maxGracePeriod,
            lateFeeAPR,
            0 // minEscrow
        );
        vm.stopPrank();
    }

    function openEscrowLoan(uint minLoanAmount, uint providerOfferId, uint escrowOfferId, uint escrowFee)
        internal
        returns (uint loanId, uint providerId, uint loanAmount)
    {
        vm.startPrank(user);
        // Approve underlying amount plus escrow fee
        pair.underlying.approve(address(pair.loansContract), underlyingAmount + escrowFee);

        (loanId, providerId, loanAmount) = pair.loansContract.openEscrowLoan(
            underlyingAmount,
            minLoanAmount,
            ILoansNFT.SwapParams(0, address(pair.loansContract.defaultSwapper()), ""),
            ILoansNFT.ProviderOffer(pair.providerNFT, providerOfferId),
            ILoansNFT.EscrowOffer(pair.escrowNFT, escrowOfferId),
            escrowFee
        );
        vm.stopPrank();
    }

    function createEscrowOffers() internal returns (uint offerId, uint escrowOfferId) {
        uint providerBalanceBefore = pair.cashAsset.balanceOf(provider);
        offerId = createProviderOffer(pair, callstrikeToUse, offerAmount);
        assertEq(pair.cashAsset.balanceOf(provider), providerBalanceBefore - offerAmount);

        // Create escrow offer
        escrowOfferId = createEscrowOffer(pair.durations[0]);
    }

    function executeEscrowLoan(uint offerId, uint escrowOfferId)
        internal
        returns (uint loanId, uint providerId, uint loanAmount)
    {
        uint expectedEscrowFee = pair.escrowNFT.interestFee(escrowOfferId, underlyingAmount);

        // Open escrow loan using base function
        (loanId, providerId, loanAmount) = openEscrowLoan(
            0.3e6, // minLoanAmount
            offerId,
            escrowOfferId,
            expectedEscrowFee
        );
    }

    function verifyEscrowLoan(
        uint loanId,
        uint providerId,
        uint loanAmount,
        uint escrowOfferId,
        uint feeRecipientBalanceBefore,
        uint expectedProtocolFee
    ) internal view {
        uint expectedEscrowFee = pair.escrowNFT.interestFee(escrowOfferId, underlyingAmount);

        uint userUnderlyingBefore = pair.underlying.balanceOf(user) + underlyingAmount + expectedEscrowFee;
        uint escrowSupplierUnderlyingBefore = pair.underlying.balanceOf(escrowSupplier);

        assertGt(loanAmount, 0);
        assertGt(loanId, 0);
        assertGt(providerId, 0);

        // Verify protocol fee
        assertEq(pair.cashAsset.balanceOf(feeRecipient) - feeRecipientBalanceBefore, expectedProtocolFee);

        // Verify loan state
        ILoansNFT.Loan memory loan = pair.loansContract.getLoan(loanId);
        assertTrue(loan.usesEscrow);
        assertEq(address(loan.escrowNFT), address(pair.escrowNFT));
        assertGt(loan.escrowId, 0);

        // Verify balances
        assertEq(pair.underlying.balanceOf(user), userUnderlyingBefore - underlyingAmount - expectedEscrowFee);
        assertEq(pair.underlying.balanceOf(escrowSupplier), escrowSupplierUnderlyingBefore);
    }

    function fundWallets() public {
        deal(address(cashAsset), user, bigCashAmount);
        deal(address(cashAsset), provider, bigCashAmount);
        deal(address(underlying), user, bigUnderlyingAmount);
        deal(address(underlying), provider, bigUnderlyingAmount);
        deal(address(underlying), escrowSupplier, bigUnderlyingAmount);
    }
}
