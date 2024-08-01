// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import { ConfigHub } from "../../src/implementations/ConfigHub.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { DeploymentUtils } from "../utils/deployment-exporter.s.sol";
import { ProviderPositionNFT } from "../../src/ProviderPositionNFT.sol";
import { CollarTakerNFT } from "../../src/CollarTakerNFT.sol";
import { Loans } from "../../src/Loans.sol";
import { Rolls } from "../../src/Rolls.sol";
import { BaseDeployment } from "../base.s.sol";

contract CreateOffersAndOpenPosition is Script, DeploymentUtils, BaseDeployment {
    uint cashAmountPerOffer = 100_000e6;
    uint collateralAmountForLoan = 1 ether;
    uint expectedOfferCount = 44;
    address USDC = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
    address WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

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

        _createOffers(liquidityProvider, allPairs);

        console.log("\nOffers created successfully");

        _openUserPosition(user1, liquidityProvider, usdcWethPair);

        console.log("\nUser position opened successfully");
    }

    function _createOffers(address liquidityProvider, AssetPairContracts[] memory assetPairContracts)
        internal
    {
        vm.startBroadcast(liquidityProvider);

        uint totalOffers = 0;
        /**
         * @dev Create offers for all contract pairs with all durations and LTVs , they're not all equal so they depend on the contract pair ltv and duration combo
         */
        for (uint i = 0; i < assetPairContracts.length; i++) {
            AssetPairContracts memory pair = assetPairContracts[i];
            pair.cashAsset.approve(address(pair.providerNFT), type(uint).max);

            for (uint j = 0; j < pair.durations.length; j++) {
                for (uint k = 0; k < pair.ltvs.length; k++) {
                    for (uint l = 0; l < callStrikeTicks.length; l++) {
                        console.log("test", pair.providerNFT.symbol());
                        uint offerId = pair.providerNFT.createOffer(
                            callStrikeTicks[l], cashAmountPerOffer, pair.ltvs[k], pair.durations[j]
                        );
                        ProviderPositionNFT.LiquidityOffer memory offer = pair.providerNFT.getOffer(offerId);
                        require(
                            offer.provider == liquidityProvider, "Offer not created for liquidity provider"
                        );
                        require(offer.available == cashAmountPerOffer, "Incorrect offer amount");
                        require(offer.putStrikeDeviation == pair.ltvs[k], "Incorrect LTV");
                        require(offer.duration == pair.durations[j], "Incorrect duration");
                        require(
                            offer.callStrikeDeviation == callStrikeTicks[l], "Incorrect call strike deviation"
                        );
                        totalOffers++;
                    }
                }
            }
        }

        vm.stopBroadcast();
        console.log("Total offers created: ", totalOffers);
    }

    function _openUserPosition(address user, address liquidityProvider, AssetPairContracts memory pair)
        internal
    {
        vm.startBroadcast(user);
        // Use the first contract pair (USDC/WETH) for this example
        uint userCollateralBalance = pair.collateralAsset.balanceOf(user);
        require(userCollateralBalance >= collateralAmountForLoan, "User does not have enough collateral");
        // Approve collateral spending
        pair.collateralAsset.approve(address(pair.loansContract), type(uint).max);

        // Find the first available offer
        uint offerId = 0;
        require(offerId < pair.providerNFT.nextOfferId(), "No available offers");
        // Check initial balances
        uint initialCollateralBalance = pair.collateralAsset.balanceOf(user);
        uint initialCashBalance = pair.cashAsset.balanceOf(user);

        // Get TWAP price before loan creation
        uint twapPrice = configHub.getHistoricalAssetPriceViaTWAP(
            address(pair.collateralAsset),
            address(pair.cashAsset),
            uint32(block.timestamp),
            pair.takerNFT.TWAP_LENGTH()
        );

        // Open a position
        (uint takerId, uint providerId, uint loanAmount) = pair.loansContract.createLoan(
            collateralAmountForLoan,
            0, // slippage
            0,
            pair.providerNFT,
            offerId
        );

        _checkPosition(
            pair,
            takerId,
            providerId,
            user,
            liquidityProvider,
            initialCollateralBalance,
            initialCashBalance,
            loanAmount,
            twapPrice
        );

        console.log("Position opened:");
        console.log(" - Taker ID: %d", takerId);
        console.log(" - Provider ID: %d", providerId);
        console.log(" - Loan amount: %d", loanAmount);

        vm.stopBroadcast();
    }

    function _checkPosition(
        AssetPairContracts memory pair,
        uint takerId,
        uint providerId,
        address user,
        address liquidityProvider,
        uint initialCollateralBalance,
        uint initialCashBalance,
        uint loanAmount,
        uint twapPrice
    ) internal view {
        CollarTakerNFT.TakerPosition memory position = pair.takerNFT.getPosition(takerId);
        require(position.settled == false);
        require(position.withdrawable == 0);
        require(position.putLockedCash > 0);
        require(position.callLockedCash > 0);

        require(pair.takerNFT.ownerOf(takerId) == user);
        require(pair.providerNFT.ownerOf(providerId) == liquidityProvider);

        // Check balance changes
        uint finalCollateralBalance = pair.collateralAsset.balanceOf(user);
        uint finalCashBalance = pair.cashAsset.balanceOf(user);

        assert(initialCollateralBalance - finalCollateralBalance == collateralAmountForLoan);
        assert(finalCashBalance - initialCashBalance == loanAmount);

        // Check loan amount using TWAP
        uint expectedLoanAmount = collateralAmountForLoan * twapPrice * pair.ltvs[0] / (1e18 * 10_000);
        uint loanAmountTolerance = expectedLoanAmount / 100; // 1% tolerance
        require(
            loanAmount >= expectedLoanAmount - loanAmountTolerance
                && loanAmount <= expectedLoanAmount + loanAmountTolerance,
            "Loan amount is outside the expected range"
        );
    }
}
