// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

import "forge-std/console.sol";

import { ICollarVaultState } from "../../src/interfaces/ICollarVaultState.sol";
import { CollarIntegrationPriceManipulation } from "./utils/PriceManipulation.t.sol";
import { VaultOperationsTest } from "./utils/VaultOperations.t.sol";

/**
 * @dev This contract should generate test to ensure all the cases and math from this sheet is correct and verified
 * https://docs.google.com/spreadsheets/d/18e5ola3JJ2HKRQyAoPNmVrV4fnRcLdckOhQIxrN_hwY/edit#gid=1819672818
 */
contract ForkTestCollarEthereumMainnetNon18BasedCollateral is
    CollarIntegrationPriceManipulation,
    VaultOperationsTest
{
    /* We set up the test environment as follows:

    1. We fork Ethereum mainnet and activate the fork
    2. We deploy the CollarEngine with the dex set to SwapRouter02 from Uniswap on the Ethereum mainnet fork
    3. We add the LTV of 90% to the engine, as well as the cash and collateral assets & duration
    4. We deploy a CollarPool with the following parameters:
        - engine: address of the CollarEngine
        - tickScaleFactor: 100 (1 tick = 1%)
        - cashAsset: USDT
        - collateralAsset: WBTC
        - duration: 1 day
        - ltv: 9000 (90%)
    5. We add the pool to the engine
    6. We give the user USDT and WBTC, as well as the liquidity provider
    7. WE label existing addresses for better test output
    8. We deploy a vault manager for the user
    9. We approve the vault manager to spend the user's USDT and WBTC
    10. We approve the pool to spend the liquidity provider's USDT and WBTC
    11. We add liquidity to the pool in ticks 111 through 130 (as the liquidity provider)

    */

    function setUp() public {
        uint _blockNumberToUse = 20_091_414;
        string memory forkRPC = vm.envString("ETHEREUM_MAINNET_RPC");
        vm.createSelectFork(forkRPC, _blockNumberToUse);
        assertEq(block.number, _blockNumberToUse);
        address _swapRouter = address(0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45);
        address collateralAssetAddress = address(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);
        address cashAssetAddress = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
        address _uniV3Pool = address(0x4e68Ccd3E89f51C3074ca5072bbAC773960dFa36);
        address _whale = address(0xF04a5cC80B1E94C69B48f5ee68a08CD2F09A7c3E);
        _setupConfig(
            _swapRouter,
            cashAssetAddress,
            collateralAssetAddress,
            _uniV3Pool,
            _whale,
            _blockNumberToUse,
            3_393_819_954, // $3393 the price for WBTC in USDT on the specified block of ethereum mainnet
            120,
            1 days,
            9000,
            8 // collateral decimals , WBTC has 8 decimals
        );
        uint amountToProvide = 1_000_000e6;
        _fundWallets();
        _addLiquidityToPool(amountToProvide);
        vm.stopPrank();
        _validateSetup(amountToProvide, 1 days, 9000);
    }

    uint24[] public fixtureTick = [110, 115, 120, 130];

    modifier assumeTickFuzzValues(uint24 tick) {
        vm.assume(tick == 110 || tick == 115 || tick == 120 || tick == 130);
        _;
    }

    function test_openAndCloseVaultNoPriceChange() public {
        (bytes32 uuid,) = openVaultAsUserAndCheckValues(2e8, user1, CALL_STRIKE_TICK);
        // in order for the price to not change we need to do an equal amount of tokens swapped in both directions
        vm.roll(block.number + 43_200);
        skip(1.5 days);
        startHoax(user1);
        // close the vault
        // price before close vault
        vaultManager.closeVault(uuid);
        /**
         * @dev trying to manipulate price to be exactly the same as the moment of opening vault is too hard , so we'll skip this case unless there's a better proposal
         */
    }

    function testFuzz_openAndCloseVaultPriceUnderPutStrike(uint collateralAmount, uint24 tick)
        public
        assumeTickFuzzValues(tick)
    {
        collateralAmount = bound(collateralAmount, 2e8, 20e8);
        (bytes32 uuid, ICollarVaultState.Vault memory vault) =
            openVaultAsUserAndCheckValues(collateralAmount, user1, tick);
        uint userCashBalanceAfterOpen = cashAsset.balanceOf(user1);
        uint providerCashBalanceBeforeClose = cashAsset.balanceOf(provider);

        manipulatePriceDownwardPastPutStrike(true);
        checkPriceUnderPutStrikeValues(uuid, vault, userCashBalanceAfterOpen, providerCashBalanceBeforeClose);
    }

    function test_openAndCloseVaultPriceUnderPutStrike() public {
        (bytes32 uuid, ICollarVaultState.Vault memory vault) =
            openVaultAsUserAndCheckValues(2e8, user1, CALL_STRIKE_TICK);
        uint userCashBalanceAfterOpen = cashAsset.balanceOf(user1);
        uint providerCashBalanceBeforeClose = cashAsset.balanceOf(provider);

        manipulatePriceDownwardPastPutStrike(false);
        checkPriceUnderPutStrikeValues(uuid, vault, userCashBalanceAfterOpen, providerCashBalanceBeforeClose);
    }

    function testFuzz_openAndCloseVaultPriceDownShortOfPutStrike(uint collateralAmount, uint24 tick)
        public
        assumeTickFuzzValues(tick)
    {
        collateralAmount = bound(collateralAmount, 2e8, 20e8);
        console.log("collateralAmount: %d", collateralAmount);
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
            openVaultAsUserAndCheckValues(2e8, user1, CALL_STRIKE_TICK);
        uint userCashBalanceAfterOpen = cashAsset.balanceOf(user1);
        uint providerCashBalanceBeforeClose = cashAsset.balanceOf(provider);
        uint finalPrice = manipulatePriceDownwardShortOfPutStrike(false);
        checkPriceDownShortOfPutStrikeValues(
            uuid, vault, userCashBalanceAfterOpen, providerCashBalanceBeforeClose, finalPrice
        );
    }

    function testFuzz_openAndCloseVaultPriceUpPastCallStrike(uint collateralAmount, uint24 tick)
        public
        assumeTickFuzzValues(tick)
    {
        collateralAmount = bound(collateralAmount, 2e8, 20e8);
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
            openVaultAsUserAndCheckValues(2e8, user1, CALL_STRIKE_TICK);
        uint userCashBalanceAfterOpen = cashAsset.balanceOf(user1);
        uint providerCashBalanceBeforeClose = cashAsset.balanceOf(provider);
        manipulatePriceUpwardPastCallStrike(false);
        checkPriceUpPastCallStrikeValues(
            uuid, vault, userCashBalanceAfterOpen, providerCashBalanceBeforeClose
        );
    }

    function testFuzz_openAndCloseVaultPriceUpShortOfCallStrike(uint collateralAmount, uint24 tick)
        public
        assumeTickFuzzValues(tick)
    {
        collateralAmount = bound(collateralAmount, 2e8, 20e8);
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
            openVaultAsUserAndCheckValues(2e8, user1, CALL_STRIKE_TICK);
        uint userCashBalanceAfterOpen = cashAsset.balanceOf(user1);
        uint providerCashBalanceBeforeClose = cashAsset.balanceOf(provider);
        uint finalPrice = manipulatePriceUpwardShortOfCallStrike(false);
        checkPriceUpShortOfCallStrikeValues(
            uuid, vault, userCashBalanceAfterOpen, providerCashBalanceBeforeClose, finalPrice
        );
    }

    function manipulatePriceDownwardPastPutStrike(bool isFuzzTest) internal {
        uint targetPrice = 349955888794672307829;
        _manipulatePriceDownwardPastPutStrike(200e8, isFuzzTest, targetPrice);
    }

    function manipulatePriceDownwardShortOfPutStrike(bool isFuzzTest) internal returns (uint finalPrice) {
        uint targetPrice = 622459347786056128427;
        finalPrice = _manipulatePriceDownwardShortOfPutStrike(50e8, isFuzzTest, targetPrice);
    }

    function manipulatePriceUpwardPastCallStrike(bool isFuzzTest) internal {
        uint targetPrice = 927560830499000417295;

        _manipulatePriceUpwardPastCallStrike(16_800_000e6, isFuzzTest, targetPrice);
    }

    function manipulatePriceUpwardShortOfCallStrike(bool isFuzzTest) internal returns (uint finalPrice) {
        uint targetPrice = 661609347110400360503;
        finalPrice = _manipulatePriceUpwardShortOfCallStrike(1000_000e6, isFuzzTest, targetPrice);

    }
}
