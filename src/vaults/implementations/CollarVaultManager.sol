// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

// how does this contract work exactly? let's ask chatGPT
// https://chat.openai.com/share/fcdbd3fa-5aa3-42ef-8c61-cbcfe7f09524

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

    function open(
        CollarVaultState.AssetSpecifiers calldata assets,
        CollarVaultState.CollarOpts calldata collarOpts,
        CollarVaultState.LiquidityOpts calldata liquidityOpts
    ) external override returns (bytes32 vaultUUID) {
        validateAssets(assets);
        validateOpts(collarOpts);
        validateLiquidity(liquidityOpts);

        // lock liquidity from the liquidity pool (to pay out potentially up to the callstrike)
        CollarLiquidityPool(liquidityOpts.liquidityPool).lock(liquidityOpts.amountToLock, liquidityOpts.callStrikeTick);

        // transfer in collateral
        IERC20(assets.collateralAsset).transferFrom(msg.sender, address(this), assets.collateralAmount);

        // swap collateral for cash
        uint256 cashAmount = swap(assets);
        
        // calculate locked & unlocked balances
        uint256 unlockedCashBalance; uint256 lockedCashBalance;
        (unlockedCashBalance, lockedCashBalance) = calculateCashBalances(cashAmount, collarOpts.ltv);

        // caulate a bunch of stuff we need to create the vault

        uint256 startingPrice = ICollarEngine(engine).getCurrentAssetPrice(assets.cashAsset);

        uint24 putStrikeTick = liquidityOpts.putStrikeTick;
        uint24 callStrikeTick = liquidityOpts.callStrikeTick;

        uint256 tickScale = CollarLiquidityPool(liquidityOpts.liquidityPool).scaleFactor();
        
        uint256 putStrikePrice = TickCalculations.tickToPrice(putStrikeTick, tickScale, startingPrice);
        uint256 callStrikePrice = TickCalculations.tickToPrice(callStrikeTick, tickScale, startingPrice);

        // generate nonce-based UUID & pre-increment vault count
        vaultUUID = keccak256(abi.encodePacked(user, ++vaultCount));

        // create the vault
        vaultsByUUID[vaultUUID] = CollarVaultState.Vault(
            true,                           // vault is now active
            block.timestamp,                // creation time = now
            collarOpts.expiry,              // expires some time in the future
            collarOpts.ltv,                 // loan-to-value for withdrawal

            assets.collateralAsset,         // collateral token address (ERC20)
            assets.cashAsset,               // cash token address (ERC20)
            assets.collateralAmount,        // amount of collateral tokens
            cashAmount,                     // amount of cash tokens total

            liquidityOpts.liquidityPool,    // address of the liquidity pool
            liquidityOpts.amountToLock,     // the amount of liquidity locked
            startingPrice,                  // starting (current) price of collateral asset
            putStrikePrice,                 // price of collateral @ the put strike
            callStrikePrice,                // price of collateral @ the call strike
            putStrikeTick,                  // index of the put strike tick in the liquidity pool
            callStrikeTick,                 // index of the call strike tick  in the liquidity pool

            unlockedCashBalance,            // unlocked cash balance (withdrawable from the vault)
            lockedCashBalance               // locked cash balance (unwithdrawable from the vault)
        );

        // set various vault mappings
        vaultUUIDsByIndex[vaultCount] = vaultUUID;
        vaultIndexByUUID[vaultUUID] = vaultCount;
    }

    function finalize(bytes32 vaultUUID) external override vaultExists(vaultUUID) vaultIsActive(vaultUUID) vaultIsExpired(vaultUUID) {
        CollarVaultState.Vault storage vault = vaultsByUUID[vaultUUID];

        // vault can finalze in 4 possible states, depending on where the final price (P_1) ends up
        // relative to the put strike (PUT), the call strike (CAL), and the starting price (P_0)
        //
        // (CASE 1) final price < put strike
        //  - P_1 --- PUT --- P_0 --- CAL 
        //  - locked vault cash is rewarded to the liquidity provider
        //  - locked pool liquidity is entirely returned to the liquidity provider
        //
        // (CASE 2) final price > call strike 
        //  - PUT --- P_0 --- CAL --- P_1 
        //  - locked vault cash is given to the user to cover collateral appreciation
        //  - locked pool liquidity is entirely used to cover collateral appreciation
        //
        // (CASE 3) put strike < final price < starting price 
        //  - PUT --- P_1 --- P_0 --- CAL 
        //  - locked vault cash is partially given to the user to cover some collateral appreciation
        //  - locked pool liquidity is entirely returned to the liquidity provider
        //
        // (CASE 4) call strike > final price > starting price 
        //  - PUT --- P_0 --- P_1 --- CAL 
        //  - locked vault cash is given to the user to cover collateral appreciation
        //  - locked pool liquidity is partially used to cover some collateral appreciation

        // unlock the liquidty from the pool first
        CollarLiquidityPool(vault.liquidityPool).unlock(vault.cashAmount, vault.callStrikeTick);

        // grab all price info
        uint256 startingPrice = vault.startingPrice;
        uint256 putStrikePrice = vault.putStrikePrice;
        uint256 callStrikePrice = vault.callStrikePrice;
        uint256 finalPrice = ICollarEngine(engine).getHistoricalAssetPrice(vault.collateralAsset, vault.expiresAt);

        CollarLiquidityPool pool = CollarLiquidityPool(vault.liquidityPool);

        if (finalPrice < putStrikePrice) {

            // CASE 1 - all vault cash to liquidity pool

            pool.reward(vault.lockedVaultCash, vault.callStrikeTick);

        } else if (finalPrice > callStrikePrice) {

            // CASE 2 - all vault cash to user, all locked pool cash to user

            vault.unlockedVaultCash += vault.lockedVaultCash;
            vault.lockedVaultCash = 0;

            pool.withdraw(address(this), vault.lockedPoolCash);

        } else if (putStrikePrice < finalPrice && finalPrice < startingPrice) {

            // CASE 3 - proportional vault cash to user
            
            uint256 vaultCashToPool = ((vault.lockedVaultCash * (startingPrice - finalPrice) * 1e32) / (startingPrice - putStrikePrice)) / 1e32;
            uint256 vaultCashToUser = vault.lockedVaultCash - vaultCashToPool;

            vault.unlockedVaultCash += vaultCashToUser;

            pool.reward(vaultCashToPool, vault.callStrikeTick);

        } else if (callStrikePrice > finalPrice && finalPrice > startingPrice) {

            // CASE 4 - all vault cash to user, proportional locked pool cash to user

            uint256 poolCashToUser = ((vault.lockedPoolCash * (finalPrice - startingPrice) * 1e32) / (callStrikePrice - startingPrice)) / 1e32;

            pool.withdraw(address(this), poolCashToUser);

            vault.unlockedVaultCash += poolCashToUser;
            vault.unlockedVaultCash += vault.lockedVaultCash;
            vault.lockedVaultCash = 0;
        }

        vault.active = false;
    }

    function deposit(bytes32 vaultUUID, uint256 amount, address from) external override vaultExists(vaultUUID) returns (uint256 newUnlockedCashBalance) {
        CollarVaultState.Vault storage vault = vaultsByUUID[vaultUUID];

        // increment the cash balance of this vault
        newUnlockedCashBalance = vault.unlockedVaultCash += amount;

        // transfer in the cash
        IERC20(vault.cashAsset).transferFrom(from, address(this), amount);
    }

    function withdraw(bytes32 vaultUUID, uint256 amount, address to) external override vaultExists(vaultUUID) returns (uint256 newUnlockedCashBalance) {
        CollarVaultState.Vault storage vault = vaultsByUUID[vaultUUID];

        // decrement the token balance of the vault
        newUnlockedCashBalance = vault.unlockedVaultCash -= amount;

        // transfer out the cash
        IERC20(vault.cashAsset).transfer(to, amount);
    }

    function swap(CollarVaultState.AssetSpecifiers calldata assets) internal returns (uint256 cashReceived) {
        IERC20(assets.collateralAsset).approve(ICollarEngine(engine).dexRouter(), assets.collateralAmount);

        ISwapRouter.ExactInputSingleParams memory swapParams = ISwapRouter.ExactInputSingleParams({
            tokenIn: assets.collateralAsset,
            tokenOut: assets.cashAsset,
            fee: 3000,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: assets.collateralAmount,
            amountOutMinimum: assets.cashAmount,
            sqrtPriceLimitX96: 0
        });

        cashReceived = ISwapRouter(payable(ICollarEngine(engine).dexRouter())).exactInputSingle(swapParams);
    }

    function calculateCashBalances(uint256 cashAmount, uint256 ltv) internal pure returns (
        uint256 unlockedCashBalance, 
        uint256 lockedCashBalance) 
    {
        unlockedCashBalance = (cashAmount * ltv) / 10000;
        lockedCashBalance = cashAmount - unlockedCashBalance;
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
        /*if (liquidityOpts.amounts.length != liquidityOpts.ticks.length) revert InvalidLiquidityOpts();*/
    }
}