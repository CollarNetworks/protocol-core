// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "forge-std/Test.sol";

import { BaseLoansForkTest } from "./BaseForkTest.sol";

contract USDCWETHForkTest is BaseLoansForkTest {
    function setUp() public override {
        super.setUp();

        // set up all the variables for this pair
        cashAsset = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8; // USDC
        underlying = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1; // WETH
        offerAmount = 100_000e6;
        underlyingAmount = 1 ether;
        minLoanAmount = 0.3e6; // arbitrary low value
        rollFee = 100e6;
        rollDeltaFactor = 10_000;
        bigCashAmount = 1_000_000e6;
        bigUnderlyingAmount = 1000 ether;
        SWAP_POOL_FEE_TIER = 500;

        // Initial swap amounts (from proven fork tests)
        AMOUNT_FOR_CALL_STRIKE = 1_000_000e6; // Amount in USDC to move past call strike
        AMOUNT_FOR_PUT_STRIKE = 250 ether; // Amount in WETH to move past put strike
        AMOUNT_FOR_PARTIAL_MOVE = 600_000e6; // Amount in USDC to move partially up

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
        SWAP_POOL_FEE_TIER = 500;

        // Initial swap amounts (from proven fork tests)
        AMOUNT_FOR_CALL_STRIKE = 2_000_000e6; // Amount in USDC to move past call strike
        AMOUNT_FOR_PUT_STRIKE = 250 ether; // Amount in WETH to move past put strike
        AMOUNT_FOR_PARTIAL_MOVE = 600_000e6; // Amount in USDC to move partially up

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

contract USDCWBTCForkTest is BaseLoansForkTest {
    function setUp() public override {
        super.setUp();

        // set up all the variables for this pair
        cashAsset = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8; // USDT
        underlying = 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f; // WBTC
        offerAmount = 100_000e6;
        underlyingAmount = 0.1e8;
        minLoanAmount = 0.3e6; // arbitrary low value
        rollFee = 100e6;
        rollDeltaFactor = 10_000;
        bigCashAmount = 1_000_000e6;
        bigUnderlyingAmount = 100e8;
        SWAP_POOL_FEE_TIER = 500;

        // Initial swap amounts (from proven fork tests)
        AMOUNT_FOR_CALL_STRIKE = 70_000e6; // Amount in USDC to move past call strike
        AMOUNT_FOR_PUT_STRIKE = 1e8; // Amount in WBTC to move past put strike
        AMOUNT_FOR_PARTIAL_MOVE = 15_000e6; // Amount in USDC to move partially up

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
