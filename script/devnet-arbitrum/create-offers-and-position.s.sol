// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import { ConfigHub } from "../../src/ConfigHub.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { DeploymentUtils } from "../utils/deployment-exporter.s.sol";
import { ShortProviderNFT } from "../../src/ShortProviderNFT.sol";
import { CollarTakerNFT } from "../../src/CollarTakerNFT.sol";
import { Loans } from "../../src/Loans.sol";
import { Rolls } from "../../src/Rolls.sol";
import { BaseDeployment } from "../BaseDeployment.s.sol";

contract CreateOffersAndOpenPosition is Script, DeploymentUtils, BaseDeployment {
    uint cashAmountPerOffer = 100_000e6;
    uint collateralAmountForLoan = 1 ether;
    uint expectedOfferCount = 44;
    address USDC = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
    address WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    int rollFee = 100e6;
    int rollDeltaFactor = 10_000;

    function run() external {
        (, address user1,, address liquidityProvider) = setup();

        // Load deployed contract addresses
        if (configHub == ConfigHub(address(0))) {
            configHub = ConfigHub(getConfigHub());
        }

        AssetPairContracts[] memory allPairs = getAll();
        AssetPairContracts memory usdcWethPair = getByAssetPair(USDC, WETH);

        require(liquidityProvider != address(0), "liquidity provider address not set");
        require(liquidityProvider.balance > 1000, "liquidity provider address not funded");

        uint lpBalance = usdcWethPair.cashAsset.balanceOf(liquidityProvider);
        require(
            lpBalance >= cashAmountPerOffer * expectedOfferCount,
            "liquidity provider does not have enough funds"
        );
        vm.startBroadcast(liquidityProvider);
        _createOffers(liquidityProvider, allPairs);
        vm.stopBroadcast();
        console.log("\nOffers created successfully");
        uint offerId = 0;
        vm.startBroadcast(user1);
        (uint takerId, uint providerId,) =
            _openUserPosition(user1, liquidityProvider, usdcWethPair, collateralAmountForLoan, offerId);
        vm.stopBroadcast();
        console.log("\nUser position opened successfully");
        console.log(" - Taker ID: %d", takerId);
        console.log(" - Provider ID: %d", providerId);

        vm.startBroadcast(liquidityProvider);
        uint rollOfferId = _createRollOffer(usdcWethPair, takerId, providerId, rollFee, rollDeltaFactor);
        vm.stopBroadcast();
        console.log("roll offer created successfully with id: %d", rollOfferId);
    }

    function _createOffers(address liquidityProvider, AssetPairContracts[] memory assetPairContracts)
        internal
    {
        vm.startBroadcast(liquidityProvider);

        /**
         * @dev Create offers for all contract pairs with all durations and LTVs , they're not all equal so they depend on the contract pair ltv and duration combo
         */
        for (uint i = 0; i < assetPairContracts.length; i++) {
            AssetPairContracts memory pair = assetPairContracts[i];
            pair.cashAsset.approve(address(pair.providerNFT), type(uint).max);
            _createOffersForPair(liquidityProvider, pair, cashAmountPerOffer);
        }

        vm.stopBroadcast();
    }
}
