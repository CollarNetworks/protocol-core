// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import { ConfigHub } from "../src/implementations/ConfigHub.sol";
import { ProviderPositionNFT } from "../src/ProviderPositionNFT.sol";
import { CollarTakerNFT } from "../src/CollarTakerNFT.sol";
import { Loans } from "../src/Loans.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Rolls } from "../src/Rolls.sol";
// import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title DeployInitializedDevnetProtocol
 * @dev This script deploys and initializes the Collar Protocol for a development environment.
 *
 * It performs the following actions:
 * 1. Deploys the ConfigHub contract.
 * 2. Creates 11 pairs of ProviderPositionNFT, CollarTakerNFT, and Loans contracts.
 * 3. Sets up supported assets, LTVs, and durations in the ConfigHub.
 * 4. Creates initial liquidity offers for each pair.
 * 5. Performs various checks to ensure correct deployment and initialization.
 *
 * The script is designed to work on an Arbitrum fork, but can be adapted for other networks.
 */
contract DeployInitializedDevnetProtocol is Script {
    address router;
    ConfigHub configHub;

    uint chainId = 137_999; // id for ethereum mainnet fork on tenderly
    address USDC = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
    address USDT = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;
    address WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address stETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84; // wsteth doesnt have any 0.3% fee with neither USDC nor USDT on arbitrum uniswap
    address weETH = 0x35751007a407ca6FEFfE80b3cB397736D2cf4dbe; // Wrapped weETH on arbitrum doesnt have USDC pools on uniswap
    address WBTC = 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f;
    address MATIC = 0x561877b6b3DD7651313794e5F2894B2F18bE0766;
    address swapRouterAddress = address(0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45);
    uint constant numOfPairs = 11;
    uint[] callStrikeTicks = [11_100, 11_200, 11_500, 12_000];
    uint[] allDurations = [5 minutes, 30 days, 12 * 30 days];
    uint[] allLTVs = [9000, 5000];
    uint cashAmountPerOffer = 100_000e6;
    uint collateralAmountForLoan = 1 ether;
    uint expectedOfferCount = 44;
    int rollFee = 1e6;
    int rollDeltaFactor = 10_000;

    address deployerAddress;

    struct AssetPairContracts {
        ProviderPositionNFT providerNFT;
        CollarTakerNFT takerNFT;
        Loans loansContract;
        Rolls rollsContract;
        IERC20 cashAsset;
        IERC20 collateralAsset;
        uint[] durations;
        uint[] ltvs;
    }

    AssetPairContracts[] public assetPairContracts;

    function setup()
        internal
        returns (address deployer, address user1, address user2, address liquidityProvider)
    {
        VmSafe.Wallet memory deployerWallet = vm.createWallet(vm.envUint("PRIVKEY_DEV_DEPLOYER"));
        VmSafe.Wallet memory user1Wallet = vm.createWallet(vm.envUint("PRIVKEY_DEV_TEST1"));
        VmSafe.Wallet memory user2Wallet = vm.createWallet(vm.envUint("PRIVKEY_DEV_TEST2"));
        VmSafe.Wallet memory liquidityProviderWallet = vm.createWallet(vm.envUint("PRIVKEY_DEV_DEPLOYER"));

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

    function _deployandSetupConfigHub() internal {
        router = swapRouterAddress;
        configHub = new ConfigHub(router);

        // add supported cash assets
        configHub.setCashAssetSupport(USDC, true);
        configHub.setCashAssetSupport(USDT, true);
        configHub.setCashAssetSupport(WETH, true);
        // add supported collateral assets
        configHub.setCollateralAssetSupport(WETH, true);
        configHub.setCollateralAssetSupport(WBTC, true);
        configHub.setCollateralAssetSupport(MATIC, true);
        configHub.setCollateralAssetSupport(weETH, true);
        configHub.setCollateralAssetSupport(stETH, true);
        configHub.setLTVRange(allLTVs[1], allLTVs[0]);
        configHub.setCollarDurationRange(allDurations[0], allDurations[2]);

        console.log("\n --- Dev Environment Deployed ---");
        console.log("\n # Contract Addresses\n");
        console.log(" - Router:  - - - - - - ", router);
        console.log(" - ConfigHub - - - - - - - ", address(configHub));
    }

    function _createContractPairs() internal {
        uint[] memory singleDuration = new uint[](1);
        singleDuration[0] = allDurations[0];

        uint[] memory singleLTV = new uint[](1);
        singleLTV[0] = allLTVs[0];
        console.log("ltv: %d", singleLTV[0]);
        _createContractPair(IERC20(USDC), IERC20(WETH), "USDC/WETH", allDurations, allLTVs);
        _createContractPair(IERC20(USDT), IERC20(WETH), "USDT/WETH", singleDuration, singleLTV);
        _createContractPair(IERC20(USDC), IERC20(WBTC), "USDC/WBTC", singleDuration, singleLTV);
        _createContractPair(IERC20(USDC), IERC20(MATIC), "USDC/MATIC", singleDuration, singleLTV);
        _createContractPair(IERC20(USDC), IERC20(stETH), "USDC/stETH", singleDuration, singleLTV);
        _createContractPair(IERC20(WETH), IERC20(weETH), "WETH/weETH", singleDuration, singleLTV);
    }

    function _createContractPair(
        IERC20 cashAsset,
        IERC20 collateralAsset,
        string memory pairName,
        uint[] memory durations,
        uint[] memory ltvs
    ) internal {
        CollarTakerNFT takerNFT = new CollarTakerNFT(
            deployerAddress,
            configHub,
            cashAsset,
            collateralAsset,
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
        Rolls rollsContract = new Rolls(deployerAddress, takerNFT, cashAsset);
        loansContract.setRollsContract(rollsContract);

        AssetPairContracts memory contracts = AssetPairContracts(
            providerNFT, takerNFT, loansContract, rollsContract, cashAsset, collateralAsset, durations, ltvs
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
        assetPairContracts.push(contracts);
        console.log(" - %s Taker NFT: %s", pairName, address(takerNFT));
        console.log(" - %s Provider NFT: %s", pairName, address(providerNFT));
        console.log(" - %s Loans Contract: %s", pairName, address(loansContract));
        console.log(" - %s Rolls Contract: %s", pairName, address(rollsContract));
    }

    function _createOffers(address liquidityProvider) internal {
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

    function run() external {
        require(chainId == block.chainid, "chainId does not match the chainId in config");
        (address deployer, address user1,, address liquidityProvider) = setup();
        deployerAddress = deployer;
        require(liquidityProvider != address(0), "liquidity provider address not set");
        require(liquidityProvider.balance > 1000, "liquidity provider address not funded");

        vm.startBroadcast(deployer);
        _deployandSetupConfigHub();
        _createContractPairs();
        vm.stopBroadcast();

        IERC20 firstCashAsset = assetPairContracts[0].cashAsset;
        uint lpBalance = firstCashAsset.balanceOf(liquidityProvider);
        require(
            lpBalance >= cashAmountPerOffer * expectedOfferCount,
            "liquidity provider does not have enough funds"
        );

        _createOffers(liquidityProvider);

        console.log("\nDeployment and initialization completed successfully");

        // Open a position as user1 to test the protocol
        _openUserPosition(user1, liquidityProvider);

        console.log("\nDeployment, initialization, and user position creation completed successfully");
    }

    function _openUserPosition(address user, address liquidityProvider) internal {
        vm.startBroadcast(user);

        // Use the first contract pair (USDC/WETH) for this example
        AssetPairContracts memory pair = assetPairContracts[0];
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
        _createAndExecuteRoll(liquidityProvider, user, pair, takerId, providerId);
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
        uint expectedLoanAmount = collateralAmountForLoan * twapPrice * allLTVs[0] / (1e18 * 10_000);
        uint loanAmountTolerance = expectedLoanAmount / 100; // 1% tolerance
        require(
            loanAmount >= expectedLoanAmount - loanAmountTolerance
                && loanAmount <= expectedLoanAmount + loanAmountTolerance,
            "Loan amount is outside the expected range"
        );
    }

    function _createAndExecuteRoll(
        address provider,
        address user,
        AssetPairContracts memory pair,
        uint loanId,
        uint providerId
    ) internal {
        // Record initial balances
        uint initialUserCashBalance = pair.cashAsset.balanceOf(user);
        uint initialLoanAmount = pair.loansContract.getLoan(loanId).loanAmount;

        vm.startBroadcast(provider);
        uint currentPrice = pair.takerNFT.getReferenceTWAPPrice(block.timestamp);
        pair.cashAsset.approve(address(pair.rollsContract), type(uint).max);
        pair.providerNFT.approve(address(pair.rollsContract), providerId);
        uint rollOfferId = pair.rollsContract.createRollOffer(
            loanId,
            rollFee, // Roll fee
            rollDeltaFactor, // Roll fee delta factor (100%)
            currentPrice * 90 / 100, // Min price (90% of current price)
            currentPrice * 110 / 100, // Max price (110% of current price)
            0, // Min to provider
            block.timestamp + 1 hours // Deadline
        );
        vm.stopBroadcast();

        vm.startBroadcast(user);
        pair.cashAsset.approve(address(pair.loansContract), type(uint).max);
        pair.takerNFT.approve(address(pair.loansContract), loanId);
        (int toTaker,,) = pair.rollsContract.calculateTransferAmounts(rollOfferId, currentPrice);
        (uint newTakerId, uint newLoanAmount, int actualTransferAmount) =
            pair.loansContract.rollLoan(loanId, pair.rollsContract, rollOfferId, toTaker - 0.3e6); // 0.3e6 slippage
        console.logInt(actualTransferAmount);
        vm.stopBroadcast();

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
        require(loanAmountChange == userBalanceChange + rollFee, "Loan amount change is incorrect");

        // Additional checks
        require(newPosition.expiration > block.timestamp, "New position expiration should be in the future");
        require(
            newPosition.initialPrice == currentPrice, "New position initial price should match current price"
        );
        require(newPosition.putStrikePrice < currentPrice, "Put strike price should be below current price");
        require(newPosition.callStrikePrice > currentPrice, "Call strike price should be above current price");
    }
}
