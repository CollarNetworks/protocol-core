// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IUniswapV3Factory } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import { PrintVaultStatsUtility } from "../utils/PrintVaultStats.sol";
import { IV3SwapRouter } from "@uniswap/v3-swap-contracts/interfaces/IV3SwapRouter.sol";
import { IPeripheryImmutableState } from
    "@uniswap/v3-periphery/contracts/interfaces/IPeripheryImmutableState.sol";

import { CollarEngine } from "../../src/implementations/CollarEngine.sol";
import { CollarVaultManager } from "../../src/implementations/CollarVaultManager.sol";
import { CollarPool } from "../../src/implementations/CollarPool.sol";
import { ICollarVaultState } from "../../src/interfaces/ICollarVaultState.sol";
import { IWETH9 } from "../../src/interfaces/external/IWETH9.sol";

import { TestPriceOracle } from "../utils/TestPriceOracle.sol";

import "forge-std/Test.sol";

// Polygon Addresses for Uniswap V3

// QuoterV2 - - - - - - - - - - - - - - 0x61fFE014bA17989E743c5F6cB21bF9697530B21e
// SwapRouter02 - - - - - - - - - - - - 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45
// UniversalRouter  - - - - - - - - - - 0xec7BE89e9d109e7e3Fec59c222CF297125FEFda2
// NonFungiblePositionManager - - - - - 0xC36442b4a4522E871399CD717aBDD847Ab11FE88
// TickLens - - - - - - - - - - - - - - 0xbfd8137f7d1516D3ea5cA83523914859ec47F573
// WETH - - - - - - - - - - - - - - - 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270
// USDT - - - - - - - - - - - - - - - - 0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359
// Binance-Hot-Wallet-2 - - - - - - - - 0xe7804c37c13166fF0b37F5aE0BB07A3aEbb6e245
// Uniswap v3 Factory - - - - - - - - - 0x1F98431c8aD98523631AE4a59f267346ea31F984
// WETH / USDT UniV3 Pool - - - - - - 0x2DB87C4831B2fec2E35591221455834193b50D1B
// Mean Finance Polygon Static Oracle - 0xB210CE856631EeEB767eFa666EC7C1C57738d438
/**
 * @todo add fuzz testing that runs these with multiple collateral amounts and call strike ticks
 */
/**
 * @dev This contract should generate test to ensure all the cases and math from this sheet is correct and
 * verified
 * https://docs.google.com/spreadsheets/d/18e5ola3JJ2HKRQyAoPNmVrV4fnRcLdckOhQIxrN_hwY/edit#gid=1819672818
 */
