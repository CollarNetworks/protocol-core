// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import { DeploymentArtifactsLib } from "../utils/DeploymentArtifacts.sol";
import { WalletLoader } from "../wallet-loader.s.sol";
import { ArbitrumSepoliaDeployer, BaseDeployer } from "../ArbitrumSepoliaDeployer.sol";

contract DeployContractsArbitrumSepolia is Script {
    function run() external {
        (address deployerAddress,,,) = WalletLoader.loadWalletsFromEnv(vm);
        vm.startBroadcast(deployerAddress);

        BaseDeployer deployerContract = new ArbitrumSepoliaDeployer();
        require(deployerContract.chainId() == block.chainid, "chainId mismatch");
        BaseDeployer.DeploymentResult memory result =
            deployerContract.deployAndSetupFullProtocol(deployerAddress);

        vm.stopBroadcast();

        DeploymentArtifactsLib.exportDeployment(
            vm,
            "arbitrum_sepolia_collar_protocol_deployment",
            address(result.configHub),
            result.assetPairContracts
        );
        console.log("\nDeployment completed successfully");
    }
}
