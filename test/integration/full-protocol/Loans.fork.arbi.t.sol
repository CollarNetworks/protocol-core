// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "forge-std/Test.sol";
import { Const } from "../../../script/utils/Const.sol";
import { DeployArbitrumMainnet, DeployArbitrumSepolia } from "../../../script/deploy/deploy-protocol.s.sol";
import {
    AcceptOwnershipArbiMainnet,
    AcceptOwnershipArbiSepolia
} from "../../../script/deploy/accept-ownership.s.sol";

import { BaseAssetPairForkTest_ScriptTest, BaseDeployer } from "./Loans.fork.opbase.t.sol";

contract WETHUSDC_ArbiMain_LoansForkTest is BaseAssetPairForkTest_ScriptTest {
    function deployFullProtocol()
        internal
        virtual
        override
        returns (BaseDeployer.DeploymentResult memory result)
    {
        result = (new DeployArbitrumMainnet()).run(fakeArtifactsName);

        // accept ownership of the new deployment from the owner (via broadcast instead of prank)
        (new AcceptOwnershipArbiMainnet()).run(fakeArtifactsName);
    }

    function _setTestValues() internal virtual override {
        RPCEnvVarsBase = "ARBITRUM_MAINNET";

        owner = Const.ArbiMain_owner;

        // config params
        protocolFeeAPR = 90;
        protocolFeeRecipient = Const.ArbiMain_feeRecipient;

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

        expectedOraclePrice = 2_000_000_000;
    }
}

contract WETHUSDC_ArbiMain_LoansForkTest_noExport is WETHUSDC_ArbiMain_LoansForkTest {
    function _setTestValues() internal virtual override {
        super._setTestValues();
        testMode = TestMode.deployOnly;
    }
}

contract ArbiMain_LoansForkTest_LatestBlock is WETHUSDC_ArbiMain_LoansForkTest {
    function _setTestValues() internal virtual override {
        super._setTestValues();
        forceLatestBlock = true;
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

        RPCEnvVarsBase = "ARBITRUM_SEPOLIA";

        owner = Const.ArbiSep_owner;
        protocolFeeRecipient = Const.ArbiSep_feeRecipient;

        // @dev all pairs must be tested, so if this number is increased, test classes must be added
        expectedNumPairs = 2;

        // set up all the variables for this pair
        expectedPairIndex = 0;
        underlying = Const.ArbiSep_tWETH;
        cashAsset = Const.ArbiSep_tUSDC;
        oracleDescription = "Comb(CL(TWAPMock(ETH / USD))|inv(CL(FixedMock(USDC / USD))))";

        expectedOraclePrice = 2_000_000_000;
    }

    function deployFullProtocol()
        internal
        virtual
        override
        returns (BaseDeployer.DeploymentResult memory result)
    {
        result = (new DeployArbitrumSepolia()).run(fakeArtifactsName);

        // accept ownership of the new deployment from the owner (via broadcast instead of prank)
        (new AcceptOwnershipArbiSepolia()).run(fakeArtifactsName);
    }
}

contract ArbiSep_LoansForkTest_LatestBlock is WETHUSDC_ArbiSep_LoansForkTest {
    function _setTestValues() internal virtual override {
        super._setTestValues();
        forceLatestBlock = true;
    }
}

contract WBTCUSDC_ArbiSep_LoansForkTest is WETHUSDC_ArbiSep_LoansForkTest {
    function _setTestValues() internal virtual override {
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
    function _setTestValues() internal virtual override {
        super._setTestValues();
        testMode = TestMode.deployOnly;
    }
}

contract WBTCUSDC_ArbiSep_LoansForkTest_noExport is WBTCUSDC_ArbiSep_LoansForkTest {
    function _setTestValues() internal virtual override {
        super._setTestValues();
        testMode = TestMode.deployOnly;
    }
}

////// load existing sepolia deployment
contract WETHUSDC_ArbiSep_LoansForkTest_NoDeploy is ArbiSep_LoansForkTest_LatestBlock {
    function _setTestValues() internal virtual override {
        super._setTestValues();
        testMode = TestMode.noDeploy;
        vm.skip(true); // deployment is outdated (0.2.0), ArbiSep isn't planned to be updated
        realArtifactsName = Const.ArbiSep_artifactsName;
    }
}

contract WBTCUSDC_ArbiSep_LoansForkTest_NoDeploy is WBTCUSDC_ArbiSep_LoansForkTest {
    function _setTestValues() internal virtual override {
        super._setTestValues();
        testMode = TestMode.noDeploy;
        vm.skip(true); // deployment is outdated (0.2.0), ArbiSep isn't planned to be updated
        realArtifactsName = Const.ArbiSep_artifactsName;
    }
}
