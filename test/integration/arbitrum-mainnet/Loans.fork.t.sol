// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "forge-std/Test.sol";

import { BaseLoansForkTest } from "./BaseLoansForkTest.sol";
import { ArbitrumMainnetDeployer } from "../../../script/ArbitrumMainnetDeployer.sol";

contract WETHUSDCLoansForkTest is BaseLoansForkTest {
    function setUp() public override {
        super.setUp();

        _setParams();

        uint pairIndex;
        (pair, pairIndex) = getPairByAssets(address(cashAsset), address(underlying));
        require(address(pair.loansContract) != address(0), "Loans contract not deployed");
        // ensure we're testing all deployed pairs
        require(pairIndex == expectedPairIndex, "pair index mismatch");
        require(deployedPairs.length == expectedNumPairs, "number of pairs mismatch");

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
        // @dev all pairs must be tested, so if this number is increased, test classes must be added
        expectedNumPairs = 3;

        // set up all the variables for this pair
        expectedPairIndex = 0;
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

    function setupNewFork() internal virtual override {
        // if we are in development we want to fix the block to reduce the time it takes to run the tests
        if (vm.envBool("FIX_BLOCK_ARBITRUM_MAINNET")) {
            vm.createSelectFork(
                vm.envString("ARBITRUM_MAINNET_RPC"), vm.envUint("BLOCK_NUMBER_ARBITRUM_MAINNET")
            );
        } else {
            vm.createSelectFork(vm.envString("ARBITRUM_MAINNET_RPC"));
        }
    }

    function setupDeployer() internal virtual override {
        deployer = new ArbitrumMainnetDeployer();
    }

    function deploymentName() internal pure virtual override returns (string memory) {
        return "collar_protocol_fork_deployment";
    }
}

contract ArbiMainnetLoansForkTest_LatestBlock is WETHUSDCLoansForkTest {
    function setupNewFork() internal override {
        // always use latest block for this one, even on local
        vm.createSelectFork(vm.envString("ARBITRUM_MAINNET_RPC"));
    }
}

contract WETHUSDTLoansForkTest is WETHUSDCLoansForkTest {
    function _setParams() internal virtual override {
        super._setParams();
        expectedPairIndex = 1;
        underlying = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1; // WETH
        cashAsset = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9; // USDT
    }
}

contract WBTCUSDTLoansForkTest is WETHUSDCLoansForkTest {
    function _setParams() internal virtual override {
        super._setParams();

        expectedPairIndex = 2;
        underlying = 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f; // WBTC
        cashAsset = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9; // USDT
        underlyingAmount = 0.1e8;
        bigUnderlyingAmount = 100e8;

        callstrikeToUse = 10_500;

        expectedOraclePrice = 90_000_000_000;
    }
}
