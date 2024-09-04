// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "forge-std/Test.sol";
import "../../../script/arbitrum-mainnet/deploy-contracts.s.sol";
import "./validation.t.sol";
import "./Loans.fork.t.sol";

contract ArbitrumMainnetFullProtocolForkTest is Test {
    uint forkId;
    DeployContractsArbitrumMainnet deployer;

    function setUp() public {
        // Setup fork

        console.log("Setting up ArbitrumMainnetForkTest forkId: ", forkId);
        if (forkId == 0) {
            forkId = vm.createFork(vm.envString("ARBITRUM_MAINNET_RPC"));
            vm.selectFork(forkId);
            // Deploy contracts
            deployer = new DeployContractsArbitrumMainnet();
            deployer.run();
        } else {
            vm.selectFork(forkId);
        }
        console.log("ArbitrumMainnetForkTest setup complete");
    }

    function testDeploymentValidation() public {
        vm.selectFork(forkId);
        DeploymentValidator validator = new DeploymentValidator();
        validator.setForkId(forkId);
        validator.setUp();
        validator.test_validateConfigHubDeployment();
        validator.test_validatePairDeployments();
    }

    function testFullIntegration() public {
        // need to select fork and fund wallets since loans test suite creates a fork (cause it should run independently) we need to make sure its running in the one from  this contract
        vm.selectFork(forkId);
        LoansForkTest loansTest = new LoansForkTest();
        loansTest.setForkId(forkId);
        loansTest.setUp();
        console.log("Running full integration test...");
        // Run all integration tests
        loansTest.testOpenAndCloseLoan();
        loansTest.testRollLoan();
        loansTest.testFullLoanLifecycle();
        console.log("Full integration test complete");
    }
}
