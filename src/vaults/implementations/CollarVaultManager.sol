// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SwapRouter } from "@uni-v3-periphery/SwapRouter.sol";
import { ISwapRouter } from "@uni-v3-periphery/interfaces/ISwapRouter.sol";
import { ICollarEngine, ICollarEngineErrors } from "../../protocol/interfaces/IEngine.sol";
import { ICollarVaultManager } from "../interfaces/ICollarVaultManager.sol";
import { CollarLiquidityPool } from "../../liquidity/implementations/CollarLiquidityPool.sol";
import { ICollarLiquidityPoolManager } from "../../protocol/interfaces/ICollarLiquidityPoolManager.sol";
import { CollarVaultState, CollarVaultManagerErrors, CollarVaultManagerEvents, CollarVaultConstants } from "../../vaults/interfaces/CollarLibs.sol";
import { CollarVaultLens } from "./CollarVaultLens.sol";
import { TickCalculations } from "../../liquidity/implementations/TickCalculations.sol";

contract CollarVaultManager is ICollarVaultManager, ICollarEngineErrors, CollarVaultLens {
    constructor(address _engine, address _owner) ICollarVaultManager(_engine) {
        user = _owner;
     }

    function openVault(
        CollarVaultState.AssetSpecifiers calldata assetSpecifiers,
        CollarVaultState.CollarOpts calldata collarOpts,
        CollarVaultState.LiquidityOpts calldata liquidityOpts
    ) external override returns (bytes32 vaultUUID) {
        // basic validations
        validateAssets(assetSpecifiers);
        validateOpts(collarOpts);
        validateLiquidity(liquidityOpts);

        // attempt to lock the liquidity (to pay out max call strike)
        CollarLiquidityPool(liquidityOpts.liquidityPool).lockLiquidityAtTicks(liquidityOpts.amounts, liquidityOpts.ticks);

        // swap entire amount of collateral for cash
        ISwapRouter.ExactInputSingleParams memory swapParams = ISwapRouter.ExactInputSingleParams({
            tokenIn: assetSpecifiers.collateralAsset,
            tokenOut: assetSpecifiers.cashAsset,
            fee: 3000,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: assetSpecifiers.collateralAmount,
            amountOutMinimum: assetSpecifiers.cashAmount,
            sqrtPriceLimitX96: 0
        });
    
        IERC20(assetSpecifiers.collateralAsset).transferFrom(msg.sender, address(this), assetSpecifiers.collateralAmount);
        IERC20(assetSpecifiers.collateralAsset).approve(ICollarEngine(engine).dexRouter(), assetSpecifiers.collateralAmount);
        uint256 cashAmount = ISwapRouter(payable(ICollarEngine(engine).dexRouter())).exactInputSingle(swapParams);

        // mark LTV as withdrawable and the rest as locked
        uint256 unlockedCashBalance = (cashAmount * collarOpts.ltv) / 10000;
        uint256 lockedCashBalance = cashAmount - unlockedCashBalance;

        // increment vault count
        vaultCount++;

        // generate UUID and set vault storage
        vaultUUID = keccak256(abi.encodePacked(user, vaultCount));

        vaultsByUUID[vaultUUID] = CollarVaultState.Vault(
            true,
            collarOpts.expiry,
            collarOpts.ltv,
            assetSpecifiers.collateralAsset,
            assetSpecifiers.collateralAmount,
            assetSpecifiers.cashAsset,
            cashAmount,
            unlockedCashBalance,
            lockedCashBalance,
            liquidityOpts.liquidityPool,
            liquidityOpts.ticks,
            liquidityOpts.amounts
        );

        vaultUUIDsByIndex[vaultCount] = vaultUUID;
        vaultIndexByUUID[vaultUUID] = vaultCount;

        tokenVaultCount[assetSpecifiers.cashAsset]++;
        tokenTotalBalance[assetSpecifiers.cashAsset] += assetSpecifiers.collateralAmount;

        // emit event
        emit CollarVaultManagerEvents.VaultOpened(vaultUUID);

        return vaultUUID;
    }

    function finalizeVault(
        bytes32 vaultUUID
    ) external override vaultExists(vaultUUID) returns (int256 net) {
        // get vault info
        CollarVaultState.Vault storage vault = vaultsByUUID[vaultUUID];

        // verify vault is active
        if (!vault.active) revert CollarVaultManagerErrors.InactiveVault(vaultUUID);

        // verify vault is expired
        if (vault.expiry < block.timestamp) revert CollarVaultManagerErrors.NotYetExpired(vaultUUID);

        // calculate payouts to user and/or market maker
        uint256 collateralPriceFinal = ICollarEngine(engine).getHistoricalAssetPrice(vault.collateralAsset, vault.expiry);

        // for now, we're using ltv as a standin for put-strike
        uint256 putStrikePrice = (vault.ltv * vault.cashAmount) / 10_000;

        // calculate the initial price
        uint256 startingPrice = vault.collateralAmount / vault.cashAmount;

        // for each tick of liquidity locked, calculate whether it is below the put strike, above the call strike, or somewhere in between
        // if it is below the put strike, this liquidity unit goes to the market maker
        // if it is above the call strike, this liquidity unit goes to the user
        // if it is in between, the amount above the put strike goes to the user and the remaining goes to the market maker

        uint256 scaleFactor = CollarLiquidityPool(vault.liquidityPool).scaleFactor();

        uint24[] memory ticks = vault.ticks;
        uint256[] memory amounts = vault.amounts;

        uint256[] memory payoutsToUser = new uint256[](ticks.length);

        for (uint256 tick = 0; tick < ticks.length; tick++) {
            uint24 tickIndex = ticks[tick];
            uint256 amount = amounts[tick];

            uint256 tickPrice = TickCalculations.tickToPrice(tickIndex, scaleFactor, startingPrice);

            uint256 marketMakerAmount = 0;
            uint256 userAmount = 0;

            if (collateralPriceFinal < putStrikePrice) {
                // this liquidity goes to the market maker
                marketMakerAmount = amount;
            } else if (collateralPriceFinal > tickPrice) {
                // this liquidity goes to the user
                userAmount = amount;
            } else {
                // this liquidity is split between the user and the market maker
                marketMakerAmount = (tickPrice - collateralPriceFinal) * amount;
                userAmount = (collateralPriceFinal - putStrikePrice) * amount;
            }

            payoutsToUser[tick] = userAmount;
        }

        // unlock all the liquidity used for this vault
        CollarLiquidityPool(vault.liquidityPool).unlockLiquidityAtTicks(amounts, ticks);

        // transfer from the liquidity pool to the vault if applicable
        CollarLiquidityPool(vault.liquidityPool).withdrawFromTicks(address(this), payoutsToUser, ticks);

        // mark vault as finalized
        vault.active = false;

        return net;
    }

    function depositCash(
        bytes32 vaultUUID, 
        uint256 amount, 
        address from
    ) external override vaultExists(vaultUUID) returns (uint256 newUnlockedCashBalance) {
        // grab reference to the vault
        CollarVaultState.Vault storage vault = vaultsByUUID[vaultUUID];
        
        // cache the token address
        address cashToken = vault.cashAsset;

        // increment the cash balance of this vault
        vault.unlockedCashBalance += amount;

        // update the total balance tracker
        tokenTotalBalance[cashToken] += amount;

        // transfer in the cash
        IERC20(cashToken).transferFrom(from, address(this), amount);

        return vault.unlockedCashBalance;
    }

    function withdrawCash(
        bytes32 vaultUUID, 
        uint256 amount, 
        address to
    ) external override vaultExists(vaultUUID) returns (uint256 newUnlockedCashBalance) {
        // grab refernce to the vault 
        CollarVaultState.Vault storage vault = vaultsByUUID[vaultUUID];

        // cache the token address
        address cashToken = vault.cashAsset;

        // decrement the token balance of the vault
        vault.unlockedCashBalance -= amount;

        // update the total balance tracker
        tokenTotalBalance[cashToken] -= amount;

        // transfer out the cash
        IERC20(cashToken).transfer(to, amount);

        return vault.unlockedCashBalance;
    }

    function validateAssets(CollarVaultState.AssetSpecifiers calldata assetSpecifiers) internal view {
        if (assetSpecifiers.cashAsset == address(0)) revert CollarVaultManagerErrors.InvalidAssetSpecifiers();
        if (assetSpecifiers.collateralAsset == address(0)) revert CollarVaultManagerErrors.InvalidAssetSpecifiers();
        if (assetSpecifiers.cashAmount == 0) revert CollarVaultManagerErrors.InvalidAssetSpecifiers();
        if (assetSpecifiers.collateralAmount == 0) revert CollarVaultManagerErrors.InvalidAssetSpecifiers();

        // verify validity of assets
        if (!(ICollarEngine(engine)).isSupportedCashAsset(assetSpecifiers.cashAsset)) revert CashAssetNotSupported(assetSpecifiers.cashAsset);    
        if (!(ICollarEngine(engine)).isSupportedCollateralAsset(assetSpecifiers.collateralAsset)) revert CollateralAssetNotSupported(assetSpecifiers.collateralAsset);  
    }

    function validateOpts(CollarVaultState.CollarOpts calldata collarOpts) internal view {
        // very expiry / length
        uint256 collarLength = collarOpts.expiry - block.timestamp; // calculate how long the collar will be
        if (!(ICollarEngine(engine)).isValidCollarLength(collarLength)) revert CollarLengthNotSupported(collarLength);
    }

    function validateLiquidity(CollarVaultState.LiquidityOpts calldata liquidityOpts) internal pure {
        // verify amounts & ticks are equal; specific ticks and amoutns verified in transfer step
        if (liquidityOpts.amounts.length != liquidityOpts.ticks.length) revert InvalidLiquidityOpts();
    }
}