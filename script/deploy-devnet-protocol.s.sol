// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import { ICollarVaultState } from "../src/interfaces/ICollarVaultState.sol";
import { CollarPool } from "../src/implementations/CollarPool.sol";
import { CollarVaultManager } from "../src/implementations/CollarVaultManager.sol";
import { CollarEngine } from "../src/implementations/CollarEngine.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
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
    address cashToken;
    address collateralToken;

    address oneDayPool;
    address oneWeekPool;

    address router;
    address engine;

    address USDC = 0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359;
    address WMATIC = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;
    address swapRouterAddress = address(0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45);
    address uniV3Pool = address(0x2DB87C4831B2fec2E35591221455834193b50D1B);

    function run() external {
        VmSafe.Wallet memory deployer = vm.createWallet(vm.envUint("PRIVKEY_DEV_DEPLOYER"));
        VmSafe.Wallet memory testWallet1 = vm.createWallet(vm.envUint("PRIVKEY_DEV_TEST1"));
        VmSafe.Wallet memory testWallet2 = vm.createWallet(vm.envUint("PRIVKEY_DEV_TEST2"));
        VmSafe.Wallet memory testWallet3 = vm.createWallet(vm.envUint("PRIVKEY_DEV_TEST3"));

        vm.rememberKey(deployer.privateKey);
        vm.rememberKey(testWallet1.privateKey);
        vm.rememberKey(testWallet2.privateKey);
        vm.rememberKey(testWallet3.privateKey);

        vm.startBroadcast(deployer.addr);

        cashToken = USDC;
        collateralToken = WMATIC;
        router = swapRouterAddress;
        engine = address(new CollarEngine(router));
        CollarEngine(engine).addLTV(9000);

        oneDayPool = address(new CollarPool(engine, 1, cashToken, collateralToken, 1 days, 9000));
        oneWeekPool = address(new CollarPool(engine, 1, cashToken, collateralToken, 7 days, 9000));

        CollarEngine(engine).addLiquidityPool(oneDayPool);
        CollarEngine(engine).addLiquidityPool(oneWeekPool);
        CollarEngine(engine).addSupportedCashAsset(cashToken);
        CollarEngine(engine).addSupportedCollateralAsset(collateralToken);
        CollarEngine(engine).addCollarDuration(100 seconds);
        CollarEngine(engine).addCollarDuration(1 hours);
        CollarEngine(engine).addCollarDuration(1 days);
        CollarEngine(engine).addCollarDuration(7 days);
        CollarEngine(engine).addCollarDuration(30 days);
        CollarEngine(engine).addCollarDuration(180 days);
        vm.stopBroadcast();
        vm.startBroadcast(testWallet1.addr);

        address user1VaultManager = address(CollarEngine(engine).createVaultManager());

        vm.stopBroadcast();

        vm.startBroadcast(testWallet2.addr);

        address user2VaultManager = address(CollarEngine(engine).createVaultManager());

        vm.stopBroadcast();

        require(CollarEngine(engine).addressToVaultManager(testWallet1.addr) == user1VaultManager);
        require(CollarEngine(engine).addressToVaultManager(testWallet2.addr) == user2VaultManager);
        console.log("\n --- Dev Environment Deployed ---");
        console.log("\n # Dev Deployer Address: %x", deployer.addr);
        console.log("\n # Dev Deployer Key:     %x", deployer.privateKey);
        console.log("\n # Contract Addresses\n");
        console.log(" - Cash ERC20 - - - - - ", cashToken);
        console.log(" - Collateral ERC20 - - ", collateralToken);
        console.log(" - Router:  - - - - - - ", router);
        console.log(" - Engine - - - - - - - ", engine);
        console.log(" - Collar One day Pool - - - - - - - ", oneDayPool);
        console.log(" - Collar One week Pool - - - - - - - ", oneWeekPool);
        console.log("\n # Test Users\n");
        console.log(" - User 1 Address: %s", testWallet1.addr);
        console.log(" - User 1 Privkey: %x", testWallet1.privateKey);
        console.log(" - User 2 Address: %s", testWallet2.addr);
        console.log(" - User 2 Privkey: %x", testWallet2.privateKey);
        console.log(" - User 3 Address: %s", testWallet3.addr);
        console.log(" - User 3 Privkey: %x", testWallet3.privateKey);
        console.log("\n # Vault Managers\n");
        console.log(" - User 1 Vault Manager: ", user1VaultManager);
        console.log(" - User 2 Vault Manager: ", user2VaultManager);
        console.log("\n");

        console.log("Verifying deployment : ");

        // supportedLiquidityPoolsLength
        uint256 shouldBePoolLength = CollarEngine(engine).supportedLiquidityPoolsLength();
        console.log(" shouldBePoolLength", shouldBePoolLength);
        require(shouldBePoolLength == 2);

        // getSupportedLiquidityPool
        address shouldBeOneDay = CollarEngine(engine).getSupportedLiquidityPool(0);
        console.log(" shouldBeOneDay", shouldBeOneDay);
        require(shouldBeOneDay == oneDayPool);
    }
}
