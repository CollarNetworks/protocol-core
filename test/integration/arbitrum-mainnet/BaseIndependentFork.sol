// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import { DeployContractsArbitrumMainnet } from "../../../script/arbitrum-mainnet/deploy-contracts.s.sol";

/**
 * this is a base contract for fork test contracts to inherit in order to be able to be ran independently as well as through another contract that sets up the fork
 */
contract ArbitrumMainnetBaseIndependentForkTestContract is Test {
    uint private forkId;
    bool private forkSet;

    function setUp() public virtual {
        if (!forkSet) {
            // this test suite needs to run independently so we load a fork here
            forkId = vm.createFork(vm.envString("ARBITRUM_MAINNET_RPC"));
            vm.selectFork(forkId);
            // Deploy contracts
            DeployContractsArbitrumMainnet deployer = new DeployContractsArbitrumMainnet();
            deployer.run();
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
