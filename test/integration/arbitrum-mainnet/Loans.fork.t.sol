// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "forge-std/Test.sol";

import { BaseLoansForkTest } from "./BaseForkTest.sol";

contract WETHUSDCLoansForkTest is BaseLoansForkTest {
    function setUp() public override {
        super.setUp();

        _setParams();

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

        duration = 5 minutes;
        ltv = 9000;
    }

    function _setParams() internal virtual {
        // set up all the variables for this pair
        underlying = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1; // WETH
        cashAsset = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831; // USDC
        offerAmount = 100_000e6;
        underlyingAmount = 1 ether;
        minLoanAmount = 0.3e6; // arbitrary low value
        rollFee = 100e6;
        rollDeltaFactor = 10_000;
        bigCashAmount = 1_000_000e6;
        bigUnderlyingAmount = 1000 ether;
        swapPoolFeeTier = 500;

        slippage = 100; // 1%
        callstrikeToUse = 11_000;

        expectedOraclePrice = 3_000_000_000;
    }
}

contract WETHUSDTLoansForkTest is WETHUSDCLoansForkTest {
    function _setParams() internal virtual override {
        super._setParams();
        underlying = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1; // WETH
        cashAsset = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9; // USDT
    }
}

contract WBTCUSDTLoansForkTest is WETHUSDCLoansForkTest {
    function _setParams() internal virtual override {
        super._setParams();

        underlying = 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f; // WBTC
        cashAsset = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9; // USDT
        underlyingAmount = 0.1e8;
        bigUnderlyingAmount = 100e8;

        callstrikeToUse = 10_500;

        expectedOraclePrice = 90_000_000_000;
    }
}
