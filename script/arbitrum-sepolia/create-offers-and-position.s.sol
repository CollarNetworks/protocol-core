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
        // _createOffers(liquidityProvider, pair);
        vm.stopBroadcast();

        console.log("\nOffers created successfully");

        vm.startBroadcast(user);
        (uint takerId, uint providerId, uint loanAmount) = _openUserPosition(pair);
        vm.stopBroadcast();

        console.log("\nUser position opened successfully");
        console.log(" - Taker ID: %d", takerId);
        console.log(" - Provider ID: %d", providerId);
        console.log(" - Loan Amount: %d", loanAmount);

        vm.startBroadcast(liquidityProvider);
        uint rollOfferId = _createRollOffer(pair, takerId, providerId);
        vm.stopBroadcast();

        console.log("Roll offer created successfully with id: %d", rollOfferId);
    }

    function _fundLiquidityProvider(address liquidityProvider) internal {
        cashAsset.mint(liquidityProvider, cashAmountPerOffer * expectedOfferCount * 2);
    }

    function _fundUser(address user) internal {
        collateralAsset.mint(user, collateralAmountForLoan * 2);
    }

    function _createOffers(address liquidityProvider, AssetPairContracts memory pair) internal {
        pair.cashAsset.approve(address(pair.providerNFT), type(uint).max);

        for (uint i = 0; i < callStrikeTicks.length; i++) {
            uint offerId = pair.providerNFT.createOffer(
                callStrikeTicks[i], cashAmountPerOffer, pair.ltvs[0], pair.durations[0]
            );
            ProviderPositionNFT.LiquidityOffer memory offer = pair.providerNFT.getOffer(offerId);
            require(offer.provider == liquidityProvider, "Incorrect offer provider");
            require(offer.available == cashAmountPerOffer, "Incorrect offer amount");
            require(offer.putStrikeDeviation == ltv, "Incorrect LTV");
            require(offer.duration == duration, "Incorrect duration");
            require(offer.callStrikeDeviation == callStrikeTicks[i], "Incorrect call strike deviation");
            console.log("Offer created successfully : ", offerId);
        }

        console.log("Total offers created: %d", callStrikeTicks.length);
    }

    function _openUserPosition(AssetPairContracts memory pair)
        internal
        returns (uint takerId, uint providerId, uint loanAmount)
    {
        pair.collateralAsset.approve(address(pair.loansContract), type(uint).max);

        uint offerId = 0;
        require(offerId < pair.providerNFT.nextOfferId(), "No available offers");

        (takerId, providerId, loanAmount) = pair.loansContract.createLoan(
            collateralAmountForLoan,
            0, // minLoanAmount (no slippage protection)
            0, // minSwapCash (no slippage protection)
            pair.providerNFT,
            offerId
        );
    }

    function _createRollOffer(AssetPairContracts memory pair, uint loanId, uint providerId)
        internal
        returns (uint rollOfferId)
    {
        uint currentPrice = pair.takerNFT.getReferenceTWAPPrice(block.timestamp);
        pair.cashAsset.approve(address(pair.rollsContract), type(uint).max);
        pair.providerNFT.approve(address(pair.rollsContract), providerId);
        rollOfferId = pair.rollsContract.createRollOffer(
            loanId,
            rollFee,
            rollDeltaFactor,
            currentPrice * 90 / 100,
            currentPrice * 110 / 100,
            0,
            block.timestamp + 7 * 24 hours
        );
    }
}
