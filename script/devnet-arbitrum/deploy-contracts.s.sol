// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import { ConfigHub } from "../../src/ConfigHub.sol";
import { ShortProviderNFT } from "../../src/ShortProviderNFT.sol";
import { CollarTakerNFT } from "../../src/CollarTakerNFT.sol";
import { Loans } from "../../src/Loans.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Rolls } from "../../src/Rolls.sol";
import { DeploymentUtils } from "../utils/deployment-exporter.s.sol";
import { BaseDeployment } from "../BaseDeployment.s.sol";
import { OracleUniV3TWAP } from "../../src/OracleUniV3TWAP.sol";

contract DeployContracts is Script, DeploymentUtils, BaseDeployment {
    uint chainId = 42_161; // id for ethereum mainnet fork on tenderly
    address USDC = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
    address USDT = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;
    address WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address stETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84; // wsteth doesnt have any 0.3% fee with neither USDC nor USDT on arbitrum uniswap
    address weETH = 0x35751007a407ca6FEFfE80b3cB397736D2cf4dbe; // Wrapped weETH on arbitrum doesnt have USDC pools on uniswap
    address WBTC = 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f;
    address MATIC = 0x561877b6b3DD7651313794e5F2894B2F18bE0766;
    address swapRouterAddress = address(0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45);
    uint constant numOfPairs = 11;
    AssetPairContracts[] public assetPairContracts;
    uint[] allDurations = [5 minutes, 30 days, 12 * 30 days];
    uint[] allLTVs = [9000, 5000];
    uint24 oracleFeeTier = 500;
    uint24 swapFeeTier = 500;
    uint32 twapWindow = 15 minutes;

    function run() external {
        require(chainId == block.chainid, "chainId does not match the chainId in config");
        (address deployer,,,) = setup();
        vm.startBroadcast(deployer);
        _deployConfigHub();
        address[] memory collateralAssets = new address[](5);
        collateralAssets[0] = WETH;
        collateralAssets[1] = WBTC;
        collateralAssets[2] = MATIC;
        collateralAssets[3] = weETH;
        collateralAssets[4] = stETH;
        address[] memory cashAssets = new address[](3);
        cashAssets[0] = USDC;
        cashAssets[1] = USDT;
        cashAssets[2] = WETH;
        uint minLTV = allLTVs[1];
        uint maxLTV = allLTVs[0];
        uint minDuration = allDurations[0];
        uint maxDuration = allDurations[2];

        _deployConfigHub();

        _setupConfigHub(
            BaseDeployment.HubParams({
                cashAssets: cashAssets,
                collateralAssets: collateralAssets,
                minLTV: minLTV,
                maxLTV: maxLTV,
                minDuration: minDuration,
                maxDuration: maxDuration
            })
        );

        _createContractPairs();
        vm.stopBroadcast();

        exportDeployment(
            "collar_protocol_deployment", address(configHub), swapRouterAddress, assetPairContracts
        );

        console.log("\nDeployment completed successfully");
    }

    function _createContractPairs() internal {
        uint[] memory singleDuration = new uint[](1);
        singleDuration[0] = allDurations[0];

        uint[] memory singleLTV = new uint[](1);
        singleLTV[0] = allLTVs[0];

        BaseDeployment.PairConfig memory USDCWETHPairConfig = BaseDeployment.PairConfig({
            name: "USDC/WETH",
            durations: allDurations,
            ltvs: allLTVs,
            cashAsset: IERC20(USDC),
            collateralAsset: IERC20(WETH),
            oracleFeeTier: oracleFeeTier,
            swapFeeTier: swapFeeTier,
            twapWindow: twapWindow,
            swapRouter: swapRouterAddress
        });

        assetPairContracts.push(_createContractPair(USDCWETHPairConfig));

        BaseDeployment.PairConfig memory USDTWETHPairConfig = BaseDeployment.PairConfig({
            name: "USDT/WETH",
            durations: singleDuration,
            ltvs: singleLTV,
            cashAsset: IERC20(USDT),
            collateralAsset: IERC20(WETH),
            oracleFeeTier: oracleFeeTier,
            swapFeeTier: swapFeeTier,
            twapWindow: twapWindow,
            swapRouter: swapRouterAddress
        });

        assetPairContracts.push(_createContractPair(USDTWETHPairConfig));

        BaseDeployment.PairConfig memory USDCWBTCPairConfig = BaseDeployment.PairConfig({
            name: "USDC/WBTC",
            durations: singleDuration,
            ltvs: singleLTV,
            cashAsset: IERC20(USDC),
            collateralAsset: IERC20(WBTC),
            oracleFeeTier: oracleFeeTier,
            swapFeeTier: swapFeeTier,
            twapWindow: twapWindow,
            swapRouter: swapRouterAddress
        });

        assetPairContracts.push(_createContractPair(USDCWBTCPairConfig));

        BaseDeployment.PairConfig memory USDCMATICPairConfig = BaseDeployment.PairConfig({
            name: "USDC/MATIC",
            durations: singleDuration,
            ltvs: singleLTV,
            cashAsset: IERC20(USDC),
            collateralAsset: IERC20(MATIC),
            oracleFeeTier: oracleFeeTier,
            swapFeeTier: swapFeeTier,
            twapWindow: twapWindow,
            swapRouter: swapRouterAddress
        });

        assetPairContracts.push(_createContractPair(USDCMATICPairConfig));

        BaseDeployment.PairConfig memory USDCstEthPairConfig = BaseDeployment.PairConfig({
            name: "USDC/stETH",
            durations: singleDuration,
            ltvs: singleLTV,
            cashAsset: IERC20(USDC),
            collateralAsset: IERC20(stETH),
            oracleFeeTier: oracleFeeTier,
            swapFeeTier: swapFeeTier,
            twapWindow: twapWindow,
            swapRouter: swapRouterAddress
        });

        assetPairContracts.push(_createContractPair(USDCstEthPairConfig));

        BaseDeployment.PairConfig memory WETHweEthPairConfig = BaseDeployment.PairConfig({
            name: "WETH/weETH",
            durations: singleDuration,
            ltvs: singleLTV,
            cashAsset: IERC20(WETH),
            collateralAsset: IERC20(weETH),
            oracleFeeTier: oracleFeeTier,
            swapFeeTier: swapFeeTier,
            twapWindow: twapWindow,
            swapRouter: swapRouterAddress
        });

        assetPairContracts.push(_createContractPair(WETHweEthPairConfig));

        for (uint i = 0; i < assetPairContracts.length; i++) {
            _setupContractPair(configHub, assetPairContracts[i]);
            _verifyDeployment(configHub, assetPairContracts[i]);
        }
    }
}
