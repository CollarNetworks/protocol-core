// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import { ICollarVaultState } from "../src/interfaces/ICollarVaultState.sol";
import { IFiatTokenV1 } from "../src/interfaces/external/IFiatTokenV1.sol";
import { CollarPool } from "../src/implementations/CollarPool.sol";
import { CollarVaultManager } from "../src/implementations/CollarVaultManager.sol";
import { CollarEngine } from "../src/implementations/CollarEngine.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
/**
 * THIS SCRIPT ASSUMES A POLYGON MAINNET FORK ENVIRONMENT
 *
 * 1. deploys the following contracts:
 * cashToken:  cash asset for the collar pool
 * collateralToken :  colaterall asset for the collar pool
 * router: uniswap router for the engine
 * engine: collar engine
 * oneDayPool: Collar pool with 1 day duration
 * oneWeekPool: Collar pool with 7 days duration
 *
 * 2. adds liquidity pools,assets and durations to the engine
 * 3. mints a million of each asset to the router
 * 4. mints 100k and 200k to test addresses
 * 5. creates vault managers for two test addresses
 * 6. adds liquidity to the slots `11_100,11_200,11_500,12_000` for both pools
 */

contract DeployInitializedDevnetProtocol is Script {
    using SafeERC20 for IERC20;

    address router;
    address engine;

    address USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address stETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address eETH = 0x35fA164735182de50811E8e2E824cFb9B6118ac2;
    address WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address MATIC = 0x7D1AfA7B718fb893dB30A3aBc0Cfc608AaCfeBB0;
    address swapRouterAddress = address(0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45);

    function run() external {
        VmSafe.Wallet memory deployer = vm.createWallet(vm.envUint("PRIVKEY_DEV_DEPLOYER"));
        VmSafe.Wallet memory user1 = vm.createWallet(vm.envUint("PRIVKEY_DEV_TEST1"));
        VmSafe.Wallet memory user2 = vm.createWallet(vm.envUint("PRIVKEY_DEV_TEST2"));
        VmSafe.Wallet memory liquidityProvider = vm.createWallet(vm.envUint("PRIVKEY_DEV_TEST3"));

        vm.rememberKey(deployer.privateKey);
        vm.rememberKey(user1.privateKey);
        vm.rememberKey(user2.privateKey);
        vm.rememberKey(liquidityProvider.privateKey);

        vm.startBroadcast(deployer.addr);

        router = swapRouterAddress;
        engine = address(new CollarEngine(router));

        // add supported LTV values
        CollarEngine(engine).addLTV(9000);
        CollarEngine(engine).addLTV(5000);
        // add supported durations
        CollarEngine(engine).addCollarDuration(5 minutes);
        CollarEngine(engine).addCollarDuration(30 days);
        CollarEngine(engine).addCollarDuration(12 * 30 days);
        // add supported cash assets
        CollarEngine(engine).addSupportedCashAsset(USDC);
        CollarEngine(engine).addSupportedCashAsset(USDT);
        // add supported collateral assets
        CollarEngine(engine).addSupportedCollateralAsset(WETH);
        CollarEngine(engine).addSupportedCollateralAsset(WBTC);
        CollarEngine(engine).addSupportedCollateralAsset(MATIC);
        CollarEngine(engine).addSupportedCollateralAsset(stETH);
        CollarEngine(engine).addSupportedCollateralAsset(eETH);

        // create main WETH pools
        address fiveMin90ltvPool = address(new CollarPool(engine, 1, USDC, WETH, 5 minutes, 9000));
        address fiveMin90LTVTetherPool = address(new CollarPool(engine, 1, USDT, WETH, 5 minutes, 9000));
        address fiveMin50LTVPool = address(new CollarPool(engine, 1, USDC, WETH, 5 minutes, 5000));
        address oneMonth90LTVPool = address(new CollarPool(engine, 1, USDC, WETH, 30 days, 9000));
        address oneMonth50LTVPool = address(new CollarPool(engine, 1, USDC, WETH, 30 days, 5000));
        address oneYear90LTVPool = address(new CollarPool(engine, 1, USDC, WETH, 12 * 30 days, 9000));
        address oneYear50LTVPool = address(new CollarPool(engine, 1, USDC, WETH, 12 * 30 days, 5000));

        CollarEngine(engine).addLiquidityPool(fiveMin90ltvPool);
        CollarEngine(engine).addLiquidityPool(fiveMin90LTVTetherPool);
        CollarEngine(engine).addLiquidityPool(fiveMin50LTVPool);
        CollarEngine(engine).addLiquidityPool(oneMonth90LTVPool);
        CollarEngine(engine).addLiquidityPool(oneMonth50LTVPool);
        CollarEngine(engine).addLiquidityPool(oneYear90LTVPool);
        CollarEngine(engine).addLiquidityPool(oneYear50LTVPool);

        // rest of pools all 5 minutes with usdc

        address fiveMin90LTVWBTCPool = address(new CollarPool(engine, 1, USDC, WBTC, 5 minutes, 9000));
        address fiveMin90LTVMATICPool = address(new CollarPool(engine, 1, USDC, MATIC, 5 minutes, 9000));
        address fiveMin90LTVstETHPool = address(new CollarPool(engine, 1, USDC, stETH, 5 minutes, 9000));
        address fiveMin90LTVeETHPool = address(new CollarPool(engine, 1, USDC, eETH, 5 minutes, 9000));

        CollarEngine(engine).addLiquidityPool(fiveMin90LTVWBTCPool);
        CollarEngine(engine).addLiquidityPool(fiveMin90LTVMATICPool);
        CollarEngine(engine).addLiquidityPool(fiveMin90LTVstETHPool);
        CollarEngine(engine).addLiquidityPool(fiveMin90LTVeETHPool);

        vm.stopBroadcast();
        vm.startBroadcast(user1.addr);

        address user1VaultManager = address(CollarEngine(engine).createVaultManager());

        vm.stopBroadcast();

        vm.startBroadcast(user2.addr);

        address user2VaultManager = address(CollarEngine(engine).createVaultManager());

        vm.stopBroadcast();

        require(CollarEngine(engine).addressToVaultManager(user1.addr) == user1VaultManager);
        require(CollarEngine(engine).addressToVaultManager(user2.addr) == user2VaultManager);
        console.log("\n --- Dev Environment Deployed ---");
        console.log("\n # Dev Deployer Address: %x", deployer.addr);
        console.log("\n # Dev Deployer Key:     %x", deployer.privateKey);
        console.log("\n # Contract Addresses\n");
        console.log(" - Router:  - - - - - - ", router);
        console.log(" - Engine - - - - - - - ", engine);
        console.log(" - Collar 5 minutes 90LTV WETH/USDC Pool - - - - - - - ", fiveMin90ltvPool);
        console.log(" - Collar 5 minutes 90LTV USDT/WETH Pool - - - - - - - ", fiveMin90LTVTetherPool);
        console.log(" - Collar 5 minutes 50LTV WETH/USDC Pool - - - - - - - ", fiveMin50LTVPool);
        console.log(" - Collar 30 days 90LTV WETH/USDC Pool - - - - - - - - ", oneMonth90LTVPool);
        console.log(" - Collar 30 days 50LTV WETH/USDC Pool - - - - - - - - ", oneMonth50LTVPool);
        console.log(" - Collar 12 months 90LTV WETH/USDC Pool - - - - - - - ", oneYear90LTVPool);
        console.log(" - Collar 12 months 50LTV WETH/USDC Pool - - - - - - - ", oneYear50LTVPool);
        console.log(" - Collar 5 minutes 90LTV WBTC/USDC Pool - - - - - - - ", fiveMin90LTVWBTCPool);
        console.log(" - Collar 5 minutes 90LTV MATIC/USDC Pool - - - - - - - ", fiveMin90LTVMATICPool);
        console.log(" - Collar 5 minutes 90LTV stETH/USDC Pool - - - - - - - ", fiveMin90LTVstETHPool);
        console.log(" - Collar 5 minutes 90LTV eETH/USDC Pool - - - - - - - ", fiveMin90LTVeETHPool);
        console.log("\n # Test Users\n");
        console.log(" - User 1 Address: %s", user1.addr);
        console.log(" - User 1 Privkey: %x", user1.privateKey);
        console.log(" - User 2 Address: %s", user2.addr);
        console.log(" - User 2 Privkey: %x", user2.privateKey);
        console.log(" - Liquidity provider Address: %s", liquidityProvider.addr);
        console.log(" - Liquidity provider Privkey: %x", liquidityProvider.privateKey);
        console.log("\n # Vault Managers\n");
        console.log(" - User 1 Vault Manager: ", user1VaultManager);
        console.log(" - User 2 Vault Manager: ", user2VaultManager);
        console.log("\n");

        console.log("Verifying deployment : ");

        // supportedLiquidityPoolsLength
        uint256 shouldBePoolLength = CollarEngine(engine).supportedLiquidityPoolsLength();
        console.log(" shouldBePoolLength", shouldBePoolLength);
        require(shouldBePoolLength == 11);

        // getSupportedLiquidityPool
        address shouldBeOneDay = CollarEngine(engine).getSupportedLiquidityPool(0);
        console.log(" shouldBeOneDay", shouldBeOneDay);
        require(shouldBeOneDay == fiveMin90ltvPool);

        // setup pool liquidity // assume provider has enough funds

        // add liquidity to each pool
        /**
         * @dev in order for this part to work provider address needs to be funded with casdh assets through tenderly previously
         */
        uint256 amountToAdd = 100_000e6;
        vm.startBroadcast(liquidityProvider.addr);

        IERC20(USDC).forceApprove(fiveMin90ltvPool, 1_000_000e6);
        CollarPool(fiveMin90ltvPool).addLiquidityToSlot(11_100, amountToAdd);
        CollarPool(fiveMin90ltvPool).addLiquidityToSlot(11_200, amountToAdd);
        CollarPool(fiveMin90ltvPool).addLiquidityToSlot(11_500, amountToAdd);
        CollarPool(fiveMin90ltvPool).addLiquidityToSlot(12_000, amountToAdd);

        IERC20(USDT).forceApprove(fiveMin90LTVTetherPool, 1_000_000e6);
        CollarPool(fiveMin90LTVTetherPool).addLiquidityToSlot(11_100, amountToAdd);
        CollarPool(fiveMin90LTVTetherPool).addLiquidityToSlot(11_200, amountToAdd);
        CollarPool(fiveMin90LTVTetherPool).addLiquidityToSlot(11_500, amountToAdd);
        CollarPool(fiveMin90LTVTetherPool).addLiquidityToSlot(12_000, amountToAdd);

        IERC20(USDC).forceApprove(fiveMin50LTVPool, 1_000_000e6);
        CollarPool(fiveMin50LTVPool).addLiquidityToSlot(11_100, amountToAdd);
        CollarPool(fiveMin50LTVPool).addLiquidityToSlot(11_200, amountToAdd);
        CollarPool(fiveMin50LTVPool).addLiquidityToSlot(11_500, amountToAdd);
        CollarPool(fiveMin50LTVPool).addLiquidityToSlot(12_000, amountToAdd);

        IERC20(USDC).forceApprove(oneMonth90LTVPool, 1_000_000e6);
        CollarPool(oneMonth90LTVPool).addLiquidityToSlot(11_100, amountToAdd);
        CollarPool(oneMonth90LTVPool).addLiquidityToSlot(11_200, amountToAdd);
        CollarPool(oneMonth90LTVPool).addLiquidityToSlot(11_500, amountToAdd);
        CollarPool(oneMonth90LTVPool).addLiquidityToSlot(12_000, amountToAdd);

        IERC20(USDC).forceApprove(oneMonth50LTVPool, 1_000_000e6);
        CollarPool(oneMonth50LTVPool).addLiquidityToSlot(11_100, amountToAdd);
        CollarPool(oneMonth50LTVPool).addLiquidityToSlot(11_200, amountToAdd);
        CollarPool(oneMonth50LTVPool).addLiquidityToSlot(11_500, amountToAdd);
        CollarPool(oneMonth50LTVPool).addLiquidityToSlot(12_000, amountToAdd);

        IERC20(USDC).forceApprove(oneYear90LTVPool, 1_000_000e6);
        CollarPool(oneYear90LTVPool).addLiquidityToSlot(11_100, amountToAdd);
        CollarPool(oneYear90LTVPool).addLiquidityToSlot(11_200, amountToAdd);
        CollarPool(oneYear90LTVPool).addLiquidityToSlot(11_500, amountToAdd);
        CollarPool(oneYear90LTVPool).addLiquidityToSlot(12_000, amountToAdd);

        IERC20(USDC).forceApprove(oneYear50LTVPool, 1_000_000e6);
        CollarPool(oneYear50LTVPool).addLiquidityToSlot(11_100, amountToAdd);
        CollarPool(oneYear50LTVPool).addLiquidityToSlot(11_200, amountToAdd);
        CollarPool(oneYear50LTVPool).addLiquidityToSlot(11_500, amountToAdd);
        CollarPool(oneYear50LTVPool).addLiquidityToSlot(12_000, amountToAdd);

        IERC20(USDC).forceApprove(fiveMin90LTVWBTCPool, 1_000_000e6);
        CollarPool(fiveMin90LTVWBTCPool).addLiquidityToSlot(11_100, amountToAdd);
        CollarPool(fiveMin90LTVWBTCPool).addLiquidityToSlot(11_200, amountToAdd);
        CollarPool(fiveMin90LTVWBTCPool).addLiquidityToSlot(11_500, amountToAdd);
        CollarPool(fiveMin90LTVWBTCPool).addLiquidityToSlot(12_000, amountToAdd);

        IERC20(USDC).forceApprove(fiveMin90LTVMATICPool, 1_000_000e6);
        CollarPool(fiveMin90LTVMATICPool).addLiquidityToSlot(11_100, amountToAdd);
        CollarPool(fiveMin90LTVMATICPool).addLiquidityToSlot(11_200, amountToAdd);
        CollarPool(fiveMin90LTVMATICPool).addLiquidityToSlot(11_500, amountToAdd);
        CollarPool(fiveMin90LTVMATICPool).addLiquidityToSlot(12_000, amountToAdd);

        IERC20(USDC).forceApprove(fiveMin90LTVstETHPool, 1_000_000e6);
        CollarPool(fiveMin90LTVstETHPool).addLiquidityToSlot(11_100, amountToAdd);
        CollarPool(fiveMin90LTVstETHPool).addLiquidityToSlot(11_200, amountToAdd);
        CollarPool(fiveMin90LTVstETHPool).addLiquidityToSlot(11_500, amountToAdd);
        CollarPool(fiveMin90LTVstETHPool).addLiquidityToSlot(12_000, amountToAdd);

        IERC20(USDC).forceApprove(fiveMin90LTVeETHPool, 1_000_000e6);
        CollarPool(fiveMin90LTVeETHPool).addLiquidityToSlot(11_100, amountToAdd);
        CollarPool(fiveMin90LTVeETHPool).addLiquidityToSlot(11_200, amountToAdd);
        CollarPool(fiveMin90LTVeETHPool).addLiquidityToSlot(11_500, amountToAdd);
        CollarPool(fiveMin90LTVeETHPool).addLiquidityToSlot(12_000, amountToAdd);

        vm.stopBroadcast();
    }
}
