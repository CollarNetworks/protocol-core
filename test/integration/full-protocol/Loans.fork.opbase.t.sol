// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "forge-std/Test.sol";
import { Const } from "../../../script/utils/Const.sol";
import { DeploymentArtifactsLib } from "../../../script/libraries/DeploymentArtifacts.sol";
import { BaseAssetPairForkTest, ConfigHub } from "./BaseAssetPairForkTest.sol";
import { BaseDeployer } from "../../../script/libraries/BaseDeployer.sol";
import { DeployOPBaseMainnet, DeployOPBaseSepolia } from "../../../script/deploy/deploy-protocol.s.sol";
import {
    AcceptOwnershipOPBaseSepolia,
    AcceptOwnershipOPBaseMainnet
} from "../../../script/deploy/accept-ownership.s.sol";

abstract contract BaseAssetPairForkTest_ScriptTest is BaseAssetPairForkTest {
    string fakeArtifactsName = "collar_protocol_fork_deployment";

    enum TestMode {
        // deploys everything, saves artifacts, loads artifacts
        deploySaveLoad,
        // deploys everything, no artifacts
        deployOnly,
        // only loads an existing deployment
        noDeploy
    }

    TestMode testMode = TestMode.deploySaveLoad;
    bool forceLatestBlock = false; // whether to use latest regardless of env flags

    string RPCEnvVarsBase; // eg OPBASE_MAINNET
    string realArtifactsName; // needed for noDeploy mode

    function getDeployedContracts()
        internal
        virtual
        override
        returns (ConfigHub hub, BaseDeployer.AssetPairContracts[] memory pairs)
    {
        setupNewFork();

        if (testMode == TestMode.noDeploy) {
            return DeploymentArtifactsLib.loadHubAndAllPairs(vm, realArtifactsName);
        } else {
            BaseDeployer.DeploymentResult memory result = deployFullProtocol();
            if (testMode == TestMode.deploySaveLoad) {
                return DeploymentArtifactsLib.loadHubAndAllPairs(vm, fakeArtifactsName);
            } else {
                return (result.configHub, result.assetPairContracts);
            }
        }
    }

    function setupNewFork() internal virtual {
        string memory rpc = vm.envString(string.concat(RPCEnvVarsBase, "_RPC"));
        // if we are in development we want to fix the block to reduce the time it takes to run the tests
        if (forceLatestBlock || !vm.envBool(string.concat("FIX_BLOCK_", RPCEnvVarsBase))) {
            vm.createSelectFork(rpc);
        } else {
            vm.createSelectFork(rpc, vm.envUint(string.concat("BLOCK_NUMBER_", RPCEnvVarsBase)));
        }
    }

    // abstract

    function deployFullProtocol() internal virtual returns (BaseDeployer.DeploymentResult memory);
}

// OPBase mainnet

contract WETHUSDC_OPBaseMain_LoansForkTest is BaseAssetPairForkTest_ScriptTest {
    function deployFullProtocol()
        internal
        virtual
        override
        returns (BaseDeployer.DeploymentResult memory result)
    {
        result = (new DeployOPBaseMainnet()).run(fakeArtifactsName);

        // accept ownership of the new deployment from the owner (via broadcast instead of prank)
        (new AcceptOwnershipOPBaseMainnet()).run(fakeArtifactsName);
    }

    function _setTestValues() internal virtual override {
        RPCEnvVarsBase = "OPBASE_MAINNET";

        owner = Const.OPBaseMain_owner;

        // config params
        protocolFeeAPR = 90;
        protocolFeeRecipient = Const.OPBaseMain_feeRecipient;

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

        expectedOraclePrice = 2_000_000_000;
    }
}

contract WETHUSDC_OPBaseMain_LoansForkTest_noExport is WETHUSDC_OPBaseMain_LoansForkTest {
    function _setTestValues() internal virtual override {
        super._setTestValues();
        testMode = TestMode.deployOnly;
    }
}

contract WETHUSDC_OPBaseMain_LoansForkTest_NoDeploy is WETHUSDC_OPBaseMain_LoansForkTest {
    function _setTestValues() internal virtual override {
        super._setTestValues();
        forceLatestBlock = true;
        testMode = TestMode.noDeploy;
        realArtifactsName = Const.OPBaseMain_artifactsName;
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

contract CBBTCUSDC_OPBaseMain_LoansForkTest_NoDeploy is CBBTCUSDC_OPBaseMain_LoansForkTest {
    function _setTestValues() internal virtual override {
        super._setTestValues();
        forceLatestBlock = true;
        testMode = TestMode.noDeploy;
        realArtifactsName = Const.OPBaseMain_artifactsName;
    }
}

//// OPBase sep
contract TWETHTUSDC_OPBaseSep_LoansForkTest is WETHUSDC_OPBaseMain_LoansForkTest {
    function deployFullProtocol()
        internal
        virtual
        override
        returns (BaseDeployer.DeploymentResult memory result)
    {
        // run the deployment and setup
        result = (new DeployOPBaseSepolia()).run(fakeArtifactsName);

        // accept ownership of the new deployment from the owner (via broadcast instead of prank)
        (new AcceptOwnershipOPBaseSepolia()).run(fakeArtifactsName);
    }

    function _setTestValues() internal virtual override {
        super._setTestValues();

        RPCEnvVarsBase = "OPBASE_SEPOLIA";

        owner = Const.OPBaseSep_owner;

        // config params
        protocolFeeRecipient = Const.OPBaseSep_feeRecipient;

        // @dev all pairs must be tested, so if this number is increased, test classes must be added
        expectedNumPairs = 2;

        // set up all the variables for this pair
        expectedPairIndex = 0;
        underlying = Const.OPBaseSep_tWETH;
        cashAsset = Const.OPBaseSep_tUSDC;
        oracleDescription = "Comb(CL(TWAPMock(ETH / USD))|inv(CL(FixedMock(USDC / USD))))";

        expectedOraclePrice = 2_000_000_000; // 2k in 1e6
    }
}

contract TWETHTUSDC_OPBaseSep_LoansForkTest_NoDeploy is TWETHTUSDC_OPBaseSep_LoansForkTest {
    function _setTestValues() internal virtual override {
        super._setTestValues();
        forceLatestBlock = true;
        testMode = TestMode.noDeploy;
        realArtifactsName = Const.OPBaseSep_artifactsName;
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

contract TWBTCTUSDC_OPBaseSep_LoansForkTest_NoDeploy is TWBTCTUSDC_OPBaseSep_LoansForkTest {
    function _setTestValues() internal virtual override {
        super._setTestValues();
        forceLatestBlock = true;
        testMode = TestMode.noDeploy;
        realArtifactsName = Const.OPBaseSep_artifactsName;
    }
}
