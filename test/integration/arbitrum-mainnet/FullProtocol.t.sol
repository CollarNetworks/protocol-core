// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "forge-std/Test.sol";
import { ArbitrumMainnetDeployer, BaseDeployer } from "../../../script/ArbitrumMainnetDeployer.sol";
import { DeploymentArtifactsLib } from "../../../script/utils/DeploymentArtifacts.sol";
import "./DeploymentValidation.t.sol";
import "./Loans.fork.t.sol";

contract ArbitrumMainnetFullProtocolForkTest is Test {
    uint forkId;
    bool forkSet;
    BaseDeployer deployer;

    function setUp() public {
        // Setup fork,
        /// @dev this code is copied from deployment loader, but necessary because we want all tests in this contract to run on
        /// the same deployment so we force fork selection to bypass them deploying independently
        if (!forkSet) {
            forkId = vm.createFork(vm.envString("ARBITRUM_MAINNET_RPC"));
            vm.selectFork(forkId);
            // Deploy contracts
            deployer = new ArbitrumMainnetDeployer();
            uint deployerPrivKey = vm.envUint("PRIVKEY_DEV_DEPLOYER");
            address owner = vm.addr(deployerPrivKey);
            vm.startPrank(owner);
            BaseDeployer.DeploymentResult memory result = deployer.deployAndSetupFullProtocol(owner);
            DeploymentArtifactsLib.exportDeployment(
                vm, "collar_protocol_fork_deployment", address(result.configHub), result.assetPairContracts
            );
            forkSet = true;
            vm.stopPrank();
        } else {
            vm.selectFork(forkId);
        }
    }

    function setupLoansForkTest() internal returns (WETHUSDCLoansForkTest loansTest) {
        // need to select fork and fund wallets since loans test suite creates a fork
        // (cause it should run independently) we need to make sure its running in the one from this contract
        vm.selectFork(forkId);
        loansTest = new WETHUSDCLoansForkTest();
        loansTest.setForkId(forkId);
        loansTest.setUp();
    }

    function testDeploymentValidation() public {
        vm.selectFork(forkId);
        DeploymentValidatorForkTest validator = new DeploymentValidatorForkTest();
        validator.setForkId(forkId);
        validator.setUp();
        validator.test_validateConfigHubDeployment();
        validator.test_validatePairDeployments();
    }

    function testFullIntegration() public {
        WETHUSDCLoansForkTest loansTest = setupLoansForkTest();
        console.log("Running full integration test...");
        // Run all integration tests
        loansTest.testOpenAndCloseLoan();
        loansTest.testRollLoan();
        loansTest.testFullLoanLifecycle();

        console.log("Full integration test complete");
    }

    function testEscrowLoans() public {
        WETHUSDCLoansForkTest loansTest = setupLoansForkTest();
        loansTest.testOpenEscrowLoan();
        loansTest.testOpenAndCloseEscrowLoan();
        loansTest.testCloseEscrowLoanAfterGracePeriod();
        loansTest.testSeizeEscrowAndUnwrapLoan();
        loansTest.testCloseEscrowLoanWithPartialLateFees();
        loansTest.testRollEscrowLoanBetweenSuppliers();
    }
}
