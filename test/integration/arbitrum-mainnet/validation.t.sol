// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "../utils/DeploymentLoader.sol";

contract DeploymentValidator is Test, DeploymentLoader {
    function setUp() public override {
        super.setUp();
    }

    function test_validateConfigHubDeployment() public view {
        assertEq(address(configHub) != address(0), true, "ConfigHub not deployed");

        // Add more ConfigHub validations here
        assertEq(configHub.owner(), owner, "ConfigHub owner not set correctly");
    }

    function test_validatePairDeployments() public view {
        for (uint i = 0; i < deployedPairs.length; i++) {
            DeploymentHelper.AssetPairContracts memory pair = deployedPairs[i];

            assertEq(address(pair.providerNFT) != address(0), true, "Provider NFT not created");
            assertEq(address(pair.takerNFT) != address(0), true, "Taker NFT not created");
            assertEq(address(pair.loansContract) != address(0), true, "Loans contract not created");
            assertEq(address(pair.rollsContract) != address(0), true, "Rolls contract not created");

            assertEq(configHub.takerNFTCanOpen(address(pair.takerNFT)), true, "TakerNFT not authorized");
            assertEq(
                configHub.providerNFTCanOpen(address(pair.providerNFT)), true, "ProviderNFT not authorized"
            );
            assertEq(
                configHub.isSupportedCashAsset(address(pair.cashAsset)), true, "Cash asset not supported"
            );
            assertEq(
                configHub.isSupportedCollateralAsset(address(pair.collateralAsset)),
                true,
                "Collateral asset not supported"
            );

            for (uint j = 0; j < pair.durations.length; j++) {
                assertEq(configHub.isValidCollarDuration(pair.durations[j]), true, "Duration not supported");
            }

            for (uint j = 0; j < pair.ltvs.length; j++) {
                assertEq(configHub.isValidLTV(pair.ltvs[j]), true, "LTV not supported");
            }

            assertEq(address(pair.loansContract.rollsContract()) == address(pair.rollsContract), true);
            assertEq(address(pair.rollsContract.takerNFT()) == address(pair.takerNFT), true);
        }
    }
}
