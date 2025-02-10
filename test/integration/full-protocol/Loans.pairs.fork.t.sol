// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "forge-std/Test.sol";
import { Const } from "../../../script/utils/Const.sol";
import { DeploymentArtifactsLib } from "../../../script/libraries/DeploymentArtifacts.sol";
import { BaseAssetPairForkTest, ConfigHub } from "./BaseAssetPairForkTest.sol";
import { BaseDeployer } from "../../../script/libraries/BaseDeployer.sol";
import { OPBaseMainnetDeployer } from "../../../script/libraries/OPBaseMainnetDeployer.sol";
import {
    DeployArbitrumMainnet,
    DeployArbitrumSepolia,
    DeployOPBaseMainnet,
    DeployOPBaseSepolia
} from "../../../script/deploy/deploy-protocol.s.sol";
import {
    AcceptOwnershipOPBaseSepolia,
    AcceptOwnershipOPBaseMainnet,
    AcceptOwnershipArbiMainnet,
    AcceptOwnershipArbiSepolia
} from "../../../script/deploy/accept-ownership.s.sol";

abstract contract BaseAssetPairForkTest_ScriptTest is BaseAssetPairForkTest {
    string constant deploymentName = "collar_protocol_fork_deployment";

    bool loadFromArtifacts = true;

    function getDeployedContracts()
        internal
        virtual
        override
        returns (ConfigHub hub, BaseDeployer.AssetPairContracts[] memory pairs)
    {
        setupNewFork();

        BaseDeployer.DeploymentResult memory result = deployFullProtocol();

        // load and return the deployment from artifacts
        if (loadFromArtifacts) {
            (hub, pairs) = DeploymentArtifactsLib.loadHubAndAllPairs(vm, deploymentName);
        } else {
            (hub, pairs) = (result.configHub, result.assetPairContracts);
        }
    }

    // abstract

    function setupNewFork() internal virtual;

    function deployFullProtocol() internal virtual returns (BaseDeployer.DeploymentResult memory);
}

