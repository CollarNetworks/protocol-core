// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import { CollarEngine } from "../src/implementations/CollarEngine.sol";
import { ProviderPositionNFT } from "../src/ProviderPositionNFT.sol";
import { CollarTakerNFT } from "../src/CollarTakerNFT.sol";
import { Loans } from "../src/Loans.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

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
    using SafeERC20 for IERC20;

    address router;
    address engine;

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

    struct ContractPair {
        address providerNFT;
        address takerNFT;
        address loansContract;
        address cashAsset;
        address collateralAsset;
        uint[] durations;
        uint[] ltvs;
    }

    ContractPair[] public contractPairs;

    function setup()
        internal
        returns (address deployer, address user1, address user2, address liquidityProvider)
    {
        VmSafe.Wallet memory deployerWallet = vm.createWallet(vm.envUint("PRIVKEY_DEV_DEPLOYER"));
        VmSafe.Wallet memory user1Wallet = vm.createWallet(vm.envUint("PRIVKEY_DEV_TEST1"));
        VmSafe.Wallet memory user2Wallet = vm.createWallet(vm.envUint("PRIVKEY_DEV_TEST2"));
        VmSafe.Wallet memory liquidityProviderWallet = vm.createWallet(vm.envUint("PRIVKEY_DEV_TEST3"));

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
        engine = address(new CollarEngine(router));

        // add supported LTV values
        CollarEngine(engine).addLTV(9000);
        CollarEngine(engine).addLTV(5000);

        // add supported durations
        CollarEngine(engine).addCollarDuration(5 minutes);
        CollarEngine(engine).addCollarDuration(30 days);
        CollarEngine(engine).addCollarDuration(12 * 30 days);

        // add supported assets
        CollarEngine(engine).addSupportedCashAsset(USDC);
        CollarEngine(engine).addSupportedCashAsset(USDT);
        CollarEngine(engine).addSupportedCashAsset(WETH);
        CollarEngine(engine).addSupportedCollateralAsset(WETH);
        CollarEngine(engine).addSupportedCollateralAsset(WBTC);
        CollarEngine(engine).addSupportedCollateralAsset(MATIC);
        CollarEngine(engine).addSupportedCollateralAsset(stETH);
        CollarEngine(engine).addSupportedCollateralAsset(weETH);

        console.log("\n --- Dev Environment Deployed ---");
        console.log("\n # Contract Addresses\n");
        console.log(" - Router:  - - - - - - ", router);
        console.log(" - Engine - - - - - - - ", engine);
    }

    function _createContractPairs() internal {
        uint[] memory allDurations = new uint[](3);
        allDurations[0] = 5 minutes;
        allDurations[1] = 30 days;
        allDurations[2] = 12 * 30 days;

        uint[] memory allLTVs = new uint[](2);
        allLTVs[0] = 9000;
        allLTVs[1] = 5000;

        uint[] memory singleDuration = new uint[](1);
        singleDuration[0] = 5 minutes;

        uint[] memory singleLTV = new uint[](1);
        singleLTV[0] = 9000;

        _createContractPair(USDC, WETH, "USDC/WETH", allDurations, allLTVs);
        _createContractPair(USDT, WETH, "USDT/WETH", singleDuration, singleLTV);
        _createContractPair(USDC, WBTC, "USDC/WBTC", singleDuration, singleLTV);
        _createContractPair(USDC, MATIC, "USDC/MATIC", singleDuration, singleLTV);
        _createContractPair(USDC, stETH, "USDC/stETH", singleDuration, singleLTV);
        _createContractPair(WETH, weETH, "WETH/weETH", singleDuration, singleLTV);
    }

    function _createContractPair(
        address cashAsset,
        address collateralAsset,
        string memory pairName,
        uint[] memory durations,
        uint[] memory ltvs
    ) internal {
        address takerNFT = address(
            new CollarTakerNFT(
                address(this),
                CollarEngine(engine),
                IERC20(cashAsset),
                IERC20(collateralAsset),
                string(abi.encodePacked("Taker ", pairName)),
                string(abi.encodePacked("T", pairName))
            )
        );
        address providerNFT = address(
            new ProviderPositionNFT(
                address(this),
                CollarEngine(engine),
                IERC20(cashAsset),
                IERC20(collateralAsset),
                takerNFT,
                string(abi.encodePacked("Provider ", pairName)),
                string(abi.encodePacked("P", pairName))
            )
        );
        address loansContract = address(
            new Loans(
                address(this),
                CollarEngine(engine),
                CollarTakerNFT(takerNFT),
                IERC20(cashAsset),
                IERC20(collateralAsset)
            )
        );

        CollarEngine(engine).setCollarTakerContractAuth(takerNFT, true);
        CollarEngine(engine).setProviderContractAuth(providerNFT, true);

        contractPairs.push(
            ContractPair(providerNFT, takerNFT, loansContract, cashAsset, collateralAsset, durations, ltvs)
        );

        console.log(" - %s Taker NFT: %s", pairName, takerNFT);
        console.log(" - %s Provider NFT: %s", pairName, providerNFT);
        console.log(" - %s Loans Contract: %s", pairName, loansContract);
    }

    function _verifyContractPairCreation() internal view {
        for (uint i = 0; i < contractPairs.length; i++) {
            require(contractPairs[i].providerNFT != address(0), "Provider NFT not created");
            require(contractPairs[i].takerNFT != address(0), "Taker NFT not created");
            require(contractPairs[i].loansContract != address(0), "Loans contract not created");
            require(
                CollarEngine(engine).isProviderNFT(contractPairs[i].providerNFT),
                "Provider NFT not authorized in engine"
            );
            require(
                CollarEngine(engine).isCollarTakerNFT(contractPairs[i].takerNFT),
                "Taker NFT not authorized in engine"
            );
        }
        console.log("Contract pair creation verified successfully");
    }

    function _createOffers(address liquidityProvider) internal {
        vm.startBroadcast(liquidityProvider);

        uint amountToAdd = 100_000e6; // 100,000 USDC or equivalent
        uint totalOffers = 0;
        /**
         * @dev Create offers for all contract pairs with all durations and LTVs , they're not all equal so they depend on the contract pair ltv and duration combo
         */
        for (uint i = 0; i < contractPairs.length; i++) {
            ContractPair memory pair = contractPairs[i];
            IERC20(pair.cashAsset).approve(pair.providerNFT, type(uint).max);

            for (uint j = 0; j < pair.durations.length; j++) {
                for (uint k = 0; k < pair.ltvs.length; k++) {
                    for (uint l = 0; l < callStrikeTicks.length; l++) {
                        ProviderPositionNFT(pair.providerNFT).createOffer(
                            callStrikeTicks[l], amountToAdd, pair.ltvs[k], pair.durations[j]
                        );
                        totalOffers++;
                    }
                }
            }
        }

        vm.stopBroadcast();
        console.log("Total offers created: ", totalOffers);
    }

    function _verifyOfferCreation(address liquidityProvider) internal view {
        uint totalOffers = 0;
        for (uint i = 0; i < contractPairs.length; i++) {
            ContractPair memory pair = contractPairs[i];
            ProviderPositionNFT providerNFT = ProviderPositionNFT(pair.providerNFT);
            uint offerCount = 0;

            for (uint j = 0; j < pair.durations.length; j++) {
                for (uint k = 0; k < pair.ltvs.length; k++) {
                    for (uint l = 0; l < callStrikeTicks.length; l++) {
                        ProviderPositionNFT.LiquidityOffer memory offer = providerNFT.getOffer(offerCount);
                        require(
                            offer.provider == liquidityProvider, "Offer not created for liquidity provider"
                        );
                        require(offer.available == 100_000e6, "Incorrect offer amount");
                        require(offer.putStrikeDeviation == pair.ltvs[k], "Incorrect LTV");
                        require(offer.duration == pair.durations[j], "Incorrect duration");
                        require(
                            offer.callStrikeDeviation == callStrikeTicks[l], "Incorrect call strike deviation"
                        );

                        offerCount++;
                        totalOffers++;
                    }
                }
            }
        }
        require(totalOffers == 44, "Incorrect total number of offers created");
        console.log("Offer creation verified successfully. Total offers created: ", totalOffers);
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

        _verifyContractPairCreation();

        uint amountToAdd = 100_000e6; // 100,000 USDC or equivalent
        address firstCashAsset = contractPairs[0].cashAsset;
        uint lpBalance = IERC20(firstCashAsset).balanceOf(liquidityProvider);
        require(lpBalance >= amountToAdd * 44, "liquidity provider does not have enough funds");

        _createOffers(liquidityProvider);
        _verifyOfferCreation(liquidityProvider);

        console.log("\nDeployment and initialization completed successfully");

        // Open a position as user1 to test the protocol
        _openUserPosition(user1);

        // Verify the opened position
        _verifyUserPosition(user1);

        console.log("\nDeployment, initialization, and user position creation completed successfully");
    }

    function _openUserPosition(address user) internal {
        vm.startBroadcast(user);

        // Use the first contract pair (USDC/WETH) for this example
        ContractPair memory pair = contractPairs[0];
        ProviderPositionNFT providerNFT = ProviderPositionNFT(pair.providerNFT);
        Loans loansContract = Loans(pair.loansContract);
        uint userCollateralBalance = IERC20(pair.collateralAsset).balanceOf(user);
        require(userCollateralBalance >= 1 ether, "User does not have enough collateral");
        // Approve collateral spending
        IERC20(pair.collateralAsset).approve(address(loansContract), type(uint).max);

        // Find the first available offer
        uint offerId = 0;
        require(offerId < providerNFT.nextOfferId(), "No available offers");

        // Open a position
        uint collateralAmount = 1 ether; // 1 WETH
        uint minCashAmount = 0; // Set to 0 for this example, adjust as needed
        (uint borrowId, uint cashReceived, uint collateralLocked) = loansContract.createLoan(
            collateralAmount,
            0, // slippage
            minCashAmount,
            providerNFT,
            offerId
        );

        console.log("Position opened:");
        console.log(" - Borrow ID: ", borrowId);
        console.log(" - Cash received: ", cashReceived);
        console.log(" - Collateral locked: ", collateralLocked);

        vm.stopBroadcast();
    }

    function _verifyUserPosition(address user) internal view {
        ContractPair memory pair = contractPairs[0];
        CollarTakerNFT takerNFT = CollarTakerNFT(pair.takerNFT);

        uint borrowId = takerNFT.nextPositionId() - 1;
        CollarTakerNFT.TakerPosition memory position = takerNFT.getPosition(borrowId);

        require(takerNFT.ownerOf(borrowId) == user, "User does not own the position");
        require(position.settled == false, "Position should not be settled");
        require(position.withdrawable == 0, "Position should not have withdrawable amount");
        require(position.putLockedCash > 0, "Position should have locked cash");
        require(position.callLockedCash > 0, "Position should have locked collateral");

        console.log("User position verified successfully");
    }
}
