// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import { DeploymentArtifactsLib } from "../libraries/DeploymentArtifacts.sol";
import { BaseDeployer } from "../libraries/BaseDeployer.sol";
import { Const } from "../utils/Const.sol";

/**
 * This simulates the ownership acceptance for two use-cases:
 * - Creating a broadcast artifact that can be used to create the Safe batch.
 * - Simulating the above step in fork tests.
 *
 * To create the Safe batch using this:
 * 1. Run the script as dry-run (i.e. without --broadcast)
 * 2. Run jq transform on the script's output JSON ("Transactions saved to: .."):
 *    `jq -f script/utils/safe-batch-from-broadcast.jq <sim-JSON> | tee temp-safe-batch.json'
 * 3. Load `temp-safe-batch.json` in Safe > Transaction Builder > choose a file
 * 4. Verify, simulate, inspect tenderly, create, inspect, and submit for signers to verify.
 */
abstract contract AcceptOwnershipScript is Script {
    address public owner;
    string public defaultArtifactsName;

    // default run() as script
    function run() external {
        run("");
    }

    /// @param artifactsName loads the deployment to accept ownership for
    function run(string memory artifactsName) public {
        setParams();

        // this is hardcoded to the owner:
        // - in script usage this simulates and saves the txs batch to be imported
        // into the Safe
        // - in test usage this works as a prank for simulating the safe executing it
        vm.startBroadcast(owner);

        // artifact name if not given (should only be specified in tests)
        if (bytes(artifactsName).length == 0) {
            artifactsName = defaultArtifactsName;
        }
        // load the deployment artifacts
        BaseDeployer.DeploymentResult memory result;
        (result.configHub, result.assetPairContracts) =
            DeploymentArtifactsLib.loadHubAndAllPairs(vm, artifactsName);

        // deploy and nominate owner
        BaseDeployer.acceptOwnershipAsSender(owner, result.configHub);

        vm.stopBroadcast();
    }

    function setParams() internal virtual;
}

contract AcceptOwnershipOPBaseMainnet is AcceptOwnershipScript {
    function setParams() internal override {
        owner = Const.OPBaseMain_owner;
        defaultArtifactsName = Const.OPBaseMain_artifactsName;
    }
}

contract AcceptOwnershipOPBaseSepolia is AcceptOwnershipScript {
    function setParams() internal override {
        owner = Const.OPBaseSep_owner;
        defaultArtifactsName = Const.OPBaseSep_artifactsName;
    }
}

contract AcceptOwnershipArbiMainnet is AcceptOwnershipScript {
    function setParams() internal override {
        owner = Const.ArbiMain_owner;
        defaultArtifactsName = Const.ArbiMain_artifactsName;
    }
}

contract AcceptOwnershipArbiSepolia is AcceptOwnershipScript {
    function setParams() internal override {
        owner = Const.ArbiSep_owner;
        defaultArtifactsName = Const.ArbiSep_artifactsName;
    }
}
