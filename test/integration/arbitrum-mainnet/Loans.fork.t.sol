// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "forge-std/Test.sol";
import "../utils/DeploymentLoader.sol";
import { ILoansNFT } from "../../../src/interfaces/ILoansNFT.sol";
import { DeployContractsArbitrumMainnet } from "../../../script/arbitrum-mainnet/deploy-contracts.s.sol";

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
        uint cashBalance = pair.cashAsset.balanceOf(provider);
        console.log("Provider cash balance: %d", cashBalance);
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
    ) internal returns (uint loanId, uint providerId, uint loanAmount) {
        vm.startPrank(user);
        pair.collateralAsset.approve(address(pair.loansContract), collateralAmount);
        (loanId, providerId, loanAmount) = pair.loansContract.openLoan(
            collateralAmount,
            minLoanAmount,
            ILoansNFT.SwapParams(0, address(pair.loansContract.defaultSwapper()), ""),
            pair.providerNFT,
            offerId
        );
        vm.stopPrank();
    }

    function closeLoan(
        DeploymentHelper.AssetPairContracts memory pair,
        address user,
        uint loanId,
        uint minCollateralOut
    ) internal returns (uint collateralOut) {
        vm.startPrank(user);
        ILoansNFT.Loan memory loan = pair.loansContract.getLoan(loanId);
        // approve repayment amount in cash asset to loans contract
        pair.cashAsset.approve(address(pair.loansContract), loan.loanAmount);
        collateralOut = pair.loansContract.closeLoan(
            loanId, ILoansNFT.SwapParams(minCollateralOut, address(pair.loansContract.defaultSwapper()), "")
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
        uint loanId,
        uint rollOfferId,
        int minToUser
    ) internal returns (uint newLoanId, uint newLoanAmount, int transferAmount) {
        vm.startPrank(user);
        pair.cashAsset.approve(address(pair.loansContract), type(uint).max);
        (newLoanId, newLoanAmount, transferAmount) =
            pair.loansContract.rollLoan(loanId, rollOfferId, minToUser, 0);
        vm.stopPrank();
    }
}

contract LoansForkTest is LoansTestBase {
    address cashAsset = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8; // USDC
    address collateralAsset = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1; // WETH
    DeploymentHelper.AssetPairContracts internal pair;
    uint public forkId;
    bool public forkSet;
    uint callstrikeToUse = 12_000;
    uint offerAmount = 100_000e6;
    uint collateralAmount = 1 ether;
    int rollFee = 100e6;
    int rollDeltaFactor = 10_000;
    uint bigCashAmount = 1_000_000e6;
    uint bigCollateralAmount = 1000 ether;
    uint slippage = 1; // 1%

    function setUp() public virtual override {
        if (!forkSet) {
            // this test suite needs to run independently so we load a fork here
            forkId = vm.createFork(vm.envString("ARBITRUM_MAINNET_RPC"));
            vm.selectFork(forkId);
            // Deploy contracts
            DeployContractsArbitrumMainnet deployer = new DeployContractsArbitrumMainnet();
            deployer.run();
            forkSet = true;
        } else {
            vm.selectFork(forkId);
        }
        super.setUp();
        pair = getPairByAssets(address(cashAsset), address(collateralAsset));
        fundWallets();
    }

    function setForkId(uint _forkId) public {
        forkId = _forkId;
        forkSet = true;
    }

    function testOpenAndCloseLoan() public {
        uint offerId = createProviderOffer(pair, callstrikeToUse, offerAmount);

        uint minLoanAmount = 0.3e6;
        (uint loanId,, uint loanAmount) = openLoan(pair, user, collateralAmount, minLoanAmount, offerId);

        assertGt(loanAmount, 0);
        skip(pair.durations[0]);
        // no price change so collateral out should be collateral in minus slippage
        uint minCollateralOut = collateralAmount;
        uint minCollateralOutWithSlippage = minCollateralOut * (100 - slippage) / 100;
        uint collateralOut = closeLoan(pair, user, loanId, minCollateralOutWithSlippage);
        assertGe(collateralOut, minCollateralOutWithSlippage);
    }

    function testRollLoan() public {
        uint offerId = createProviderOffer(pair, callstrikeToUse, offerAmount);

        uint minLoanAmount = 0.3e6;
        (uint loanId, uint providerId, uint initialLoanAmount) =
            openLoan(pair, user, collateralAmount, minLoanAmount, offerId);

        uint rollOfferId = createRollOffer(pair, provider, loanId, providerId, rollFee, rollDeltaFactor);

        int minToUser = -1000e6; // Allow up to 1000 tokens to be paid by the user
        (uint newLoanId, uint newLoanAmount, int transferAmount) =
            rollLoan(pair, user, loanId, rollOfferId, minToUser);

        assertGt(newLoanId, loanId);
        assertGe(int(newLoanAmount), int(initialLoanAmount) + transferAmount);
    }

    function testFullLoanLifecycle() public {
        uint offerId = createProviderOffer(pair, callstrikeToUse, offerAmount);
        uint minLoanAmount = 0.3e6;
        (uint loanId, uint providerId, uint initialLoanAmount) =
            openLoan(pair, user, collateralAmount, minLoanAmount, offerId);

        // Advance time to simulate passage of time
        vm.warp(block.timestamp + pair.durations[0] - 20);

        uint rollOfferId = createRollOffer(pair, provider, loanId, providerId, rollFee, rollDeltaFactor);

        int minToUser = -1000e6;
        (uint newLoanId, uint newLoanAmount, int transferAmount) =
            rollLoan(pair, user, loanId, rollOfferId, minToUser);

        // Advance time again
        vm.warp(block.timestamp + pair.durations[0]);

        uint minCollateralOut = collateralAmount * 95 / 100; // 5% slippage
        uint collateralOut = closeLoan(pair, user, newLoanId, minCollateralOut);

        assertGt(initialLoanAmount, 0);
        assertGt(newLoanId, loanId);
        assertGe(int(newLoanAmount), int(initialLoanAmount) + transferAmount);
        assertGe(collateralOut, minCollateralOut);
    }

    function fundWallets() public {
        deal(address(cashAsset), user, bigCashAmount);
        deal(address(cashAsset), provider, bigCashAmount);
        deal(address(collateralAsset), user, bigCollateralAmount);
        deal(address(collateralAsset), provider, bigCollateralAmount);
    }
}
