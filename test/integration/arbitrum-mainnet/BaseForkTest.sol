// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "forge-std/Test.sol";
import "./DeploymentLoader.sol";
import { ILoansNFT } from "../../../src/interfaces/ILoansNFT.sol";
import { IRolls } from "../../../src/interfaces/IRolls.sol";
import { ICollarTakerNFT } from "../../../src/interfaces/ICollarTakerNFT.sol";
import { ICollarProviderNFT } from "../../../src/interfaces/ICollarProviderNFT.sol";
import { PriceMovementHelper } from "../utils/PriceMovement.sol";
import { ArbitrumMainnetDeployer, BaseDeployer } from "../../../script/ArbitrumMainnetDeployer.sol";
import { DeploymentUtils } from "../../../script/utils/deployment-exporter.s.sol";

abstract contract LoansForkTestBase is Test, DeploymentLoader {
    function setUp() public virtual override {
        super.setUp();
    }

    function createProviderOffer(
        BaseDeployer.AssetPairContracts memory pair,
        uint callStrikePercent,
        uint amount,
        uint duration,
        uint ltv
    ) internal returns (uint offerId) {
        vm.startPrank(provider);
        pair.cashAsset.approve(address(pair.providerNFT), amount);
        offerId = pair.providerNFT.createOffer(callStrikePercent, amount, ltv, duration, 0);
        vm.stopPrank();
    }

    function openLoan(
        BaseDeployer.AssetPairContracts memory pair,
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
        BaseDeployer.AssetPairContracts memory pair,
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
        BaseDeployer.AssetPairContracts memory pair,
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
            currentPrice * 90 / 100, // minPrice 90% of current
            currentPrice * 110 / 100, // maxPrice 110% of current
            0,
            block.timestamp + 1 hours
        );
        vm.stopPrank();
    }

    function rollLoan(
        BaseDeployer.AssetPairContracts memory pair,
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

abstract contract BaseLoansForkTest is LoansForkTestBase {
    // constants for all pairs
    uint constant BIPS_BASE = 10_000;

    //escrow related constants
    uint constant interestAPR = 500; // 5% APR
    uint constant gracePeriod = 7 days;
    uint constant lateFeeAPR = 5000; // 50% APR

    // Protocol fee params
    uint constant feeAPR = 100; // 1% APR

    uint expectedOraclePrice;

    uint expectedNumPairs;

    // values to be set by pair
    address cashAsset;
    address underlying;
    uint expectedPairIndex;
    uint offerAmount;
    uint underlyingAmount;
    uint minLoanAmount;
    int rollFee;
    int rollDeltaFactor;
    uint bigCashAmount;
    uint bigUnderlyingAmount;

    // Swap amounts
    uint swapStepCashAmount;

    // Pool fee tier
    uint24 swapPoolFeeTier;

    // Protocol fee values
    address feeRecipient;

    // escrow related values
    address escrowSupplier;

    // whale address
    address whale;

    uint slippage;
    uint callstrikeToUse;
    uint duration;
    uint ltv;

    BaseDeployer.AssetPairContracts internal pair;

    function setUp() public virtual override {
        super.setUp();

        // create addresses
        whale = makeAddr("whale");
        feeRecipient = makeAddr("feeRecipient");
        escrowSupplier = makeAddr("escrowSupplier");
    }

    function setForkId(uint _forkId) public {
        forkId = _forkId;
        forkSet = true;
    }

    function createEscrowOffer(uint _duration) internal returns (uint offerId) {
        vm.startPrank(escrowSupplier);
        pair.underlying.approve(address(pair.escrowNFT), underlyingAmount);
        offerId = pair.escrowNFT.createOffer(
            underlyingAmount,
            _duration,
            interestAPR,
            gracePeriod,
            lateFeeAPR,
            0 // minEscrow
        );
        vm.stopPrank();
    }

    function openEscrowLoan(uint _minLoanAmount, uint providerOfferId, uint escrowOfferId, uint escrowFee)
        internal
        returns (uint loanId, uint providerId, uint loanAmount)
    {
        vm.startPrank(user);
        // Approve underlying amount plus escrow fee
        pair.underlying.approve(address(pair.loansContract), underlyingAmount + escrowFee);

        (loanId, providerId, loanAmount) = pair.loansContract.openEscrowLoan(
            underlyingAmount,
            _minLoanAmount,
            ILoansNFT.SwapParams(0, address(pair.loansContract.defaultSwapper()), ""),
            ILoansNFT.ProviderOffer(pair.providerNFT, providerOfferId),
            ILoansNFT.EscrowOffer(pair.escrowNFT, escrowOfferId),
            escrowFee
        );
        vm.stopPrank();
    }

    function createEscrowOffers() internal returns (uint offerId, uint escrowOfferId) {
        uint providerBalanceBefore = pair.cashAsset.balanceOf(provider);
        offerId = createProviderOffer(pair, callstrikeToUse, offerAmount, duration, ltv);
        assertEq(pair.cashAsset.balanceOf(provider), providerBalanceBefore - offerAmount);

        // Create escrow offer
        escrowOfferId = createEscrowOffer(duration);
    }

    function executeEscrowLoan(uint offerId, uint escrowOfferId)
        internal
        returns (uint loanId, uint providerId, uint loanAmount)
    {
        (uint expectedEscrowFee,,) = pair.escrowNFT.upfrontFees(escrowOfferId, underlyingAmount);

        // Open escrow loan using base function
        (loanId, providerId, loanAmount) = openEscrowLoan(
            minLoanAmount, // minLoanAmount
            offerId,
            escrowOfferId,
            expectedEscrowFee
        );
    }

    function verifyEscrowLoan(
        uint loanId,
        uint loanAmount,
        uint escrowOfferId,
        uint feeRecipientBalanceBefore,
        uint escrowSupplierUnderlyingBefore,
        uint expectedProtocolFee
    ) internal view {
        (uint expectedEscrowFee,,) = pair.escrowNFT.upfrontFees(escrowOfferId, underlyingAmount);

        uint userUnderlyingBefore = pair.underlying.balanceOf(user) + underlyingAmount + expectedEscrowFee;

        checkLoanAmount(loanAmount);

        // Verify protocol fee
        assertEq(pair.cashAsset.balanceOf(feeRecipient) - feeRecipientBalanceBefore, expectedProtocolFee);

        // Verify loan state
        ILoansNFT.Loan memory loan = pair.loansContract.getLoan(loanId);
        assertTrue(loan.usesEscrow);
        assertEq(address(loan.escrowNFT), address(pair.escrowNFT));
        assertGt(loan.escrowId, 0);

        // Verify balances
        assertEq(pair.underlying.balanceOf(user), userUnderlyingBefore - underlyingAmount - expectedEscrowFee);
        assertEq(escrowSupplierUnderlyingBefore - pair.underlying.balanceOf(escrowSupplier), underlyingAmount);
    }

    function checkLoanAmount(uint actualLoanAmount) internal view {
        uint oraclePrice = pair.takerNFT.currentOraclePrice();
        uint expectedCashFromSwap = pair.oracle.convertToQuoteAmount(underlyingAmount, oraclePrice);
        // Calculate minimum expected loan amount (expectedCash * LTV)
        // Apply slippage tolerance for swaps and rounding
        uint minExpectedLoan = expectedCashFromSwap * ltv * (BIPS_BASE - slippage) / (BIPS_BASE * BIPS_BASE);

        // Check actual loan amount is at least the minimum expected
        assertGe(actualLoanAmount, minExpectedLoan);
    }

    function fundWallets() public {
        deal(address(cashAsset), user, bigCashAmount);
        deal(address(cashAsset), provider, bigCashAmount);
        deal(address(underlying), user, bigUnderlyingAmount);
        deal(address(underlying), provider, bigUnderlyingAmount);
        deal(address(underlying), escrowSupplier, bigUnderlyingAmount);
    }

    // tests

    function testOraclePrice() public view {
        uint oraclePrice = pair.oracle.currentPrice();
        (uint a, uint b) = (oraclePrice, expectedOraclePrice);
        uint absDiffRatio = a > b ? (a - b) * BIPS_BASE / b : (b - a) * BIPS_BASE / a;
        // if bigger price is less than 2x the smaller price, we're still in the same range
        // otherwise, either the expected price needs to be updated (hopefully up), or the
        // oracle is misconfigured
        assertLt(absDiffRatio, BIPS_BASE, "prices differ by more than 2x");

        assertEq(oraclePrice, pair.takerNFT.currentOraclePrice());
    }

    function testOpenAndCloseLoan() public {
        uint providerBalanceBefore = pair.cashAsset.balanceOf(provider);
        uint offerId = createProviderOffer(pair, callstrikeToUse, offerAmount, duration, ltv);
        assertEq(pair.cashAsset.balanceOf(provider), providerBalanceBefore - offerAmount);
        uint feeRecipientBalanceBefore = pair.cashAsset.balanceOf(feeRecipient);

        (uint loanId,, uint loanAmount) = openLoan(
            pair,
            user,
            underlyingAmount,
            minLoanAmount, // minLoanAmount
            offerId
        );
        // Verify fee taken and sent to recipient
        uint expectedFee = getProviderProtocolFeeByLoanAmount(loanAmount);
        assertEq(pair.cashAsset.balanceOf(feeRecipient) - feeRecipientBalanceBefore, expectedFee);
        checkLoanAmount(loanAmount);
        skip(duration);
        ICollarTakerNFT.TakerPosition memory position = pair.takerNFT.getPosition(loanId);
        uint currentPrice = pair.oracle.currentPrice();
        (uint takerWithdrawal,) = pair.takerNFT.previewSettlement(position, currentPrice);

        closeAndCheckLoan(loanId, loanAmount, loanAmount + takerWithdrawal, currentPrice, 0);
    }

    function testOpenEscrowLoan() public {
        uint escrowSupplierUnderlyingBefore = pair.underlying.balanceOf(escrowSupplier);
        (uint offerId, uint escrowOfferId) = createEscrowOffers();
        uint feeRecipientBalanceBefore = pair.cashAsset.balanceOf(feeRecipient);
        (uint loanId,, uint loanAmount) = executeEscrowLoan(offerId, escrowOfferId);
        uint expectedProtocolFee = getProviderProtocolFeeByLoanAmount(loanAmount);
        verifyEscrowLoan(
            loanId,
            loanAmount,
            escrowOfferId,
            feeRecipientBalanceBefore,
            escrowSupplierUnderlyingBefore,
            expectedProtocolFee
        );
    }

    function testOpenAndCloseEscrowLoan() public {
        //  create provider and escrow offers
        (uint offerId, uint escrowOfferId) = createEscrowOffers();
        (uint loanId,, uint loanAmount) = executeEscrowLoan(offerId, escrowOfferId);
        ILoansNFT.Loan memory loanBefore = pair.loansContract.getLoan(loanId);

        uint escrowSupplierBefore = pair.underlying.balanceOf(escrowSupplier);
        uint userBefore = pair.underlying.balanceOf(user);
        (, uint interestFeeHeld, uint lateFeeHeld) =
            pair.escrowNFT.upfrontFees(escrowOfferId, underlyingAmount);

        // Skip to expiry
        skip(duration);

        ICollarTakerNFT.TakerPosition memory position = pair.takerNFT.getPosition(loanId);
        uint currentPrice = pair.oracle.currentPrice();
        (uint takerWithdrawal,) = pair.takerNFT.previewSettlement(position, currentPrice);

        uint underlyingOut =
            closeAndCheckLoan(loanId, loanAmount, loanAmount + takerWithdrawal, currentPrice, lateFeeHeld);

        // Check escrow position's withdrawable amount (underlying + interest)
        uint withdrawable = pair.escrowNFT.getEscrow(loanBefore.escrowId).withdrawable;
        assertEq(withdrawable, underlyingAmount + interestFeeHeld);

        // Execute withdrawal and verify balance change
        vm.startPrank(escrowSupplier);
        pair.escrowNFT.withdrawReleased(loanBefore.escrowId);
        vm.stopPrank();

        assertEq(
            pair.underlying.balanceOf(escrowSupplier) - escrowSupplierBefore,
            underlyingAmount + interestFeeHeld
        );
        assertEq(pair.underlying.balanceOf(user) - userBefore, underlyingOut);
    }

    function testRollEscrowLoanBetweenSuppliers() public {
        // Create first provider and escrow offers
        (uint offerId1, uint escrowOfferId1) = createEscrowOffers();
        (uint escrowFees1,,) = pair.escrowNFT.upfrontFees(escrowOfferId1, underlyingAmount);

        uint userUnderlyingBefore = pair.underlying.balanceOf(user);
        (uint loanId, uint providerId,) = executeEscrowLoan(offerId1, escrowOfferId1);
        ILoansNFT.Loan memory loan = pair.loansContract.getLoan(loanId);
        // User has paid underlyingAmount + escrowFees1 at this point
        assertEq(userUnderlyingBefore - pair.underlying.balanceOf(user), underlyingAmount + escrowFees1);

        uint escrowSupplier1Before = pair.underlying.balanceOf(escrowSupplier);

        // Create second escrow supplier
        address escrowSupplier2 = makeAddr("escrowSupplier2");
        deal(address(underlying), escrowSupplier2, bigUnderlyingAmount);

        // Skip half the duration to test partial fees
        skip(duration / 2);

        // Get exact refund amount from contract
        (uint withdrawal, uint toLoans,) = pair.escrowNFT.previewRelease(loan.escrowId, 0);

        // Create second escrow supplier's offer
        vm.startPrank(escrowSupplier2);
        pair.underlying.approve(address(pair.escrowNFT), underlyingAmount);
        uint escrowOfferId2 = pair.escrowNFT.createOffer(
            underlyingAmount,
            duration,
            interestAPR,
            gracePeriod,
            lateFeeAPR,
            0 // minEscrow
        );
        vm.stopPrank();

        // Create roll offer using existing provider position
        uint rollOfferId = createRollOffer(pair, provider, loanId, providerId, rollFee, rollDeltaFactor);

        (uint newEscrowFees,,) = pair.escrowNFT.upfrontFees(escrowOfferId2, underlyingAmount);
        uint userUnderlyingBeforeRoll = pair.underlying.balanceOf(user);

        vm.startPrank(user);
        IRolls.PreviewResults memory results =
            pair.rollsContract.previewRoll(rollOfferId, pair.takerNFT.currentOraclePrice());
        // make sure preview roll fee is within 10% of actual roll fee
        assertApproxEqAbs(-results.toTaker, rollFee, uint(rollFee) * 1000 / 10_000);
        if (results.toTaker < 0) {
            pair.cashAsset.approve(address(pair.loansContract), uint(-results.toTaker));
        }
        pair.underlying.approve(address(pair.loansContract), newEscrowFees);
        (uint newLoanId, uint newLoanAmount,) = pair.loansContract.rollLoan(
            loanId,
            ILoansNFT.RollOffer(pair.rollsContract, rollOfferId),
            -1000e6,
            escrowOfferId2,
            newEscrowFees
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
        assertEq(userUnderlyingBeforeRoll - pair.underlying.balanceOf(user) + toLoans, newEscrowFees);

        // Skip to end of new loan term
        skip(duration);

        // Track second supplier balance before closing
        uint escrowSupplier2Before = pair.underlying.balanceOf(escrowSupplier2);

        uint escrowRefund;
        {
            uint currentPrice = pair.oracle.currentPrice();
            (uint takerWithdrawal,) =
                pair.takerNFT.previewSettlement(pair.takerNFT.getPosition(newLoanId), currentPrice);
            (escrowRefund,,,) = pair.escrowNFT.feesRefunds(pair.loansContract.getLoan(newLoanId).escrowId);

            closeAndCheckLoan(
                newLoanId, newLoanAmount, newLoanAmount + takerWithdrawal, currentPrice, escrowRefund
            );
        }

        // Execute withdrawal for second supplier
        vm.startPrank(escrowSupplier2);
        pair.escrowNFT.withdrawReleased(newLoanId);
        vm.stopPrank();

        // Verify second supplier got full amount - refund
        assertEq(
            pair.underlying.balanceOf(escrowSupplier2) - escrowSupplier2Before,
            underlyingAmount + newEscrowFees - escrowRefund
        );
    }

    function testRollLoan() public {
        uint offerId = createProviderOffer(pair, callstrikeToUse, offerAmount, duration, ltv);
        (uint loanId, uint providerId, uint initialLoanAmount) = openLoan(
            pair,
            user,
            underlyingAmount,
            minLoanAmount, // minLoanAmount
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

        uint offerId = createProviderOffer(pair, callstrikeToUse, offerAmount, duration, ltv);

        (uint loanId, uint providerId, uint initialLoanAmount) =
            openLoan(pair, user, underlyingAmount, minLoanAmount, offerId);
        uint initialFee = getProviderProtocolFeeByLoanAmount(initialLoanAmount);
        // Verify fee taken and sent to recipient
        assertEq(pair.cashAsset.balanceOf(feeRecipient) - feeRecipientBalanceBefore, initialFee);

        // Advance time
        skip(duration - 20);

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
        skip(duration);

        ICollarTakerNFT.TakerPosition memory position = pair.takerNFT.getPosition(newLoanId);
        uint currentPrice = pair.oracle.currentPrice();
        (uint takerWithdrawal,) = pair.takerNFT.previewSettlement(position, currentPrice);

        closeAndCheckLoan(newLoanId, newLoanAmount, newLoanAmount + takerWithdrawal, currentPrice, 0);
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
        uint swapOut = loanAmount * BIPS_BASE / ltv;
        uint initProviderLocked = swapOut * (callstrikeToUse - BIPS_BASE) / BIPS_BASE;
        (protocolFee,) = pair.providerNFT.protocolFee(initProviderLocked, duration);
        assertGt(protocolFee, 0);
    }

    function closeAndCheckLoan(
        uint loanId,
        uint loanAmount,
        uint totalAmountToSwap,
        uint currentPrice,
        uint escrowRefund
    ) internal returns (uint underlyingOut) {
        // Track balances before closing
        uint userCashBefore = pair.cashAsset.balanceOf(user);
        uint userUnderlyingBefore = pair.underlying.balanceOf(user);
        // Convert cash amount to expected underlying amount using oracle's conversion
        uint expectedFromSwap = pair.oracle.convertToBaseAmount(totalAmountToSwap, currentPrice);

        uint minUnderlyingOut = (expectedFromSwap * (BIPS_BASE - slippage) / BIPS_BASE);
        underlyingOut = closeLoan(pair, user, loanId, minUnderlyingOut);

        assertApproxEqAbs(
            underlyingOut, expectedFromSwap + escrowRefund, expectedFromSwap * slippage / BIPS_BASE
        );
        // Verify balance changes
        assertEq(userCashBefore - pair.cashAsset.balanceOf(user), loanAmount);
        assertEq(pair.underlying.balanceOf(user) - userUnderlyingBefore, underlyingOut);
    }

    function testCloseEscrowLoanAfterGracePeriod() public {
        //  create provider and escrow offers
        (uint offerId, uint escrowOfferId) = createEscrowOffers();
        (uint loanId,, uint loanAmount) = executeEscrowLoan(offerId, escrowOfferId);

        ILoansNFT.Loan memory loan = pair.loansContract.getLoan(loanId);
        uint escrowSupplierBefore = pair.underlying.balanceOf(escrowSupplier);
        uint userBefore = pair.underlying.balanceOf(user);
        (, uint interestFeeHeld, uint lateFeeHeld) =
            pair.escrowNFT.upfrontFees(escrowOfferId, underlyingAmount);

        // Skip past expiry
        skip(duration);
        uint expiryPrice = pair.oracle.currentPrice();
        // Get expiry price from oracle
        ICollarTakerNFT.TakerPosition memory position = pair.takerNFT.getPosition(loanId);
        (uint takerWithdrawal,) = pair.takerNFT.previewSettlement(position, expiryPrice);
        // bot settles the position
        pair.takerNFT.settlePairedPosition(loanId);

        // skip past grace period
        skip(gracePeriod + 1);

        uint totalAmountToSwap = loanAmount + takerWithdrawal;
        uint underlyingOut = closeAndCheckLoan(loanId, loanAmount, totalAmountToSwap, expiryPrice, 0);

        // Check escrow position's withdrawable (underlying + interest + late fee)
        uint withdrawable = pair.escrowNFT.getEscrow(loan.escrowId).withdrawable;
        // interest and late fee goes to escrow owner
        assertEq(withdrawable, underlyingAmount + interestFeeHeld + lateFeeHeld);

        // Execute withdrawal and verify balance
        vm.startPrank(escrowSupplier);
        pair.escrowNFT.withdrawReleased(loan.escrowId);
        vm.stopPrank();

        assertEq(
            pair.underlying.balanceOf(escrowSupplier) - escrowSupplierBefore,
            underlyingAmount + interestFeeHeld + lateFeeHeld
        );
        assertEq(pair.underlying.balanceOf(user) - userBefore, underlyingOut);
    }

    function testSeizeEscrowAndUnwrapLoan() public {
        //  create provider and escrow offers
        (uint offerId, uint escrowOfferId) = createEscrowOffers();
        (uint loanId,,) = executeEscrowLoan(offerId, escrowOfferId);

        ILoansNFT.Loan memory loan = pair.loansContract.getLoan(loanId);
        uint escrowSupplierBefore = pair.underlying.balanceOf(escrowSupplier);
        uint userBeforeUnderlying = pair.underlying.balanceOf(user);
        uint userBeforeCash = pair.cashAsset.balanceOf(user);
        (, uint interestFeeHeld, uint lateFeeHeld) =
            pair.escrowNFT.upfrontFees(escrowOfferId, underlyingAmount);

        // Skip past expiry
        skip(duration);
        uint expiryPrice = pair.oracle.currentPrice();
        // Get expiry price from oracle
        ICollarTakerNFT.TakerPosition memory position = pair.takerNFT.getPosition(loanId);
        (uint takerWithdrawal,) = pair.takerNFT.previewSettlement(position, expiryPrice);
        // bot settles the position
        pair.takerNFT.settlePairedPosition(loanId);

        // skip past grace period
        skip(gracePeriod + 1);

        // seize and withdraw from supplier
        vm.startPrank(escrowSupplier);
        pair.escrowNFT.seizeEscrow(loan.escrowId);
        assertEq(
            pair.underlying.balanceOf(escrowSupplier) - escrowSupplierBefore,
            underlyingAmount + interestFeeHeld + lateFeeHeld
        );

        // cancel and withdraw from user
        vm.startPrank(user);
        pair.loansContract.unwrapAndCancelLoan(loanId);
        pair.takerNFT.withdrawFromSettled(loanId);
        assertEq(pair.underlying.balanceOf(user) - userBeforeUnderlying, 0);
        assertEq(pair.cashAsset.balanceOf(user) - userBeforeCash, takerWithdrawal);
    }

    function testCloseEscrowLoanWithPartialLateFees() public {
        //  create provider and escrow offers
        (uint offerId, uint escrowOfferId) = createEscrowOffers();
        (uint loanId,, uint loanAmount) = executeEscrowLoan(offerId, escrowOfferId);

        ILoansNFT.Loan memory loanBefore = pair.loansContract.getLoan(loanId);
        uint escrowSupplierBefore = pair.underlying.balanceOf(escrowSupplier);
        uint userBefore = pair.underlying.balanceOf(user);
        (, uint interestFeeHeld, uint lateFeeHeld) =
            pair.escrowNFT.upfrontFees(escrowOfferId, underlyingAmount);

        // Skip past expiry but only halfway through grace period
        skip(duration);
        uint expiryPrice = pair.oracle.currentPrice();

        // bot settles the position
        pair.takerNFT.settlePairedPosition(loanId);

        skip(gracePeriod / 2);

        // Calculate expected late fee refund
        (,, uint lateFeeRefund,) = pair.escrowNFT.feesRefunds(loanBefore.escrowId);
        assertGt(lateFeeHeld, 0);
        assertEq(lateFeeRefund, lateFeeHeld / 2);
        ICollarTakerNFT.TakerPosition memory position = pair.takerNFT.getPosition(loanId);
        uint takerWithdrawal = position.withdrawable;

        uint underlyingOut =
            closeAndCheckLoan(loanId, loanAmount, loanAmount + takerWithdrawal, expiryPrice, lateFeeHeld);

        // Check escrow position's withdrawable (underlying + interest + partial late fee)
        uint withdrawable = pair.escrowNFT.getEscrow(loanBefore.escrowId).withdrawable;
        uint expectedWithdrawal = underlyingAmount + interestFeeHeld + lateFeeHeld - lateFeeRefund;
        assertEq(withdrawable, expectedWithdrawal);

        // Execute withdrawal and verify balance
        vm.startPrank(escrowSupplier);
        pair.escrowNFT.withdrawReleased(loanBefore.escrowId);
        vm.stopPrank();

        assertEq(pair.underlying.balanceOf(escrowSupplier) - escrowSupplierBefore, expectedWithdrawal);
        assertEq(pair.underlying.balanceOf(user) - userBefore, underlyingOut);
    }
}
