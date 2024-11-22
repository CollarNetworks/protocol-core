// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import { DeploymentUtils } from "../utils/deployment-exporter.s.sol";
import { WalletLoader } from "../wallet-loader.s.sol";
import { ArbitrumSepoliaDeployer } from "../ArbitrumSepoliaDeployer.sol";

contract DeployContractsArbitrumSepolia is Script, ArbitrumSepoliaDeployer {
    function run() external {
        require(chainId == block.chainid, "chainId does not match the chainId in config");
        (address deployer,,,) = WalletLoader.loadWalletsFromEnv(vm);

        vm.startBroadcast(deployer);

        DeploymentResult memory result = deployAndSetupProtocol(deployer);

        vm.stopBroadcast();

        DeploymentUtils.exportDeployment(
            vm,
            "arbitrum_sepolia_collar_protocol_deployment",
            address(result.configHub),
            swapRouterAddress,
            result.assetPairContracts
        );
        console.log("\nDeployment completed successfully");
    }
}
