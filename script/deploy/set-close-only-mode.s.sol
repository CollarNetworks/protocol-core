// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import { DeploymentArtifactsLib } from "../libraries/DeploymentArtifacts.sol";
import { BaseDeployer, ConfigHub } from "../libraries/BaseDeployer.sol";
import { Const } from "../utils/Const.sol";

/**
 * This simulates set close-only mode (i.e. disabling opening positions) on an outdated deployment from owner for:
 * - Creating a broadcast artifact that can be used to create the Safe batch.
 * - Simulating the above step in fork tests
 *
 * To create the Safe batch using this:
 * 1. Run the script as dry-run (i.e. without --broadcast)
 * 2. Run jq transform on the script's output JSON ("Transactions saved to: .."):
 *    `jq -f script/utils/safe-batch-from-broadcast.jq <sim-JSON> | tee temp-safe-batch.json'
 * 3. Load `temp-safe-batch.json` in Safe > Transaction Builder > choose a file
 * 4. Verify, simulate, inspect tenderly, create, inspect, and submit for signers to verify.
 */
abstract contract SetCloseOnlyModeScript is Script {
    address public owner;
    string public artifactsName;

    function run() external {
        setParams();

        // this is hardcoded to the owner:
        // - in script usage this simulates and saves the txs batch to be imported
        // into the Safe
        // - in test usage this works as a prank for simulating the safe executing it
        vm.startBroadcast(owner);

        // load the deployment artifacts
        BaseDeployer.DeploymentResult memory deployment;
        (deployment.configHub, deployment.assetPairContracts) =
            DeploymentArtifactsLib.loadHubAndAllPairs(vm, artifactsName);

        for (uint i = 0; i < deployment.assetPairContracts.length; i++) {
            BaseDeployer.disableContractPair(deployment.configHub, deployment.assetPairContracts[i]);
        }

        vm.stopBroadcast();

        // @dev this only happens in simulation (when broadcast txs are being collected), so this validates
        // vs the simulated state (fake, local) - while the actual onchain state is still different (would not pass).
        // The actual state will be changed if and when the transactions are actually executed (and succeed).
        validateCloseOnlyMode(deployment);
    }

    function setParams() internal virtual;

    function validateCloseOnlyMode(BaseDeployer.DeploymentResult memory deployment) internal view {
        // this can be done in fork tests too, but it makes sense to validate what's easy here
        for (uint i = 0; i < deployment.assetPairContracts.length; i++) {
            BaseDeployer.AssetPairContracts memory pair = deployment.assetPairContracts[i];

            // we do NOT want to disable swappers, since closing should be possible
            require(pair.loansContract.allAllowedSwappers().length != 0, "Loans allAllowedSwappers is empty");

            // check all canOpenPair auth tuples for pair are empty
            ConfigHub hub = deployment.configHub;
            address[] memory arr = hub.allCanOpenPair(address(pair.underlying), address(pair.cashAsset));
            require(arr.length == 0, "ConfigHub's allCanOpenPair not empty for pair");

            // checking the above for a pair should be sufficient to ensure no positions can be opened,
            // but we can check more combinations here, so why not
            arr = hub.allCanOpenPair(address(pair.cashAsset), address(pair.underlying));
            require(arr.length == 0, "ConfigHub's allCanOpenPair not empty for pair (reverse)");

            arr = hub.allCanOpenPair(address(pair.underlying), deployment.configHub.ANY_ASSET());
            require(arr.length == 0, "ConfigHub's allCanOpenPair not empty for underlying & ANY");

            arr = hub.allCanOpenPair(address(pair.cashAsset), deployment.configHub.ANY_ASSET());
            require(arr.length == 0, "ConfigHub's allCanOpenPair not empty for cashAsset & ANY");

            arr = hub.allCanOpenPair(address(pair.underlying), address(pair.escrowNFT));
            require(arr.length == 0, "ConfigHub's allCanOpenPair not empty for underlying & escrow");
        }
    }
}

contract SetCloseOnlyModeOPBaseMainnet is SetCloseOnlyModeScript {
    function setParams() internal override {
        owner = Const.OPBaseMain_owner;
        artifactsName = string.concat("DEPRECATED-", Const.OPBaseMain_artifactsName);
    }
}

contract SetCloseOnlyModeOPBaseSepolia is SetCloseOnlyModeScript {
    function setParams() internal override {
        owner = Const.OPBaseSep_owner;
        artifactsName = string.concat("DEPRECATED-", Const.OPBaseSep_artifactsName);
    }
}
