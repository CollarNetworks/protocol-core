// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

import "forge-std/console.sol";
import { ICollarVaultState } from "../../../src/interfaces/ICollarVaultState.sol";
import { CollarBaseIntegrationTestConfig } from "./BaseIntegration.t.sol";
import { PrintVaultStatsUtility } from "../../utils/PrintVaultStats.sol";

abstract contract VaultOperationsTest is CollarBaseIntegrationTestConfig, PrintVaultStatsUtility {
    function openVaultAsUser(uint collateralAmount, address user, uint24 tick)
        internal
        returns (bytes32 uuid, ICollarVaultState.Vault memory vault)
    {
        ICollarVaultState.AssetSpecifiers memory assets = ICollarVaultState.AssetSpecifiers({
            collateralAsset: collateralAssetAddress,
            collateralAmount: collateralAmount,
            cashAsset: cashAssetAddress,
            cashAmount: 0.3e6
        });

        ICollarVaultState.CollarOpts memory collarOpts =
            ICollarVaultState.CollarOpts({ duration: poolDuration, ltv: poolLTV });

        ICollarVaultState.LiquidityOpts memory liquidityOpts = ICollarVaultState.LiquidityOpts({
            liquidityPool: address(pool),
            putStrikeTick: 90,
            callStrikeTick: tick
        });

        startHoax(user);
        uint poolBalanceCollateral = collateralAsset.balanceOf(uniV3Pool);
        uint poolBalanceCash = cashAsset.balanceOf(uniV3Pool);
        vaultManager.openVault(assets, collarOpts, liquidityOpts, false);
        poolBalanceCollateral = collateralAsset.balanceOf(uniV3Pool);
        poolBalanceCash = cashAsset.balanceOf(uniV3Pool);
        uuid = vaultManager.getVaultUUID(0);
        bytes memory rawVault = vaultManager.vaultInfo(uuid);
        vault = abi.decode(rawVault, (ICollarVaultState.Vault));
        _printVaultStats(vault, "VAULT OPENED");
    }

    function openVaultAsUserAndCheckValues(uint amount, address user, uint24 tick)
        internal
        returns (bytes32 uuid, ICollarVaultState.Vault memory vault)
    {
        (uuid, vault) = openVaultAsUser(amount, user, tick);
        // check basic vault info
        assertEq(vault.active, true);
        assertEq(vault.openedAt, block.timestamp);
        assertEq(vault.expiresAt, block.timestamp + 1 days);
        assertEq(vault.duration, poolDuration);
        assertEq(vault.ltv, poolLTV);
        assertEq(vault.collateralAmount, amount);
        // check asset specific info
        assertEq(vault.collateralAsset, collateralAssetAddress);
        assertEq(vault.cashAsset, cashAssetAddress);

        // check liquidity pool stuff
        assertEq(vault.liquidityPool, address(pool));
        assertEq(vault.putStrikeTick, poolLTV / tickScaleFactor); // assuming 100 as tickScaleFactor
    }

    /**
     * PRICE CHECKING UTIL FUNCTIONS
     */
    function checkPriceUnderPutStrikeValues(
        bytes32 uuid,
        ICollarVaultState.Vault memory vault,
        uint userCashBalanceAfterOpen,
        uint providerCashBalanceBeforeClose
    ) internal {
        vm.roll(block.number + 43_200);
        skip(poolDuration + 1 days);
        startHoax(user1);
        // close the vault
        vaultManager.closeVault(uuid);
        _printVaultStats(vault, "VAULT CLOSED");

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
        assertEq(cashAsset.balanceOf(user1), userCashBalanceAfterOpen);
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
        uint providerCashBalanceAfterRedeem = cashAsset.balanceOf(provider);
        // liquidity providers new cash balance is previous balance + withdrawable liquidity
        assertEq(
            providerCashBalanceAfterRedeem,
            providerCashBalanceBeforeClose + vault.lockedPoolCash + vault.lockedVaultCash
        );
    }

    function checkPriceDownShortOfPutStrikeValues(
        bytes32 uuid,
        ICollarVaultState.Vault memory vault,
        uint userCashBalanceAfterOpen,
        uint providerCashBalanceBeforeClose,
        uint finalPrice
    ) internal {
        vm.roll(block.number + 43_200);
        skip(poolDuration + 1 days);
        startHoax(user1);
        // close the vault
        vaultManager.closeVault(uuid);
        _printVaultStats(vault, "VAULT CLOSED");
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
        assertEq(cashAsset.balanceOf(user1), userCashBalanceAfterOpen + vaultLockedCash);

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
        uint providerCashBalanceAfterRedeem = cashAsset.balanceOf(provider);
        // liquidity providers new cash balance is previous balance + withdrawable liquidity
        assertEq(providerCashBalanceAfterRedeem, providerCashBalanceBeforeClose + withdrawable);
    }

    function checkPriceUpPastCallStrikeValues(
        bytes32 uuid,
        ICollarVaultState.Vault memory vault,
        uint userCashBalanceAfterOpen,
        uint providerCashBalanceBeforeClose
    ) internal {
        vm.roll(block.number + 43_200);
        skip(poolDuration + 1 days);
        startHoax(user1);
        // close the vault
        vaultManager.closeVault(uuid);
        _printVaultStats(vault, "VAULT CLOSED");
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
        assertEq(cashAsset.balanceOf(user1), userCashBalanceAfterOpen + vaultLockedCash);

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
        uint providerCashBalanceAfterRedeem = cashAsset.balanceOf(provider);
        // liquidity providers cash balance does not change since they have no withdrawable liquidity
        assertEq(providerCashBalanceAfterRedeem, providerCashBalanceBeforeClose);
    }

    function checkPriceUpShortOfCallStrikeValues(
        bytes32 uuid,
        ICollarVaultState.Vault memory vault,
        uint userCashBalanceAfterOpen,
        uint providerCashBalanceBeforeClose,
        uint finalPrice
    ) internal {
        vm.roll(block.number + 43_200);
        skip(poolDuration + 1 days);
        startHoax(user1);
        // close the vault
        vaultManager.closeVault(uuid);
        _printVaultStats(vault, "VAULT CLOSED");
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
        assertEq(cashAsset.balanceOf(user1), userCashBalanceAfterOpen + vaultLockedCash);

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
        uint providerCashBalanceAfterRedeem = cashAsset.balanceOf(provider);
        // liquidity providers new cash balance is previous balance + withdrawable liquidity
        assertEq(providerCashBalanceAfterRedeem, providerCashBalanceBeforeClose + withdrawable);
    }
}