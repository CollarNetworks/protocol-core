// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import { ConfigHub } from "../src/implementations/ConfigHub.sol";
import { ProviderPositionNFT } from "../src/ProviderPositionNFT.sol";
import { CollarTakerNFT } from "../src/CollarTakerNFT.sol";
import { Loans } from "../src/Loans.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IUniswapV3Factory } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import { IV3SwapRouter } from "@uniswap/swap-router-contracts/contracts/interfaces/IV3SwapRouter.sol";
import { CollarOwnedERC20 } from "../test/utils/CollarOwnedERC20.sol";
import { Rolls } from "../src/Rolls.sol";

contract DeployArbitrumSepoliaProtocol is Script {
    using SafeERC20 for IERC20;

    uint constant chainId = 421_614; // Arbitrum Sepolia
    address constant uniswapV3FactoryAddress = 0x248AB79Bbb9bC29bB72f7Cd42F17e054Fc40188e; // Arbitrum Sepolia UniswapV3Factory
    uint24 constant POOL_FEE = 3000;
    uint[] public callStrikeDeviations = [11_100, 11_200, 11_500, 12_000];
    uint ltvToUse = 9000;
    uint durationToUse = 300;
    uint amountToMintForLP = 100_000_000 ether;
    uint amountPerOffer = 100_000 ether;
    uint amountToProvideToPool = 10_000_000 ether;
    uint amountForLoanCollateral = 10 ether;
    uint amountExpectedForCashLoan = 9 ether;
    mapping(uint offerId => ProviderPositionNFT.LiquidityOffer offer) createdOffers;

    struct DeployedContracts {
        CollarOwnedERC20 cashAsset;
        CollarOwnedERC20 collateralAsset;
        ProviderPositionNFT providerNFT;
        CollarTakerNFT takerNFT;
        Loans loansContract;
        Rolls rollsContract;
        address uniswapPool;
    }

    IV3SwapRouter constant SWAP_ROUTER = IV3SwapRouter(0x101F443B4d1b059569D643917553c771E1b9663E);
    CollarOwnedERC20 constant CASH_TOKEN = CollarOwnedERC20(0x5D01F1E59C188a2A9Afc376cF6627dd5F28DC28F);
    CollarOwnedERC20 constant COLLATERAL_TOKEN = CollarOwnedERC20(0x9A6E1a5f94De0aD8ca15b55eA0d39bEaEc579434);
    INonfungiblePositionManager constant POSITION_MANAGER =
        INonfungiblePositionManager(0x6b2937Bde17889EDCf8fbD8dE31C3C2a70Bc4d65);

    function run() external {
        require(block.chainid == chainId, "Wrong chain");

        uint deployerPrivateKey = vm.envUint("PRIVKEY_DEV_DEPLOYER");
        address deployer = vm.addr(deployerPrivateKey);
        uint liquidityProviderKey = vm.envUint("LIQUIDITY_PROVIDER_KEY");
        address liquidityProvider = vm.addr(liquidityProviderKey);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy and setup configHub
        ConfigHub configHub = new ConfigHub(address(SWAP_ROUTER));
        configHub.setLTVRange(ltvToUse, ltvToUse);
        configHub.setCollarDurationRange(durationToUse, durationToUse);

        DeployedContracts memory contracts = deployContracts(configHub, deployer);

        _verifyDeployment(configHub, contracts);

        contracts.cashAsset.mint(liquidityProvider, amountToMintForLP);

        vm.stopBroadcast();

        console.log("ConfigHub deployed at:", address(configHub));
        console.log("Cash Asset deployed at:", address(contracts.cashAsset));
        console.log("Collateral Asset deployed at:", address(contracts.collateralAsset));
        console.log("TakerNFT deployed at:", address(contracts.takerNFT));
        console.log("ProviderNFT deployed at:", address(contracts.providerNFT));
        console.log("Loans contract deployed at:", address(contracts.loansContract));
        console.log("Uniswap V3 pool created at:", contracts.uniswapPool);

        // Verify deployment
        // Create offers
        _createOffers(liquidityProviderKey, liquidityProvider, contracts.providerNFT, contracts.cashAsset);

        // // add liquidity to the new asset pool

        // _initializePool(
        //     liquidityProviderKey,
        //     liquidityProvider,
        //     contracts.uniswapPool,
        //     contracts.cashAsset,
        //     contracts.collateralAsset
        // );

        (uint loanId, uint providerId) = _createLoan(
            deployerPrivateKey,
            contracts.loansContract,
            ProviderPositionNFT(contracts.providerNFT),
            contracts.cashAsset,
            contracts.collateralAsset
        );

        _createAndAcceptRoll(liquidityProviderKey, deployerPrivateKey, contracts, loanId, providerId);
    }

    function deployContracts(ConfigHub configHub, address deployer)
        internal
        returns (DeployedContracts memory)
    {
        // Deploy custom ERC20 tokens
        CollarOwnedERC20 cashAsset = CASH_TOKEN;
        CollarOwnedERC20 collateralAsset = COLLATERAL_TOKEN;
        if (address(cashAsset) == address(0)) {
            cashAsset = new CollarOwnedERC20(deployer, "Cash Asset", "CASH");
            collateralAsset = new CollarOwnedERC20(deployer, "Collateral Asset", "COLL");
        }

        IUniswapV3Factory factory = IUniswapV3Factory(uniswapV3FactoryAddress);
        // check factory owner
        console.log("Factory owner:", factory.owner());
        // check fee tier is enabled
        console.logInt(factory.feeAmountTickSpacing(POOL_FEE));
        // Check if pool already exists
        address existingPool = factory.getPool(address(collateralAsset), address(cashAsset), POOL_FEE);
        console.log("Existing pool address:", existingPool);
        // Create Uniswap V3 pool
        address pool = existingPool;
        if (existingPool == address(0)) {
            pool = factory.createPool(address(cashAsset), address(collateralAsset), POOL_FEE);
        }

        // Add support for assets in the configHub
        configHub.setCollateralAssetSupport(address(collateralAsset), true);
        configHub.setCashAssetSupport(address(cashAsset), true);

        // Deploy contract pair
        CollarTakerNFT takerNFT = new CollarTakerNFT(
            deployer, configHub, cashAsset, collateralAsset, "Taker COLL/CASH", "TCOLL/CASH"
        );

        ProviderPositionNFT providerNFT = new ProviderPositionNFT(
            deployer,
            configHub,
            cashAsset,
            collateralAsset,
            address(takerNFT),
            "Provider COLL/CASH",
            "PCOLL/CASH"
        );

        configHub.setCollarTakerContractAuth(address(takerNFT), true);
        configHub.setProviderContractAuth(address(providerNFT), true);

        Loans loansContract = new Loans(deployer, takerNFT);
        Rolls rollsContract = new Rolls(deployer, takerNFT, cashAsset);

        configHub.setCollarTakerContractAuth(address(takerNFT), true);
        configHub.setProviderContractAuth(address(providerNFT), true);

        // Set the Rolls contract in the Loans contract
        loansContract.setRollsContract(rollsContract);

        return DeployedContracts({
            cashAsset: cashAsset,
            collateralAsset: collateralAsset,
            providerNFT: providerNFT,
            takerNFT: takerNFT,
            loansContract: loansContract,
            rollsContract: rollsContract,
            uniswapPool: pool
        });
    }

    function _verifyDeployment(ConfigHub configHub, DeployedContracts memory contracts) internal view {
        require(configHub.isCollarTakerNFT(address(contracts.takerNFT)), "TakerNFT not authorized");
        require(configHub.isProviderNFT(address(contracts.providerNFT)), "ProviderNFT not authorized");
        require(configHub.isSupportedCashAsset(address(contracts.cashAsset)), "Cash asset not supported");
        require(
            configHub.isSupportedCollateralAsset(address(contracts.collateralAsset)),
            "Collateral asset not supported"
        );
        require(configHub.isValidLTV(ltvToUse), "LTV  not supported");
        require(configHub.isValidCollarDuration(durationToUse), "duration not supported");
        console.log("Deployment verified successfully");
    }

    function _createOffers(
        uint liquidityProviderPrivateKey,
        address liquidityProviderAddress,
        ProviderPositionNFT providerNFT,
        CollarOwnedERC20 cashAsset
    ) internal {
        vm.startBroadcast(liquidityProviderPrivateKey);
        vm.stopBroadcast();
        vm.startBroadcast(vm.envUint("LIQUIDITY_PROVIDER_KEY"));
        cashAsset.approve(address(providerNFT), type(uint).max);
        for (uint i = 0; i < callStrikeDeviations.length; i++) {
            uint offerId =
                providerNFT.createOffer(callStrikeDeviations[i], amountPerOffer, ltvToUse, durationToUse);
            ProviderPositionNFT.LiquidityOffer memory offer = providerNFT.getOffer(offerId);
            require(offer.provider == liquidityProviderAddress, "Incorrect offer provider");
            require(offer.available == amountPerOffer, "Incorrect offer amount");
            require(offer.putStrikeDeviation == ltvToUse, "Incorrect LTV");
            require(offer.duration == durationToUse, "Incorrect duration");
            require(offer.callStrikeDeviation == callStrikeDeviations[i], "Incorrect call strike deviation");
            console.log("Offer created successfully : ", offerId);
        }

        vm.stopBroadcast();
    }

    function _initializePool(
        uint providerKey,
        address provider,
        address pool,
        CollarOwnedERC20 cashAsset,
        CollarOwnedERC20 collateralAsset
    ) internal {
        vm.startBroadcast(providerKey);
        // Approve tokens
        collateralAsset.approve(address(POSITION_MANAGER), type(uint).max);
        cashAsset.approve(address(POSITION_MANAGER), type(uint).max);
        // Get current tick
        (, int24 currentTick,,,,,) = IUniswapV3Pool(pool).slot0();

        // Set price range
        int24 tickLower = currentTick - 600;
        int24 tickUpper = currentTick + 600;

        // Set the initial price
        uint160 sqrtPriceX96 = 79_228_162_514_264_337_593_543_950_336; // Represents a price of 1:1

        // Initialize the pool
        IUniswapV3Pool(pool).initialize(sqrtPriceX96);
        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token1: address(collateralAsset),
            token0: address(cashAsset),
            fee: POOL_FEE,
            tickLower: tickLower,
            tickUpper: tickUpper,
            amount0Desired: amountToProvideToPool,
            amount1Desired: amountToProvideToPool,
            amount0Min: 0,
            amount1Min: 0,
            recipient: provider,
            deadline: block.timestamp + 15 minutes
        });

        // Add liquidity
        POSITION_MANAGER.mint(params);
    }

    function _createLoan(
        uint privKey,
        Loans loansContract,
        ProviderPositionNFT providerNFT,
        CollarOwnedERC20 cashAsset,
        CollarOwnedERC20 collateralAsset
    ) internal returns (uint loanId, uint providerId) {
        vm.startBroadcast(privKey);
        // Create loan
        cashAsset.approve(address(loansContract), amountPerOffer);
        collateralAsset.approve(address(loansContract), amountPerOffer);
        (loanId, providerId,) =
            loansContract.createLoan(amountForLoanCollateral, amountExpectedForCashLoan, 0, providerNFT, 0);
        // Get loan
        Loans.Loan memory loan = loansContract.getLoan(loanId);
        console.log("Loan collateral amount:", loan.collateralAmount);
        console.log("Loan loan amount:", loan.loanAmount);
        vm.stopBroadcast();
    }

    function _createAndAcceptRoll(
        uint providerKey,
        uint userKey,
        DeployedContracts memory contracts,
        uint loanId,
        uint providerId
    ) internal {
        // Get current price
        uint currentPrice = contracts.takerNFT.getReferenceTWAPPrice(block.timestamp);
        console.log("Current TWAP price:", currentPrice);

        // Create roll offer
        vm.startBroadcast(providerKey);

        contracts.cashAsset.approve(address(contracts.rollsContract), type(uint).max);
        contracts.providerNFT.approve(address(contracts.rollsContract), providerId);
        uint rollOfferId = contracts.rollsContract.createRollOffer(
            loanId,
            1 ether, // user pays for roll
            5000,
            currentPrice * 90 / 100, // 90% of the current price
            currentPrice * 110 / 100, // 110% of the current price
            0,
            block.timestamp + 1 hours
        );
        vm.stopBroadcast();
        console.log("Roll offer created with ID:", rollOfferId);
        // Accept roll offer
        vm.startBroadcast(userKey);
        contracts.cashAsset.approve(address(contracts.loansContract), type(uint).max);
        contracts.takerNFT.approve(address(contracts.loansContract), loanId);

        // Calculate roll parameters
        (int toTaker,,) = contracts.rollsContract.calculateTransferAmounts(rollOfferId, currentPrice);
        (uint newTakerId, uint newLoanAmount,) =
            contracts.loansContract.rollLoan(loanId, contracts.rollsContract, rollOfferId, toTaker);
        console.log("Roll executed successfully");
        console.log("New Taker ID:", newTakerId);
        console.log("New Loan Amount:", newLoanAmount);

        vm.stopBroadcast();
    }
}
