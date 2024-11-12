// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "forge-std/Test.sol";

import { BaseLoansForkTest } from "./BaseForkTest.sol";

contract USDCWETHForkTest is BaseLoansForkTest {
    function setUp() public override {
        super.setUp();

        // set up all the variables for this pair
        cashAsset = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831; // USDC
        underlying = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1; // WETH
        offerAmount = 100_000e6;
        underlyingAmount = 1 ether;
        minLoanAmount = 0.3e6; // arbitrary low value
        rollFee = 100e6;
        rollDeltaFactor = 10_000;
        bigCashAmount = 1_000_000e6;
        bigUnderlyingAmount = 1000 ether;
        swapPoolFeeTier = 500;

        // price movement swap amounts
        swapStepCashAmount = 250_000e6;

        pair = getPairByAssets(address(cashAsset), address(underlying));
        require(address(pair.loansContract) != address(0), "Loans contract not deployed");

        // Fund whale for price manipulation
        deal(address(pair.cashAsset), whale, 100 * bigCashAmount);
        deal(address(pair.underlying), whale, 100 * bigUnderlyingAmount);

        // Setup protocol fee
        vm.startPrank(owner);
        configHub.setProtocolFeeParams(feeAPR, feeRecipient);
        vm.stopPrank();
        fundWallets();

        duration = pair.durations[0];
        durationPriceMovement = pair.durations[1];
    }
}

contract USDTWETHForkTest is BaseLoansForkTest {
    function setUp() public override {
        super.setUp();

        // set up all the variables for this pair
        cashAsset = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9; // USDT
        underlying = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1; // WETH
        offerAmount = 100_000e6;
        underlyingAmount = 1 ether;
        minLoanAmount = 0.3e6; // arbitrary low value
        rollFee = 100e6;
        rollDeltaFactor = 10_000;
        bigCashAmount = 1_000_000e6;
        bigUnderlyingAmount = 1000 ether;
        swapPoolFeeTier = 500;

        // price movement swap amounts
        swapStepCashAmount = 1_000_000e6;

        pair = getPairByAssets(address(cashAsset), address(underlying));
        require(address(pair.loansContract) != address(0), "Loans contract not deployed");

        // Fund whale for price manipulation
        deal(address(pair.cashAsset), whale, 100 * bigCashAmount);
        deal(address(pair.underlying), whale, 100 * bigUnderlyingAmount);

        // Setup protocol fee
        vm.startPrank(owner);
        configHub.setProtocolFeeParams(feeAPR, feeRecipient);
        vm.stopPrank();
        fundWallets();

        duration = pair.durations[0];
        durationPriceMovement = pair.durations[1];
    }
}

contract USDTWBTCForkTest is BaseLoansForkTest {
    function setUp() public override {
        super.setUp();

        callstrikeToUse = 11_000; // not enough liquidity at 120%

        // set up all the variables for this pair
        cashAsset = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9; // USDT
        underlying = 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f; // WBTC
        offerAmount = 100_000e6;
        underlyingAmount = 0.1e8;
        minLoanAmount = 0.3e6; // arbitrary low value
        rollFee = 100e6;
        rollDeltaFactor = 10_000;
        bigCashAmount = 1_000_000e6;
        bigUnderlyingAmount = 100e8;
        swapPoolFeeTier = 500;

        // price movement swap amounts
        swapStepCashAmount = 500_000e6;

        // change callstrike cause price impact is harder to manage on this pool

        pair = getPairByAssets(address(cashAsset), address(underlying));
        require(address(pair.loansContract) != address(0), "Loans contract not deployed");

        // Fund whale for price manipulation
        deal(address(pair.cashAsset), whale, 100 * bigCashAmount);
        deal(address(pair.underlying), whale, 100 * bigUnderlyingAmount);

        // Setup protocol fee
        vm.startPrank(owner);
        configHub.setProtocolFeeParams(feeAPR, feeRecipient);
        vm.stopPrank();
        fundWallets();

        duration = pair.durations[0];
        durationPriceMovement = pair.durations[1];
    }
}
