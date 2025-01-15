// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import { DeploymentArtifactsLib } from "../utils/DeploymentArtifacts.sol";
import { WalletLoader } from "../wallet-loader.s.sol";

import { ArbitrumSepoliaDeployer as deployerLib, BaseDeployer } from "../ArbitrumSepoliaDeployer.sol";

contract DeployContractsArbitrumSepolia is Script {
    function run() external {
        (address deployerAddress,,,) = WalletLoader.loadWalletsFromEnv(vm);
        vm.startBroadcast(deployerAddress);

        require(deployerLib.chainId == block.chainid, "chainId mismatch");
        BaseDeployer.DeploymentResult memory result = deployerLib.deployAndSetupFullProtocol(deployerAddress);

        vm.stopBroadcast();

        DeploymentArtifactsLib.exportDeployment(
            vm, "arbitrum_sepolia_collar_protocol_deployment", result.configHub, result.assetPairContracts
        );
        console.log("\nDeployment completed successfully");
    }
}
