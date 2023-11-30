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
        CollarLiquidityPool(liquidityOpts.liquidityPool).lock(liquidityOpts.amount, liquidityOpts.tick);

        // transfer in collateral & swap to cash 
        IERC20(assets.collateralAsset).transferFrom(msg.sender, address(this), assets.collateralAmount);
        uint256 cashAmount = swapCollateral(assets);

        // calculate locked & unlocked balances
        uint256 unlockedCashBalance; uint256 lockedCashBalance;
        (unlockedCashBalance, lockedCashBalance) = calculateCashBalances(cashAmount, collarOpts.ltv);

        // calculate the put & call strike prices (in terms of how much cash asset you'd get for 1e18 of the collateral asset)
        uint256 putStrikePrice = (collarOpts.ltv * cashAmount * 1e12) / 10_000;
        uint256 callStrikePrice = (10000 * cashAmount * 1e12) / collarOpts.ltv;
        uint256 startingPrice = 0; // todo calculate this

        // generate nonce-based UUID & pre-increment vault count
        vaultUUID = keccak256(abi.encodePacked(user, ++vaultCount));

        // create the vault
        vaultsByUUID[vaultUUID] = CollarVaultState.Vault(
            true,                           // vault is now active
            block.timestamp,                // creation time = now
            collarOpts.expiry,              // expires some time in the future
            collarOpts.ltv,                 // loan-to-value for withdrawal
            assets.collateralAsset,         // collateral token address (ERC20)
            assets.collateralAmount,        // amount of collateral tokens
            assets.cashAsset,               // cash token address (ERC20)
            cashAmount,                     // amount of cash tokens total
            putStrikePrice,                 // price of 1e18 of the collateral asset @ put strike in terms of the cash asset
            callStrikePrice,                // price of 1e18 of the collateral asset @ call strike in terms of the cash asset
            startingPrice,                  // price of 1e18 of the collateral asset @ start in terms of the cash asset
            unlockedCashBalance,            // amount (initially & currently) withdrawable
            lockedCashBalance,              // amount locked
            liquidityOpts.liquidityPool,    // address of the liquidity pool
            liquidityOpts.amount,           // the amount of liquidity locked
            liquidityOpts.tick              // the tick at which liquidity is locked
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

        // calculate payouts to user and/or market maker
        uint256 finalCollateralPrice = ICollarEngine(engine).getHistoricalAssetPrice(vault.collateralAsset, vault.expiresAt);

        uint256 putStrikePrice = vault.putStrikePrice;
        uint256 startingPrice = vault.startingPrice;

        uint256 poolScaleFactor = CollarLiquidityPool(vault.liquidityPool).scaleFactor();

        CollarLiquidityPool(vault.liquidityPool).unlock(vault.cashAmount, vault.tick);

        vault.active = false;
    }

    function deposit(
        bytes32 vaultUUID, 
        uint256 amount, 
        address from
    ) external override vaultExists(vaultUUID) returns (uint256 newUnlockedCashBalance) {
        // grab reference to the vault
        CollarVaultState.Vault storage vault = vaultsByUUID[vaultUUID];
        
        // cache the token address
        address cashToken = vault.cashAsset;

        // increment the cash balance of this vault
        vault.unlockedCashTotal += amount;

        // transfer in the cash
        IERC20(cashToken).transferFrom(from, address(this), amount);

        return vault.unlockedCashTotal;
    }

    function withdraw(
        bytes32 vaultUUID, 
        uint256 amount, 
        address to
    ) external override vaultExists(vaultUUID) returns (uint256 newUnlockedCashBalance) {
        // grab refernce to the vault 
        CollarVaultState.Vault storage vault = vaultsByUUID[vaultUUID];

        // cache the token address
        address cashToken = vault.cashAsset;

        // decrement the token balance of the vault
        vault.unlockedCashTotal -= amount;

        // transfer out the cash
        IERC20(cashToken).transfer(to, amount);

        return vault.unlockedCashTotal;
    }

    function swapCollateral(CollarVaultState.AssetSpecifiers calldata assets) internal returns (uint256 cashReceived) {
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

    function calculateCashBalances(uint256 cashAmount, uint256 ltv) internal pure returns (uint256 unlockedCashBalance, uint256 lockedCashBalance) {
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