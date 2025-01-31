// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import { DeploymentArtifactsLib } from "../libraries/DeploymentArtifacts.sol";
import { WalletLoader } from "../wallet-loader.s.sol";

import { OPBaseMainnetDeployer, BaseDeployer, Const } from "../libraries/OPBaseMainnetDeployer.sol";

contract DeployOPBaseMainnet is Script {
    // default run() as script
    function run() external {
        run("");
    }

    /// run() that can be used for tests, or for scripts by specifying `"" --sig 'run(string)'`
    /// @param artifactsName overrides the default artifacts name when used in tests
    function run(string memory artifactsName) public returns (BaseDeployer.DeploymentResult memory result) {
        // note: when in tests, this also has the effect of "pranking" msg.sender
        vm.startBroadcast(msg.sender);

        // deploy and nominate owner
        result = OPBaseMainnetDeployer.deployAndSetupFullProtocol(msg.sender, Const.OPBaseMain_owner);

        // artifact name if not given (should only be specified in tests)
        if (bytes(artifactsName).length == 0) {
            artifactsName = Const.OPBaseMain_artifactsName;
        }
        // save the deployment artifacts
        DeploymentArtifactsLib.exportDeployment(vm, artifactsName, result);

        vm.stopBroadcast();
    }
}
