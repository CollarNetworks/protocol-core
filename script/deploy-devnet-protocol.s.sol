// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import { ICollarVaultState } from "../src/interfaces/ICollarVaultState.sol";
import { CollarPool } from "../src/implementations/CollarPool.sol";
import { CollarVaultManager } from "../src/implementations/CollarVaultManager.sol";
import { CollarEngine } from "../src/implementations/CollarEngine.sol";

import { TestERC20 } from "../test/utils/TestERC20.sol";
import { MockUniRouter } from "../test/utils/MockUniRouter.sol";
import { MockEngine } from "../test/utils/MockEngine.sol";

import { Multicall3 } from "../lib/other/multicall3.sol";
/**
 * 1. deploys the following contracts:
 * cashTestToken: test ERC20 cash asset for the collar pool
 * collateralTestToken : test ERC20 colaterall asset for the collar pool
 * router: mock uniswap router for the engine
 * engine: Mock collar engine
 * oneDayPool: Collar pool with 1 day duration
 * oneWeekPool: Collar pool with 7 days duration
 * multicall3
 * 2. adds liquidity pools,assets and durations to the engine
 * 3. mints a million of each asset to the router
 * 4. mints 100k and 200k to test addresses
 * 5. creates vault managers for two test addresses
 * 6. adds liquidity to the slots `11_100,11_200,11_500,12_000` for both pools
 */

contract DeployInitializedDevnetProtocol is Script {
    address cashTestToken;
    address collateralTestToken;

    address oneDayPool;
    address oneWeekPool;

    address router;
    address engine;

    address multicall3;

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

        cashTestToken = address(new TestERC20("CashTestToken", "CSH-TST"));
        collateralTestToken = address(new TestERC20("CollateralTestToken", "COL-TST"));
        router = address(new MockUniRouter());
        engine = address(new MockEngine(router, address(0xDEAD)));
        CollarEngine(engine).addLTV(9000);

        oneDayPool = address(new CollarPool(engine, 1, cashTestToken, collateralTestToken, 1 days, 9000));
        oneWeekPool = address(new CollarPool(engine, 1, cashTestToken, collateralTestToken, 7 days, 9000));

        multicall3 = address(new Multicall3());

        CollarEngine(engine).addLiquidityPool(oneDayPool);
        CollarEngine(engine).addLiquidityPool(oneWeekPool);
        CollarEngine(engine).addSupportedCashAsset(cashTestToken);
        CollarEngine(engine).addSupportedCollateralAsset(collateralTestToken);
        CollarEngine(engine).addCollarDuration(100 seconds);
        CollarEngine(engine).addCollarDuration(1 hours);
        CollarEngine(engine).addCollarDuration(1 days);
        CollarEngine(engine).addCollarDuration(7 days);
        CollarEngine(engine).addCollarDuration(30 days);
        CollarEngine(engine).addCollarDuration(180 days);

        TestERC20(cashTestToken).mint(router, 1_000_000e18);
        TestERC20(collateralTestToken).mint(router, 1_000_000e18);

        TestERC20(cashTestToken).mint(testWallet1.addr, 100_000e18);
        TestERC20(cashTestToken).mint(testWallet2.addr, 100_000e18);
        TestERC20(cashTestToken).mint(testWallet3.addr, 200_000e18);

        TestERC20(collateralTestToken).mint(testWallet1.addr, 100_000e18);
        TestERC20(collateralTestToken).mint(testWallet2.addr, 100_000e18);
        TestERC20(collateralTestToken).mint(testWallet3.addr, 200_000e18);

        MockEngine(engine).setCurrentAssetPrice(collateralTestToken, 1e18);

        vm.stopBroadcast();
        vm.startBroadcast(testWallet1.addr);

        address user1VaultManager = address(CollarEngine(engine).createVaultManager());

        vm.stopBroadcast();

        vm.startBroadcast(testWallet2.addr);

        address user2VaultManager = address(CollarEngine(engine).createVaultManager());

        vm.stopBroadcast();

        require(CollarEngine(engine).addressToVaultManager(testWallet1.addr) == user1VaultManager);
        require(CollarEngine(engine).addressToVaultManager(testWallet2.addr) == user2VaultManager);
        /**
         * add liquidity to slots
         */
        vm.startBroadcast(testWallet3.addr);

        TestERC20(cashTestToken).approve(oneDayPool, 100_000 ether);
        TestERC20(cashTestToken).approve(oneWeekPool, 200_000 ether);

        CollarPool(oneDayPool).addLiquidityToSlot(11_100, 10_000 ether);
        CollarPool(oneDayPool).addLiquidityToSlot(11_200, 25_000 ether);
        CollarPool(oneDayPool).addLiquidityToSlot(11_500, 17_500 ether);
        CollarPool(oneDayPool).addLiquidityToSlot(12_000, 20_000 ether);
        CollarPool(oneWeekPool).addLiquidityToSlot(11_100, 10_000 ether);
        CollarPool(oneWeekPool).addLiquidityToSlot(11_200, 25_000 ether);
        CollarPool(oneWeekPool).addLiquidityToSlot(11_500, 17_500 ether);
        CollarPool(oneWeekPool).addLiquidityToSlot(12_000, 20_000 ether);

        vm.stopBroadcast();

        require(CollarEngine(engine).addressToVaultManager(testWallet1.addr) == user1VaultManager);
        require(CollarEngine(engine).addressToVaultManager(testWallet2.addr) == user2VaultManager);

        require(CollarPool(oneDayPool).getLiquidityForSlot(11_100) == 10_000 ether);
        require(CollarPool(oneDayPool).getLiquidityForSlot(11_200) == 25_000 ether);
        require(CollarPool(oneDayPool).getLiquidityForSlot(11_500) == 17_500 ether);
        require(CollarPool(oneDayPool).getLiquidityForSlot(12_000) == 20_000 ether);
        require(CollarPool(oneWeekPool).getLiquidityForSlot(11_100) == 10_000 ether);
        require(CollarPool(oneWeekPool).getLiquidityForSlot(11_200) == 25_000 ether);
        require(CollarPool(oneWeekPool).getLiquidityForSlot(11_500) == 17_500 ether);
        require(CollarPool(oneWeekPool).getLiquidityForSlot(12_000) == 20_000 ether);
        console.log("\n --- Dev Environment Deployed ---");
        console.log("\n # Dev Deployer Address: %x", deployer.addr);
        console.log("\n # Dev Deployer Key:     %x", deployer.privateKey);
        console.log("\n # Multicall3 Contract:  %x", multicall3);
        console.log("\n # Contract Addresses\n");
        console.log(" - Cash Test ERC20 - - - - - ", cashTestToken);
        console.log(" - Collateral Test ERC20 - - ", collateralTestToken);
        console.log(" - Mock Router:  - - - - - - ", router);
        console.log(" - Mock Engine - - - - - - - ", engine);
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
