// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "forge-std/Test.sol";
import "./DeploymentLoader.sol";
import { ILoansNFT } from "../../../src/interfaces/ILoansNFT.sol";
import { IRolls } from "../../../src/interfaces/IRolls.sol";
import { ICollarTakerNFT } from "../../../src/interfaces/ICollarTakerNFT.sol";
import { ICollarProviderNFT } from "../../../src/interfaces/ICollarProviderNFT.sol";
import { ArbitrumMainnetDeployer } from "../../../script/arbitrum-mainnet/deployer.sol";
import { DeploymentUtils } from "../../../script/utils/deployment-exporter.s.sol";
import { PriceManipulationLib } from "../utils/PriceManipulation.sol";

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
    address cashAsset = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8; // USDC
    address underlying = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1; // WETH
    uint24 POOL_FEE_TIER = 500;
    uint callstrikeToUse = 12_000;
    uint offerAmount = 100_000e6;
    uint underlyingAmount = 1 ether;
    int rollFee = 100e6;
    int rollDeltaFactor = 10_000;
    uint bigCashAmount = 1_000_000e6;
    uint bigUnderlyingAmount = 1000 ether;
    uint slippage = 1; // 1%
    uint constant BIPS_BASE = 10_000;
    // Protocol fee params
    address feeRecipient;
    uint feeAPR = 100; // 1% APR

    // whale address
    address whale;

    DeploymentHelper.AssetPairContracts internal pair;

    function setUp() public virtual override {
        super.setUp();
        pair = getPairByAssets(address(cashAsset), address(underlying));
        fundWallets();
        require(address(pair.loansContract) != address(0), "Loans contract not deployed");

        // create whale address
        whale = makeAddr("whale");
        // Fund whale for price manipulation
        deal(address(pair.cashAsset), whale, 100 * bigCashAmount);
        deal(address(pair.underlying), whale, 100 * bigUnderlyingAmount);

        // Setup protocol fee
        feeRecipient = makeAddr("feeRecipient");
        vm.startPrank(owner);
        configHub.setProtocolFeeParams(feeAPR, feeRecipient);
        vm.stopPrank();
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

        uint expectedFee = getProviderProtocolFeeByUnderlying();
        uint minLoanAmount = 0.3e6; // arbitrary
        (uint loanId,, uint loanAmount) = openLoan(pair, user, underlyingAmount, minLoanAmount, offerId);
        // Verify fee taken and sent to recipient
        assertEq(pair.cashAsset.balanceOf(feeRecipient) - feeRecipientBalanceBefore, expectedFee);
        /// @dev offerAmount change (offerAmount-providerLocked-fee) could be checked
        /// but would require a lot of precision due to slippage from swap on final providerLocked value
        assertGt(loanAmount, 0);
        skip(pair.durations[0]);
        closeAndCheckLoan(loanId, loanAmount);
    }

    function testRollLoan() public {
        uint offerId = createProviderOffer(pair, callstrikeToUse, offerAmount);
        uint minLoanAmount = 0.3e6;
        (uint loanId, uint providerId, uint initialLoanAmount) =
            openLoan(pair, user, underlyingAmount, minLoanAmount, offerId);

        uint rollOfferId = createRollOffer(pair, provider, loanId, providerId, rollFee, rollDeltaFactor);

        // Calculate and verify protocol fee based on new position's provider locked amount
        uint newPositionPrice = pair.takerNFT.currentOraclePrice();
        IRolls.PreviewResults memory expectedResults =
            pair.rollsContract.previewRoll(rollOfferId, newPositionPrice);
        assertGt(expectedResults.protocolFee, 0);
        assertGt(expectedResults.toProvider, 0);

        uint providerBalanceBefore = pair.cashAsset.balanceOf(provider);
        uint feeRecipientBalanceBefore = pair.cashAsset.balanceOf(feeRecipient);
        int minToUser = -1000e6; // Allow up to 1000 tokens to be paid by the user
        (uint newLoanId, uint newLoanAmount, int transferAmount) =
            rollLoan(pair, user, loanId, rollOfferId, minToUser);

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
        uint initialFee = getProviderProtocolFeeByUnderlying();

        (uint loanId, uint providerId, uint initialLoanAmount) =
            openLoan(pair, user, underlyingAmount, 0.3e6, offerId);

        // Verify fee taken and sent to recipient
        assertEq(pair.cashAsset.balanceOf(feeRecipient) - feeRecipientBalanceBefore, initialFee);

        // Advance time
        vm.warp(block.timestamp + pair.durations[0] - 20);

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
        vm.warp(block.timestamp + pair.durations[0]);

        closeAndCheckLoan(newLoanId, newLoanAmount);
        assertGt(initialLoanAmount, 0);
        assertGe(int(newLoanAmount), int(initialLoanAmount) + transferAmount);

        // Verify total protocol fees collected
        assertEq(
            pair.cashAsset.balanceOf(feeRecipient) - feeRecipientBalanceBefore,
            initialFee + expectedResults.protocolFee
        );
    }

    function getProviderProtocolFeeByUnderlying() internal view returns (uint protocolFee) {
        // Calculate protocol fee based on post-swap provider locked amount
        uint swapOut = underlyingAmount * pair.takerNFT.currentOraclePrice() / pair.oracle.baseUnitAmount();
        uint initProviderLocked = swapOut * (callstrikeToUse - BIPS_BASE) / BIPS_BASE;
        (protocolFee,) = pair.providerNFT.protocolFee(initProviderLocked, pair.durations[0]);
        assertGt(protocolFee, 0);
    }

    function closeAndCheckLoan(uint loanId, uint loanAmount) internal {
        // Track balances before closing
        uint userCashBefore = pair.cashAsset.balanceOf(user);
        uint userUnderlyingBefore = pair.underlying.balanceOf(user);
        uint expiration = pair.takerNFT.getPosition(loanId).expiration;
        // Scale expected underlying based on current oracle price vs start price
        // Get current price from oracle
        uint currentPrice = pair.oracle.pastPrice(uint32(expiration));
        // Convert cash amount to expected underlying amount using oracle's conversion
        uint expectedUnderlying = pair.oracle.convertToBaseAmount(loanAmount, currentPrice);

        uint minUnderlyingOutWithSlippage = expectedUnderlying * (100 - slippage) / 100;
        console.log("Expected underlying out: %d", expectedUnderlying);
        console.log("currentPrice %d", currentPrice);
        console.log("minUnderlyingOutWithSlippage %d", minUnderlyingOutWithSlippage);
        uint underlyingOut = closeLoan(pair, user, loanId, minUnderlyingOutWithSlippage);
        assertGe(underlyingOut, minUnderlyingOutWithSlippage);
        // Verify balance changes
        assertEq(userCashBefore - pair.cashAsset.balanceOf(user), loanAmount);
        assertEq(pair.underlying.balanceOf(user) - userUnderlyingBefore, underlyingOut);
    }

    // price movement settlement tests

    function testSettlementPriceAboveCallStrike() public {
        // Create provider offer & open loan
        uint offerId = createProviderOffer(pair, callstrikeToUse, offerAmount);
        (uint loanId,, uint loanAmount) = openLoan(pair, user, underlyingAmount, 0.3e6, offerId);

        ICollarTakerNFT.TakerPosition memory position = pair.takerNFT.getPosition(loanId);
        // Move price above call strike using lib
        PriceManipulationLib.movePriceUpPastCallStrike(
            vm,
            address(pair.swapperUniV3.uniV3SwapRouter()),
            whale,
            pair.cashAsset,
            pair.underlying,
            pair.oracle,
            position.callStrikePercent,
            POOL_FEE_TIER
        );
        // Preview settlement at above call strike

        // Skip to expiry
        skip(pair.durations[0]);
        uint expiration = position.providerNFT.expiration(position.providerId);
        (uint expectedTakerWithdrawal,) =
            pair.takerNFT.previewSettlement(position, pair.oracle.pastPrice(uint32(expiration)));

        // Total cash = taker withdrawal + loan repayment
        // Convert expected total cash to underlying at current price
        uint expectedUnderlyingOut = pair.oracle.convertToBaseAmount(
            expectedTakerWithdrawal + loanAmount, pair.oracle.pastPrice(uint32(expiration))
        );

        // Record user's underlying balance before close
        uint userUnderlyingBefore = pair.underlying.balanceOf(user);

        // Close loan and settle
        closeAndCheckLoan(loanId, loanAmount + expectedTakerWithdrawal);

        // Check provider's withdrawable amount
        uint providerWithdrawable = position.providerNFT.getPosition(position.providerId).withdrawable;
        assertEq(providerWithdrawable, 0, "provider withdrawable should be 0"); // everything to user

        // Check user's underlying balance change against calculated expected amount
        assertEq(
            pair.underlying.balanceOf(user) - userUnderlyingBefore,
            expectedUnderlyingOut,
            "Underlying out should match preview"
        );
    }

    function fundWallets() public {
        deal(address(cashAsset), user, bigCashAmount);
        deal(address(cashAsset), provider, bigCashAmount);
        deal(address(underlying), user, bigUnderlyingAmount);
        deal(address(underlying), provider, bigUnderlyingAmount);
    }
}
