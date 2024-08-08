// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import { ConfigHub } from "../src/ConfigHub.sol";
import { ProviderPositionNFT } from "../src/ProviderPositionNFT.sol";
import { CollarTakerNFT } from "../src/CollarTakerNFT.sol";
import { Loans } from "../src/Loans.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Rolls } from "../src/Rolls.sol";
import { DeploymentUtils } from "./utils/deployment-exporter.s.sol";
import { OracleUniV3TWAP } from "../src/OracleUniV3TWAP.sol";

contract BaseDeployment is Script {
    address router;
    ConfigHub configHub;
    address deployerAddress;

    struct AssetPairContracts {
        ProviderPositionNFT providerNFT;
        CollarTakerNFT takerNFT;
        Loans loansContract;
        Rolls rollsContract;
        IERC20 cashAsset;
        IERC20 collateralAsset;
        OracleUniV3TWAP oracle;
        uint[] durations;
        uint[] ltvs;
    }

    uint[] callStrikeTicks = [11_100, 11_200, 11_500, 12_000];

    uint24 constant FEE_TIER = 3000;
    uint32 constant TWAP_WINDOW = 15 minutes;

    function setup()
        internal
        returns (address deployer, address user1, address user2, address liquidityProvider)
    {
        VmSafe.Wallet memory deployerWallet = vm.createWallet(vm.envUint("PRIVKEY_DEV_DEPLOYER"));
        VmSafe.Wallet memory user1Wallet = vm.createWallet(vm.envUint("PRIVKEY_DEV_TEST1"));
        VmSafe.Wallet memory user2Wallet = vm.createWallet(vm.envUint("PRIVKEY_DEV_TEST2"));
        VmSafe.Wallet memory liquidityProviderWallet = vm.createWallet(vm.envUint("LIQUIDITY_PROVIDER_KEY"));

        vm.rememberKey(deployerWallet.privateKey);
        vm.rememberKey(user1Wallet.privateKey);
        vm.rememberKey(user2Wallet.privateKey);
        vm.rememberKey(liquidityProviderWallet.privateKey);

        console.log("\n # Dev Deployer Address: %x", deployerWallet.addr);
        console.log("\n # Dev Deployer Key:     %x", deployerWallet.privateKey);
        console.log("\n # Test Users\n");
        console.log(" - User 1 Address: %s", user1Wallet.addr);
        console.log(" - User 1 Privkey: %x", user1Wallet.privateKey);
        console.log(" - User 2 Address: %s", user2Wallet.addr);
        console.log(" - User 2 Privkey: %x", user2Wallet.privateKey);
        console.log(" - Liquidity provider Address: %s", liquidityProviderWallet.addr);
        console.log(" - Liquidity provider Privkey: %x", liquidityProviderWallet.privateKey);

        return (deployerWallet.addr, user1Wallet.addr, user2Wallet.addr, liquidityProviderWallet.addr);
    }

    function _createContractPair(
        IERC20 cashAsset,
        IERC20 collateralAsset,
        string memory pairName,
        uint[] memory durations,
        uint[] memory ltvs
    ) internal returns (AssetPairContracts memory contracts) {
        OracleUniV3TWAP oracle =
            new OracleUniV3TWAP(address(collateralAsset), address(cashAsset), FEE_TIER, TWAP_WINDOW, router);

        CollarTakerNFT takerNFT = new CollarTakerNFT(
            deployerAddress,
            configHub,
            cashAsset,
            collateralAsset,
            oracle,
            string(abi.encodePacked("Taker ", pairName)),
            string(abi.encodePacked("T", pairName))
        );
        ProviderPositionNFT providerNFT = new ProviderPositionNFT(
            deployerAddress,
            configHub,
            cashAsset,
            collateralAsset,
            address(takerNFT),
            string(abi.encodePacked("Provider ", pairName)),
            string(abi.encodePacked("P", pairName))
        );
        Loans loansContract = new Loans(deployerAddress, takerNFT);

        configHub.setCollarTakerContractAuth(address(takerNFT), true);
        configHub.setProviderContractAuth(address(providerNFT), true);
        Rolls rollsContract = new Rolls(deployerAddress, takerNFT);
        loansContract.setRollsContract(rollsContract);

        contracts = AssetPairContracts(
            providerNFT,
            takerNFT,
            loansContract,
            rollsContract,
            cashAsset,
            collateralAsset,
            oracle,
            durations,
            ltvs
        );
        require(address(contracts.providerNFT) != address(0), "Provider NFT not created");
        require(address(contracts.takerNFT) != address(0), "Taker NFT not created");
        require(address(contracts.loansContract) != address(0), "Loans contract not created");
        require(
            configHub.isProviderNFT(address(contracts.providerNFT)),
            "Provider NFT not authorized in configHub"
        );
        require(
            configHub.isCollarTakerNFT(address(contracts.takerNFT)), "Taker NFT not authorized in configHub"
        );
        require(address(contracts.rollsContract) != address(0), "Rolls contract not created");
        console.log(" - %s Taker NFT: %s", pairName, address(takerNFT));
        console.log(" - %s Provider NFT: %s", pairName, address(providerNFT));
        console.log(" - %s Loans Contract: %s", pairName, address(loansContract));
        console.log(" - %s Rolls Contract: %s", pairName, address(rollsContract));
    }

    function _deployandSetupConfigHub(
        address swapRouterAddress,
        address[] memory collateralAssets,
        address[] memory cashAssets,
        uint minLTV,
        uint maxLTV,
        uint minDuration,
        uint maxDuration
    ) internal {
        router = swapRouterAddress;
        configHub = new ConfigHub(deployerAddress);
        configHub.setUniV3Router(router);

        // add supported cash assets
        for (uint i = 0; i < cashAssets.length; i++) {
            configHub.setCashAssetSupport(cashAssets[i], true);
        }
        // add supported collateral assets
        for (uint i = 0; i < collateralAssets.length; i++) {
            configHub.setCollateralAssetSupport(collateralAssets[i], true);
        }
        configHub.setLTVRange(minLTV, maxLTV);
        configHub.setCollarDurationRange(minDuration, maxDuration);

        console.log("\n --- Dev Environment Deployed ---");
        console.log("\n # Contract Addresses\n");
        console.log(" - Router:  - - - - - - ", router);
        console.log(" - ConfigHub - - - - - - - ", address(configHub));
    }

    function _createOffersForPair(
        address liquidityProvider,
        BaseDeployment.AssetPairContracts memory pair,
        uint cashAmountPerOffer
    ) internal {
        pair.cashAsset.approve(address(pair.providerNFT), type(uint).max);

        for (uint j = 0; j < pair.durations.length; j++) {
            for (uint k = 0; k < pair.ltvs.length; k++) {
                for (uint l = 0; l < callStrikeTicks.length; l++) {
                    console.log("test", pair.providerNFT.symbol());
                    uint offerId = pair.providerNFT.createOffer(
                        callStrikeTicks[l], cashAmountPerOffer, pair.ltvs[k], pair.durations[j]
                    );
                    ProviderPositionNFT.LiquidityOffer memory offer = pair.providerNFT.getOffer(offerId);
                    require(offer.provider == liquidityProvider, "Offer not created for liquidity provider");
                    require(offer.available == cashAmountPerOffer, "Incorrect offer amount");
                    require(offer.putStrikeDeviation == pair.ltvs[k], "Incorrect LTV");
                    require(offer.duration == pair.durations[j], "Incorrect duration");
                    require(
                        offer.callStrikeDeviation == callStrikeTicks[l], "Incorrect call strike deviation"
                    );
                }
            }
        }
        console.log("Total offers created: %d", callStrikeTicks.length);
    }

    function _createRollOffer(
        address provider,
        AssetPairContracts memory pair,
        uint loanId,
        uint providerId,
        int rollFee,
        int rollDeltaFactor
    ) internal returns (uint rollOfferId) {
        uint currentPrice = pair.takerNFT.currentOraclePrice();
        pair.cashAsset.approve(address(pair.rollsContract), type(uint).max);
        pair.providerNFT.approve(address(pair.rollsContract), providerId);
        rollOfferId = pair.rollsContract.createRollOffer(
            loanId,
            rollFee, // Roll fee
            rollDeltaFactor, // Roll fee delta factor (100%)
            currentPrice * 90 / 100, // Min price (90% of current price)
            currentPrice * 110 / 100, // Max price (110% of current price)
            0, // Min to provider
            block.timestamp + 1 hours // Deadline
        );
    }

    function _openUserPosition(
        address user,
        address liquidityProvider,
        AssetPairContracts memory pair,
        uint collateralAmountForLoan,
        uint offerId
    ) internal returns (uint takerId, uint providerId, uint loanAmount) {
        // Use the first contract pair (USDC/WETH) for this example
        uint userCollateralBalance = pair.collateralAsset.balanceOf(user);
        require(userCollateralBalance >= collateralAmountForLoan, "User does not have enough collateral");
        // Approve collateral spending
        pair.collateralAsset.approve(address(pair.loansContract), type(uint).max);

        require(offerId < pair.providerNFT.nextOfferId(), "No available offers");
        // Check initial balances
        uint initialCollateralBalance = pair.collateralAsset.balanceOf(user);
        uint initialCashBalance = pair.cashAsset.balanceOf(user);

        // Get TWAP price before loan creation
        uint twapPrice = pair.takerNFT.currentOraclePrice();

        // Open a position
        (takerId, providerId, loanAmount) = pair.loansContract.createLoan(
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
            twapPrice,
            collateralAmountForLoan
        );

        console.log("Position opened:");
        console.log(" - Taker ID: %d", takerId);
        console.log(" - Provider ID: %d", providerId);
        console.log(" - Loan amount: %d", loanAmount);
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
        uint twapPrice,
        uint collateralAmountForLoan
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
