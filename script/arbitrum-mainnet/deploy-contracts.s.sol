// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import { DeploymentArtifactsLib } from "../utils/DeploymentArtifacts.sol";
import { WalletLoader } from "../wallet-loader.s.sol";

import { ArbitrumMainnetDeployer as deployerLib, BaseDeployer, Const } from "../ArbitrumMainnetDeployer.sol";

contract DeployContractsArbitrumMainnet is Script {
    function run() external {
        (address deployerAddress,,,) = WalletLoader.loadWalletsFromEnv(vm);
        vm.startBroadcast(deployerAddress);

        // TODO: use the real owner instead of the deployer
        address owner = deployerAddress;

        // check we're on the right chain
        require(block.chainid == Const.ArbiMain_chainId, "chainId mismatch");

        // deploy and nominate owner
        BaseDeployer.DeploymentResult memory result = deployerLib.deployAndSetupFullProtocol(owner);

        // accept ownership from the owner
        BaseDeployer.acceptOwnershipAsSender(owner, result);

        vm.stopBroadcast();

        DeploymentArtifactsLib.exportDeployment(
            vm, Const.ArbiMain_artifactsKey, result.configHub, result.assetPairContracts
        );
        console.log("\nDeployment completed successfully");
    }
}
