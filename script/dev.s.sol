// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import { CollarVaultState } from "../src/libs/CollarLibs.sol";
import { CollarPool } from "../src/implementations/CollarPool.sol";
import { CollarVaultManager } from "../src/implementations/CollarVaultManager.sol";
import { CollarEngine } from "../src/implementations/CollarEngine.sol";

import { TestERC20 } from "../test/utils/TestERC20.sol";
import { MockUniRouter } from "../test/utils/MockUniRouter.sol";
import { MockEngine } from "../test/utils/MockEngine.sol";

import { Multicall3 } from "../lib/other/multicall3.sol";

contract DeployEmptyProtocol is Script {
    address cashTestToken;
    address collateralTestToken;

    address pool;

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
        engine = address(new MockEngine(router));
        pool = address(new CollarPool(engine, 1, cashTestToken));

        multicall3 = address(new Multicall3());

        CollarEngine(engine).addLiquidityPool(pool);
        CollarEngine(engine).addSupportedCashAsset(cashTestToken);
        CollarEngine(engine).addSupportedCollateralAsset(collateralTestToken);

        TestERC20(cashTestToken).mint(router, 1000000e18);
        TestERC20(collateralTestToken).mint(router, 1000000e18);

        vm.stopBroadcast();

        console.log("\n --- Dev Environment Deployed ---");
        console.log("\n # Dev Deployer Address: %x", deployer.addr);
        console.log("\n # Dev Deployer Key:     %x", deployer.privateKey);
        console.log("\n # Multicall3 Contract:  %x", multicall3);
        console.log("\n # Contract Addresses\n");
        console.log(" - Cash Test ERC20 - - - - - ", cashTestToken);
        console.log(" - Collateral Test ERC20 - - ", collateralTestToken);
        console.log(" - Mock Router:  - - - - - - ", router);
        console.log(" - Mock Engine - - - - - - - ", engine);
        console.log(" - Collar Pool - - - - - - - ", pool);
        console.log("\n # Test Users\n");
        console.log(" - User 1 Address: %x", testWallet1.addr);
        console.log(" - User 1 Privkey: %x", testWallet1.privateKey);
        console.log(" - User 2 Address: %x", testWallet2.addr);
        console.log(" - User 2 Privkey: %x", testWallet2.privateKey);
        console.log(" - User 3 Address: %x", testWallet3.addr);
        console.log(" - User 3 Privkey: %x", testWallet3.privateKey);
    }
}

contract DeployInitializedProtocol is Script {
    address cashTestToken;
    address collateralTestToken;

    address pool;

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
        engine = address(new MockEngine(router));
        pool = address(new CollarPool(engine, 1, cashTestToken));

        multicall3 = address(new Multicall3());

        CollarEngine(engine).addLiquidityPool(pool);
        CollarEngine(engine).addSupportedCashAsset(cashTestToken);
        CollarEngine(engine).addSupportedCollateralAsset(collateralTestToken);

        TestERC20(cashTestToken).mint(router, 1000000e18);
        TestERC20(collateralTestToken).mint(router, 1000000e18);

        TestERC20(cashTestToken).mint(testWallet1.addr, 100000e18);
        TestERC20(cashTestToken).mint(testWallet2.addr, 100000e18);
        TestERC20(cashTestToken).mint(testWallet3.addr, 100000e18);

        TestERC20(collateralTestToken).mint(testWallet1.addr, 100000e18);
        TestERC20(collateralTestToken).mint(testWallet2.addr, 100000e18);
        TestERC20(collateralTestToken).mint(testWallet3.addr, 100000e18);

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

        console.log("\n --- Dev Environment Deployed ---");
        console.log("\n # Dev Deployer Address: %x", deployer.addr);
        console.log("\n # Dev Deployer Key:     %x", deployer.privateKey);
        console.log("\n # Multicall3 Contract:  %x", multicall3);
        console.log("\n # Contract Addresses\n");
        console.log(" - Cash Test ERC20 - - - - - ", cashTestToken);
        console.log(" - Collateral Test ERC20 - - ", collateralTestToken);
        console.log(" - Mock Router:  - - - - - - ", router);
        console.log(" - Mock Engine - - - - - - - ", engine);
        console.log(" - Collar Pool - - - - - - - ", pool);
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
    }
}
