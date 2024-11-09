// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import { ConfigHub } from "../../src/ConfigHub.sol";
import { EscrowSupplierNFT } from "../../src/EscrowSupplierNFT.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SetupHelper } from "../setup-helper.sol";
import { DeploymentHelper } from "../deployment-helper.sol";

library ArbitrumMainnetDeployer {
    uint constant chainId = 42_161; // id for arbitrum mainnet
    address constant USDC = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
    address constant USDT = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;
    address constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

    address constant WBTC = 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f;
    address constant MATIC = 0x561877b6b3DD7651313794e5F2894B2F18bE0766;
    address constant swapRouterAddress = address(0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45);

    address constant sequencerUptimeFeed = address(0xFdB631F5EE196F0ed6FAa767959853A9F217697D);

    uint24 constant oracleFeeTier = 500;
    uint24 constant swapFeeTier = 500;
    uint32 constant twapWindow = 15 minutes;
    uint8 constant pairsToDeploy = 3; // change for the number of pairs to be deployed by the _createContractPairs function

    /**
     * these are not a constant but a function instead cause cannot initialize array constants and cant have state in library
     */
    function getAllDurations() internal pure returns (uint[] memory) {
        uint[] memory durations = new uint[](3);
        durations[0] = 5 minutes;
        durations[1] = 30 days;
        durations[2] = 12 * 30 days;
        return durations;
    }

    function getAllLTVs() internal pure returns (uint[] memory) {
        uint[] memory ltvs = new uint[](2);
        ltvs[0] = 9000;
        ltvs[1] = 5000;
        return ltvs;
    }

    struct DeploymentResult {
        ConfigHub configHub;
        DeploymentHelper.AssetPairContracts[] assetPairContracts;
    }

    function deployAndSetupProtocol(address owner) internal returns (DeploymentResult memory result) {
        require(chainId == block.chainid, "chainId does not match the chainId in config");

        result.configHub = DeploymentHelper.deployConfigHub(owner);

        address[] memory underlyings = new address[](3);
        underlyings[0] = WETH;
        underlyings[1] = WBTC;
        underlyings[2] = MATIC;
        address[] memory cashAssets = new address[](3);
        cashAssets[0] = USDC;
        cashAssets[1] = USDT;
        cashAssets[2] = WETH;
        uint[] memory allLTVs = getAllLTVs();
        uint[] memory allDurations = getAllDurations();
        uint minLTV = allLTVs[1];
        uint maxLTV = allLTVs[0];
        uint minDuration = allDurations[0];
        uint maxDuration = allDurations[2];

        SetupHelper.setupConfigHub(
            result.configHub,
            SetupHelper.HubParams({
                cashAssets: cashAssets,
                underlyings: underlyings,
                minLTV: minLTV,
                maxLTV: maxLTV,
                minDuration: minDuration,
                maxDuration: maxDuration
            })
        );

        result.assetPairContracts = _createContractPairs(result.configHub, owner);

        for (uint i = 0; i < result.assetPairContracts.length; i++) {
            SetupHelper.setupContractPair(result.configHub, result.assetPairContracts[i]);
        }
    }

    function _createContractPairs(ConfigHub configHub, address owner)
        internal
        returns (DeploymentHelper.AssetPairContracts[] memory assetPairContracts)
    {
        assetPairContracts = new DeploymentHelper.AssetPairContracts[](pairsToDeploy);
        uint[] memory allDurations = getAllDurations();
        uint[] memory allLTVs = getAllLTVs();
        uint[] memory singleDuration = new uint[](1);
        singleDuration[0] = allDurations[0];

        uint[] memory singleLTV = new uint[](1);
        singleLTV[0] = allLTVs[0];

        // if any escrowNFT contracts will be reused for multiple pairs, they should be deployed first
        EscrowSupplierNFT wethEscrow =
            DeploymentHelper.deployEscrowNFT(configHub, owner, IERC20(WETH), "WETH");

        DeploymentHelper.PairConfig memory USDCWETHPairConfig = DeploymentHelper.PairConfig({
            name: "USDC/WETH",
            durations: allDurations,
            ltvs: allLTVs,
            cashAsset: IERC20(USDC),
            underlying: IERC20(WETH),
            oracleFeeTier: oracleFeeTier,
            swapFeeTier: swapFeeTier,
            twapWindow: twapWindow,
            swapRouter: swapRouterAddress,
            sequencerUptimeFeed: sequencerUptimeFeed,
            existingEscrowNFT: address(wethEscrow)
        });
        assetPairContracts[0] = DeploymentHelper.deployContractPair(configHub, USDCWETHPairConfig, owner);

        DeploymentHelper.PairConfig memory USDTWETHPairConfig = DeploymentHelper.PairConfig({
            name: "USDT/WETH",
            durations: allDurations,
            ltvs: allLTVs,
            cashAsset: IERC20(USDT),
            underlying: IERC20(WETH),
            oracleFeeTier: oracleFeeTier,
            swapFeeTier: swapFeeTier,
            twapWindow: twapWindow,
            swapRouter: swapRouterAddress,
            sequencerUptimeFeed: sequencerUptimeFeed,
            existingEscrowNFT: address(wethEscrow)
        });

        assetPairContracts[1] = DeploymentHelper.deployContractPair(configHub, USDTWETHPairConfig, owner);

        DeploymentHelper.PairConfig memory USDCWBTCPairConfig = DeploymentHelper.PairConfig({
            name: "USDC/WBTC",
            durations: allDurations,
            ltvs: allLTVs,
            cashAsset: IERC20(USDC),
            underlying: IERC20(WBTC),
            oracleFeeTier: oracleFeeTier,
            swapFeeTier: swapFeeTier,
            twapWindow: twapWindow,
            swapRouter: swapRouterAddress,
            sequencerUptimeFeed: sequencerUptimeFeed,
            existingEscrowNFT: address(0)
        });

        assetPairContracts[2] = DeploymentHelper.deployContractPair(configHub, USDCWBTCPairConfig, owner);

        // DeploymentHelper.PairConfig memory USDCMATICPairConfig = DeploymentHelper.PairConfig({
        //     name: "USDC/MATIC",
        //     durations: singleDuration,
        //     ltvs: singleLTV,
        //     cashAsset: IERC20(USDC),
        //     underlying: IERC20(MATIC),
        //     oracleFeeTier: oracleFeeTier,
        //     swapFeeTier: swapFeeTier,
        //     twapWindow: twapWindow,
        //     swapRouter: swapRouterAddress
        // });

        // assetPairContracts[3] = deployContractPair(configHub, USDCMATICPairConfig, owner);
    }
}
