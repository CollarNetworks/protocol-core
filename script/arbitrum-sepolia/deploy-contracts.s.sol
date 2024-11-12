// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import { DeploymentUtils } from "../utils/deployment-exporter.s.sol";
import { WalletLoader } from "../wallet-loader.s.sol";
import { ArbitrumSepoliaDeployer } from "./deployer.sol";

contract DeployContractsArbitrumSepolia is Script {
    uint chainId = 421_614; // Arbitrum Sepolia chain ID

    function run() external {
        require(chainId == block.chainid, "chainId does not match the chainId in config");
        (address deployer,,,) = WalletLoader.loadWalletsFromEnv(vm);

        vm.startBroadcast(deployer);

        ArbitrumSepoliaDeployer.DeploymentResult memory result =
            ArbitrumSepoliaDeployer.deployAndSetupProtocol(deployer);

        vm.stopBroadcast();

        DeploymentUtils.exportDeployment(
            vm,
            "arbitrum_sepolia_collar_protocol_deployment",
            address(result.configHub),
            ArbitrumSepoliaDeployer.swapRouterAddress,
            result.assetPairContracts
        );
        console.log("\nDeployment completed successfully");
    }
}
