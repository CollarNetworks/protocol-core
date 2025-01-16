// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "forge-std/Test.sol";
import { DeploymentArtifactsLib } from "../../../script/utils/DeploymentArtifacts.sol";
import { BaseAssetPairForkTest, ConfigHub } from "./BaseAssetPairForkTest.sol";
import { ArbitrumMainnetDeployer, BaseDeployer } from "../../../script/ArbitrumMainnetDeployer.sol";
import { ArbitrumSepoliaDeployer } from "../../../script/ArbitrumSepoliaDeployer.sol";

abstract contract BaseAssetPairForkTest_NewDeploymentWithExport is BaseAssetPairForkTest {
    string constant deploymentName = "collar_protocol_fork_deployment";

    bool exportAndLoad = true;

    function getDeployedContracts()
        internal
        virtual
        override
        returns (ConfigHub hub, BaseDeployer.AssetPairContracts[] memory pairs)
    {
        setupNewFork();

        BaseDeployer.DeploymentResult memory result = deployFullProtocol();

        vm.startPrank(owner);
        BaseDeployer.acceptOwnershipAsSender(owner, result);
        vm.stopPrank();

        if (exportAndLoad) {
            DeploymentArtifactsLib.exportDeployment(
                vm, deploymentName, result.configHub, result.assetPairContracts
            );
            return DeploymentArtifactsLib.loadHubAndAllPairs(vm, deploymentName);
        } else {
            return (result.configHub, result.assetPairContracts);
        }
    }

    function setupNewFork() internal virtual {
        // if we are in development we want to fix the block to reduce the time it takes to run the tests
        if (vm.envBool("FIX_BLOCK_ARBITRUM_MAINNET")) {
            vm.createSelectFork(
                vm.envString("ARBITRUM_MAINNET_RPC"), vm.envUint("BLOCK_NUMBER_ARBITRUM_MAINNET")
            );
        } else {
            vm.createSelectFork(vm.envString("ARBITRUM_MAINNET_RPC"));
        }
    }

    function deployFullProtocol()
        internal
        virtual
        returns (BaseDeployer.DeploymentResult memory)
    {
        return ArbitrumMainnetDeployer.deployAndSetupFullProtocol(owner);
    }
}

contract WETHUSDC_ArbiMain_LoansForkTest is BaseAssetPairForkTest_NewDeploymentWithExport {
    function _setPairParams() internal virtual override {
        // @dev all pairs must be tested, so if this number is increased, test classes must be added
        expectedNumPairs = 3;

        // set up all the variables for this pair
        expectedPairIndex = 0;
        underlying = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1; // WETH
        cashAsset = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831; // USDC
        oracleDescription = "Comb(CL(ETH / USD)|inv(CL(USDC / USD)))";

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

contract WETHUSDC_ArbiMain_LoansForkTest_noExport is WETHUSDC_ArbiMain_LoansForkTest {
    function setUp() public override {
        // do not use the artifacts for this one
        exportAndLoad = false;
        super.setUp();
    }
}

contract ArbiMain_LoansForkTest_LatestBlock is WETHUSDC_ArbiMain_LoansForkTest {
    function setupNewFork() internal override {
        // always use latest block for this one, even on local
        vm.createSelectFork(vm.envString("ARBITRUM_MAINNET_RPC"));
    }
}

contract WETHUSDT_ArbiMain_LoansForkTest is WETHUSDC_ArbiMain_LoansForkTest {
    function _setPairParams() internal virtual override {
        super._setPairParams();
        expectedPairIndex = 1;
        underlying = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1; // WETH
        cashAsset = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9; // USDT
        oracleDescription = "Comb(CL(ETH / USD)|inv(CL(USDT / USD)))";
    }
}

contract WBTCUSDT_ArbiMain_LoansForkTest is WETHUSDC_ArbiMain_LoansForkTest {
    function _setPairParams() internal virtual override {
        super._setPairParams();

        expectedPairIndex = 2;
        underlying = 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f; // WBTC
        cashAsset = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9; // USDT
        oracleDescription = "Comb(CL(WBTC / USD)|inv(CL(USDT / USD)))";
        underlyingAmount = 0.1e8;
        bigUnderlyingAmount = 100e8;

        callstrikeToUse = 10_500;

        expectedOraclePrice = 90_000_000_000;
    }
}

// Sepolia

contract WETHUSDC_ArbiSep_LoansForkTest is WETHUSDC_ArbiMain_LoansForkTest {
    function _setPairParams() internal virtual override {
        super._setPairParams();
        // @dev all pairs must be tested, so if this number is increased, test classes must be added
        expectedNumPairs = 2;

        // set up all the variables for this pair
        expectedPairIndex = 0;
        underlying = 0xF17eb654885Afece15039a9Aa26F91063cC693E0; // tWETH CollarOwnedERC20
        cashAsset = 0x69fC9D4d59843C6E55f00b5F66b263C963214C53; // tUSDC CollarOwnedERC20
        oracleDescription = "Comb(CL(TWAPMock(ETH / USD))|inv(CL(FixedMock(USDC / USD))))";

        expectedOraclePrice = 3_000_000_000;
    }

    function setupNewFork() internal virtual override {
        // if we are in development we want to fix the block to reduce the time it takes to run the tests
        if (vm.envBool("FIX_BLOCK_ARBITRUM_SEPOLIA")) {
            vm.createSelectFork(
                vm.envString("ARBITRUM_SEPOLIA_RPC"), vm.envUint("BLOCK_NUMBER_ARBITRUM_SEPOLIA")
            );
        } else {
            vm.createSelectFork(vm.envString("ARBITRUM_SEPOLIA_RPC"));
        }
    }

    function deployFullProtocol()
        internal
        virtual
        override
        returns (BaseDeployer.DeploymentResult memory)
    {
        return ArbitrumSepoliaDeployer.deployAndSetupFullProtocol(owner);
    }
}

contract ArbiSep_LoansForkTest_LatestBlock is WETHUSDC_ArbiSep_LoansForkTest {
    function setupNewFork() internal override {
        // always use latest block for this one, even on local
        vm.createSelectFork(vm.envString("ARBITRUM_SEPOLIA_RPC"));
    }
}

contract WBTCUSDC_ArbiSep_LoansForkTest is WETHUSDC_ArbiSep_LoansForkTest {
    function _setPairParams() internal override {
        super._setPairParams();

        // set up all the variables for this pair
        expectedPairIndex = 1;
        underlying = 0x19d87c960265C229D4b1429DF6F0C7d18F0611F3; // tWBTC CollarOwnedERC20
        cashAsset = 0x69fC9D4d59843C6E55f00b5F66b263C963214C53; // tUSDC CollarOwnedERC20
        oracleDescription = "Comb(CL(TWAPMock(BTC / USD))|inv(CL(FixedMock(USDC / USD))))";

        underlyingAmount = 0.1e8;
        bigUnderlyingAmount = 100e8;

        expectedOraclePrice = 90_000_000_000;
    }
}

//// load existing
//
//contract WETHUSDC_ArbiSep_LoansForkTest_NoDeploy is WETHUSDC_ArbiSep_LoansForkTest {
//    function getDeployedContracts()
//    internal
//    override
//    returns (ConfigHub hub, BaseDeployer.AssetPairContracts[] memory pairs)
//    {
//        setupNewFork();
//
//        return DeploymentArtifactsLib.loadHubAndAllPairs(vm, "arbitrum_sepolia_collar_protocol_deployment");
//    }
//}
