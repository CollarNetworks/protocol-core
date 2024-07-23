// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import { CollarEngine } from "../src/implementations/CollarEngine.sol";
import { ProviderPositionNFT } from "../src/ProviderPositionNFT.sol";
import { CollarTakerNFT } from "../src/CollarTakerNFT.sol";
import { Loans } from "../src/Loans.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title DeployInitializedDevnetProtocol
 * @dev This script deploys and initializes the Collar Protocol for a development environment.
 *
 * It performs the following actions:
 * 1. Deploys the CollarEngine contract.
 * 2. Creates 11 pairs of ProviderPositionNFT, CollarTakerNFT, and Loans contracts.
 * 3. Sets up supported assets, LTVs, and durations in the CollarEngine.
 * 4. Creates initial liquidity offers for each pair.
 * 5. Performs various checks to ensure correct deployment and initialization.
 *
 * The script is designed to work on an Arbitrum fork, but can be adapted for other networks.
 */
contract DeployInitializedDevnetProtocol is Script {
    address router;
    CollarEngine engine;

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

    struct AssetPairContracts {
        ProviderPositionNFT providerNFT;
        CollarTakerNFT takerNFT;
        Loans loansContract;
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

    function _deployandSetupEngine() internal {
        router = swapRouterAddress;
        engine = new CollarEngine(router);

        // add supported cash assets
        engine.setCashAssetSupport(USDC, true);
        engine.setCashAssetSupport(USDT, true);
        engine.setCashAssetSupport(WETH, true);
        // add supported collateral assets
        engine.setCollateralAssetSupport(WETH, true);
        engine.setCollateralAssetSupport(WBTC, true);
        engine.setCollateralAssetSupport(MATIC, true);
        engine.setCollateralAssetSupport(weETH, true);
        engine.setCollateralAssetSupport(stETH, true);
        engine.setLTVRange(allLTVs[1], allLTVs[0]);
        engine.setCollarDurationRange(allDurations[0], allDurations[2]);

        console.log("\n --- Dev Environment Deployed ---");
        console.log("\n # Contract Addresses\n");
        console.log(" - Router:  - - - - - - ", router);
        console.log(" - Engine - - - - - - - ", address(engine));
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
            address(this),
            engine,
            cashAsset,
            collateralAsset,
            string(abi.encodePacked("Taker ", pairName)),
            string(abi.encodePacked("T", pairName))
        );
        ProviderPositionNFT providerNFT = new ProviderPositionNFT(
            address(this),
            engine,
            cashAsset,
            collateralAsset,
            address(takerNFT),
            string(abi.encodePacked("Provider ", pairName)),
            string(abi.encodePacked("P", pairName))
        );
        Loans loansContract = new Loans(address(this), engine, takerNFT, cashAsset, collateralAsset);

        engine.setCollarTakerContractAuth(address(takerNFT), true);
        engine.setProviderContractAuth(address(providerNFT), true);
        AssetPairContracts memory contracts = AssetPairContracts(
            providerNFT, takerNFT, loansContract, cashAsset, collateralAsset, durations, ltvs
        );
        require(address(contracts.providerNFT) != address(0), "Provider NFT not created");
        require(address(contracts.takerNFT) != address(0), "Taker NFT not created");
        require(address(contracts.loansContract) != address(0), "Loans contract not created");
        require(engine.isProviderNFT(address(contracts.providerNFT)), "Provider NFT not authorized in engine");
        require(engine.isCollarTakerNFT(address(contracts.takerNFT)), "Taker NFT not authorized in engine");
        assetPairContracts.push(contracts);
        console.log(" - %s Taker NFT: %s", pairName, address(takerNFT));
        console.log(" - %s Provider NFT: %s", pairName, address(providerNFT));
        console.log(" - %s Loans Contract: %s", pairName, address(loansContract));
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

        require(liquidityProvider != address(0), "liquidity provider address not set");
        require(liquidityProvider.balance > 1000, "liquidity provider address not funded");

        vm.startBroadcast(deployer);
        _deployandSetupEngine();
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
        uint twapPrice = engine.getHistoricalAssetPriceViaTWAP(
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
        uint expectedLoanAmount = collateralAmountForLoan * twapPrice * allLTVs[0] / (1e18 * 10_000);
        uint loanAmountTolerance = expectedLoanAmount / 100; // 1% tolerance
        require(
            loanAmount >= expectedLoanAmount - loanAmountTolerance
                && loanAmount <= expectedLoanAmount + loanAmountTolerance,
            "Loan amount is outside the expected range"
        );
    }
}