contract CollarOpenAndCloseVaultOnEthereumMainnetIntegrationTest is Test, PrintVaultStatsUtility {
    using SafeERC20 for IERC20;

    address user1 = makeAddr("user1"); // the person who will be opening a vault
    address provider = makeAddr("user2"); // the person who will be providing liquidity
    address swapRouterAddress = address(0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45);
    address WETHAddress = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    address USDTAddress = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address uniV3Pool = address(0x4e68Ccd3E89f51C3074ca5072bbAC773960dFa36);
    address binanceHotWalletTwo = address(0xF04a5cC80B1E94C69B48f5ee68a08CD2F09A7c3E);
    address USDTWhale = 0xF977814e90dA44bFA03b6295A0616a897441aceC;
    uint BLOCK_NUMBER_TO_USE = 20_091_414;
    uint24 CALL_STRIKE_TICK = 120;

    IWETH9 WETH = IWETH9(WETHAddress);
    IERC20 USDT = IERC20(USDTAddress);

    CollarEngine engine;
    CollarVaultManager vaultManager;
    CollarPool pool;
    CollarPool usdtPool;

    /* We set up the test environment as follows:

    1. We fork Polygon and activate the fork
    2. We deploy the CollarEngine with the dex set to SwapRouter02 from Uniswap on the polygon fork
    3. We add the LTV of 90% to the engine, as well as the cash and collateral assets & duration
    4. We deploy a CollarPool with the following parameters:
        - engine: address of the CollarEngine
        - tickScaleFactor: 100 (1 tick = 1%)
        - cashAsset: USDT
        - collateralAsset: WETH
        - duration: 1 day
        - ltv: 9000 (90%)
    5. We add the pool to the engine
    6. We give the user USDT and WETH, as well as the liquidity provider
    7. WE label existing addresses for better test output
    8. We deploy a vault manager for the user
    9. We approve the vault manager to spend the user's USDT and WETH
    10. We approve the pool to spend the liquidity provider's USDT and WETH
    11. We add liquidity to the pool in ticks 110 through 115 (as the liquidity provider)

    */

    function setWETHBalance(address user, uint amount) internal {
        startHoax(user);
        vm.deal(user, amount * 2);
        WETH.deposit{ value: amount }();
    }

    function setUp() public {
        string memory forkRPC = vm.envString("ETHEREUM_MAINNET_RPC");
        vm.createSelectFork(forkRPC, BLOCK_NUMBER_TO_USE);
        assertEq(block.number, BLOCK_NUMBER_TO_USE);

        engine = new CollarEngine(swapRouterAddress); // @todo make this non-polygon-exclusive
        engine.addLTV(9000);

        pool = new CollarPool(address(engine), 100, USDTAddress, WETHAddress, 1 days, 9000);

        engine.addSupportedCashAsset(USDTAddress);
        engine.addSupportedCollateralAsset(WETHAddress);
        engine.addCollarDuration(1 days);
        engine.addLiquidityPool(address(pool));

        vm.label(user1, "USER");
        vm.label(provider, "LIQUIDITY PROVIDER");
        vm.label(address(engine), "ENGINE");
        vm.label(address(pool), "POOL");
        vm.label(swapRouterAddress, "SWAP ROUTER 02");
        vm.label(USDTAddress, "USDT");
        vm.label(WETHAddress, "WETH");

        setWETHBalance(user1, 100_000 ether);
        setWETHBalance(provider, 100_000 ether);
        setWETHBalance(binanceHotWalletTwo, 1_000_000 ether);

        // startHoax(USDTWhale);
        deal(USDTAddress, user1, 100_000 ether);
        // USDT.transfer(user1, 100_000 ether);
        deal(USDTAddress, provider, 100_000 ether);
        // USDT.transfer(provider, 100_000 ether);
        deal(USDTAddress, binanceHotWalletTwo, 1_000_000 ether);
        // USDT.transfer(binanceHotWalletTwo, 1_000_000 ether);

        startHoax(user1);
        vaultManager = CollarVaultManager(engine.createVaultManager());
        USDT.forceApprove(address(vaultManager), 0);
        USDT.forceApprove(address(vaultManager), type(uint).max);
        WETH.approve(address(vaultManager), type(uint).max);

        startHoax(provider);

        USDT.forceApprove(address(pool), 0);
        USDT.forceApprove(address(pool), type(uint).max);
        WETH.approve(address(pool), type(uint).max);
        uint liquidityToAdd = 100_000e6;
        pool.addLiquidityToSlot(110, liquidityToAdd);
        pool.addLiquidityToSlot(111, liquidityToAdd);
        pool.addLiquidityToSlot(112, liquidityToAdd);
        pool.addLiquidityToSlot(115, liquidityToAdd);
        pool.addLiquidityToSlot(120, liquidityToAdd);
        pool.addLiquidityToSlot(130, liquidityToAdd);

        vm.stopPrank();

        assertEq(engine.isValidCollarDuration(1 days), true);
        assertEq(engine.isValidLTV(9000), true);
        assertEq(engine.isSupportedCashAsset(USDTAddress), true);
        assertEq(engine.isSupportedCollateralAsset(WETHAddress), true);
        assertEq(engine.addressToVaultManager(user1), address(vaultManager));
        assertEq(engine.supportedLiquidityPoolsLength(), 1);
        assertEq(engine.isSupportedLiquidityPool(address(pool)), true);

        assertEq(pool.getLiquidityForSlot(110), liquidityToAdd);
        assertEq(pool.getLiquidityForSlot(111), liquidityToAdd);
        assertEq(pool.getLiquidityForSlot(112), liquidityToAdd);
        assertEq(pool.getLiquidityForSlot(115), liquidityToAdd);
        assertEq(pool.getLiquidityForSlot(120), liquidityToAdd);
        assertEq(pool.getLiquidityForSlot(130), liquidityToAdd);
    }

    modifier assumeFuzzValues(uint72 collateralAmount, uint24 tick) {
        vm.assume(
            collateralAmount > 1 ether && collateralAmount < 20 ether
                && (tick == 110 || tick == 115 || tick == 120 || tick == 130)
        );
        _;
    }

    function getCurrentAssetPrice(address baseToken, address quoteToken) internal returns (uint) {
        address uniV3Factory = IPeripheryImmutableState(CollarEngine(engine).dexRouter()).factory();
        return TestPriceOracle.getUnsafePrice(baseToken, quoteToken, uniV3Factory);
    }

    function test_openAndCloseVaultNoPriceChange() public {
        (bytes32 uuid, bytes memory rawVault, ICollarVaultState.Vault memory vault) =
            openVaultAsUserWith1AndCheckValues(user1, CALL_STRIKE_TICK);

        swapAsWhale(1_712_999_999_000_000_000_000, false);
        // in order for the price to not change we need to do an equal amount of tokens swapped in both
        // directions
        vm.roll(block.number + 43_200);
        skip(1.5 days);
        startHoax(user1);
        // close the vault
        // price before close vault
        vaultManager.closeVault(uuid);
        uint priceAfterClose = CollarEngine(engine).getHistoricalAssetPriceViaTWAP(
            WETHAddress, USDTAddress, vault.expiresAt, 15 minutes
        );
        /**
         * @dev trying to manipulate price to be exactly the same as the moment of opening vault is too hard ,
         * so we'll skip this case unless there's a better proposal
         */
        // assertEq(vault.initialCollateralPrice, priceAfterClose);

        // PrintVaultStatsUtility(address(this)).printVaultStats(rawVault, "VAULT CLOSED");

        // check the numbers on bothuser and marketmaker sides
        // since the price did not change , the vault should be able to withdraw the same amount of cash as it
        // deposited and the MarketMaker should be also able to withdraw his initial locked value
        /**
         * step 9	No money moves around anywhere
         * step 10	User can redeem their vault tokens for the original $10
         * step 11	Liquidity provider can redeem their vault tokens for $20
         */
        // checked that the vault tokens are worth the same amount of cash as the cash locked when colaterall
        // was deposited
        // startHoax(user1);
        // uint vaultLockedCash = vaultManager.vaultTokenCashSupply(uuid);
        // assertEq(vaultLockedCash, vault.lockedVaultCash);
        // uint userCashbalance = USDT.balanceOf(user1);
        // vaultManager.redeem(uuid, vaultLockedCash);
        // assertEq(USDT.balanceOf(user1), userCashbalance);
    }

    uint24[] public fixtureTick = [110, 115, 120, 130];

    function checkPriceUnderPutStrikeValues(
        bytes32 uuid,
        bytes memory rawVault,
        ICollarVaultState.Vault memory vault,
        uint userCashBalanceAfterOpen,
        uint providerCashBalanceBeforeClose
    )
        internal
    {
        vm.roll(block.number + 43_200);
        skip(1.5 days);
        startHoax(user1);
        // close the vault
        vaultManager.closeVault(uuid);
        PrintVaultStatsUtility(address(this)).printVaultStats(rawVault, "VAULT CLOSED");

        // check the numbers on both user and marketmaker sides after executing withdraws and closes
        /**
         * since the price went down:
         * step 9	all  locked in the vault manager gets sent to the liquidity pool
         * step 10	user's vault tokens are now worth $0
         * step 11	liquidity provider's tokens are worth the  from the vault + original
         */

        // user loses the locked cash and gains nothing , redeemable cash is 0 and balance doesnt change
        uint vaultLockedCash = vaultManager.vaultTokenCashSupply(uuid);
        assertEq(vaultLockedCash, 0);
        assertEq(USDT.balanceOf(user1), userCashBalanceAfterOpen);
        // liquidity provider gets the locked cash from the vault plus the original locked cash on the pool
        // position
        (,, uint withdrawable) = pool.positions(uuid);
        uint totalSupply = pool.totalSupply(uint(uuid));
        // supply from vault is equal to the locked pool cash
        assertEq(totalSupply, vault.lockedPoolCash);
        // withdrawable liquidity is equal to the locked value from both parties
        assertEq(withdrawable, totalSupply + vault.lockedVaultCash);
        uint providerShares = pool.balanceOf(provider, uint(uuid));
        startHoax(provider);
        pool.redeem(uuid, providerShares);
        uint providerCashBalanceAfterRedeem = USDT.balanceOf(provider);
        // liquidity providers new cash balance is previous balance + withdrawable liquidity
        assertEq(
            providerCashBalanceAfterRedeem,
            providerCashBalanceBeforeClose + vault.lockedPoolCash + vault.lockedVaultCash
        );
    }

    function testFuzz_openAndCloseVaultPriceUnderPutStrike(
        uint72 collateralAmount,
        uint24 tick
    )
        public
        assumeFuzzValues(collateralAmount, tick)
    {
        (bytes32 uuid, bytes memory rawVault, ICollarVaultState.Vault memory vault) =
            openVaultAsUserAndCheckValues(collateralAmount, user1, tick);
        uint userCashBalanceAfterOpen = USDT.balanceOf(user1);
        uint providerCashBalanceBeforeClose = USDT.balanceOf(provider);

        manipulatePriceDownwardPastPutStrike(true);
        checkPriceUnderPutStrikeValues(
            uuid, rawVault, vault, userCashBalanceAfterOpen, providerCashBalanceBeforeClose
        );
    }

    function test_openAndCloseVaultPriceUnderPutStrike() public {
        (bytes32 uuid, bytes memory rawVault, ICollarVaultState.Vault memory vault) =
            openVaultAsUserWith1AndCheckValues(user1, CALL_STRIKE_TICK);
        uint userCashBalanceAfterOpen = USDT.balanceOf(user1);
        uint providerCashBalanceBeforeClose = USDT.balanceOf(provider);

        manipulatePriceDownwardPastPutStrike(false);
        checkPriceUnderPutStrikeValues(
            uuid, rawVault, vault, userCashBalanceAfterOpen, providerCashBalanceBeforeClose
        );
    }

    function checkPriceDownShortOfPutStrikeValues(
        bytes32 uuid,
        bytes memory rawVault,
        ICollarVaultState.Vault memory vault,
        uint userCashBalanceAfterOpen,
        uint providerCashBalanceBeforeClose,
        uint finalPrice
    )
        internal
    {
        vm.roll(block.number + 43_200);
        skip(1.5 days);
        startHoax(user1);
        // close the vault
        vaultManager.closeVault(uuid);
        PrintVaultStatsUtility(address(this)).printVaultStats(rawVault, "VAULT CLOSED");
        // check the numbers on both user and marketmaker sides after executing withdraws and closes
        uint amountToProvider = (
            (vault.lockedVaultCash * (vault.initialCollateralPrice - finalPrice) * 1e32)
                / (vault.initialCollateralPrice - vault.putStrikePrice)
        ) / 1e32;
        console.log("Amount to provider: %d", amountToProvider);
        /**
         * step 9	a partial amount (amountToProvider) from the Vault manager gets transferred to the liquidity
         * pool
         * step 10	user can now redeem their vault tokens for a total of  originalCashLock - partial amount
         * (amountToProvider)
         * step 11	liquidity provider's tokens can now be redeemed for initial Lock + partial amount from
         * vault manager (amountToProvider)
         */
        // user loses a partial amount of the locked cash and gains the rest , redeemable cash is the
        // difference between the locked cash and the partial amount
        uint vaultLockedCash = vaultManager.vaultTokenCashSupply(uuid);
        assertEq(vaultLockedCash, vault.lockedVaultCash - amountToProvider);
        uint vaultSharesBalance = vaultManager.totalSupply(uint(uuid));
        // user gets the locked cash from the vault minus the partial amount sent to  the provider
        startHoax(user1);
        vaultManager.redeem(uuid, vaultSharesBalance);
        assertEq(USDT.balanceOf(user1), userCashBalanceAfterOpen + vaultLockedCash);

        startHoax(provider);
        // liquidity provider gets the partial locked cash from the vault plus the original locked cash on the
        // pool position
        (,, uint withdrawable) = pool.positions(uuid);
        uint totalSupply = pool.totalSupply(uint(uuid));
        // supply from vault must be equal to the locked pool cash + partial amount from locked vault cash
        assertEq(totalSupply, vault.lockedPoolCash);
        // withdrawable liquidity is equal to the locked value from provider + partial locked value from vault
        // (since shares are 1:1)
        assertEq(withdrawable, totalSupply + amountToProvider);
        uint providerShares = pool.balanceOf(provider, uint(uuid));
        startHoax(provider);
        pool.redeem(uuid, providerShares);
        uint providerCashBalanceAfterRedeem = USDT.balanceOf(provider);
        // liquidity providers new cash balance is previous balance + withdrawable liquidity
        assertEq(providerCashBalanceAfterRedeem, providerCashBalanceBeforeClose + withdrawable);
    }

    function testFuzz_openAndCloseVaultPriceDownShortOfPutStrike(
        uint72 collateralAmount,
        uint24 tick
    )
        public
        assumeFuzzValues(collateralAmount, tick)
    {
        (bytes32 uuid, bytes memory rawVault, ICollarVaultState.Vault memory vault) =
            openVaultAsUserAndCheckValues(collateralAmount, user1, tick);
        uint userCashBalanceAfterOpen = USDT.balanceOf(user1);
        uint providerCashBalanceBeforeClose = USDT.balanceOf(provider);
        uint finalPrice = manipulatePriceDownwardShortOfPutStrike(true);
        checkPriceDownShortOfPutStrikeValues(
            uuid, rawVault, vault, userCashBalanceAfterOpen, providerCashBalanceBeforeClose, finalPrice
        );
    }

    function test_openAndCloseVaultPriceDownShortOfPutStrike() public {
        (bytes32 uuid, bytes memory rawVault, ICollarVaultState.Vault memory vault) =
            openVaultAsUserWith1AndCheckValues(user1, CALL_STRIKE_TICK);
        uint userCashBalanceAfterOpen = USDT.balanceOf(user1);
        uint providerCashBalanceBeforeClose = USDT.balanceOf(provider);
        uint finalPrice = manipulatePriceDownwardShortOfPutStrike(false);
        checkPriceDownShortOfPutStrikeValues(
            uuid, rawVault, vault, userCashBalanceAfterOpen, providerCashBalanceBeforeClose, finalPrice
        );
    }

    function checkPriceUpPastCallStrikeValues(
        bytes32 uuid,
        bytes memory rawVault,
        ICollarVaultState.Vault memory vault,
        uint userCashBalanceAfterOpen,
        uint providerCashBalanceBeforeClose
    )
        internal
    {
        vm.roll(block.number + 43_200);
        skip(1.5 days);
        startHoax(user1);
        // close the vault
        vaultManager.closeVault(uuid);
        PrintVaultStatsUtility(address(this)).printVaultStats(rawVault, "VAULT CLOSED");
        // check the numbers on both user and marketmaker sides after executing withdraws and closes
        /**
         * step 9	all cash locked in the liquidity pool gets sent to the vault manager
         * step 10	user can now redeem their vault tokens for a total of their cash locked in vault + the
         * liquidity provider's locked in pool
         * step 11	liquidity provider's tokens are worth 0
         */

        // user gets the locked cash from the vault plus the locked cash from the pool
        uint vaultLockedCash = vaultManager.vaultTokenCashSupply(uuid);
        assertEq(vaultLockedCash, vault.lockedVaultCash + vault.lockedPoolCash);
        uint vaultSharesBalance = vaultManager.totalSupply(uint(uuid));
        // user gets the locked cash from the vault plus the locked cash from the pool
        startHoax(user1);
        vaultManager.redeem(uuid, vaultSharesBalance);
        assertEq(USDT.balanceOf(user1), userCashBalanceAfterOpen + vaultLockedCash);

        // liquidity provider gets 0
        (,, uint withdrawable) = pool.positions(uuid);
        uint totalSupply = pool.totalSupply(uint(uuid));
        // total supply from vault must be equal to the locked pool cash
        assertEq(totalSupply, vault.lockedPoolCash);
        // withdrawable liquidity is 0 since it was all sent to vault manager
        assertEq(withdrawable, 0);
        uint providerShares = pool.balanceOf(provider, uint(uuid));
        startHoax(provider);
        pool.redeem(uuid, providerShares);
        uint providerCashBalanceAfterRedeem = USDT.balanceOf(provider);
        // liquidity providers cash balance does not change since they have no withdrawable liquidity
        assertEq(providerCashBalanceAfterRedeem, providerCashBalanceBeforeClose);
    }

    function testFuzz_openAndCloseVaultPriceUpPastCallStrike(
        uint72 collateralAmount,
        uint24 tick
    )
        public
        assumeFuzzValues(collateralAmount, tick)
    {
        (bytes32 uuid, bytes memory rawVault, ICollarVaultState.Vault memory vault) =
            openVaultAsUserAndCheckValues(collateralAmount, user1, tick);
        uint userCashBalanceAfterOpen = USDT.balanceOf(user1);
        uint providerCashBalanceBeforeClose = USDT.balanceOf(provider);
        manipulatePriceUpwardPastCallStrike(true);
        checkPriceUpPastCallStrikeValues(
            uuid, rawVault, vault, userCashBalanceAfterOpen, providerCashBalanceBeforeClose
        );
    }

    function test_openAndCloseVaultPriceUpPastCallStrike() public {
        (bytes32 uuid, bytes memory rawVault, ICollarVaultState.Vault memory vault) =
            openVaultAsUserWith1AndCheckValues(user1, CALL_STRIKE_TICK);
        uint userCashBalanceAfterOpen = USDT.balanceOf(user1);
        uint providerCashBalanceBeforeClose = USDT.balanceOf(provider);
        manipulatePriceUpwardPastCallStrike(false);
        checkPriceUpPastCallStrikeValues(
            uuid, rawVault, vault, userCashBalanceAfterOpen, providerCashBalanceBeforeClose
        );
    }

    function checkPriceUpShortOfCallStrikeValues(
        bytes32 uuid,
        bytes memory rawVault,
        ICollarVaultState.Vault memory vault,
        uint userCashBalanceAfterOpen,
        uint providerCashBalanceBeforeClose,
        uint finalPrice
    )
        internal
    {
        vm.roll(block.number + 43_200);
        skip(1.5 days);
        startHoax(user1);
        // close the vault
        vaultManager.closeVault(uuid);
        PrintVaultStatsUtility(address(this)).printVaultStats(rawVault, "VAULT CLOSED");
        // check the numbers on both user and marketmaker sides after executing withdraws and closes
        uint amountToVault = (
            (vault.lockedPoolCash * (finalPrice - vault.initialCollateralPrice) * 1e32)
                / (vault.callStrikePrice - vault.initialCollateralPrice)
        ) / 1e32;
        console.log("Amount to vault: %d", amountToVault);
        /**
         * step 9	a partial amount (amountToVault) from the liquidity pool gets transferred to the Vault
         * manager
         * step 10	user can now redeem their vault tokens for a total of  originalCashLock + partial amount
         * (amountToVault)
         * step 11	liquidity provider's tokens can now be redeemed for initial Lock - partial amount sent to
         * vault manager (amountToVault)
         */
        // user gets the locked cash from the vault plus the partial amount from locked cash in the pool
        uint vaultLockedCash = vaultManager.vaultTokenCashSupply(uuid);
        assertEq(vaultLockedCash, vault.lockedVaultCash + amountToVault);
        uint vaultSharesBalance = vaultManager.totalSupply(uint(uuid));
        // user gets the locked cash from the vault plus the partial amount from locked cash in the pool
        startHoax(user1);
        vaultManager.redeem(uuid, vaultSharesBalance);
        assertEq(USDT.balanceOf(user1), userCashBalanceAfterOpen + vaultLockedCash);

        // liquidity provider gets the locked cash from pool minus the partial amount sent to the vault
        // manager
        (,, uint withdrawable) = pool.positions(uuid);
        uint totalSupply = pool.totalSupply(uint(uuid));
        // total supply from vault must be equal to the locked pool cash
        assertEq(totalSupply, vault.lockedPoolCash);
        // withdrawable liquidity is equal to the locked value from provider minus the partial amount sent to
        // the vault manager
        assertEq(withdrawable, totalSupply - amountToVault);
        uint providerShares = pool.balanceOf(provider, uint(uuid));
        startHoax(provider);
        pool.redeem(uuid, providerShares);
        uint providerCashBalanceAfterRedeem = USDT.balanceOf(provider);
        // liquidity providers new cash balance is previous balance + withdrawable liquidity
        assertEq(providerCashBalanceAfterRedeem, providerCashBalanceBeforeClose + withdrawable);
    }

    function testFuzz_openAndCloseVaultPriceUpShortOfCallStrike(
        uint72 collateralAmount,
        uint24 tick
    )
        public
        assumeFuzzValues(collateralAmount, tick)
    {
        (bytes32 uuid, bytes memory rawVault, ICollarVaultState.Vault memory vault) =
            openVaultAsUserAndCheckValues(collateralAmount, user1, tick);
        uint userCashBalanceAfterOpen = USDT.balanceOf(user1);
        uint providerCashBalanceBeforeClose = USDT.balanceOf(provider);
        uint finalPrice = manipulatePriceUpwardShortOfCallStrike(true);
        checkPriceUpShortOfCallStrikeValues(
            uuid, rawVault, vault, userCashBalanceAfterOpen, providerCashBalanceBeforeClose, finalPrice
        );
    }

    function test_openAndCloseVaultPriceUpShortOfCallStrike() public {
        (bytes32 uuid, bytes memory rawVault, ICollarVaultState.Vault memory vault) =
            openVaultAsUserWith1AndCheckValues(user1, CALL_STRIKE_TICK);
        uint userCashBalanceAfterOpen = USDT.balanceOf(user1);
        uint providerCashBalanceBeforeClose = USDT.balanceOf(provider);
        uint finalPrice = manipulatePriceUpwardShortOfCallStrike(false);
        checkPriceUpShortOfCallStrikeValues(
            uuid, rawVault, vault, userCashBalanceAfterOpen, providerCashBalanceBeforeClose, finalPrice
        );
    }

    function openVaultAsUserAndCheckValues(
        uint amount,
        address user,
        uint24 tick
    )
        internal
        returns (bytes32 uuid, bytes memory rawVault, ICollarVaultState.Vault memory vault)
    {
        (uuid, rawVault, vault) = openVaultAsUser(amount, user, tick);
        // check basic vault info
        assertEq(vault.active, true);
        assertEq(vault.openedAt, block.timestamp);
        assertEq(vault.expiresAt, block.timestamp + 1 days);
        assertEq(vault.duration, 1 days);
        assertEq(vault.ltv, 9000);

        // check asset specific info
        assertEq(vault.collateralAsset, WETHAddress);
        assertEq(vault.cashAsset, USDTAddress);
        // for the assert directly above this line, we need to consider that the price of WETH is 73 cents at
        // this time; (specifically: $0.739504999)
        // (which converts to about 739 when considering USDT has 6 decimals and we swapped 1000 WETH)

        // check liquidity pool stuff
        assertEq(vault.liquidityPool, address(pool));
        assertEq(vault.putStrikeTick, 90);
    }

    function openVaultAsUserWith1AndCheckValues(
        address user,
        uint24 tick
    )
        internal
        returns (bytes32 uuid, bytes memory rawVault, ICollarVaultState.Vault memory vault)
    {
        uint collateralAmountToUse = 1 ether;
        (uuid, rawVault, vault) = openVaultAsUser(collateralAmountToUse, user, tick);
        // check basic vault info
        assertEq(vault.active, true);
        assertEq(vault.openedAt, block.timestamp);
        assertEq(vault.expiresAt, block.timestamp + 1 days);
        assertEq(vault.duration, 1 days);
        assertEq(vault.ltv, 9000);

        // check asset specific info
        assertEq(vault.collateralAsset, WETHAddress);
        assertEq(vault.cashAsset, USDTAddress);
        assertEq(vault.collateralAmount, 1 ether); // we use 1000 "ether" here (it's actually WETH, but still
            // 18 decimals)
        // for the assert directly above this line, we need to consider that the price of WETH is 73 cents at
        // this time; (specifically: $0.739504999)
        // (which converts to about 739 when considering USDT has 6 decimals and we swapped 1000 WETH)

        // check liquidity pool stuff
        assertEq(vault.liquidityPool, address(pool));
        assertEq(vault.putStrikeTick, 90);
    }

    function openVaultAsUser(
        uint collateralAmount,
        address user,
        uint24 tick
    )
        internal
        returns (bytes32 uuid, bytes memory rawVault, ICollarVaultState.Vault memory vault)
    {
        ICollarVaultState.AssetSpecifiers memory assets = ICollarVaultState.AssetSpecifiers({
            collateralAsset: WETHAddress,
            collateralAmount: collateralAmount,
            cashAsset: USDTAddress,
            cashAmount: 0.3e6
        });

        ICollarVaultState.CollarOpts memory collarOpts =
            ICollarVaultState.CollarOpts({ duration: 1 days, ltv: 9000 });

        ICollarVaultState.LiquidityOpts memory liquidityOpts = ICollarVaultState.LiquidityOpts({
            liquidityPool: address(pool),
            putStrikeTick: 90,
            callStrikeTick: tick
        });

        startHoax(user);
        uint poolBalanceWETH = WETH.balanceOf(uniV3Pool);
        uint poolBalanceUSDT = USDT.balanceOf(uniV3Pool);
        vaultManager.openVault(assets, collarOpts, liquidityOpts, false);
        poolBalanceWETH = WETH.balanceOf(uniV3Pool);
        poolBalanceUSDT = USDT.balanceOf(uniV3Pool);
        uuid = vaultManager.getVaultUUID(0);
        rawVault = vaultManager.vaultInfo(uuid);
        vault = abi.decode(rawVault, (ICollarVaultState.Vault));

        PrintVaultStatsUtility(address(this)).printVaultStats(rawVault, "VAULT OPENED");
    }

    function manipulatePriceDownwardPastPutStrike(bool isFuzzTest) internal {
        // Trade on Uniswap to make the price go down past the put strike price .9 * COLLATERAL_PRICE_ON_BLOCK
        // end price should be 632310
        uint targetPrice = 2_566_273_536;
        swapAsWhale(10_000 ether, false);
        if (!isFuzzTest) {
            assertEq(getCurrentAssetPrice(WETHAddress, USDTAddress), targetPrice);
        }
    }

    function manipulatePriceDownwardShortOfPutStrike(bool isFuzzTest) internal returns (uint finalPrice) {
        // Trade on Uniswap to make the price go down but not past the put strike price .9 *
        // COLLATERAL_PRICE_ON_BLOCK
        // end price should be 703575
        uint targetPrice = 3_146_355_099;
        swapAsWhale(5000 ether, false);
        finalPrice = getCurrentAssetPrice(WETHAddress, USDTAddress);
        if (!isFuzzTest) {
            assertEq(getCurrentAssetPrice(WETHAddress, USDTAddress), targetPrice);
        } else {
            console.log("Current price of WETH in USDT after swap: %d", targetPrice);
        }
    }

    function manipulatePriceUpwardPastCallStrike(bool isFuzzTest) internal {
        // Trade on Uniswap to make the price go up past the call strike price 1.1 * COLLATERAL_PRICE_ON_BLOCK
        // end price should be 871978
        uint targetPrice = 49_072_885_881_217;
        swapAsWhale(60_000_000e6, true);
        if (!isFuzzTest) {
            assertEq(getCurrentAssetPrice(WETHAddress, USDTAddress), targetPrice);
        }
    }

    function manipulatePriceUpwardShortOfCallStrike(bool isFuzzTest) internal returns (uint finalPrice) {
        // Trade on Uniswap to make the price go up but not past the call strike price 1.1 *
        // COLLATERAL_PRICE_ON_BLOCK
        // end price should be 794385
        uint targetPrice = 3_418_632_174;
        swapAsWhale(1_000_000e6, true);
        finalPrice = getCurrentAssetPrice(WETHAddress, USDTAddress);
        if (!isFuzzTest) {
            assertEq(getCurrentAssetPrice(WETHAddress, USDTAddress), targetPrice);
        }
    }

    function swapAsWhale(uint amount, bool swapCash) internal {
        // Trade on Uniswap to manipulate the price
        uint currentPrice = getCurrentAssetPrice(WETHAddress, USDTAddress);
        console.log("Current price of WETH in USDT before swap: %d", currentPrice);

        uint poolBalanceWETH = WETH.balanceOf(uniV3Pool);
        uint poolBalanceUSDT = USDT.balanceOf(uniV3Pool);
        // build the swap transaction
        IV3SwapRouter.ExactInputSingleParams memory swapParams = IV3SwapRouter.ExactInputSingleParams({
            tokenIn: USDTAddress,
            tokenOut: WETHAddress,
            fee: 3000,
            recipient: address(this),
            amountIn: amount,
            amountOutMinimum: 100,
            sqrtPriceLimitX96: 0
        });
        startHoax(binanceHotWalletTwo);
        if (swapCash) {
            IERC20(USDTAddress).forceApprove(CollarEngine(engine).dexRouter(), amount);
            swapParams.tokenIn = USDTAddress;
            swapParams.tokenOut = WETHAddress;
            // execute the swap
            // we're not worried about slippage here
            IV3SwapRouter(payable(CollarEngine(engine).dexRouter())).exactInputSingle(swapParams);
        } else {
            IERC20(WETHAddress).forceApprove(CollarEngine(engine).dexRouter(), amount);

            swapParams.tokenIn = WETHAddress;
            swapParams.tokenOut = USDTAddress;
            // execute the swap
            // we're not worried about slippage here
            IV3SwapRouter(payable(CollarEngine(engine).dexRouter())).exactInputSingle(swapParams);
        }

        currentPrice = getCurrentAssetPrice(WETHAddress, USDTAddress);
        poolBalanceWETH = WETH.balanceOf(uniV3Pool);
        poolBalanceUSDT = USDT.balanceOf(uniV3Pool);
        console.log("Current price of WETH in USDT after swap: %d", currentPrice);
    }
}
