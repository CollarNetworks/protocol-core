// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import { ConfigHub } from "../../src/implementations/ConfigHub.sol";
import { ProviderPositionNFT } from "../../src/ProviderPositionNFT.sol";
import { CollarTakerNFT } from "../../src/CollarTakerNFT.sol";
import { Loans } from "../../src/Loans.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Rolls } from "../../src/Rolls.sol";
import { DeploymentUtils } from "../utils/deployment-exporter.s.sol";
import { BaseDeployment } from "../base.s.sol";

contract DeployContracts is Script, DeploymentUtils, BaseDeployment {
    uint chainId = 137_999; // id for ethereum mainnet fork on tenderly
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

    function run() external {
        require(chainId == block.chainid, "chainId does not match the chainId in config");
        (address deployer,,,) = setup();
        deployerAddress = deployer;

        vm.startBroadcast(deployer);
        _deployandSetupConfigHub();
        _createContractPairs();
        vm.stopBroadcast();

        _exportDeployment();

        console.log("\nDeployment completed successfully");
    }

    function _deployandSetupConfigHub() internal {
        router = swapRouterAddress;
        configHub = new ConfigHub(router);

        // add supported cash assets
        configHub.setCashAssetSupport(USDC, true);
        configHub.setCashAssetSupport(USDT, true);
        configHub.setCashAssetSupport(WETH, true);
        // add supported collateral assets
        configHub.setCollateralAssetSupport(WETH, true);
        configHub.setCollateralAssetSupport(WBTC, true);
        configHub.setCollateralAssetSupport(MATIC, true);
        configHub.setCollateralAssetSupport(weETH, true);
        configHub.setCollateralAssetSupport(stETH, true);
        configHub.setLTVRange(allLTVs[1], allLTVs[0]);
        configHub.setCollarDurationRange(allDurations[0], allDurations[2]);

        console.log("\n --- Dev Environment Deployed ---");
        console.log("\n # Contract Addresses\n");
        console.log(" - Router:  - - - - - - ", router);
        console.log(" - ConfigHub - - - - - - - ", address(configHub));
    }

    function _createContractPairs() internal {
        uint[] memory singleDuration = new uint[](1);
        singleDuration[0] = allDurations[0];

        uint[] memory singleLTV = new uint[](1);
        singleLTV[0] = allLTVs[0];
        console.log("ltv: %d", singleLTV[0]);
        _createContractPair(IERC20(USDC), IERC20(WETH), "USDC/WETH", allDurations, allLTVs);
        _createContractPair(IERC20(USDT), IERC20(WETH), "USDT/WETH", singleDuration, singleLTV);
        _createContractPair(IERC20(USDC), IERC20(WBTC), "USDC/WBTC", singleDuration, singleLTV);
        _createContractPair(IERC20(USDC), IERC20(MATIC), "USDC/MATIC", singleDuration, singleLTV);
        _createContractPair(IERC20(USDC), IERC20(stETH), "USDC/stETH", singleDuration, singleLTV);
        _createContractPair(IERC20(WETH), IERC20(weETH), "WETH/weETH", singleDuration, singleLTV);
    }

    function _createContractPair(
        IERC20 cashAsset,
        IERC20 collateralAsset,
        string memory pairName,
        uint[] memory durations,
        uint[] memory ltvs
    ) internal {
        CollarTakerNFT takerNFT = new CollarTakerNFT(
            deployerAddress,
            configHub,
            cashAsset,
            collateralAsset,
            string(abi.encodePacked("Taker ", pairName)),
            string(abi.encodePacked("T", pairName))
        );
        ProviderPositionNFT providerNFT = new ProviderPositionNFT(
            deployerAddress,
            configHub,
            cashAsset,
            collateralAsset,
            address(takerNFT),
            string(abi.encodePacked("Provider ", pairName)),
            string(abi.encodePacked("P", pairName))
        );
        Loans loansContract = new Loans(deployerAddress, takerNFT);

        configHub.setCollarTakerContractAuth(address(takerNFT), true);
        configHub.setProviderContractAuth(address(providerNFT), true);
        Rolls rollsContract = new Rolls(deployerAddress, takerNFT, cashAsset);
        loansContract.setRollsContract(rollsContract);

        AssetPairContracts memory contracts = AssetPairContracts(
            providerNFT, takerNFT, loansContract, rollsContract, cashAsset, collateralAsset, durations, ltvs
        );
        require(address(contracts.providerNFT) != address(0), "Provider NFT not created");
        require(address(contracts.takerNFT) != address(0), "Taker NFT not created");
        require(address(contracts.loansContract) != address(0), "Loans contract not created");
        require(
            configHub.isProviderNFT(address(contracts.providerNFT)),
            "Provider NFT not authorized in configHub"
        );
        require(
            configHub.isCollarTakerNFT(address(contracts.takerNFT)), "Taker NFT not authorized in configHub"
        );
        require(address(contracts.rollsContract) != address(0), "Rolls contract not created");
        assetPairContracts.push(contracts);
        console.log(" - %s Taker NFT: %s", pairName, address(takerNFT));
        console.log(" - %s Provider NFT: %s", pairName, address(providerNFT));
        console.log(" - %s Loans Contract: %s", pairName, address(loansContract));
        console.log(" - %s Rolls Contract: %s", pairName, address(rollsContract));
    }

    function _exportDeployment() internal {
        exportDeployment("collar_protocol_deployment", address(configHub), router, assetPairContracts);
    }
}
