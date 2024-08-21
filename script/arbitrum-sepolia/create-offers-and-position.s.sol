// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import { ConfigHub } from "../../src/ConfigHub.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { DeploymentUtils } from "../utils/deployment-exporter.s.sol";
import { ProviderPositionNFT } from "../../src/ProviderPositionNFT.sol";
import { CollarTakerNFT } from "../../src/CollarTakerNFT.sol";
import { Loans } from "../../src/Loans.sol";
import { Rolls } from "../../src/Rolls.sol";
import { BaseDeployment } from "../base.s.sol";
import { CollarOwnedERC20 } from "../../test/utils/CollarOwnedERC20.sol";

contract CreateOffersAndOpenPosition is Script, DeploymentUtils, BaseDeployment {
    uint cashAmountPerOffer = 1_000_000 ether;
    uint collateralAmountForLoan = 1 ether;
    uint expectedOfferCount = 4;
    CollarOwnedERC20 constant cashAsset = CollarOwnedERC20(0x5D01F1E59C188a2A9Afc376cF6627dd5F28DC28F);
    CollarOwnedERC20 constant collateralAsset = CollarOwnedERC20(0x9A6E1a5f94De0aD8ca15b55eA0d39bEaEc579434);
    int rollFee = 100 ether;
    int rollDeltaFactor = 10_000;
    uint duration = 300;
    uint ltv = 9000;

    function run() external {
        (address deployer, address user,, address liquidityProvider) = setup();

        if (configHub == ConfigHub(address(0))) {
            configHub = ConfigHub(getConfigHub());
        }

        AssetPairContracts memory pair = getByAssetPair(address(cashAsset), address(collateralAsset));
        vm.startBroadcast(deployer);

        _fundLiquidityProvider(liquidityProvider);
        _fundUser(liquidityProvider);
        vm.stopBroadcast();
        vm.startBroadcast(liquidityProvider);
        _createOffersForPair(liquidityProvider, pair, cashAmountPerOffer);
        vm.stopBroadcast();
        console.log("\nOffers created successfully");

        vm.startBroadcast(user);
        uint offerId = 0;
        (uint takerId, uint providerId, uint loanAmount) =
            _openUserPosition(user, liquidityProvider, pair, collateralAmountForLoan, offerId);
        vm.stopBroadcast();

        console.log("\nUser position opened successfully");
        console.log(" - Taker ID: %d", takerId);
        console.log(" - Provider ID: %d", providerId);
        console.log(" - Loan Amount: %d", loanAmount);

        vm.startBroadcast(liquidityProvider);
        uint rollOfferId = _createRollOffer(pair, takerId, providerId, rollFee, rollDeltaFactor);
        vm.stopBroadcast();

        console.log("Roll offer created successfully with id: %d", rollOfferId);
    }

    function _fundLiquidityProvider(address liquidityProvider) internal {
        cashAsset.mint(liquidityProvider, cashAmountPerOffer * expectedOfferCount * 2);
    }

    function _fundUser(address user) internal {
        collateralAsset.mint(user, collateralAmountForLoan * 2);
    }
}
