// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import { DeploymentArtifactsLib } from "../libraries/DeploymentArtifacts.sol";
import { WalletLoader } from "../wallet-loader.s.sol";

import { ArbitrumSepoliaDeployer, BaseDeployer, Const } from "../libraries/ArbitrumSepoliaDeployer.sol";

contract DeployArbitrumSepolia is Script {
    // default run() as script
    function run() external {
        run("");
    }

    /// run() that can be used for tests, or for scripts by specifying `"" --sig 'run(string)'`
    /// @param artifactsName overrides the default artifacts name when used in tests
    function run(string memory artifactsName) public returns (BaseDeployer.DeploymentResult memory result) {
        WalletLoader.loadWalletsFromEnv(vm);

        // note: when in tests, this also has the effect of "pranking" msg.sender
        vm.startBroadcast(msg.sender);

        // deploy and nominate owner
        result = ArbitrumSepoliaDeployer.deployAndSetupFullProtocol(msg.sender, Const.ArbiSep_owner);

        // artifact name if not given (should only be specified in tests)
        if (bytes(artifactsName).length == 0) {
            artifactsName = Const.ArbiSep_artifactsName;
        }
        // save the deployment artifacts
        DeploymentArtifactsLib.exportDeployment(vm, artifactsName, result);

        vm.stopBroadcast();
    }
}
