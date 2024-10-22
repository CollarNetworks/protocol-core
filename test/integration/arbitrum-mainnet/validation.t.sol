// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "forge-std/Test.sol";
import "../utils/DeploymentLoader.sol";
import { ArbitrumMainnetDeployer } from "../../../script/arbitrum-mainnet/deployer.sol";
import { DeploymentUtils } from "../../../script/utils/deployment-exporter.s.sol";

contract DeploymentValidatorForkTest is Test, DeploymentLoader {
    function setUp() public override {
        super.setUp();
    }

    function setForkId(uint _forkId) public {
        forkId = _forkId;
        forkSet = true;
    }

    function test_validateConfigHubDeployment() public view {
        assertEq(address(configHub) != address(0), true);

        // Add more ConfigHub validations here
        assertEq(configHub.owner(), owner);
    }

    function test_validatePairDeployments() public view {
        for (uint i = 0; i < deployedPairs.length; i++) {
            DeploymentHelper.AssetPairContracts memory pair = deployedPairs[i];

            assertEq(address(pair.providerNFT) != address(0), true);
            assertEq(address(pair.takerNFT) != address(0), true);
            assertEq(address(pair.loansContract) != address(0), true);
            assertEq(address(pair.rollsContract) != address(0), true);

            assertEq(configHub.canOpen(address(pair.takerNFT)), true);
            assertEq(configHub.canOpen(address(pair.providerNFT)), true);
            assertEq(configHub.isSupportedCashAsset(address(pair.cashAsset)), true);
            assertEq(configHub.isSupportedUnderlying(address(pair.underlying)), true);

            for (uint j = 0; j < pair.durations.length; j++) {
                assertEq(configHub.isValidCollarDuration(pair.durations[j]), true);
            }

            for (uint j = 0; j < pair.ltvs.length; j++) {
                assertEq(configHub.isValidLTV(pair.ltvs[j]), true);
            }

            assertEq(address(pair.loansContract.currentRolls()) == address(pair.rollsContract), true);
            assertEq(address(pair.rollsContract.takerNFT()) == address(pair.takerNFT), true);
        }
    }
}
