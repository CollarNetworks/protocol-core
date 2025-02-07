// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import { DeploymentArtifactsLib } from "../libraries/DeploymentArtifacts.sol";
import { BaseDeployer, Const } from "../libraries/OPBaseSepoliaDeployer.sol";

/**
 * This simulates the ownership acceptance for two use-cases:
 * - Creating a broadcast artifact that can be used to create the Safe batch.
 * - Simulating the above step in fork tests.
 *
 * To create the Safe batch using this:
 *     1. Run the script as dry-run (default)
 *     2. Use the script output JSON (saved in ./broadcast/<script-name> and run jq transform:
 *         ```
 *         jq -f script/utils/safe-batch-from-broadcast.jq \
 *             broadcast/AcceptOwnershipOPBaseSepolia.s.sol/84532/dry-run/run-latest.json \
 *             | tee temp-safe-batch.json
 *         ```
 *     3. Load `temp-safe-batch.json` in Safe > Transaction Builder > choose a file
 *     4. Verify, simulate, inspect tenderly, create, inspect, and submit for signers to verify.
 */
contract AcceptOwnershipOPBaseSepolia is Script {
    // default run() as script
    function run() external {
        run("");
    }

    /// run() that can be used for tests, or for scripts by specifying `"" --sig 'run(string)'`
    /// @param artifactsName loads the deployment to accept ownership for
    function run(string memory artifactsName) public {
        address owner = Const.OPBaseSep_owner;

        // this is hardcoded to the owner:
        // - in script usage this simulates and saves the txs batch to be imported
        // into the Safe
        // - in test usage this works as a prank for simulating the safe executing it
        vm.startBroadcast(owner);

        // artifact name if not given (should only be specified in tests)
        if (bytes(artifactsName).length == 0) {
            artifactsName = Const.OPBaseSep_artifactsName;
        }
        // load the deployment artifacts
        BaseDeployer.DeploymentResult memory result;
        (result.configHub, result.assetPairContracts) =
            DeploymentArtifactsLib.loadHubAndAllPairs(vm, artifactsName);

        // deploy and nominate owner
        BaseDeployer.acceptOwnershipAsSender(owner, result.configHub, result.assetPairContracts);

        vm.stopBroadcast();
    }
}
