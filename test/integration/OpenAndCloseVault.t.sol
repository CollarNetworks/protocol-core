// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import { CollarEngine } from "../../src/implementations/CollarEngine.sol";
import { CollarVaultManager } from "../../src/implementations/CollarVaultManager.sol";
import { CollarPool } from "../../src/implementations/CollarPool.sol";
import { ICollarVaultState } from "../../src/interfaces/ICollarVaultState.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ISwapRouter } from "@uni-v3-periphery/interfaces/ISwapRouter.sol";
import { IStaticOracle } from "@mean-finance/interfaces/IStaticOracle.sol";
import { StaticOracle } from "@mean-finance/implementations/StaticOracle.sol";
import { IUniswapV3Factory } from '@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol';
import { PrintVaultStatsUtility } from "../utils/PrintVaultStats.sol";
import { IV3SwapRouter } from "@uniswap/v3-swap-contracts/interfaces/IV3SwapRouter.sol";

// Polygon Addresses for Uniswap V3

// QuoterV2 - - - - - - - - - - - - - - 0x61fFE014bA17989E743c5F6cB21bF9697530B21e
// SwapRouter02 - - - - - - - - - - - - 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45
// UniversalRouter  - - - - - - - - - - 0xec7BE89e9d109e7e3Fec59c222CF297125FEFda2
// NonFungiblePositionManager - - - - - 0xC36442b4a4522E871399CD717aBDD847Ab11FE88
// TickLens - - - - - - - - - - - - - - 0xbfd8137f7d1516D3ea5cA83523914859ec47F573
// WMatic - - - - - - - - - - - - - - - 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270
// USDC - - - - - - - - - - - - - - - - 0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359
// Binance-Hot-Wallet-2 - - - - - - - - 0xe7804c37c13166fF0b37F5aE0BB07A3aEbb6e245
// Uniswap v3 Factory - - - - - - - - - 0x1F98431c8aD98523631AE4a59f267346ea31F984
// WMatic / USDC UniV3 Pool - - - - - - 0x2DB87C4831B2fec2E35591221455834193b50D1B
// Mean Finance Polygon Static Oracle - 0xB210CE856631EeEB767eFa666EC7C1C57738d438

