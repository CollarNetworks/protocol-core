// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import { DeploymentUtils } from "../utils/deployment-exporter.s.sol";
import { WalletLoader } from "../wallet-loader.s.sol";
import { ArbitrumMainnetDeployer } from "./deployer.sol";

contract DeployContractsArbitrumMainnet is Script {
    function run() external {
        (address deployer,,,) = WalletLoader.loadWalletsFromEnv(vm);
        vm.startBroadcast(deployer);

        ArbitrumMainnetDeployer.DeploymentResult memory result =
            ArbitrumMainnetDeployer.deployAndSetupProtocol(deployer);

        vm.stopBroadcast();

        DeploymentUtils.exportDeployment(
            vm,
            "collar_protocol_deployment",
            address(result.configHub),
            ArbitrumMainnetDeployer.swapRouterAddress,
            result.assetPairContracts
        );
        console.log("\nDeployment completed successfully");
    }
}
