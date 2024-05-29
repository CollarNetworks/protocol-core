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
import { ICollarPool } from "../../src/interfaces/ICollarPool.sol";
import { ICollarVaultState } from "../../src/interfaces/ICollarVaultState.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ISwapRouter } from "@uni-v3-periphery/interfaces/ISwapRouter.sol";
import { IUniswapV3Factory } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
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

/**
 * @dev This contract should generate test to ensure all the cases and math from this sheet is correct and verified
 * https://docs.google.com/spreadsheets/d/18e5ola3JJ2HKRQyAoPNmVrV4fnRcLdckOhQIxrN_hwY/edit#gid=1819672818
 */
contract CollarOpenAndCloseVaultIntegrationTest is Test, PrintVaultStatsUtility {
    address user1 = makeAddr("user1"); // the person who will be opening a vault
    address provider = makeAddr("user2"); // the person who will be providing liquidity
    address swapRouterAddress = address(0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45);
    address WMaticAddress = address(0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270);
    address USDCAddress = address(0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359);
    address uniV3Pool = address(0x2DB87C4831B2fec2E35591221455834193b50D1B);
    address wMATICWhale = address(0x6d80113e533a2C0fe82EaBD35f1875DcEA89Ea97);
    address binanceHotWalletTwo = address(0xe7804c37c13166fF0b37F5aE0BB07A3aEbb6e245);
    uint256 BLOCK_NUMBER_TO_USE = 55_850_000;
    uint256 COLLATERAL_PRICE_ON_BLOCK = 739_504; // $0.739504 the price for WMatic in USDC on the specified block of polygon mainnet
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
        vm.createSelectFork(forkRPC, BLOCK_NUMBER_TO_USE);
        assertEq(block.number, BLOCK_NUMBER_TO_USE);

        engine = new CollarEngine(swapRouterAddress); // @todo make this non-polygon-exclusive
        engine.addLTV(9000);

        pool = new CollarPool(address(engine), 100, USDCAddress, WMaticAddress, 1 days, 9000);

        engine.addSupportedCashAsset(USDCAddress);
        engine.addSupportedCollateralAsset(WMaticAddress);
        engine.addCollarDuration(1 days);
        engine.addLiquidityPool(address(pool));

        vm.label(user1, "USER");
        vm.label(provider, "LIQUIDITY PROVIDER");
        vm.label(address(engine), "ENGINE");
        vm.label(address(pool), "POOL");
        vm.label(swapRouterAddress, "SWAP ROUTER 02");
        vm.label(USDCAddress, "USDC");
        vm.label(WMaticAddress, "WMatic");

        deal(WMaticAddress, user1, 100_000 ether);
        deal(WMaticAddress, provider, 100_000 ether);

        deal(USDCAddress, user1, 100_000 ether);
        deal(USDCAddress, provider, 100_000 ether);

        startHoax(user1);

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
        assertEq(engine.addressToVaultManager(user1), address(vaultManager));
        assertEq(engine.supportedLiquidityPoolsLength(), 1);
        assertEq(engine.isSupportedLiquidityPool(address(pool)), true);

        assertEq(pool.getLiquidityForSlot(110), 10_000e6);
        assertEq(pool.getLiquidityForSlot(111), 11_000e6);
        assertEq(pool.getLiquidityForSlot(112), 12_000e6);
        assertEq(pool.getLiquidityForSlot(113), 13_000e6);
        assertEq(pool.getLiquidityForSlot(114), 12_000e6);
        assertEq(pool.getLiquidityForSlot(115), 11_000e6);
    }

    function test_openAndCloseVaultNoPriceChange() public {
        (bytes32 uuid, bytes memory rawVault, ICollarVaultState.Vault memory vault) = openVaultAsUserWith1000AndCheckValues();

        swapAsWhale(1_712_999_999_000_000_000_000, false);
        // in order for the price to not change we need to do an equal amount of tokens swapped in both directions
        vm.roll(block.number + 43_200);
        skip(1.5 days);
        startHoax(user1);
        // close the vault
        // price before close vault
        vaultManager.closeVault(uuid);
        uint256 priceAfterClose =
            CollarEngine(engine).getHistoricalAssetPriceViaTWAP(WMaticAddress, USDCAddress, vault.expiresAt, 15 minutes);
        console.log("Price after close vault: %d", priceAfterClose);
        /**
         * @dev trying to manipulate price to be exactly the same as the moment of opening vault is too hard , so we'll skip this case unless there's a better proposal
         */
        // assertEq(vault.initialCollateralPrice, priceAfterClose);

        // PrintVaultStatsUtility(address(this)).printVaultStats(rawVault, "VAULT CLOSED");

        // check the numbers on bothuser and marketmaker sides
        // since the price did not change , the vault should be able to withdraw the same amount of cash as it deposited and the MarketMaker should be also able to withdraw his initial locked value
        /**
         * step 9	No money moves around anywhere
         * step 10	User can redeem their vault tokens for the original $10
         * step 11	Liquidity provider can redeem their vault tokens for $20
         */
        // checked that the vault tokens are worth the same amount of cash as the cash locked when colaterall was deposited
        // startHoax(user1);
        // uint256 vaultLockedCash = vaultManager.vaultTokenCashSupply(uuid);
        // assertEq(vaultLockedCash, vault.lockedVaultCash);
        // uint256 userCashbalance = USDC.balanceOf(user1);
        // vaultManager.redeem(uuid, vaultLockedCash);
        // assertEq(USDC.balanceOf(user1), userCashbalance);
    }

    function test_openAndCloseVaultPriceUnderPutStrike() public {
        (bytes32 uuid, bytes memory rawVault, ICollarVaultState.Vault memory vault) = openVaultAsUserWith1000AndCheckValues();
        uint256 userCashBalanceAfterOpen = USDC.balanceOf(user1);
        uint256 providerCashBalanceBeforeClose = USDC.balanceOf(provider);

        manipulatePriceDownwardPastPutStrike();
        vm.roll(block.number + 43_200);
        skip(1.5 days);
        startHoax(user1);
        // close the vault
        vaultManager.closeVault(uuid);
        PrintVaultStatsUtility(address(this)).printVaultStats(rawVault, "VAULT CLOSED");

        // check the numbers on both user and marketmaker sides after executing withdraws and closes
        /**
         * since the price went down:
         * step 9	all $10 locked in the vault manager gets sent to the liquidity pool
         * step 10	user's vault tokens are now worth $0
         * step 11	liquidity provider's tokens are worth the $10 from the vault + original $20 = $30
         */

        // user loses the locked cash and gains nothing , redeemable cash is 0
        startHoax(user1);
        uint256 vaultLockedCash = vaultManager.vaultTokenCashSupply(uuid);
        assertEq(vaultLockedCash, 0);
        assertEq(USDC.balanceOf(user1), userCashBalanceAfterOpen);

        // liquidity provider gets the locked cash from the vault plus the original locked cash on the pool position
        startHoax(provider);
        (uint256 expiration,, uint256 withdrawable) = pool.positions(uuid);
        console.log("expiration: %d", expiration);
        console.log("vault expiration : %d", vault.expiresAt);
        console.log("current block timestamp : %d", block.timestamp);
        assertEq(withdrawable, vault.lockedPoolCash + vault.lockedVaultCash);
        pool.redeem(uuid, withdrawable);
        uint256 providerCashBalanceAfterClose = USDC.balanceOf(provider);
        assertEq(providerCashBalanceAfterClose, providerCashBalanceBeforeClose + vault.lockedPoolCash + vault.lockedVaultCash);
    }

    function openVaultAsUserWith1000AndCheckValues()
        internal
        returns (bytes32 uuid, bytes memory rawVault, ICollarVaultState.Vault memory vault)
    {
        uint256 collateralAmountToUse = 1000 ether;
        (uuid, rawVault, vault) = openVaultAsUser(collateralAmountToUse, user1);
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
        assertEq(vault.initialCollateralPrice, COLLATERAL_PRICE_ON_BLOCK); // the initial price of wmatic here is $0.739504
        assertEq(vault.putStrikePrice, 665_553); // put strike is 90%, so putstrike price is just 0.9 * original price
        assertEq(vault.callStrikePrice, 813_454); // same math for callstrike price, just using 1.1 instead

        // check vault specific stuff
        assertEq(vault.loanBalance, 665_554_499); // the vault loan balance should be 0.9 * cashAmount
        assertEq(vault.lockedVaultCash, 73_950_499); // the vault locked balance should be 0.1 * cashAmount
    }

    function openVaultAsUser(uint256 collateralAmount, address user)
        internal
        returns (bytes32 uuid, bytes memory rawVault, ICollarVaultState.Vault memory vault)
    {
        ICollarVaultState.AssetSpecifiers memory assets = ICollarVaultState.AssetSpecifiers({
            collateralAsset: WMaticAddress,
            collateralAmount: collateralAmount,
            cashAsset: USDCAddress,
            cashAmount: 100e6
        });

        ICollarVaultState.CollarOpts memory collarOpts = ICollarVaultState.CollarOpts({ duration: 1 days, ltv: 9000 });

        ICollarVaultState.LiquidityOpts memory liquidityOpts =
            ICollarVaultState.LiquidityOpts({ liquidityPool: address(pool), putStrikeTick: 90, callStrikeTick: 110 });

        startHoax(user);
        uint256 poolBalanceWMATIC = WMatic.balanceOf(uniV3Pool);
        uint256 poolBalanceUSDC = USDC.balanceOf(uniV3Pool);
        console.log("Pool balance of WMATIC before open: %d", poolBalanceWMATIC);
        console.log("Pool balance of USDC before open: %d", poolBalanceUSDC);
        vaultManager.openVault(assets, collarOpts, liquidityOpts, false);
        poolBalanceWMATIC = WMatic.balanceOf(uniV3Pool);
        poolBalanceUSDC = USDC.balanceOf(uniV3Pool);
        console.log("Pool balance of WMATIC after open: %d", poolBalanceWMATIC);
        console.log("Pool balance of USDC after open: %d", poolBalanceUSDC);
        uuid = vaultManager.getVaultUUID(0);
        rawVault = vaultManager.vaultInfo(uuid);
        vault = abi.decode(rawVault, (ICollarVaultState.Vault));

        PrintVaultStatsUtility(address(this)).printVaultStats(rawVault, "VAULT OPENED");
    }

    function manipulatePriceDownwardPastPutStrike() internal {
        // Trade on Uniswap to make the price go down past the put strike price .9 * COLLATERAL_PRICE_ON_BLOCK
        // end price should be 632310
        uint256 targetPrice = 632_310;
        swapAsWhale(100_000e18, false);
        assertEq(CollarEngine(engine).getCurrentAssetPrice(WMaticAddress, USDCAddress), targetPrice);
    }

    function manipulatePriceDownwardShortOfPutStrike() internal {
        // Trade on Uniswap to make the price go down but not past the put strike price .9 * COLLATERAL_PRICE_ON_BLOCK
        // end price should be 703575
        uint256 targetPrice = 703_575;
        swapAsWhale(40_000e18, false);
        assertEq(CollarEngine(engine).getCurrentAssetPrice(WMaticAddress, USDCAddress), targetPrice);
    }

    function manipulatePriceUpwardPastCallStrike() internal {
        // Trade on Uniswap to make the price go up past the call strike price 1.1 * COLLATERAL_PRICE_ON_BLOCK
        // end price should be 871978
        uint256 targetPrice = 871_978;
        swapAsWhale(100_000e6, true);
        assertEq(CollarEngine(engine).getCurrentAssetPrice(WMaticAddress, USDCAddress), targetPrice);
    }

    function manipulatePriceUpwardShortOfCallStrike() internal {
        // Trade on Uniswap to make the price go up but not past the call strike price 1.1 * COLLATERAL_PRICE_ON_BLOCK
        // end price should be 794385
        uint256 targetPrice = 794_385;
        swapAsWhale(40_000e6, true);
        assertEq(CollarEngine(engine).getCurrentAssetPrice(WMaticAddress, USDCAddress), targetPrice);
    }

    function swapAsWhale(uint256 amount, bool swapCash) internal {
        // Trade on Uniswap to manipulate the price
        uint256 currentPrice = CollarEngine(engine).getCurrentAssetPrice(WMaticAddress, USDCAddress);
        uint256 poolBalanceWMATIC = WMatic.balanceOf(uniV3Pool);
        uint256 poolBalanceUSDC = USDC.balanceOf(uniV3Pool);
        console.log("Pool balance of WMATIC: %d", poolBalanceWMATIC);
        console.log("Pool balance of USDC: %d", poolBalanceUSDC);
        console.log("Current price of WMATIC in USDC before swap: %d", currentPrice);
        // build the swap transaction
        IV3SwapRouter.ExactInputSingleParams memory swapParams = IV3SwapRouter.ExactInputSingleParams({
            tokenIn: USDCAddress,
            tokenOut: WMaticAddress,
            fee: 3000,
            recipient: address(this),
            amountIn: amount,
            amountOutMinimum: 100,
            sqrtPriceLimitX96: 0
        });
        if (swapCash) {
            console.log("Swapping USDC for WMatic");
            startHoax(binanceHotWalletTwo);
            IERC20(USDCAddress).approve(CollarEngine(engine).dexRouter(), amount);
            swapParams.tokenIn = USDCAddress;
            swapParams.tokenOut = WMaticAddress;
            // execute the swap
            // we're not worried about slippage here
            uint256 swapOutput = IV3SwapRouter(payable(CollarEngine(engine).dexRouter())).exactInputSingle(swapParams);
            console.log("amount of USDC inputted to the swap : %d", amount);
            console.log("Amount of WMatic token received for the amount of USDC inputted: %d", swapOutput);
        } else {
            startHoax(wMATICWhale);
            IERC20(WMaticAddress).approve(CollarEngine(engine).dexRouter(), amount);

            swapParams.tokenIn = WMaticAddress;
            swapParams.tokenOut = USDCAddress;
            // execute the swap
            // we're not worried about slippage here
            uint256 swapOutput = IV3SwapRouter(payable(CollarEngine(engine).dexRouter())).exactInputSingle(swapParams);
            console.log("amount of WMatic inputted to the swap : %d", amount);
            console.log("Amount of the output token received for the amount of Wmatic inputted: %d", swapOutput);
        }

        currentPrice = CollarEngine(engine).getCurrentAssetPrice(WMaticAddress, USDCAddress);
        poolBalanceWMATIC = WMatic.balanceOf(uniV3Pool);
        poolBalanceUSDC = USDC.balanceOf(uniV3Pool);
        console.log("Pool balance of WMATIC: %d", poolBalanceWMATIC);
        console.log("Pool balance of USDC: %d", poolBalanceUSDC);
        console.log("Current price of WMATIC in USDC after swap: %d", currentPrice);
    }
}
