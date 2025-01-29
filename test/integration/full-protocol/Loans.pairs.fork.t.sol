// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "forge-std/Test.sol";
import { Const } from "../../../script/Const.sol";
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

        vm.startPrank(owner);
        BaseDeployer.DeploymentResult memory result = deployFullProtocol();

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

    function deployFullProtocol() internal virtual returns (BaseDeployer.DeploymentResult memory) {
        return ArbitrumMainnetDeployer.deployAndSetupFullProtocol(owner);
    }
}

contract WETHUSDC_ArbiMain_LoansForkTest is BaseAssetPairForkTest_NewDeploymentWithExport {
    function _setTestValues() internal virtual override {
        // config params
        protocolFeeAPR = 75;
        protocolFeeRecipient = Const.ArbiMain_deployerAcc;
        pauseGuardians.push(Const.ArbiMain_deployerAcc);

        // @dev all pairs must be tested, so if this number is increased, test classes must be added
        expectedNumPairs = 3;

        // set up all the variables for this pair
        expectedPairIndex = 0;
        underlying = Const.ArbiMain_WETH;
        cashAsset = Const.ArbiMain_USDC;
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
    function _setTestValues() internal virtual override {
        super._setTestValues();
        expectedPairIndex = 1;
        underlying = Const.ArbiMain_WETH;
        cashAsset = Const.ArbiMain_USDT;
        oracleDescription = "Comb(CL(ETH / USD)|inv(CL(USDT / USD)))";
    }
}

contract WBTCUSDT_ArbiMain_LoansForkTest is WETHUSDC_ArbiMain_LoansForkTest {
    function _setTestValues() internal virtual override {
        super._setTestValues();

        expectedPairIndex = 2;
        underlying = Const.ArbiMain_WBTC;
        cashAsset = Const.ArbiMain_USDT;
        oracleDescription = "Comb(CL(WBTC / USD)|inv(CL(USDT / USD)))";
        underlyingAmount = 0.1e8;
        bigUnderlyingAmount = 100e8;

        callstrikeToUse = 10_500;

        expectedOraclePrice = 90_000_000_000;
    }
}

// Sepolia

contract WETHUSDC_ArbiSep_LoansForkTest is WETHUSDC_ArbiMain_LoansForkTest {
    function _setTestValues() internal virtual override {
        super._setTestValues();
        // @dev all pairs must be tested, so if this number is increased, test classes must be added
        expectedNumPairs = 2;

        // set up all the variables for this pair
        expectedPairIndex = 0;
        underlying = Const.ArbiSep_tWETH;
        cashAsset = Const.ArbiSep_tUSDC;
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

    function deployFullProtocol() internal virtual override returns (BaseDeployer.DeploymentResult memory) {
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
    function _setTestValues() internal override {
        super._setTestValues();

        // set up all the variables for this pair
        expectedPairIndex = 1;
        underlying = Const.ArbiSep_tWBTC;
        cashAsset = Const.ArbiSep_tUSDC;
        oracleDescription = "Comb(CL(TWAPMock(BTC / USD))|inv(CL(FixedMock(USDC / USD))))";

        underlyingAmount = 0.1e8;
        bigUnderlyingAmount = 100e8;

        expectedOraclePrice = 90_000_000_000;
    }
}

////// load existing sepolia deployment
contract WETHUSDC_ArbiSep_LoansForkTest_NoDeploy is WETHUSDC_ArbiSep_LoansForkTest {
    function getDeployedContracts()
        internal
        override
        returns (ConfigHub hub, BaseDeployer.AssetPairContracts[] memory pairs)
    {
        setupNewFork();

        return DeploymentArtifactsLib.loadHubAndAllPairs(vm, Const.ArbiSep_artifactsName);
    }
}
