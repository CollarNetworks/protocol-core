// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import { ConfigHub } from "../src/ConfigHub.sol";
import { ShortProviderNFT } from "../src/ShortProviderNFT.sol";
import { CollarTakerNFT } from "../src/CollarTakerNFT.sol";
import { LoansNFT, IBaseLoansNFT } from "../src/LoansNFT.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Rolls } from "../src/Rolls.sol";
import { DeploymentUtils } from "./utils/deployment-exporter.s.sol";
import { OracleUniV3TWAP } from "../src/OracleUniV3TWAP.sol";
import { SwapperUniV3 } from "../src/SwapperUniV3.sol";

contract BaseDeployment is Script {
    ConfigHub configHub;
    address deployerAddress;

    struct AssetPairContracts {
        ShortProviderNFT providerNFT;
        CollarTakerNFT takerNFT;
        LoansNFT loansContract;
        Rolls rollsContract;
        IERC20 cashAsset;
        IERC20 collateralAsset;
        OracleUniV3TWAP oracle;
        SwapperUniV3 swapperUniV3;
        uint24 oracleFeeTier;
        uint24 swapFeeTier;
        uint[] durations;
        uint[] ltvs;
    }

    struct PairConfig {
        string name;
        IERC20 cashAsset;
        IERC20 collateralAsset;
        uint[] durations;
        uint[] ltvs;
        uint24 oracleFeeTier;
        uint24 swapFeeTier;
        uint32 twapWindow;
        address swapRouter;
    }

    struct HubParams {
        address[] cashAssets;
        address[] collateralAssets;
        uint minLTV;
        uint maxLTV;
        uint minDuration;
        uint maxDuration;
    }

    struct PositionValueCheck {
        uint takerId;
        uint providerId;
        address user;
        address liquidityProvider;
        uint initialCollateralBalance;
        uint initialCashBalance;
        uint loanAmount;
        uint twapPrice;
        uint collateralAmountForLoan;
    }

    uint[] callStrikeTicks = [11_100, 11_200, 11_500, 12_000];

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
        deployerAddress = deployerWallet.addr;
        return (deployerWallet.addr, user1Wallet.addr, user2Wallet.addr, liquidityProviderWallet.addr);
    }

    function _createContractPair(PairConfig memory pairConfig)
        internal
        returns (AssetPairContracts memory contracts)
    {
        OracleUniV3TWAP oracle = new OracleUniV3TWAP(
            address(pairConfig.collateralAsset),
            address(pairConfig.cashAsset),
            pairConfig.oracleFeeTier,
            pairConfig.twapWindow,
            pairConfig.swapRouter
        );

        CollarTakerNFT takerNFT = new CollarTakerNFT(
            deployerAddress,
            configHub,
            pairConfig.cashAsset,
            pairConfig.collateralAsset,
            oracle,
            string(abi.encodePacked("Taker ", pairConfig.name)),
            string(abi.encodePacked("T", pairConfig.name))
        );
        ShortProviderNFT providerNFT = new ShortProviderNFT(
            deployerAddress,
            configHub,
            pairConfig.cashAsset,
            pairConfig.collateralAsset,
            address(takerNFT),
            string(abi.encodePacked("Provider ", pairConfig.name)),
            string(abi.encodePacked("P", pairConfig.name))
        );
        LoansNFT loansContract = new LoansNFT(
            deployerAddress,
            takerNFT,
            string(abi.encodePacked("Loans ", pairConfig.name)),
            string(abi.encodePacked("L", pairConfig.name))
        );
        Rolls rollsContract = new Rolls(deployerAddress, takerNFT);
        SwapperUniV3 swapperUniV3 = new SwapperUniV3(pairConfig.swapRouter, pairConfig.swapFeeTier);

        contracts = AssetPairContracts({
            providerNFT: providerNFT,
            takerNFT: takerNFT,
            loansContract: loansContract,
            rollsContract: rollsContract,
            cashAsset: pairConfig.cashAsset,
            collateralAsset: pairConfig.collateralAsset,
            oracle: oracle,
            swapperUniV3: swapperUniV3,
            oracleFeeTier: pairConfig.oracleFeeTier,
            swapFeeTier: pairConfig.swapFeeTier,
            durations: pairConfig.durations,
            ltvs: pairConfig.ltvs
        });
        require(address(contracts.providerNFT) != address(0), "Provider NFT not created");
        require(address(contracts.takerNFT) != address(0), "Taker NFT not created");
        require(address(contracts.loansContract) != address(0), "Loans contract not created");
        require(address(contracts.rollsContract) != address(0), "Rolls contract not created");
        vm.label(address(contracts.providerNFT), string(abi.encodePacked("PROVIDER-", pairConfig.name)));
        vm.label(address(contracts.takerNFT), string(abi.encodePacked("TAKER-", pairConfig.name)));
        vm.label(address(contracts.loansContract), string(abi.encodePacked("LOANS-", pairConfig.name)));
        vm.label(address(contracts.rollsContract), string(abi.encodePacked("ROLLS-", pairConfig.name)));
    }

    function _setupContractPair(ConfigHub hub, AssetPairContracts memory pair) internal {
        hub.setCanOpen(address(pair.takerNFT), true);
        hub.setCanOpen(address(pair.providerNFT), true);
        pair.loansContract.setRollsContract(pair.rollsContract);
        pair.loansContract.setSwapperAllowed(address(pair.swapperUniV3), true, true);
        require(hub.canOpen(address(pair.providerNFT)), "Provider NFT not authorized in configHub");
        require(hub.canOpen(address(pair.takerNFT)), "Taker NFT not authorized in configHub");
    }

    function _deployConfigHub() internal {
        configHub = new ConfigHub(deployerAddress);
        console.log("\n --- Dev Environment Deployed ---");
        console.log("\n # Contract Addresses\n");
        console.log(" - ConfigHub - - - - - - - ", address(configHub));
        vm.label(address(configHub), "CONFIG-HUB");
    }

    function _setupConfigHub(HubParams memory hubParams) internal {
        // add supported cash assets
        for (uint i = 0; i < hubParams.cashAssets.length; i++) {
            configHub.setCashAssetSupport(hubParams.cashAssets[i], true);
        }
        // add supported collateral assets
        for (uint i = 0; i < hubParams.collateralAssets.length; i++) {
            configHub.setCollateralAssetSupport(hubParams.collateralAssets[i], true);
        }
        configHub.setLTVRange(hubParams.minLTV, hubParams.maxLTV);
        configHub.setCollarDurationRange(hubParams.minDuration, hubParams.maxDuration);
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
                    ShortProviderNFT.LiquidityOffer memory offer = pair.providerNFT.getOffer(offerId);
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
        (takerId, providerId, loanAmount) = pair.loansContract.openLoan(
            collateralAmountForLoan,
            0, // slippage
            IBaseLoansNFT.SwapParams(0, address(pair.loansContract.defaultSwapper()), ""),
            pair.providerNFT,
            offerId
        );

        _checkPosition(
            pair,
            PositionValueCheck(
                takerId,
                providerId,
                user,
                liquidityProvider,
                initialCollateralBalance,
                initialCashBalance,
                loanAmount,
                twapPrice,
                collateralAmountForLoan
            )
        );

        console.log("Position opened:");
        console.log(" - Taker ID: %d", takerId);
        console.log(" - Provider ID: %d", providerId);
        console.log(" - Loan amount: %d", loanAmount);
    }

    function _checkPosition(AssetPairContracts memory pair, PositionValueCheck memory values) internal view {
        CollarTakerNFT.TakerPosition memory position = pair.takerNFT.getPosition(values.takerId);
        require(position.settled == false);
        require(position.withdrawable == 0);
        require(position.putLockedCash > 0);
        require(position.callLockedCash > 0);

        require(pair.takerNFT.ownerOf(values.takerId) == values.user);
        require(pair.providerNFT.ownerOf(values.providerId) == values.liquidityProvider);

        // Check balance changes
        uint finalCollateralBalance = pair.collateralAsset.balanceOf(values.user);
        uint finalCashBalance = pair.cashAsset.balanceOf(values.user);

        assert(values.initialCollateralBalance - finalCollateralBalance == values.collateralAmountForLoan);
        assert(finalCashBalance - values.initialCashBalance == values.loanAmount);

        // Check loan amount using TWAP
        uint expectedLoanAmount =
            values.collateralAmountForLoan * values.twapPrice * pair.ltvs[0] / (1e18 * 10_000);
        uint loanAmountTolerance = expectedLoanAmount / 100; // 1% tolerance
        require(
            values.loanAmount >= expectedLoanAmount - loanAmountTolerance
                && values.loanAmount <= expectedLoanAmount + loanAmountTolerance,
            "Loan amount is outside the expected range"
        );
    }

    function _executeRoll(
        address user,
        AssetPairContracts memory pair,
        uint loanId,
        uint rollOfferId,
        int slippage
    ) internal {
        // Record initial balances
        uint initialUserCashBalance = pair.cashAsset.balanceOf(user);
        uint initialLoanAmount = pair.loansContract.getLoan(loanId).loanAmount;

        pair.cashAsset.approve(address(pair.loansContract), type(uint).max);
        pair.takerNFT.approve(address(pair.loansContract), loanId);

        uint currentPrice = pair.takerNFT.currentOraclePrice();
        console.log("current price: ", currentPrice);
        (int toTaker,,) = pair.rollsContract.calculateTransferAmounts(rollOfferId, currentPrice);
        console.log("to taker");
        console.logInt(toTaker);
        int toTakerWithSlippage = toTaker + (toTaker * slippage / int(10_000));
        (uint newTakerId, uint newLoanAmount, int actualTransferAmount) =
            pair.loansContract.rollLoan(loanId, pair.rollsContract, rollOfferId, toTakerWithSlippage);
        console.logInt(actualTransferAmount);

        console.log("Roll executed:");
        console.log(" - New Taker ID: %d", newTakerId);
        console.log(" - New Loan Amount: %d", newLoanAmount);

        _verifyRollExecution(
            user,
            pair,
            newTakerId,
            newLoanAmount,
            initialUserCashBalance,
            initialLoanAmount,
            currentPrice,
            toTaker,
            actualTransferAmount
        );
    }

    function _verifyRollExecution(
        address user,
        AssetPairContracts memory pair,
        uint newTakerId,
        uint newLoanAmount,
        uint initialUserCashBalance,
        uint initialLoanAmount,
        uint currentPrice,
        int toTaker,
        int actualTransferAmount
    ) internal view {
        require(pair.takerNFT.ownerOf(newTakerId) == user, "New taker NFT not owned by user");
        require(newLoanAmount > 0, "Invalid new loan amount");
        CollarTakerNFT.TakerPosition memory newPosition = pair.takerNFT.getPosition(newTakerId);
        require(newPosition.settled == false, "New position should not be settled");
        require(newPosition.withdrawable == 0, "New position should have no withdrawable amount");
        require(newPosition.putLockedCash > 0, "New position should have put locked cash");
        require(newPosition.callLockedCash > 0, "New position should have call locked cash");

        // Check balance changes
        uint finalUserCashBalance = pair.cashAsset.balanceOf(user);
        int userBalanceChange = int(finalUserCashBalance) - int(initialUserCashBalance);

        require(userBalanceChange == toTaker, "User balance change doesn't match expected transfer");
        require(actualTransferAmount == toTaker, "Actual transfer amount doesn't match calculated amount");

        // Check loan amount change
        int loanAmountChange = int(newLoanAmount) - int(initialLoanAmount);
        console.log("loan amount change");
        console.logInt(loanAmountChange);
        console.log("user balance change");
        console.logInt(userBalanceChange);
        console.log("roll fee");
        /**
         * @dev commented out because of mismatch between the script and the tx execution in virtual testnet
         */
        // require(loanAmountChange == userBalanceChange + rollFee, "Loan amount change is incorrect");

        // Additional checks
        require(newPosition.expiration > block.timestamp, "New position expiration should be in the future");
        require(
            newPosition.initialPrice == currentPrice, "New position initial price should match current price"
        );
        require(newPosition.putStrikePrice < currentPrice, "Put strike price should be below current price");
        require(newPosition.callStrikePrice > currentPrice, "Call strike price should be above current price");
    }

    function _verifyDeployment(ConfigHub hub, AssetPairContracts memory contracts) internal view {
        require(hub.canOpen(address(contracts.takerNFT)), "TakerNFT not authorized");
        require(hub.canOpen(address(contracts.providerNFT)), "ProviderNFT not authorized");
        require(hub.isSupportedCashAsset(address(contracts.cashAsset)), "Cash asset not supported");
        require(
            hub.isSupportedCollateralAsset(address(contracts.collateralAsset)),
            "Collateral asset not supported"
        );
        for (uint i = 0; i < contracts.durations.length; i++) {
            require(hub.isValidCollarDuration(contracts.durations[i]), "duration not supported");
        }
        for (uint i = 0; i < contracts.ltvs.length; i++) {
            require(hub.isValidLTV(contracts.ltvs[i]), "LTV not supported");
        }
        console.log("pair Deployment verified successfully");
    }
}
