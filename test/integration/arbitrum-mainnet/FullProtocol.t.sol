// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "forge-std/Test.sol";
import { ArbitrumMainnetDeployer } from "../../../script/arbitrum-mainnet/deployer.sol";
import { DeploymentUtils } from "../../../script/utils/deployment-exporter.s.sol";
import { DeploymentLoader } from "./DeploymentLoader.sol";
import "./validation.t.sol";
import "./Loans.fork.t.sol";

contract ArbitrumMainnetFullProtocolForkTest is Test {
    uint forkId;
    bool forkSet;

    function setUp() public {
        // Setup fork,
        /// @dev this code is copied from deployment loader, but necessary because we want all tests in this contract to run on
        /// the same deployment so we force fork selection to bypass them deploying independently
        if (!forkSet) {
            forkId = vm.createFork(vm.envString("ARBITRUM_MAINNET_RPC"));
            vm.selectFork(forkId);
            // Deploy contracts
            uint deployerPrivKey = vm.envUint("PRIVKEY_DEV_DEPLOYER");
            address owner = vm.addr(deployerPrivKey);
            vm.startPrank(owner);
            ArbitrumMainnetDeployer.DeploymentResult memory result =
                ArbitrumMainnetDeployer.deployAndSetupProtocol(owner);
            DeploymentUtils.exportDeployment(
                vm,
                "collar_protocol_fork_deployment",
                address(result.configHub),
                ArbitrumMainnetDeployer.swapRouterAddress,
                result.assetPairContracts
            );
            forkSet = true;
            vm.stopPrank();
        } else {
            vm.selectFork(forkId);
        }
    }

    function setupLoansForkTest() internal returns (USDCWETHForkTest loansTest) {
        // need to select fork and fund wallets since loans test suite creates a fork
        // (cause it should run independently) we need to make sure its running in the one from this contract
        vm.selectFork(forkId);
        loansTest = new USDCWETHForkTest();
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

    function testPriceMovementFlow_aboveCallStrike() public {
        setupLoansForkTest().testSettlementPriceAboveCallStrike();
    }

    function testPriceMovementFlow_belowPutStrike() public {
        setupLoansForkTest().testSettlementPriceBelowPutStrike();
    }

    function testPriceMovementFlow_upBetweenStrikes() public {
        setupLoansForkTest().testSettlementPriceUpBetweenStrikes();
    }

    function testFullIntegration() public {
        USDCWETHForkTest loansTest = setupLoansForkTest();
        console.log("Running full integration test...");
        // Run all integration tests
        loansTest.testOpenAndCloseLoan();
        loansTest.testRollLoan();
        loansTest.testFullLoanLifecycle();

        console.log("Full integration test complete");
    }

    function testEscrowLoans() public {
        USDCWETHForkTest loansTest = setupLoansForkTest();
        loansTest.testOpenEscrowLoan();
        loansTest.testOpenAndCloseEscrowLoan();
        loansTest.testCloseEscrowLoanAfterGracePeriod();
        loansTest.testCloseEscrowLoanWithPartialLateFees();
        loansTest.testRollEscrowLoanBetweenSuppliers();
    }
}
