// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import { ICollarVaultState } from "../src/interfaces/ICollarVaultState.sol";
import { CollarPool } from "../src/implementations/CollarPool.sol";
import { CollarVaultManager } from "../src/implementations/CollarVaultManager.sol";
import { CollarEngine } from "../src/implementations/CollarEngine.sol";

import { TestERC20 } from "../test/utils/TestERC20.sol";
import { Multicall3 } from "../lib/other/multicall3.sol";

// Polygon Addresses for UniswapV3
// QuoterV2 - 0x61fFE014bA17989E743c5F6cB21bF9697530B21e
// SwapRouter02 - 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45
// UniversalRouter - 0xec7BE89e9d109e7e3Fec59c222CF297125FEFda2
// NonFungiblePositionManager - 0xC36442b4a4522E871399CD717aBDD847Ab11FE88
// TickLens - 0xbfd8137f7d1516D3ea5cA83523914859ec47F573

contract DeployWithUniswapIntegrationOnPolygonFork is Script {
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
        router = address(0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45);
        engine = address(new CollarEngine(router));

        CollarEngine(engine).addLTV(9000);

        pool = address(new CollarPool(engine, 1, cashTestToken, collateralTestToken, 100, 9000));

        multicall3 = address(new Multicall3());

        CollarEngine(engine).addLiquidityPool(pool);
        CollarEngine(engine).addSupportedCashAsset(cashTestToken);
        CollarEngine(engine).addSupportedCollateralAsset(collateralTestToken);
        CollarEngine(engine).addCollarDuration(100 seconds);
        CollarEngine(engine).addCollarDuration(1 hours);
        CollarEngine(engine).addCollarDuration(1 days);
        CollarEngine(engine).addCollarDuration(30 days);
        CollarEngine(engine).addCollarDuration(180 days);

        TestERC20(cashTestToken).mint(router, 1_000_000 ether);
        TestERC20(collateralTestToken).mint(router, 1_000_000 ether);

        TestERC20(cashTestToken).mint(testWallet1.addr, 100_000 ether);
        TestERC20(cashTestToken).mint(testWallet2.addr, 100_000 ether);
        TestERC20(cashTestToken).mint(testWallet3.addr, 100_000 ether);

        TestERC20(collateralTestToken).mint(testWallet1.addr, 100_000 ether);
        TestERC20(collateralTestToken).mint(testWallet2.addr, 100_000 ether);
        TestERC20(collateralTestToken).mint(testWallet3.addr, 100_000 ether);

        vm.stopBroadcast();
        vm.startBroadcast(testWallet1.addr);

        address user1VaultManager = address(CollarEngine(engine).createVaultManager());

        vm.stopBroadcast();

        vm.startBroadcast(testWallet2.addr);

        address user2VaultManager = address(CollarEngine(engine).createVaultManager());

        vm.stopBroadcast();

        vm.startBroadcast(testWallet3.addr);

        TestERC20(cashTestToken).approve(pool, 100_000 ether);

        CollarPool(pool).addLiquidityToSlot(11_100, 10_000 ether);
        CollarPool(pool).addLiquidityToSlot(11_200, 25_000 ether);
        CollarPool(pool).addLiquidityToSlot(11_500, 17_500 ether);
        CollarPool(pool).addLiquidityToSlot(12_000, 20_000 ether);

        vm.stopBroadcast();

        require(CollarEngine(engine).addressToVaultManager(testWallet1.addr) == user1VaultManager);
        require(CollarEngine(engine).addressToVaultManager(testWallet2.addr) == user2VaultManager);

        require(CollarPool(pool).getLiquidityForSlot(11_100) == 10_000 ether);
        require(CollarPool(pool).getLiquidityForSlot(11_200) == 25_000 ether);
        require(CollarPool(pool).getLiquidityForSlot(11_500) == 17_500 ether);
        require(CollarPool(pool).getLiquidityForSlot(12_000) == 20_000 ether);

        console.log("\n --- Dev Environment Deployed ---");
        console.log("\n # Dev Deployer Address: %x", deployer.addr);
        console.log("\n # Dev Deployer Key:     %x", deployer.privateKey);
        console.log("\n # Multicall3 Contract:  %x", multicall3);
        console.log("\n # Contract Addresses\n");
        console.log(" - Cash Test ERC20 - - - - - ", cashTestToken);
        console.log(" - Collateral Test ERC20 - - ", collateralTestToken);
        console.log(" - UniV3 Router2:  - - - - - - ", router);
        console.log(" - Collar Engine - - - - - - - ", engine);
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
