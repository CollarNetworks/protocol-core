// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

import { ICollarVaultState } from "../../src/interfaces/ICollarVaultState.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { CollarIntegrationPriceManipulation } from "./utils/PriceManipulation.t.sol";
import { VaultOperationsTest } from "./utils/VaultOperations.t.sol";

/**
 * @dev This contract should generate test to ensure all the cases and math from this sheet is correct and
 * verified
 * https://docs.google.com/spreadsheets/d/18e5ola3JJ2HKRQyAoPNmVrV4fnRcLdckOhQIxrN_hwY/edit#gid=1819672818
 */
contract CollarOpenAndCloseVaultIntegrationTest is CollarIntegrationPriceManipulation, VaultOperationsTest {
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
    11. We add liquidity to the pool in ticks 111 through 130 (as the liquidity provider)
    */

    function setUp() public {
        uint _blockNumberToUse = 55_850_000;
        string memory forkRPC = vm.envString("POLYGON_MAINNET_RPC");
        vm.createSelectFork(forkRPC, _blockNumberToUse);
        assertEq(block.number, _blockNumberToUse);
        /**
         * polygon mainnet addresses
         */
        address _swapRouter = address(0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45);
        address _usdc = address(0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359);
        address _wmatic = address(0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270);
        address _uniV3Pool = address(0x2DB87C4831B2fec2E35591221455834193b50D1B);
        address _whale = address(0xe7804c37c13166fF0b37F5aE0BB07A3aEbb6e245);
        _setupConfig(
            _swapRouter,
            _usdc,
            _wmatic,
            _uniV3Pool,
            _whale,
            _blockNumberToUse,
            739_504, // $0.739504 the price for WMatic in USDC on the specified block of polygon mainnet
            120,
            1 days,
            9000
        );
        uint amountToProvide = 10_000e6;
        _fundWallets();
        _addLiquidityToPool(amountToProvide);
        vm.stopPrank();
        _validateSetup(amountToProvide, 1 days, 9000);
    }

    modifier assumeFuzzValues(uint collateralAmount, uint24 tick) {
        vm.assume(
            collateralAmount > 1 ether && collateralAmount < 20_000 ether
                && (tick == 110 || tick == 115 || tick == 120 || tick == 130)
        );
        _;
    }

    function test_openAndCloseVaultNoPriceChange() public {
        (bytes32 uuid,) = openVaultAsUserAndCheckValues(1000 ether, user1, CALL_STRIKE_TICK);
        startHoax(user1);
        // close the vault
        // price before close vault
        vm.roll(block.number + 43_200);
        skip(poolDuration + 1 days);
        vaultManager.closeVault(uuid);
        /**
         * @dev trying to manipulate price to be exactly the same as the moment of opening vault is too hard ,
         * so we'll skip this case unless there's a better proposal
         */
    }

    uint24[] public fixtureTick = [110, 115, 120, 130];

    function testFuzz_openAndCloseVaultPriceUnderPutStrike(uint collateralAmount, uint24 tick)
        public
        assumeFuzzValues(collateralAmount, tick)
    {
        (bytes32 uuid, ICollarVaultState.Vault memory vault) =
            openVaultAsUserAndCheckValues(collateralAmount, user1, tick);
        uint userCashBalanceAfterOpen = cashAsset.balanceOf(user1);
        uint providerCashBalanceBeforeClose = cashAsset.balanceOf(provider);

        manipulatePriceDownwardPastPutStrike(true);
        checkPriceUnderPutStrikeValues(uuid, vault, userCashBalanceAfterOpen, providerCashBalanceBeforeClose);
    }

    function test_openAndCloseVaultPriceUnderPutStrike() public {
        (bytes32 uuid, ICollarVaultState.Vault memory vault) =
            openVaultAsUserAndCheckValues(1000 ether, user1, CALL_STRIKE_TICK);
        uint userCashBalanceAfterOpen = cashAsset.balanceOf(user1);
        uint providerCashBalanceBeforeClose = cashAsset.balanceOf(provider);

        manipulatePriceDownwardPastPutStrike(false);
        checkPriceUnderPutStrikeValues(uuid, vault, userCashBalanceAfterOpen, providerCashBalanceBeforeClose);
    }

    function testFuzz_openAndCloseVaultPriceDownShortOfPutStrike(uint collateralAmount, uint24 tick)
        public
        assumeFuzzValues(collateralAmount, tick)
    {
        (bytes32 uuid, ICollarVaultState.Vault memory vault) =
            openVaultAsUserAndCheckValues(collateralAmount, user1, tick);
        uint userCashBalanceAfterOpen = cashAsset.balanceOf(user1);
        uint providerCashBalanceBeforeClose = cashAsset.balanceOf(provider);
        uint finalPrice = manipulatePriceDownwardShortOfPutStrike(true);
        checkPriceDownShortOfPutStrikeValues(
            uuid, vault, userCashBalanceAfterOpen, providerCashBalanceBeforeClose, finalPrice
        );
    }

    function test_openAndCloseVaultPriceDownShortOfPutStrike() public {
        (bytes32 uuid, ICollarVaultState.Vault memory vault) =
            openVaultAsUserAndCheckValues(1000 ether, user1, CALL_STRIKE_TICK);
        uint userCashBalanceAfterOpen = cashAsset.balanceOf(user1);
        uint providerCashBalanceBeforeClose = cashAsset.balanceOf(provider);
        uint finalPrice = manipulatePriceDownwardShortOfPutStrike(false);
        checkPriceDownShortOfPutStrikeValues(
            uuid, vault, userCashBalanceAfterOpen, providerCashBalanceBeforeClose, finalPrice
        );
    }

    function testFuzz_openAndCloseVaultPriceUpPastCallStrike(uint collateralAmount, uint24 tick)
        public
        assumeFuzzValues(collateralAmount, tick)
    {
        (bytes32 uuid, ICollarVaultState.Vault memory vault) =
            openVaultAsUserAndCheckValues(collateralAmount, user1, tick);
        uint userCashBalanceAfterOpen = cashAsset.balanceOf(user1);
        uint providerCashBalanceBeforeClose = cashAsset.balanceOf(provider);
        manipulatePriceUpwardPastCallStrike(true);
        checkPriceUpPastCallStrikeValues(
            uuid, vault, userCashBalanceAfterOpen, providerCashBalanceBeforeClose
        );
    }

    function test_openAndCloseVaultPriceUpPastCallStrike() public {
        (bytes32 uuid, ICollarVaultState.Vault memory vault) =
            openVaultAsUserAndCheckValues(1000 ether, user1, CALL_STRIKE_TICK);
        uint userCashBalanceAfterOpen = cashAsset.balanceOf(user1);
        uint providerCashBalanceBeforeClose = cashAsset.balanceOf(provider);
        manipulatePriceUpwardPastCallStrike(false);
        checkPriceUpPastCallStrikeValues(
            uuid, vault, userCashBalanceAfterOpen, providerCashBalanceBeforeClose
        );
    }

    function testFuzz_openAndCloseVaultPriceUpShortOfCallStrike(uint collateralAmount, uint24 tick)
        public
        assumeFuzzValues(collateralAmount, tick)
    {
        (bytes32 uuid, ICollarVaultState.Vault memory vault) =
            openVaultAsUserAndCheckValues(collateralAmount, user1, tick);
        uint userCashBalanceAfterOpen = cashAsset.balanceOf(user1);
        uint providerCashBalanceBeforeClose = cashAsset.balanceOf(provider);
        uint finalPrice = manipulatePriceUpwardShortOfCallStrike(true);
        checkPriceUpShortOfCallStrikeValues(
            uuid, vault, userCashBalanceAfterOpen, providerCashBalanceBeforeClose, finalPrice
        );
    }

    function test_openAndCloseVaultPriceUpShortOfCallStrike() public {
        (bytes32 uuid, ICollarVaultState.Vault memory vault) =
            openVaultAsUserAndCheckValues(1000 ether, user1, CALL_STRIKE_TICK);
        uint userCashBalanceAfterOpen = cashAsset.balanceOf(user1);
        uint providerCashBalanceBeforeClose = cashAsset.balanceOf(provider);
        uint finalPrice = manipulatePriceUpwardShortOfCallStrike(false);
        checkPriceUpShortOfCallStrikeValues(
            uuid, vault, userCashBalanceAfterOpen, providerCashBalanceBeforeClose, finalPrice
        );
    }

    function manipulatePriceDownwardPastPutStrike(bool isFuzzTest) internal {
        uint targetPrice = 632_310;
        _manipulatePriceDownwardPastPutStrike(100_000e18, isFuzzTest, targetPrice);
    }

    function manipulatePriceDownwardShortOfPutStrike(bool isFuzzTest) internal returns (uint finalPrice) {
        uint targetPrice = 703_575;
        finalPrice = _manipulatePriceDownwardShortOfPutStrike(40_000e18, isFuzzTest, targetPrice);
    }

    function manipulatePriceUpwardPastCallStrike(bool isFuzzTest) internal {
        uint targetPrice = 987_778;
        _manipulatePriceUpwardPastCallStrike(200_000e6, isFuzzTest, targetPrice);
    }

    function manipulatePriceUpwardShortOfCallStrike(bool isFuzzTest) internal returns (uint finalPrice) {
        uint targetPrice = 794_385;
        finalPrice = _manipulatePriceUpwardShortOfCallStrike(40_000e6, isFuzzTest, targetPrice);
    }
}
