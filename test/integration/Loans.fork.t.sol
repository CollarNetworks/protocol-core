// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "./utils/DeploymentLoader.sol";
import { ILoans } from "../../src/interfaces/ILoans.sol";
import { ProviderPositionNFT } from "../../src/ProviderPositionNFT.sol";

contract LoansForkTest is Test, DeploymentLoader {
    address cashAsset = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8; // USDC
    address collateralAsset = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1; // WETH

    function setUp() public override {
        super.setUp();
    }

    function testOpenAndCloseLoan() public {
        DeploymentHelper.AssetPairContracts memory pair =
            getPairByAssets(address(cashAsset), address(collateralAsset));

        // Open a loan
        uint collateralAmount = 1 ether;
        uint minLoanAmount = 0.3e6;
        uint offerId = createProviderOffer(pair, 12_000, 100_000e6);

        (uint takerId, uint providerId, uint loanAmount) =
            openLoan(pair, user, collateralAmount, minLoanAmount, offerId);

        assertGt(loanAmount, 0, "Loan amount should be greater than 0");

        // Close the loan
        uint minCollateralOut = collateralAmount * 95 / 100; // 5% slippage
        uint collateralOut = closeLoan(pair, user, takerId, minCollateralOut);

        assertGe(collateralOut, minCollateralOut, "Collateral out should be at least minCollateralOut");
    }

    function testRollLoan() public {
        DeploymentHelper.AssetPairContracts memory pair =
            getPairByAssets(address(cashAsset), address(collateralAsset));

        // Open a loan
        uint collateralAmount = 1 ether;
        uint minLoanAmount = 0.3e6;
        uint offerId = createProviderOffer(pair, 12_000, 100_000e6);

        (uint takerId, uint providerId, uint initialLoanAmount) =
            openLoan(pair, user, collateralAmount, minLoanAmount, offerId);

        // Create a roll offer
        int rollFee = 100e6;
        int rollDeltaFactor = 10_000;
        uint rollOfferId = createRollOffer(pair, provider, takerId, providerId, rollFee, rollDeltaFactor);

        // Execute the roll
        int minToUser = -1000e6; // Allow up to 1000 tokens to be paid by the user
        (uint newTakerId, uint newLoanAmount, int transferAmount) =
            rollLoan(pair, user, takerId, rollOfferId, minToUser);

        assertGt(newTakerId, takerId, "New taker ID should be greater than old taker ID");
        assertGe(
            int(newLoanAmount),
            int(initialLoanAmount) + transferAmount,
            "New loan amount should reflect the transfer"
        );
    }

    function createProviderOffer(
        DeploymentHelper.AssetPairContracts memory pair,
        uint callStrikeDeviation,
        uint amount
    ) internal returns (uint offerId) {
        vm.startPrank(provider);
        pair.cashAsset.approve(address(pair.providerNFT), amount);
        offerId = pair.providerNFT.createOffer(callStrikeDeviation, amount, pair.ltvs[0], pair.durations[0]);
        vm.stopPrank();
    }

    function openLoan(
        DeploymentHelper.AssetPairContracts memory pair,
        address user,
        uint collateralAmount,
        uint minLoanAmount,
        uint offerId
    ) internal returns (uint takerId, uint providerId, uint loanAmount) {
        vm.startPrank(user);
        pair.collateralAsset.approve(address(pair.loansContract), collateralAmount);
        (takerId, providerId, loanAmount) = pair.loansContract.openLoan(
            collateralAmount,
            minLoanAmount,
            ILoans.SwapParams(0, address(pair.loansContract.defaultSwapper()), ""),
            pair.providerNFT,
            offerId
        );
        vm.stopPrank();
    }

    function closeLoan(
        DeploymentHelper.AssetPairContracts memory pair,
        address user,
        uint takerId,
        uint minCollateralOut
    ) internal returns (uint collateralOut) {
        vm.startPrank(user);
        collateralOut = pair.loansContract.closeLoan(
            takerId, ILoans.SwapParams(minCollateralOut, address(pair.loansContract.defaultSwapper()), "")
        );
        vm.stopPrank();
    }

    function createRollOffer(
        DeploymentHelper.AssetPairContracts memory pair,
        address provider,
        uint takerId,
        uint providerId,
        int rollFee,
        int rollDeltaFactor
    ) internal returns (uint rollOfferId) {
        vm.startPrank(provider);
        pair.cashAsset.approve(address(pair.rollsContract), type(uint).max);
        pair.providerNFT.approve(address(pair.rollsContract), providerId);
        uint currentPrice = pair.takerNFT.currentOraclePrice();
        rollOfferId = pair.rollsContract.createRollOffer(
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
        uint takerId,
        uint rollOfferId,
        int minToUser
    ) internal returns (uint newTakerId, uint newLoanAmount, int transferAmount) {
        vm.startPrank(user);
        pair.cashAsset.approve(address(pair.loansContract), type(uint).max);
        pair.takerNFT.approve(address(pair.loansContract), takerId);
        (newTakerId, newLoanAmount, transferAmount) =
            pair.loansContract.rollLoan(takerId, pair.rollsContract, rollOfferId, minToUser);
        vm.stopPrank();
    }
}
