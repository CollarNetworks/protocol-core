// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "./utils/DeploymentLoader.sol";
import { ILoans } from "../../src/interfaces/ILoans.sol";
import { ProviderPositionNFT } from "../../src/ProviderPositionNFT.sol";
import { CollarTakerNFT } from "../../src/CollarTakerNFT.sol";
import { Rolls } from "../../src/Rolls.sol";

abstract contract LoansTestBase is Test, DeploymentLoader {
    function setUp() public virtual override {
        super.setUp();
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
        ILoans.Loan memory loan = pair.loansContract.getLoan(takerId);
        // approve repayment amount in cash asset to loans contract
        pair.cashAsset.approve(address(pair.loansContract), loan.loanAmount);
        // approve taker NFT to loans contract
        pair.takerNFT.approve(address(pair.loansContract), takerId);
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

contract LoansForkTest is LoansTestBase {
    address cashAsset = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8; // USDC
    address collateralAsset = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1; // WETH
    DeploymentHelper.AssetPairContracts internal pair;

    function setUp() public virtual override {
        // this test suite needs to run independently so we load a fork here
        uint _blockNumberToUse = 223_579_191;
        string memory forkRPC = vm.envString("ARBITRUM_MAINNET_RPC");
        vm.createSelectFork(forkRPC, _blockNumberToUse);
        assertEq(block.number, 20_127_607);

        super.setUp();
        pair = getPairByAssets(address(cashAsset), address(collateralAsset));
        _fundWallets();
    }

    function testOpenAndCloseLoan() public {
        uint offerId = createProviderOffer(pair, 12_000, 100_000e6);

        uint collateralAmount = 1 ether;
        uint minLoanAmount = 0.3e6;
        (uint takerId,, uint loanAmount) = openLoan(pair, user, collateralAmount, minLoanAmount, offerId);

        assertGt(loanAmount, 0, "Loan amount should be greater than 0");
        skip(pair.durations[0]);
        uint minCollateralOut = collateralAmount * 95 / 100; // 5% slippage
        uint collateralOut = closeLoan(pair, user, takerId, minCollateralOut);
        assertGe(collateralOut, minCollateralOut, "Collateral out should be at least minCollateralOut");
    }

    function testRollLoan() public {
        uint offerId = createProviderOffer(pair, 12_000, 100_000e6);

        uint collateralAmount = 1 ether;
        uint minLoanAmount = 0.3e6;
        (uint takerId, uint providerId, uint initialLoanAmount) =
            openLoan(pair, user, collateralAmount, minLoanAmount, offerId);

        int rollFee = 100e6;
        int rollDeltaFactor = 10_000;
        uint rollOfferId = createRollOffer(pair, provider, takerId, providerId, rollFee, rollDeltaFactor);

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

    function testFullLoanLifecycle() public {
        uint offerId = createProviderOffer(pair, 12_000, 100_000e6);

        uint collateralAmount = 1 ether;
        uint minLoanAmount = 0.3e6;
        (uint takerId, uint providerId, uint initialLoanAmount) =
            openLoan(pair, user, collateralAmount, minLoanAmount, offerId);

        // Advance time to simulate passage of time
        vm.warp(block.timestamp + pair.durations[0] - 20);

        int rollFee = 100e6;
        int rollDeltaFactor = 10_000;
        uint rollOfferId = createRollOffer(pair, provider, takerId, providerId, rollFee, rollDeltaFactor);

        int minToUser = -1000e6;
        (uint newTakerId, uint newLoanAmount, int transferAmount) =
            rollLoan(pair, user, takerId, rollOfferId, minToUser);

        // Advance time again
        vm.warp(block.timestamp + pair.durations[0]);

        uint minCollateralOut = collateralAmount * 95 / 100; // 5% slippage
        uint collateralOut = closeLoan(pair, user, newTakerId, minCollateralOut);

        assertGt(initialLoanAmount, 0, "Initial loan amount should be greater than 0");
        assertGt(newTakerId, takerId, "New taker ID should be greater than old taker ID");
        assertGe(
            int(newLoanAmount),
            int(initialLoanAmount) + transferAmount,
            "New loan amount should reflect the transfer"
        );
        assertGe(collateralOut, minCollateralOut, "Collateral out should be at least minCollateralOut");
    }

    function _fundWallets() internal {
        deal(address(cashAsset), user, 1_000_000e6);
        deal(address(cashAsset), provider, 1_000_000e6);
        deal(address(collateralAsset), user, 1000e18);
        deal(address(collateralAsset), provider, 1000e18);
    }
}
