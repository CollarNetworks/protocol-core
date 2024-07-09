// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

import "forge-std/console.sol";

import { ICollarVaultState } from "../../src/interfaces/ICollarVaultState.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { CollarIntegrationPriceManipulation } from "./utils/PriceManipulation.t.sol";
import { VaultOperationsTest } from "./utils/VaultOperations.t.sol";

/**
 * @dev This contract should generate test to ensure all the cases and math from this sheet is correct and
 * verified
 * https://docs.google.com/spreadsheets/d/18e5ola3JJ2HKRQyAoPNmVrV4fnRcLdckOhQIxrN_hwY/edit#gid=1819672818
 */
contract ForkTestCollarArbitrumMainnetIntegrationTest is
    CollarIntegrationPriceManipulation,
    VaultOperationsTest
{
    /* We set up the test environment as follows:

    1. We fork Arbitrum and activate the fork
    2. We deploy the CollarEngine with the dex set to SwapRouter02 from Uniswap on the Arbitrum fork
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
        uint _blockNumberToUse = 223_579_191;
        string memory forkRPC = vm.envString("ARBITRUM_MAINNET_RPC");
        uint bn = vm.getBlockNumber();
        console.log("Current block number: %d", bn);
        vm.createSelectFork(forkRPC, _blockNumberToUse);
        /**
         * @dev for arbitrum block.number returns the L1 block , not the L2 block so the one we pass is not the one we assert to
         */
        assertEq(block.number, 20_127_607);
        /**
         * Arbitrum mainnet addresses
         */
        _setupConfig({
            _swapRouter: 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45,
            _cashAsset: 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8, // USDC
            _collateralAsset: 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1, //WETH
            _uniV3Pool: 0x17c14D2c404D167802b16C450d3c99F88F2c4F4d,
            whaleWallet: 0xB38e8c17e38363aF6EbdCb3dAE12e0243582891D,
            blockNumber: _blockNumberToUse,
            priceOnBlock: 3_547_988_497, // $3547.988497 the price for WETH in USDC on the specified block of Arbitrum mainnet
            callStrikeTickToUse: 120,
            _poolDuration: 1 days,
            _poolLTV: 9000
        });
        uint amountToProvide = 100_000e6;
        _fundWallets();
        _addLiquidityToPool(amountToProvide);
        vm.stopPrank();
        _validateSetup(amountToProvide, 1 days, 9000);
    }

    modifier assumeTickFuzzValues(uint24 tick) {
        vm.assume(tick == 110 || tick == 115 || tick == 120 || tick == 130);
        _;
    }

    function test_openAndCloseVaultNoPriceChange() public {
        (bytes32 uuid,) = openVaultAsUserAndCheckValues(1 ether, user1, CALL_STRIKE_TICK);
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
        assumeTickFuzzValues(tick)
    {
        collateralAmount = bound(collateralAmount, 1 ether, 20 ether);
        (bytes32 uuid, ICollarVaultState.Vault memory vault) =
            openVaultAsUserAndCheckValues(collateralAmount, user1, tick);
        uint userCashBalanceAfterOpen = cashAsset.balanceOf(user1);
        uint providerCashBalanceBeforeClose = cashAsset.balanceOf(provider);

        manipulatePriceDownwardPastPutStrike(true);
        checkPriceUnderPutStrikeValues(uuid, vault, userCashBalanceAfterOpen, providerCashBalanceBeforeClose);
    }

    function test_openAndCloseVaultPriceUnderPutStrike() public {
        (bytes32 uuid, ICollarVaultState.Vault memory vault) =
            openVaultAsUserAndCheckValues(1 ether, user1, CALL_STRIKE_TICK);
        uint userCashBalanceAfterOpen = cashAsset.balanceOf(user1);
        uint providerCashBalanceBeforeClose = cashAsset.balanceOf(provider);

        manipulatePriceDownwardPastPutStrike(false);
        checkPriceUnderPutStrikeValues(uuid, vault, userCashBalanceAfterOpen, providerCashBalanceBeforeClose);
    }

    function testFuzz_openAndCloseVaultPriceDownShortOfPutStrike(uint collateralAmount, uint24 tick)
        public
        assumeTickFuzzValues(tick)
    {
        collateralAmount = bound(collateralAmount, 1 ether, 20 ether);
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
            openVaultAsUserAndCheckValues(1 ether, user1, CALL_STRIKE_TICK);
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
        collateralAmount = bound(collateralAmount, 1 ether, 20 ether);
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
            openVaultAsUserAndCheckValues(1 ether, user1, CALL_STRIKE_TICK);
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
        collateralAmount = bound(collateralAmount, 1 ether, 20 ether);
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
            openVaultAsUserAndCheckValues(1 ether, user1, CALL_STRIKE_TICK);
        uint userCashBalanceAfterOpen = cashAsset.balanceOf(user1);
        uint providerCashBalanceBeforeClose = cashAsset.balanceOf(provider);
        uint finalPrice = manipulatePriceUpwardShortOfCallStrike(false);
        checkPriceUpShortOfCallStrikeValues(
            uuid, vault, userCashBalanceAfterOpen, providerCashBalanceBeforeClose, finalPrice
        );
    }

    function manipulatePriceDownwardPastPutStrike(bool isFuzzTest) internal {
        uint targetPrice = 3_026_015_148;
        _manipulatePriceDownwardPastPutStrike(50 ether, isFuzzTest, targetPrice);
    }

    function manipulatePriceDownwardShortOfPutStrike(bool isFuzzTest) internal returns (uint finalPrice) {
        uint targetPrice = 3_332_896_653;
        finalPrice = _manipulatePriceDownwardShortOfPutStrike(20 ether, isFuzzTest, targetPrice);
    }

    function manipulatePriceUpwardPastCallStrike(bool isFuzzTest) internal {
        uint targetPrice = 5_113_174_239;
        _manipulatePriceUpwardPastCallStrike(400_000e6, isFuzzTest, targetPrice);
    }

    function manipulatePriceUpwardShortOfCallStrike(bool isFuzzTest) internal returns (uint finalPrice) {
        uint targetPrice = 3_872_244_419;
        finalPrice = _manipulatePriceUpwardShortOfCallStrike(100_000e6, isFuzzTest, targetPrice);
    }
}