contract CollarOpenAndCloseVaultIntegrationTest is Test, PrintVaultStatsUtility {
    address user = makeAddr("user1"); // the person who will be opening a vault
    address provider = makeAddr("user2"); // the person who will be providing liquidity
    address swapRouterAddress = address(0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45);
    address WMaticAddress = address(0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270);
    address USDCAddress = address(0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359);
    address uniV3Factory = address(0x1F98431c8aD98523631AE4a59f267346ea31F984);
    address binanceHotWalletTwo = address(0xe7804c37c13166fF0b37F5aE0BB07A3aEbb6e245);

    IStaticOracle oracle;

    //address polygonStaticOracleAddress = address(0xB210CE856631EeEB767eFa666EC7C1C57738d438);

    IERC20 WMatic = IERC20(WMaticAddress);
    IERC20 USDC = IERC20(USDCAddress);

    ISwapRouter swapRouter = ISwapRouter(swapRouterAddress);

    CollarEngine engine;
    CollarVaultManager vaultManager;
    CollarPool pool;

    /* We set up the test environment as follows:

    1. We fork Polygon and activate the fork
    2. We deploy the CollarEngine with the dex set to SwapRouter02 from Uniswap on the polygon fork
    3. We add the LTV of 90% to the engine, as well as the cash and collateral assets & duration
    4. We deploy a CollarPool with the following parameters:
        - engine: address of the CollarEngine
        - tickScaleFactor: 100 (1 tick = 1%)
        - cashAsset: USDC
        - collateralAsset: WMatic
        - duration: 1 day
        - ltv: 9000 (90%)
    5. We add the pool to the engine
    6. We give the user USDC and WMatic, as well as the liquidity provider
    7. WE label existing addresses for better test output
    8. We deploy a vault manager for the user
    9. We approve the vault manager to spend the user's USDC and WMatic
    10. We approve the pool to spend the liquidity provider's USDC and WMatic
    11. We add liquidity to the pool in ticks 110 through 115 (as the liquidity provider)

    */

    function setUp() public {
        string memory forkRPC = vm.envString("POLYGON_MAINNET_RPC");
        vm.createSelectFork(forkRPC, 55_850_000);
        assertEq(block.number, 55_850_000);

        oracle = new StaticOracle(IUniswapV3Factory(uniV3Factory), 30);

        engine = new CollarEngine(swapRouterAddress, address(oracle)); // @todo make this non-polygon-exclusive
        engine.addLTV(9000);

        pool = new CollarPool(address(engine), 100, USDCAddress, WMaticAddress, 1 days, 9000);

        engine.addSupportedCashAsset(USDCAddress);
        engine.addSupportedCollateralAsset(WMaticAddress);
        engine.addCollarDuration(1 days);
        engine.addLiquidityPool(address(pool));

        vm.label(user, "USER");
        vm.label(provider, "LIQUIDITY PROVIDER");
        vm.label(address(engine), "ENGINE");
        vm.label(address(pool), "POOL");
        vm.label(swapRouterAddress, "SWAP ROUTER 02");
        vm.label(USDCAddress, "USDC");
        vm.label(WMaticAddress, "WMatic");

        deal(WMaticAddress, user, 100_000 ether);
        deal(WMaticAddress, provider, 100_000 ether);

        deal(USDCAddress, user, 100_000 ether);
        deal(USDCAddress, provider, 100_000 ether);

        startHoax(user);

        vaultManager = CollarVaultManager(engine.createVaultManager());
        USDC.approve(address(vaultManager), 100_000e6);
        WMatic.approve(address(vaultManager), 100_000 ether);

        startHoax(provider);

        USDC.approve(address(pool), 100_000e6);
        WMatic.approve(address(pool), 100_000 ether);

        pool.addLiquidityToSlot(110, 10_000e6);
        pool.addLiquidityToSlot(111, 11_000e6);
        pool.addLiquidityToSlot(112, 12_000e6);
        pool.addLiquidityToSlot(113, 13_000e6);
        pool.addLiquidityToSlot(114, 12_000e6);
        pool.addLiquidityToSlot(115, 11_000e6);

        vm.stopPrank();

        assertEq(engine.isValidCollarDuration(1 days), true);
        assertEq(engine.isValidLTV(9000), true);
        assertEq(engine.isSupportedCashAsset(USDCAddress), true);
        assertEq(engine.isSupportedCollateralAsset(WMaticAddress), true);
        assertEq(engine.addressToVaultManager(user), address(vaultManager));
        assertEq(engine.supportedLiquidityPoolsLength(), 1);
        assertEq(engine.isSupportedLiquidityPool(address(pool)), true);

        assertEq(pool.getLiquidityForSlot(110), 10_000e6);
        assertEq(pool.getLiquidityForSlot(111), 11_000e6);
        assertEq(pool.getLiquidityForSlot(112), 12_000e6);
        assertEq(pool.getLiquidityForSlot(113), 13_000e6);
        assertEq(pool.getLiquidityForSlot(114), 12_000e6);
        assertEq(pool.getLiquidityForSlot(115), 11_000e6);
    }

    function test_openAndCloseVaultUpSlightly() public {
        ICollarVaultState.AssetSpecifiers memory assets = ICollarVaultState.AssetSpecifiers({
            collateralAsset: WMaticAddress,
            collateralAmount: 1000 ether,
            cashAsset: USDCAddress,
            cashAmount: 100e6
        });

        ICollarVaultState.CollarOpts memory collarOpts = ICollarVaultState.CollarOpts({ duration: 1 days, ltv: 9000 });

        ICollarVaultState.LiquidityOpts memory liquidityOpts =
            ICollarVaultState.LiquidityOpts({ liquidityPool: address(pool), putStrikeTick: 90, callStrikeTick: 110 });

        startHoax(user);

        vaultManager.openVault(assets, collarOpts, liquidityOpts);
        bytes32 uuid = vaultManager.getVaultUUID(0);
        bytes memory rawVault = vaultManager.vaultInfo(uuid);
        ICollarVaultState.Vault memory vault = abi.decode(rawVault, (ICollarVaultState.Vault));

        PrintVaultStatsUtility(address(this)).printVaultStats(rawVault, "VAULT OPENED");

        // check basic vault info
        assertEq(vault.active, true);
        assertEq(vault.openedAt, block.timestamp);
        assertEq(vault.expiresAt, block.timestamp + 1 days);
        assertEq(vault.duration, 1 days);
        assertEq(vault.ltv, 9000);

        // check asset specific info
        assertEq(vault.collateralAsset, WMaticAddress);
        assertEq(vault.cashAsset, USDCAddress);
        assertEq(vault.collateralAmount, 1000e18); // we use 1000 "ether" here (it's actually wmatic, but still 18 decimals)
        assertEq(vault.cashAmount, 739_504_999);
        // for the assert directly above this line, we need to consider that the price of wmatic is 73 cents at this time; (specifically: $0.739504999)
        // (which converts to about 739 when considering USDC has 6 decimals and we swapped 1000 wmatic)

        // check liquidity pool stuff
        assertEq(vault.liquidityPool, address(pool));
        assertEq(vault.lockedPoolCash, 73_950_499); // callstrike is 110, so locked pool cash is going to be exactly 10% of the cash received from the swap above
        assertEq(vault.putStrikeTick, 90);
        assertEq(vault.callStrikeTick, 110);
        assertEq(vault.initialCollateralPrice, 739_504); // the initial price of wmatic here is $0.739504
        assertEq(vault.putStrikePrice, 665_553); // put strike is 90%, so putstrike price is just 0.9 * original price
        assertEq(vault.callStrikePrice, 813_454); // same math for callstrike price, just using 1.1 instead

        // check vault specific stuff
        assertEq(vault.loanBalance, 665_554_499); // the vault loan balance should be 0.9 * cashAmount
        assertEq(vault.lockedVaultCash, 73_950_499); // the vault locked balance should be 0.1 * cashAmount

        vm.roll(block.number + 43200);
        skip(1.5 days);

        // close the vault
        vaultManager.closeVault(uuid);

        PrintVaultStatsUtility(address(this)).printVaultStats(rawVault, "VAULT CLOSED");

        // check the numbers on both pool & liquidity sides
        // since the price
    }

    function test_openAndCloseVaultUpALot() public {
        ICollarVaultState.AssetSpecifiers memory assets = ICollarVaultState.AssetSpecifiers({
            collateralAsset: WMaticAddress,
            collateralAmount: 1000 ether,
            cashAsset: USDCAddress,
            cashAmount: 100e6
        });

        ICollarVaultState.CollarOpts memory collarOpts = ICollarVaultState.CollarOpts({ duration: 1 days, ltv: 9000 });

        ICollarVaultState.LiquidityOpts memory liquidityOpts =
            ICollarVaultState.LiquidityOpts({ liquidityPool: address(pool), putStrikeTick: 90, callStrikeTick: 110 });

        startHoax(user);

        vaultManager.openVault(assets, collarOpts, liquidityOpts);
        bytes32 uuid = vaultManager.getVaultUUID(0);
        bytes memory rawVault = vaultManager.vaultInfo(uuid);
        ICollarVaultState.Vault memory vault = abi.decode(rawVault, (ICollarVaultState.Vault));

        PrintVaultStatsUtility(address(this)).printVaultStats(rawVault, "VAULT OPENED");

        // check basic vault info
        assertEq(vault.active, true);
        assertEq(vault.openedAt, block.timestamp);
        assertEq(vault.expiresAt, block.timestamp + 1 days);
        assertEq(vault.duration, 1 days);
        assertEq(vault.ltv, 9000);

        // check asset specific info
        assertEq(vault.collateralAsset, WMaticAddress);
        assertEq(vault.cashAsset, USDCAddress);
        assertEq(vault.collateralAmount, 1000e18); // we use 1000 "ether" here (it's actually wmatic, but still 18 decimals)
        assertEq(vault.cashAmount, 739_504_999);
        // for the assert directly above this line, we need to consider that the price of wmatic is 73 cents at this time; (specifically: $0.739504999)
        // (which converts to about 739 when considering USDC has 6 decimals and we swapped 1000 wmatic)

        // check liquidity pool stuff
        assertEq(vault.liquidityPool, address(pool));
        assertEq(vault.lockedPoolCash, 73_950_499); // callstrike is 110, so locked pool cash is going to be exactly 10% of the cash received from the swap above
        assertEq(vault.putStrikeTick, 90);
        assertEq(vault.callStrikeTick, 110);
        assertEq(vault.initialCollateralPrice, 739_504); // the initial price of wmatic here is $0.739504
        assertEq(vault.putStrikePrice, 665_553); // put strike is 90%, so putstrike price is just 0.9 * original price
        assertEq(vault.callStrikePrice, 813_454); // same math for callstrike price, just using 1.1 instead

        // check vault specific stuff
        assertEq(vault.loanBalance, 665_554_499); // the vault loan balance should be 0.9 * cashAmount
        assertEq(vault.lockedVaultCash, 73_950_499); // the vault locked balance should be 0.1 * cashAmount

        // Trade on Uniswap to make the price go up
        // Impersonate binance-hot-wallet 2 and give tokens to *this* contract
        // so that it can swap on Uni and raise the price of the collateral (by a lot
        // so that we hit our callstrike ceiling)
        
        // @todo see below todo lol

        // this doesn't work, right, because it's a FORK test? maybe?
        // let's test that theory by impersonating instead of dealing.

        // (I may have been wrong about ChatGPT not knowing forge well enough, though
        // it probably does drastically depend on the exact phrasing of your statements)
        // @todo find this our for sure and let JPaul know since I told him the opposite!

        startHoax(binanceHotWalletTwo);

        // @todo develop a little utility to quickly grab the price of a collateral asset
        // in the uniswap pool so that we don't have to print it out as part of the 
        // massive "PrintVaultStatsUtility" thing below

        // q: is 1000 ether enough to actually raise the price past our callstrike?
        // we could calculate, or let's actually just run a quick test & find out / binary search
        
        // approve the dex router for USDC not Wmatic since we know this address has THAT
        // then swap our cash for Wmatic.

        IERC20(USDCAddress).approve(CollarEngine(engine).dexRouter(), assets.collateralAmount * 100);
        IERC20(WMaticAddress).approve(CollarEngine(engine).dexRouter(), assets.collateralAmount * 100);

        // build the swap transaction
        IV3SwapRouter.ExactInputSingleParams memory swapParams = IV3SwapRouter.ExactInputSingleParams({
            tokenIn: assets.collateralAsset,
            tokenOut: assets.cashAsset,
            fee: 3000,
            recipient: address(this),
            amountIn: assets.cashAmount * 100,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        // execute the swap
        // we're not worried about slippage here

        IV3SwapRouter(payable(CollarEngine(engine).dexRouter())).exactInputSingle(swapParams);
        
        // end that prank, keep pranking as `user`

        startHoax(user);

        vm.roll(block.number + 43200);
        skip(1.5 days);

        // close the vault

        vaultManager.closeVault(uuid);

        PrintVaultStatsUtility(address(this)).printVaultStats(rawVault, "VAULT CLOSED");

        // check the numbers on both pool & liquidity sides
        // since the price
    }
}
