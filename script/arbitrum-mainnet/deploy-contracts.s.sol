// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import { DeploymentUtils } from "../utils/deployment-exporter.s.sol";
import { WalletLoader } from "../wallet-loader.s.sol";
import { ArbitrumMainnetDeployer } from "../ArbitrumMainnetDeployer.sol";

contract DeployContractsArbitrumMainnet is Script, ArbitrumMainnetDeployer {
    function run() external {
        (address deployerAddress,,,) = WalletLoader.loadWalletsFromEnv(vm);
        vm.startBroadcast(deployerAddress);

        DeploymentResult memory result = deployAndSetupProtocol(deployerAddress);

        vm.stopBroadcast();

        DeploymentUtils.exportDeployment(
            vm,
            "collar_protocol_deployment",
            address(result.configHub),
            swapRouterAddress,
            result.assetPairContracts
        );
        console.log("\nDeployment completed successfully");
    }
}
