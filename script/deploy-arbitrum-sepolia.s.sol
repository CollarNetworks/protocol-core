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
import { IUniswapV3Factory } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import { CollarOwnedERC20 } from "../src//utils/CollarOwnedERC20.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import { IV3SwapRouter } from "@uniswap/swap-router-contracts/contracts/interfaces/IV3SwapRouter.sol";

contract DeployArbitrumSepoliaProtocol is Script {
    using SafeERC20 for IERC20;

    uint constant chainId = 421_614; // Arbitrum Sepolia
    address constant uniswapV3FactoryAddress = 0x248AB79Bbb9bC29bB72f7Cd42F17e054Fc40188e; // Arbitrum Sepolia UniswapV3Factory
    uint24 constant POOL_FEE = 3000;
    uint[] public callStrikeTicks = [11_100, 11_200, 11_500, 12_000];

    struct DeployedContracts {
        address cashAsset;
        address collateralAsset;
        address providerNFT;
        address takerNFT;
        address loansContract;
        address uniswapPool;
    }

    IV3SwapRouter constant SWAP_ROUTER = IV3SwapRouter(0x101F443B4d1b059569D643917553c771E1b9663E);
    IERC20 constant COLLATERAL_TOKEN = IERC20(0x12576dc597a66A1627b75F6E9A9673e935E0f8F2);
    IERC20 constant CASH_TOKEN = IERC20(0x8FC21A6C07C9A83AcaaeB97E5F23bDf24521da5d);
    address constant POSITION_MANAGER = 0x6b2937Bde17889EDCf8fbD8dE31C3C2a70Bc4d65;

    function setUp() public { }

    function run() external {
        require(block.chainid == chainId, "Wrong chain");

        uint deployerPrivateKey = vm.envUint("PRIVKEY_DEV_DEPLOYER");
        address deployer = vm.addr(deployerPrivateKey);
        address liquidityProvider = vm.addr(vm.envUint("LIQUIDITY_PROVIDER_KEY"));

        vm.startBroadcast(deployerPrivateKey);

        // Deploy and setup engine
        CollarEngine engine = new CollarEngine(address(SWAP_ROUTER));
        engine.addLTV(9000);
        engine.addCollarDuration(300);

        DeployedContracts memory contracts = deployContracts(address(engine), deployer);

        vm.stopBroadcast();
        console.log("Engine deployed at:", address(engine));
        console.log("Cash Asset deployed at:", contracts.cashAsset);
        console.log("Collateral Asset deployed at:", contracts.collateralAsset);
        console.log("TakerNFT deployed at:", contracts.takerNFT);
        console.log("ProviderNFT deployed at:", contracts.providerNFT);
        console.log("Loans contract deployed at:", contracts.loansContract);
        console.log("Uniswap V3 pool created at:", contracts.uniswapPool);

        // Verify deployment
        _verifyDeployment(address(engine), contracts);

        // Create offers
        _createOffers(
            deployerPrivateKey,
            contracts.providerNFT,
            contracts.cashAsset,
            contracts.collateralAsset,
            liquidityProvider
        );

        // Verify offers
        _verifyOffers(contracts.providerNFT, liquidityProvider);

        // add liquidity to the new asset pool
        _addLiquidityToPool(liquidityProvider, contracts.uniswapPool);
    }

    function deployContracts(address engine, address deployer) internal returns (DeployedContracts memory) {
        // Deploy custom ERC20 tokens
        address cashAsset = address(new CollarOwnedERC20(deployer, "Cash Asset", "CASH"));
        address collateralAsset = address(new CollarOwnedERC20(deployer, "Collateral Asset", "COLL"));
        console.log("Collateral asset address:", collateralAsset);
        console.log("Cash asset address:", cashAsset);
        CollarOwnedERC20(collateralAsset).mint(deployer, 1_000_000e18);
        CollarOwnedERC20(cashAsset).mint(deployer, 1_000_000e18);
        // check total supply
        console.log("cashAsset total supply:", CollarOwnedERC20(cashAsset).totalSupply());
        console.log("collateralAsset total supply:", CollarOwnedERC20(collateralAsset).totalSupply());
        // Debug: Check if tokens exist
        console.log("collateralAsset code size:", address(collateralAsset).code.length);
        console.log("cashAsset code size:", address(cashAsset).code.length);

        IUniswapV3Factory factory = IUniswapV3Factory(uniswapV3FactoryAddress);
        // check factory owner
        console.log("Factory owner:", factory.owner());
        // check fee tier is enabled
        console.logInt(factory.feeAmountTickSpacing(POOL_FEE));
        // Check if pool already exists
        address existingPool = factory.getPool(collateralAsset, cashAsset, POOL_FEE);
        console.log("Existing pool address:", existingPool);
        // Create Uniswap V3 pool
        address pool = existingPool;
        if (existingPool == address(0)) {
            pool = factory.createPool(cashAsset, collateralAsset, POOL_FEE);
        }

        // Add support for assets in the engine
        CollarEngine(engine).addSupportedCashAsset(cashAsset);
        CollarEngine(engine).addSupportedCollateralAsset(collateralAsset);

        // Deploy contract pair
        address takerNFT = address(
            new CollarTakerNFT(
                deployer,
                CollarEngine(engine),
                IERC20(cashAsset),
                IERC20(collateralAsset),
                "Taker CASH/COLL",
                "TCASH/COLL"
            )
        );
        address providerNFT = address(
            new ProviderPositionNFT(
                deployer,
                CollarEngine(engine),
                IERC20(cashAsset),
                IERC20(collateralAsset),
                takerNFT,
                "Provider CASH/COLL",
                "PCASH/COLL"
            )
        );
        address loansContract = address(
            new Loans(
                deployer,
                CollarEngine(engine),
                CollarTakerNFT(takerNFT),
                IERC20(cashAsset),
                IERC20(collateralAsset)
            )
        );

        CollarEngine(engine).setCollarTakerContractAuth(takerNFT, true);
        CollarEngine(engine).setProviderContractAuth(providerNFT, true);

        return DeployedContracts({
            cashAsset: cashAsset,
            collateralAsset: collateralAsset,
            providerNFT: providerNFT,
            takerNFT: takerNFT,
            loansContract: loansContract,
            uniswapPool: pool
        });
    }

    function _verifyDeployment(address engine, DeployedContracts memory contracts) internal view {
        require(CollarEngine(engine).isCollarTakerNFT(contracts.takerNFT), "TakerNFT not authorized");
        require(CollarEngine(engine).isProviderNFT(contracts.providerNFT), "ProviderNFT not authorized");
        require(CollarEngine(engine).isSupportedCashAsset(contracts.cashAsset), "Cash asset not supported");
        require(
            CollarEngine(engine).isSupportedCollateralAsset(contracts.collateralAsset),
            "Collateral asset not supported"
        );
        require(CollarEngine(engine).isValidLTV(9000), "LTV 9000 not supported");
        require(CollarEngine(engine).isValidCollarDuration(300), "300 duration not supported");
        console.log("Deployment verified successfully");
    }

    function _createOffers(
        uint deployerPrivateKey,
        address providerNFT,
        address cashAsset,
        address collateralAsset,
        address liquidityProvider
    ) internal {
        vm.startBroadcast(deployerPrivateKey);

        // Mint tokens for liquidity provider
        CollarOwnedERC20(cashAsset).mint(liquidityProvider, 1_000_000 ether);
        CollarOwnedERC20(collateralAsset).mint(liquidityProvider, 1_000_000 ether);

        vm.stopBroadcast();

        vm.startBroadcast(vm.envUint("LIQUIDITY_PROVIDER_KEY"));

        uint amountToAdd = 100_000e18; // 100,000 CASH tokens
        IERC20(cashAsset).approve(providerNFT, type(uint).max);

        for (uint i = 0; i < callStrikeTicks.length; i++) {
            ProviderPositionNFT(providerNFT).createOffer(callStrikeTicks[i], amountToAdd, 9000, 300);
        }

        vm.stopBroadcast();
        console.log("Offers created successfully");
    }

    function _verifyOffers(address providerNFT, address liquidityProvider) internal view {
        ProviderPositionNFT provider = ProviderPositionNFT(providerNFT);

        for (uint i = 0; i < callStrikeTicks.length; i++) {
            ProviderPositionNFT.LiquidityOffer memory offer = provider.getOffer(i);
            require(offer.provider == liquidityProvider, "Incorrect offer provider");
            require(offer.available == 100_000e6, "Incorrect offer amount");
            require(offer.putStrikeDeviation == 9000, "Incorrect LTV");
            require(offer.duration == 300, "Incorrect duration");
            require(offer.callStrikeDeviation == callStrikeTicks[i], "Incorrect call strike deviation");
        }

        console.log("Offers verified successfully");
    }

    function _addLiquidityToPool(address provider, address pool) internal {
        vm.startBroadcast(provider);
        CollarOwnedERC20(address(CASH_TOKEN)).mint(provider, 10_000_000 ether);
        CollarOwnedERC20(address(COLLATERAL_TOKEN)).mint(provider, 10_000_000 ether);
        // Approve tokens
        IERC20(COLLATERAL_TOKEN).approve(POSITION_MANAGER, type(uint).max);
        IERC20(CASH_TOKEN).approve(POSITION_MANAGER, type(uint).max);

        // Get current tick
        (, int24 currentTick,,,,,) = IUniswapV3Pool(pool).slot0();

        // Set price range
        int24 tickLower = currentTick - 600;
        int24 tickUpper = currentTick + 600;

        // Amount of tokens to add as liquidity
        uint amount0Desired = 10_000_000 ether;
        uint amount1Desired = 10_000_000 ether;

        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: address(COLLATERAL_TOKEN),
            token1: address(CASH_TOKEN),
            fee: POOL_FEE,
            tickLower: tickLower,
            tickUpper: tickUpper,
            amount0Desired: amount0Desired,
            amount1Desired: amount1Desired,
            amount0Min: 0,
            amount1Min: 0,
            recipient: provider,
            deadline: block.timestamp + 15 minutes
        });

        // Add liquidity
        (uint tokenId, uint128 liquidity, uint amount0, uint amount1) =
            INonfungiblePositionManager(POSITION_MANAGER).mint(params);

        console.log("Liquidity added:");
        console.log("Token ID:", tokenId);
        console.log("Liquidity:", liquidity);
        console.log("Amount of token0:", amount0);
        console.log("Amount of token1:", amount1);
    }
}
