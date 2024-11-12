// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "forge-std/Test.sol";
import "./DeploymentLoader.sol";
import { ILoansNFT } from "../../../src/interfaces/ILoansNFT.sol";
import { IRolls } from "../../../src/interfaces/IRolls.sol";
import { ICollarTakerNFT } from "../../../src/interfaces/ICollarTakerNFT.sol";
import { ICollarProviderNFT } from "../../../src/interfaces/ICollarProviderNFT.sol";
import { PriceMovementHelper } from "../utils/PriceMovement.sol";
import { ArbitrumMainnetDeployer } from "../../../script/arbitrum-mainnet/deployer.sol";
import { DeploymentUtils } from "../../../script/utils/deployment-exporter.s.sol";

abstract contract LoansTestBase is Test, DeploymentLoader {
    function setUp() public virtual override {
        super.setUp();
    }

    function createProviderOffer(
        DeploymentHelper.AssetPairContracts memory pair,
        uint callStrikePercent,
        uint amount,
        uint duration
    ) internal returns (uint offerId) {
        vm.startPrank(provider);
        pair.cashAsset.approve(address(pair.providerNFT), amount);
        offerId = pair.providerNFT.createOffer(callStrikePercent, amount, pair.ltvs[0], duration, 0);
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
            currentPrice * 90 / 100, // minPrice 90% of current
            currentPrice * 110 / 100, // maxPrice 110% of current
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

abstract contract BaseLoansForkTest is LoansTestBase {
    // constants for all pairs
    uint constant BIPS_BASE = 10_000;

    //escrow related constants
    uint constant interestAPR = 500; // 5% APR
    uint constant maxGracePeriod = 7 days;
    uint constant lateFeeAPR = 10_000; // 100% APR

    // Protocol fee params
    uint constant feeAPR = 100; // 1% APR

    // values to be set by pair
    address cashAsset;
    address underlying;
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
    uint durationPriceMovement;

    DeploymentHelper.AssetPairContracts internal pair;

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

    function testOpenAndCloseLoan() public {
        uint providerBalanceBefore = pair.cashAsset.balanceOf(provider);
        uint offerId = createProviderOffer(pair, callstrikeToUse, offerAmount, duration);
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
        (uint takerWithdrawal,) = pair.takerNFT.previewSettlement(position, pair.oracle.currentPrice());

        closeAndCheckLoan(loanId, loanAmount, loanAmount + takerWithdrawal, 0);
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
        uint interestFee = pair.escrowNFT.interestFee(escrowOfferId, underlyingAmount);

        // Skip to expiry
        skip(duration);

        ICollarTakerNFT.TakerPosition memory position = pair.takerNFT.getPosition(loanId);
        (uint takerWithdrawal,) = pair.takerNFT.previewSettlement(position, pair.oracle.currentPrice());

        closeAndCheckLoan(loanId, loanAmount, loanAmount + takerWithdrawal, 0);

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
        skip(duration + maxGracePeriod + 1);

        // Calculate expected late fee
        (, uint lateFee) = pair.escrowNFT.currentOwed(loanBefore.escrowId);
        assertGt(lateFee, 0);
        // Get expiry price from oracle
        ICollarTakerNFT.TakerPosition memory position = pair.takerNFT.getPosition(loanId);
        (uint expiryPrice,) = pair.oracle.pastPriceWithFallback(uint32(position.expiration));
        (uint takerWithdrawal,) = pair.takerNFT.previewSettlement(position, expiryPrice);
        uint totalAmountToSwap = loanAmount + takerWithdrawal;

        closeAndCheckLoan(loanId, loanAmount, totalAmountToSwap, lateFee);

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
        skip(duration + maxGracePeriod / 2);

        // Calculate expected partial late fee
        (, uint lateFee) = pair.escrowNFT.currentOwed(loanBefore.escrowId);
        assertGt(lateFee, 0);
        assertLt(lateFee, underlyingAmount * lateFeeAPR * maxGracePeriod / (BIPS_BASE * 365 days));
        ICollarTakerNFT.TakerPosition memory position = pair.takerNFT.getPosition(loanId);
        (uint takerWithdrawal,) = pair.takerNFT.previewSettlement(position, pair.oracle.currentPrice());

        closeAndCheckLoan(loanId, loanAmount, loanAmount + takerWithdrawal, lateFee);

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
        (uint loanId, uint providerId,) = executeEscrowLoan(offerId1, escrowOfferId1);
        ILoansNFT.Loan memory loan = pair.loansContract.getLoan(loanId);
        // User has paid underlyingAmount + interestFee1 at this point
        assertEq(userUnderlyingBefore - pair.underlying.balanceOf(user), underlyingAmount + interestFee1);

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
        IRolls.PreviewResults memory results =
            pair.rollsContract.previewRoll(rollOfferId, pair.takerNFT.currentOraclePrice());
        // make sure preview roll fee is within 10% of actual roll fee
        assertApproxEqAbs(-results.toTaker, rollFee, uint(rollFee) * 1000 / 10_000);
        if (results.toTaker < 0) {
            pair.cashAsset.approve(address(pair.loansContract), uint(-results.toTaker));
        }
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
        skip(duration);

        // Track second supplier balance before closing
        uint escrowSupplier2Before = pair.underlying.balanceOf(escrowSupplier2);

        (uint takerWithdrawal,) =
            pair.takerNFT.previewSettlement(pair.takerNFT.getPosition(newLoanId), pair.oracle.currentPrice());

        closeAndCheckLoan(newLoanId, newLoanAmount, newLoanAmount + takerWithdrawal, 0);

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
        uint offerId = createProviderOffer(pair, callstrikeToUse, offerAmount, duration);
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

        uint offerId = createProviderOffer(pair, callstrikeToUse, offerAmount, duration);

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
        (uint takerWithdrawal,) = pair.takerNFT.previewSettlement(position, pair.oracle.currentPrice());

        closeAndCheckLoan(newLoanId, newLoanAmount, newLoanAmount + takerWithdrawal, 0);
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
        (protocolFee,) = pair.providerNFT.protocolFee(initProviderLocked, duration);
        assertGt(protocolFee, 0);
    }

    function closeAndCheckLoan(uint loanId, uint loanAmount, uint totalAmountToSwap, uint lateFee) internal {
        // Track balances before closing
        uint userCashBefore = pair.cashAsset.balanceOf(user);
        uint userUnderlyingBefore = pair.underlying.balanceOf(user);
        uint expiration = pair.takerNFT.getPosition(loanId).expiration;
        // Get current price from oracle
        (uint currentPrice,) = pair.oracle.pastPriceWithFallback(uint32(expiration));
        // Convert cash amount to expected underlying amount using oracle's conversion
        uint expectedUnderlying = (pair.oracle.convertToBaseAmount(totalAmountToSwap, currentPrice) - lateFee);

        uint minUnderlyingOutWithSlippage = (expectedUnderlying * (BIPS_BASE - slippage) / BIPS_BASE);
        uint underlyingOut = closeLoan(pair, user, loanId, minUnderlyingOutWithSlippage);

        assertApproxEqAbs(underlyingOut, expectedUnderlying, expectedUnderlying * slippage / BIPS_BASE);
        // Verify balance changes
        assertEq(userCashBefore - pair.cashAsset.balanceOf(user), loanAmount);
        assertEq(pair.underlying.balanceOf(user) - userUnderlyingBefore, underlyingOut);
    }

    // price movement settlement tests

    function testSettlementPriceAboveCallStrike() public {
        // Create provider offer & open loan
        uint offerId = createProviderOffer(pair, callstrikeToUse, offerAmount, durationPriceMovement);
        (uint loanId,, uint loanAmount) = openLoan(pair, user, underlyingAmount, minLoanAmount, offerId);

        ICollarTakerNFT.TakerPosition memory position = pair.takerNFT.getPosition(loanId);
        
        skip(durationPriceMovement / 2);

        // Move price above call strike using lib
        PriceMovementHelper.moveToTargetPrice(
            vm,
            address(pair.swapperUniV3.uniV3SwapRouter()),
            whale,
            pair.cashAsset,
            pair.underlying,
            pair.oracle,
            (pair.oracle.currentPrice() * position.callStrikePercent / BIPS_BASE),
            swapStepCashAmount,
            swapPoolFeeTier
        );

        // moving price takes time, but we need settlement price to be moved
        skip(durationPriceMovement / 2);

        (uint expectedTakerWithdrawal,) =
            pair.takerNFT.previewSettlement(position, pair.oracle.currentPrice());

        // Total cash = taker withdrawal + loan repayment
        // Convert expected total cash to underlying at current price
        uint expectedUnderlyingOut =
            pair.oracle.convertToBaseAmount(expectedTakerWithdrawal + loanAmount, pair.oracle.currentPrice());

        uint userUnderlyingBefore = pair.underlying.balanceOf(user);

        // Close loan and settle
        closeAndCheckLoan(loanId, loanAmount, loanAmount + expectedTakerWithdrawal, 0);

        // Check provider's withdrawable amount
        uint providerWithdrawable = position.providerNFT.getPosition(position.providerId).withdrawable;
        assertEq(providerWithdrawable, 0); // everything to user

        // Check user's underlying balance change against calculated expected amount
        assertApproxEqAbs(
            pair.underlying.balanceOf(user) - userUnderlyingBefore,
            expectedUnderlyingOut,
            expectedUnderlyingOut * slippage / BIPS_BASE // within slippage% of expected
        );
    }

    function testSettlementPriceBelowPutStrike() public {
        // Create provider offer & open loan
        uint offerId = createProviderOffer(pair, callstrikeToUse, offerAmount, durationPriceMovement);
        (uint loanId,, uint loanAmount) = openLoan(pair, user, underlyingAmount, minLoanAmount, offerId);

        ICollarTakerNFT.TakerPosition memory position = pair.takerNFT.getPosition(loanId);

        skip(durationPriceMovement / 2);

        // Move price below put strike
        PriceMovementHelper.moveToTargetPrice(
            vm,
            address(pair.swapperUniV3.uniV3SwapRouter()),
            whale,
            pair.cashAsset,
            pair.underlying,
            pair.oracle,
            (pair.oracle.currentPrice() * position.putStrikePercent / BIPS_BASE),
            swapStepCashAmount,
            swapPoolFeeTier
        );

        // moving price takes time, but we need settlement price to be moved
        skip(durationPriceMovement / 2);

        uint userUnderlyingBefore = pair.underlying.balanceOf(user);
        // Close loan
        closeAndCheckLoan(loanId, loanAmount, loanAmount, 0);
        uint expectedUnderlying = pair.oracle.convertToBaseAmount(loanAmount, pair.oracle.currentPrice());
        assertApproxEqAbs(
            pair.underlying.balanceOf(user) - userUnderlyingBefore,
            expectedUnderlying,
            expectedUnderlying * slippage / BIPS_BASE
        );
        // check provider gets all value
        uint providerWithdrawable = position.providerNFT.getPosition(position.providerId).withdrawable;
        uint expectedProviderWithdrawable = position.providerLocked + position.takerLocked;
        assertEq(providerWithdrawable, expectedProviderWithdrawable);
    }

    function testSettlementPriceUpBetweenStrikes() public {
        // Create provider offer & open loan with longer duration
        uint offerId = createProviderOffer(pair, callstrikeToUse, offerAmount, durationPriceMovement);
        (uint loanId,, uint loanAmount) = openLoan(pair, user, underlyingAmount, minLoanAmount, offerId);

        ICollarTakerNFT.TakerPosition memory position = pair.takerNFT.getPosition(loanId);

        skip(durationPriceMovement / 2);

        // Move price half way to call strike using lib
        uint halfDeviation = (BIPS_BASE + position.callStrikePercent) / 2;
        PriceMovementHelper.moveToTargetPrice(
            vm,
            address(pair.swapperUniV3.uniV3SwapRouter()),
            whale,
            pair.cashAsset,
            pair.underlying,
            pair.oracle,
            (pair.oracle.currentPrice() * halfDeviation / BIPS_BASE),
            swapStepCashAmount,
            swapPoolFeeTier
        );

        // moving price takes time, but we need settlement price to be moved
        skip(durationPriceMovement / 2);

        // Calculate expected settlement amounts
        uint currentPrice = pair.oracle.currentPrice();
        (uint expectedTakerWithdrawal, int expectedProviderDelta) =
            pair.takerNFT.previewSettlement(position, currentPrice);

        uint userUnderlyingBefore = pair.underlying.balanceOf(user);

        // Close loan with total cash needed
        closeAndCheckLoan(loanId, loanAmount, loanAmount + expectedTakerWithdrawal, 0);

        // User should get underlying equivalent to loanAmount + their settlement gains
        uint expectedUnderlying =
            pair.oracle.convertToBaseAmount(loanAmount + expectedTakerWithdrawal, currentPrice);
        assertApproxEqAbs(
            pair.underlying.balanceOf(user) - userUnderlyingBefore,
            expectedUnderlying,
            expectedUnderlying * slippage / BIPS_BASE
        );

        // Provider should get their locked amount adjusted by settlement delta
        uint providerWithdrawable = position.providerNFT.getPosition(position.providerId).withdrawable;
        uint expectedProviderWithdrawable = uint(int(position.providerLocked) + expectedProviderDelta);
        assertEq(providerWithdrawable, expectedProviderWithdrawable);
    }

    function createEscrowOffer(uint _duration) internal returns (uint offerId) {
        vm.startPrank(escrowSupplier);
        pair.underlying.approve(address(pair.escrowNFT), underlyingAmount);
        offerId = pair.escrowNFT.createOffer(
            underlyingAmount,
            _duration,
            interestAPR,
            maxGracePeriod,
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
        offerId = createProviderOffer(pair, callstrikeToUse, offerAmount, duration);
        assertEq(pair.cashAsset.balanceOf(provider), providerBalanceBefore - offerAmount);

        // Create escrow offer
        escrowOfferId = createEscrowOffer(duration);
    }

    function executeEscrowLoan(uint offerId, uint escrowOfferId)
        internal
        returns (uint loanId, uint providerId, uint loanAmount)
    {
        uint expectedEscrowFee = pair.escrowNFT.interestFee(escrowOfferId, underlyingAmount);

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
        uint expectedEscrowFee = pair.escrowNFT.interestFee(escrowOfferId, underlyingAmount);

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
        uint expectedCashFromSwap = underlyingAmount * oraclePrice / pair.oracle.baseUnitAmount();
        // Calculate minimum expected loan amount (expectedCash * LTV)
        // Apply slippage tolerance for swaps and rounding
        uint minExpectedLoan =
            expectedCashFromSwap * pair.ltvs[0] * (BIPS_BASE - slippage) / (BIPS_BASE * BIPS_BASE);

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
}