contract WETHUSDC_ArbiMain_LoansForkTest is BaseAssetPairForkTest_ScriptTest {
    function setupNewFork() internal virtual override {
        string memory rpc = vm.envString("ARBITRUM_MAINNET_RPC");
        // if we are in development we want to fix the block to reduce the time it takes to run the tests
        if (vm.envBool("FIX_BLOCK_ARBITRUM_MAINNET")) {
            vm.createSelectFork(rpc, vm.envUint("BLOCK_NUMBER_ARBITRUM_MAINNET"));
        } else {
            vm.createSelectFork(rpc);
        }
    }

    function deployFullProtocol()
        internal
        virtual
        override
        returns (BaseDeployer.DeploymentResult memory result)
    {
        result = (new DeployArbitrumMainnet()).run(deploymentName);

        // accept ownership of the new deployment from the owner (via broadcast instead of prank)
        (new AcceptOwnershipArbiMainnet()).run(deploymentName);
    }

    function _setTestValues() internal virtual override {
        owner = Const.ArbiMain_owner;

        // config params
        protocolFeeAPR = 90;
        protocolFeeRecipient = Const.ArbiMain_feeRecipient;
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
        // do not use the artifacts for this test (only the direct deployment result)
        loadFromArtifacts = false;
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

// Arbi Sepolia

contract WETHUSDC_ArbiSep_LoansForkTest is WETHUSDC_ArbiMain_LoansForkTest {
    function _setTestValues() internal virtual override {
        super._setTestValues();

        owner = Const.ArbiSep_owner;
        protocolFeeRecipient = Const.ArbiSep_feeRecipient;
        delete pauseGuardians;
        pauseGuardians.push(Const.ArbiSep_deployerAcc);

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
        string memory rpc = vm.envString("ARBITRUM_SEPOLIA_RPC");
        // if we are in development we want to fix the block to reduce the time it takes to run the tests
        if (vm.envBool("FIX_BLOCK_ARBITRUM_SEPOLIA")) {
            vm.createSelectFork(rpc, vm.envUint("BLOCK_NUMBER_ARBITRUM_SEPOLIA"));
        } else {
            vm.createSelectFork(rpc);
        }
    }

    function deployFullProtocol()
        internal
        virtual
        override
        returns (BaseDeployer.DeploymentResult memory result)
    {
        result = (new DeployArbitrumSepolia()).run(deploymentName);

        // accept ownership of the new deployment from the owner (via broadcast instead of prank)
        (new AcceptOwnershipArbiSepolia()).run(deploymentName);
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

contract WETHUSDC_ArbiSep_LoansForkTest_noExport is WETHUSDC_ArbiSep_LoansForkTest {
    function setUp() public override {
        // do not use the artifacts for this test (only the direct deployment result)
        loadFromArtifacts = false;
        super.setUp();
    }
}

contract WBTCUSDC_ArbiSep_LoansForkTest_noExport is WBTCUSDC_ArbiSep_LoansForkTest {
    function setUp() public override {
        // do not use the artifacts for this test (only the direct deployment result)
        loadFromArtifacts = false;
        super.setUp();
    }
}

////// load existing sepolia deployment
contract WETHUSDC_ArbiSep_LoansForkTest_NoDeploy is ArbiSep_LoansForkTest_LatestBlock {
    function getDeployedContracts()
        internal
        override
        returns (ConfigHub hub, BaseDeployer.AssetPairContracts[] memory pairs)
    {
        setupNewFork();
        return DeploymentArtifactsLib.loadHubAndAllPairs(vm, Const.ArbiSep_artifactsName);
    }
}

contract WBTCUSDC_ArbiSep_LoansForkTest_NoDeploy is WBTCUSDC_ArbiSep_LoansForkTest {
    function getDeployedContracts()
        internal
        override
        returns (ConfigHub hub, BaseDeployer.AssetPairContracts[] memory pairs)
    {
        setupNewFork();
        return DeploymentArtifactsLib.loadHubAndAllPairs(vm, Const.ArbiSep_artifactsName);
    }
}

// OPBase mainnet

contract WETHUSDC_OPBaseMain_LoansForkTest is BaseAssetPairForkTest_ScriptTest {
    function setupNewFork() internal virtual override {
        string memory rpc = vm.envString("OPBASE_MAINNET_RPC");
        // if we are in development we want to fix the block to reduce the time it takes to run the tests
        if (vm.envBool("FIX_BLOCK_OPBASE_MAINNET")) {
            vm.createSelectFork(rpc, vm.envUint("BLOCK_NUMBER_OPBASE_MAINNET"));
        } else {
            vm.createSelectFork(rpc);
        }
    }

    function deployFullProtocol()
        internal
        virtual
        override
        returns (BaseDeployer.DeploymentResult memory result)
    {
        result = (new DeployOPBaseMainnet()).run(deploymentName);

        // accept ownership of the new deployment from the owner (via broadcast instead of prank)
        (new AcceptOwnershipOPBaseMainnet()).run(deploymentName);
    }

    function _setTestValues() internal virtual override {
        owner = Const.OPBaseMain_owner;

        // config params
        protocolFeeAPR = 90;
        protocolFeeRecipient = Const.OPBaseMain_feeRecipient;
        pauseGuardians.push(Const.OPBaseMain_deployerAcc);

        // @dev all pairs must be tested, so if this number is increased, test classes must be added
        expectedNumPairs = 2;

        // set up all the variables for this pair
        expectedPairIndex = 0;
        underlying = Const.OPBaseMain_WETH;
        cashAsset = Const.OPBaseMain_USDC;
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

contract CBBTCUSDC_OPBaseMain_LoansForkTest is WETHUSDC_OPBaseMain_LoansForkTest {
    function _setTestValues() internal virtual override {
        super._setTestValues();

        // @dev all pairs must be tested, so if this number is increased, test classes must be added
        expectedNumPairs = 2;

        // set up all the variables for this pair
        expectedPairIndex = 1;
        underlying = Const.OPBaseMain_cbBTC;
        cashAsset = Const.OPBaseMain_USDC;
        oracleDescription = "Comb(CL(cbBTC / USD)|inv(CL(USDC / USD)))";

        underlyingAmount = 0.1e8;
        bigUnderlyingAmount = 100e8;

        expectedOraclePrice = 90_000_000_000;
    }
}

contract WETHUSDC_OPBaseMain_LoansForkTest_noExport is WETHUSDC_OPBaseMain_LoansForkTest {
    function setUp() public override {
        // do not use the artifacts for this one
        loadFromArtifacts = false;
        super.setUp();
    }
}

contract OPBaseMain_LoansForkTest_LatestBlock is WETHUSDC_OPBaseMain_LoansForkTest {
    function setupNewFork() internal override {
        // always use latest block for this one, even on local
        vm.createSelectFork(vm.envString("OPBASE_MAINNET_RPC"));
    }
}

//// OPBase sep
contract TWETHTUSDC_OPBaseSep_LoansForkTest is WETHUSDC_OPBaseMain_LoansForkTest {
    function setupNewFork() internal virtual override {
        string memory rpc = vm.envString("OPBASE_SEPOLIA_RPC");
        // if we are in development we want to fix the block to reduce the time it takes to run the tests
        if (vm.envBool("FIX_BLOCK_OPBASE_SEPOLIA")) {
            vm.createSelectFork(rpc, vm.envUint("BLOCK_NUMBER_OPBASE_SEPOLIA"));
        } else {
            vm.createSelectFork(rpc);
        }
    }

    function deployFullProtocol()
        internal
        virtual
        override
        returns (BaseDeployer.DeploymentResult memory result)
    {
        // run the deployment and setup
        result = (new DeployOPBaseSepolia()).run(deploymentName);

        // accept ownership of the new deployment from the owner (via broadcast instead of prank)
        (new AcceptOwnershipOPBaseSepolia()).run(deploymentName);
    }

    function _setTestValues() internal virtual override {
        super._setTestValues();
        owner = Const.OPBaseSep_owner;

        // config params
        protocolFeeRecipient = Const.OPBaseSep_feeRecipient;
        delete pauseGuardians;
        pauseGuardians.push(Const.OPBaseSep_deployerAcc);

        // @dev all pairs must be tested, so if this number is increased, test classes must be added
        expectedNumPairs = 2;

        // set up all the variables for this pair
        expectedPairIndex = 0;
        underlying = Const.OPBaseSep_tWETH;
        cashAsset = Const.OPBaseSep_tUSDC;
        oracleDescription = "Comb(CL(TWAPMock(ETH / USD))|inv(CL(FixedMock(USDC / USD))))";

        expectedOraclePrice = 3_500_000_000; // 3.5k in 1e6
    }
}

contract TWBTCTUSDC_OPBaseSep_LoansForkTest is TWETHTUSDC_OPBaseSep_LoansForkTest {
    function _setTestValues() internal virtual override {
        super._setTestValues();
        // set up all the variables for this pair
        expectedPairIndex = 1;
        underlying = Const.OPBaseSep_tWBTC;
        cashAsset = Const.OPBaseSep_tUSDC;
        oracleDescription = "Comb(CL(TWAPMock(BTC / USD))|inv(CL(FixedMock(USDC / USD))))";

        underlyingAmount = 0.1e8;
        bigUnderlyingAmount = 100e8;

        expectedOraclePrice = 100_000_000_000; // 100k in 1e6
    }
}

contract TWETHTUSDC_OPBaseSep_LoansForkTest_NoDeploy_LatestBlock is TWETHTUSDC_OPBaseSep_LoansForkTest {
    function setupNewFork() internal override {
        vm.createSelectFork(vm.envString("OPBASE_SEPOLIA_RPC"));
    }

    function getDeployedContracts()
        internal
        override
        returns (ConfigHub hub, BaseDeployer.AssetPairContracts[] memory pairs)
    {
        setupNewFork();
        return DeploymentArtifactsLib.loadHubAndAllPairs(vm, Const.OPBaseSep_artifactsName);
    }
}

contract TWBTCTUSDC_OPBaseSep_LoansForkTest_NoDeploy_LatestBlock is TWBTCTUSDC_OPBaseSep_LoansForkTest {
    function setupNewFork() internal override {
        vm.createSelectFork(vm.envString("OPBASE_SEPOLIA_RPC"));
    }

    function getDeployedContracts()
        internal
        override
        returns (ConfigHub hub, BaseDeployer.AssetPairContracts[] memory pairs)
    {
        setupNewFork();
        return DeploymentArtifactsLib.loadHubAndAllPairs(vm, Const.OPBaseSep_artifactsName);
    }
}
