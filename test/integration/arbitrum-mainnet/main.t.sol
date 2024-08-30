// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "../../../script/arbitrum-mainnet/deploy-contracts.s.sol";
import "./validation.t.sol";
import "../Loans.fork.t.sol";

contract ArbitrumMainnetForkTest is LoansForkTest {
    uint forkId;
    DeployContracts deployer;
    DeploymentValidator validator;

    function setUp() public override {
        // Setup fork
        forkId = vm.createFork(vm.envString("ARBITRUM_MAINNET_RPC"));
        vm.selectFork(forkId);

        // Deploy contracts
        deployer = new DeployContracts();
        deployer.run();

        // Run validations
        validator = new DeploymentValidator();
        validator.setUp();

        // Call LoansForkTest setUp
        super.setUp();
        console.log("ArbitrumMainnetForkTest setup complete");
    }

    function testDeploymentValidation() public {
        vm.selectFork(forkId);
        validator.test_validateConfigHubDeployment();
        validator.test_validatePairDeployments();
    }

    function testFullIntegration() public {
        // need to select fork and fund wallets since loans test suite creates a fork (cause it should run independently) we need to make sure its running in the one from  this contract
        vm.selectFork(forkId);
        _fundWallets();
        console.log("Running full integration test...");
        // Run all integration tests
        uint providerCashassetBalance = IERC20(cashAsset).balanceOf(provider);
        uint userCashassetBalance = IERC20(cashAsset).balanceOf(user);
        console.log("Provider cash asset balance: %s", providerCashassetBalance);
        console.log("User cash asset balance: %s", userCashassetBalance);
        testOpenAndCloseLoan();
        testRollLoan();
        testFullLoanLifecycle();

        console.log("Full integration test complete");
    }
}
