// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import { ArbitrumMainnetDeployer } from "../../../script/ArbitrumMainnetDeployer.sol";
import { DeploymentUtils } from "../../../script/utils/deployment-exporter.s.sol";
/**
 * this is a base contract for fork test contracts to inherit in order to be able to be ran independently as well as through another contract that sets up the fork
 */

contract ArbitrumMainnetBaseIndependentForkTestContract is Test, ArbitrumMainnetDeployer {
    uint private forkId;
    bool private forkSet;

    function setUp() public virtual {
        if (!forkSet) {
            // this test suite needs to run independently so we load a fork here
            forkId = vm.createFork(vm.envString("ARBITRUM_MAINNET_RPC"));
            vm.selectFork(forkId);

            // Deploy contracts
            DeploymentResult memory result = deployAndSetupProtocol(address(this));
            DeploymentUtils.exportDeployment(
                vm,
                "collar_protocol_deployment",
                address(result.configHub),
                swapRouterAddress,
                result.assetPairContracts
            );
            forkSet = true;
        } else {
            vm.selectFork(forkId);
        }
    }

    function setForkId(uint _forkId) public {
        forkId = _forkId;
        forkSet = true;
    }
}
