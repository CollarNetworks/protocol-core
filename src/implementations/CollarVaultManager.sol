// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

import { ICollarVaultManager } from "../interfaces/ICollarVaultManager.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Constants, CollarVaultState } from "../libs/CollarLibs.sol";
import { ISwapRouter } from "@uni-v3-periphery/interfaces/ISwapRouter.sol";
import { CollarEngine } from "../implementations/CollarEngine.sol";
import { TickCalculations } from "../libs/TickCalculations.sol";
import { CollarPool } from "./CollarPool.sol";

contract CollarVaultManager is ICollarVaultManager, Constants {
    // ----- CONSTRUCTOR ----- //

    constructor(address _engine, address _owner) ICollarVaultManager(_engine, _owner) { }

    // ----- VIEW FUNCTIONS ----- //

    function isVaultExpired(bytes32 uuid) external view override returns (bool) {
        return vaultsByUUID[uuid].expiresAt < block.timestamp;
    }

    function vaultInfo(bytes32 uuid) external view override returns (bytes memory) {
        if (vaultsByUUID[uuid].openedAt == 0) {
            revert("Vault does not exist");
        }

        bytes memory data = abi.encode(vaultsByUUID[uuid]);
        return data;
    }

    function previewRedeem(bytes32 uuid, uint256 amount) public view override returns (uint256 cashReceived) {
        if (amount == 0) revert("Amount cannot be 0");
        if (vaultsByUUID[uuid].openedAt == 0) revert("Vault does not exist");

        bool finalized = !vaultsByUUID[uuid].active;

        if (finalized) {
            // if finalized, calculate final redeem value
            // grab collateral asset value @ exact vault expiration time

            uint256 totalTokenCashSupply = vaultTokenCashSupply[uuid];
            uint256 totalTokenSupplyLocal = totalTokenSupply[uint256(uuid)];

            if (totalTokenCashSupply == 0) {
                revert("Vault has no redeemable cash");
            }

            if (totalTokenSupplyLocal == 0) {
                revert("Vault has no tokens");
            }

            cashReceived = (totalTokenCashSupply * amount) / totalTokenSupplyLocal;
        } else {
            // calculate redeem value based on current price of asset

            uint256 currentCollateralPrice = CollarEngine(engine).getCurrentAssetPrice(vaultsByUUID[uuid].collateralAsset);

            revert("Not implemented");
        }
    }

    // ----- STATE CHANGING FUNCTIONS ----- //

    function openVault(
        CollarVaultState.AssetSpecifiers calldata assetData, // addresses & amounts of collateral & cash assets
        CollarVaultState.CollarOpts calldata collarOpts, // length & ltv
        CollarVaultState.LiquidityOpts calldata liquidityOpts // pool address, callstrike & amount to lock there, putstrike
    ) external override returns (bytes32 uuid) {
        // only user is allowed to open vaults
        if (msg.sender != user) {
            revert("Only user can open vaults");
        }

        // validate parameter data
        _validateAssetData(assetData);
        _validateCollarOpts(collarOpts);
        _validateLiquidityOpts(liquidityOpts);
        _validateRequestedPoolAssets(assetData, liquidityOpts);

        // generate vault (and token) nonce
        uuid = keccak256(abi.encodePacked(user, ++vaultCount));

        // set Basic Vault Info
        vaultsByUUID[uuid].active = true;
        vaultsByUUID[uuid].openedAt = block.timestamp;
        vaultsByUUID[uuid].expiresAt = block.timestamp + collarOpts.length;
        vaultsByUUID[uuid].ltv = collarOpts.ltv;

        // set Asset Specific Info
        vaultsByUUID[uuid].collateralAsset = assetData.collateralAsset;
        vaultsByUUID[uuid].collateralAmount = assetData.collateralAmount;
        vaultsByUUID[uuid].cashAsset = assetData.cashAsset;

        // transfer collateral from user to vault
        IERC20(assetData.collateralAsset).transferFrom(user, address(this), assetData.collateralAmount);

        // swap collateral for cash & record cash amount
        uint256 cashReceivedFromSwap = _swap(assetData);
        vaultsByUUID[uuid].cashAmount = cashReceivedFromSwap;

        // calculate exactly how much cash to lock from the liquidity poolj
        // this is equal to (callstrikePercent - 100%) * totalCashReceivedFromSwap
        // first, grab the call strike percent from the call strike tick supplied
        uint256 tickScaleFactor = CollarPool(liquidityOpts.liquidityPool).tickScaleFactor();
        uint256 callStrikePercentBps = TickCalculations.tickToBps(liquidityOpts.callStrikeTick, tickScaleFactor);
        uint256 poolLiquidityToLock = ((callStrikePercentBps - ONE_HUNDRED_PERCENT) * cashReceivedFromSwap * PRECISION_MULTIPLIER)
            / (ONE_HUNDRED_PERCENT) / PRECISION_MULTIPLIER;

        // grab the current collateral price so that we can record it
        uint256 initialCollateralPrice = CollarEngine(engine).getCurrentAssetPrice(assetData.collateralAsset);

        // set Liquidity Pool Stuff
        vaultsByUUID[uuid].liquidityPool = liquidityOpts.liquidityPool;
        vaultsByUUID[uuid].lockedPoolCash = poolLiquidityToLock;
        vaultsByUUID[uuid].initialCollateralPrice = initialCollateralPrice;
        vaultsByUUID[uuid].putStrikePrice =
            TickCalculations.tickToPrice(liquidityOpts.putStrikeTick, tickScaleFactor, initialCollateralPrice);
        vaultsByUUID[uuid].callStrikePrice =
            TickCalculations.tickToPrice(liquidityOpts.callStrikeTick, tickScaleFactor, initialCollateralPrice);
        vaultsByUUID[uuid].putStrikeTick = liquidityOpts.putStrikeTick;
        vaultsByUUID[uuid].callStrikeTick = liquidityOpts.callStrikeTick;

        // mint vault tokens (equal to the amount of cash received from swap)
        _mint(user, uint256(uuid), cashReceivedFromSwap);

        // mint liquidity pool tokens
        CollarPool(liquidityOpts.liquidityPool).openPosition(uuid, liquidityOpts.callStrikeTick, poolLiquidityToLock);

        // set Vault Specific stuff
        vaultsByUUID[uuid].loanBalance = (collarOpts.ltv * cashReceivedFromSwap) / ONE_HUNDRED_PERCENT;
        vaultsByUUID[uuid].lockedVaultCash = ((ONE_HUNDRED_PERCENT - collarOpts.ltv) * cashReceivedFromSwap) / ONE_HUNDRED_PERCENT;

        // approve the pool
        IERC20(assetData.cashAsset).approve(liquidityOpts.liquidityPool, vaultsByUUID[uuid].lockedVaultCash);
    }

    function closeVault(bytes32 uuid) external override {
        // ensure vault exists
        if (vaultsByUUID[uuid].openedAt == 0) {
            revert("Vault does not exist");
        }

        // ensure vault is active (not finalized) and finalizable (past length)
        if (!vaultsByUUID[uuid].active || vaultsByUUID[uuid].expiresAt > block.timestamp) {
            revert("Vault not active or not finalizable");
        }

        // cache vault storage pointer
        CollarVaultState.Vault storage vault = vaultsByUUID[uuid];

        // grab all price info
        uint256 startingPrice = vault.initialCollateralPrice;
        uint256 putStrikePrice = vault.putStrikePrice;
        uint256 callStrikePrice = vault.callStrikePrice;

        uint256 finalPrice = CollarEngine(engine).getHistoricalAssetPrice(vault.collateralAsset, vault.expiresAt);

        if (finalPrice == 0) revert("Asset price cannot be 0");

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

        uint256 cashNeededFromPool = 0;
        uint256 cashToSendToPool = 0;

        // CASE 1 - all vault cash to liquidity pool
        if (finalPrice <= putStrikePrice) {
            cashToSendToPool = vault.lockedVaultCash;

            // CASE 2 - all vault cash to user, all locked pool cash to user
        } else if (finalPrice >= callStrikePrice) {
            cashNeededFromPool = vault.lockedPoolCash;

            // CASE 3 - all vault cash to user
        } else if (finalPrice == startingPrice) {
            // no need to update any vars here

            // CASE 4 - proportional vault cash to user
        } else if (putStrikePrice < finalPrice && finalPrice < startingPrice) {
            uint256 vaultCashToPool =
                ((vault.lockedVaultCash * (startingPrice - finalPrice) * 1e32) / (startingPrice - putStrikePrice)) / 1e32;
            // uint256 vaultCashToUser = vault.lockedVaultCash - vaultCashToPool;

            cashToSendToPool = vaultCashToPool;

            // CASE 5 - all vault cash to user, proportional locked pool cash to user
        } else if (callStrikePrice > finalPrice && finalPrice > startingPrice) {
            uint256 poolCashToUser =
                ((vault.lockedPoolCash * (finalPrice - startingPrice) * 1e32) / (callStrikePrice - startingPrice)) / 1e32;

            cashNeededFromPool = poolCashToUser;

            // ???
        } else {
            revert("This really should not be possible!");
        }

        // sanity check
        if (cashNeededFromPool > 0 && cashToSendToPool > 0) {
            revert("Vault is in an invalid state");
        }

        int256 poolProfit = cashToSendToPool > 0 ? int256(cashToSendToPool) : -int256(cashNeededFromPool);
        CollarPool(vault.liquidityPool).finalizePosition(uuid, address(this), poolProfit);

        if (cashToSendToPool > 0) {
            vault.lockedVaultCash -= cashToSendToPool;
            IERC20(vault.cashAsset).approve(vault.liquidityPool, cashToSendToPool);
        }

        // set total redeem value for vault tokens to locked vault cash + cash pulled from pool
        // also null out the locked vault cash
        vaultTokenCashSupply[uuid] = vault.lockedVaultCash + cashNeededFromPool;
        vault.lockedVaultCash = 0;

        // mark vault as finalized
        vault.active = false;
    }

    function redeem(bytes32 uuid, uint256 amount) external override {
        // ensure vault exists
        if (vaultsByUUID[uuid].openedAt == 0) {
            revert("Vault does not exist");
        }

        // ensure vault is finalized
        if (vaultsByUUID[uuid].active) {
            revert("Vault not finalized / still active!");
        }

        // check auth just in case
        if (user != msg.sender) revert("Only user can redeem tokens");

        // calculate cash redeem value
        uint256 redeemValue = previewRedeem(uuid, amount);

        // redeem to user & burn tokens
        _burn(msg.sender, uint256(uuid), amount);
        IERC20(vaultsByUUID[uuid].cashAsset).transfer(msg.sender, redeemValue);
    }

    function withdraw(bytes32 uuid, uint256 amount) external override {
        if (msg.sender != user) revert("Only user can withdraw");
        if (vaultsByUUID[uuid].openedAt == 0) revert("Vault does not exist");

        uint256 loanBalance = vaultsByUUID[uuid].loanBalance;

        // withdraw from user's loan balance
        if (amount > loanBalance) {
            revert("Insufficient loan balance");
        } else {
            vaultsByUUID[uuid].loanBalance -= amount;
            IERC20(vaultsByUUID[uuid].cashAsset).transfer(msg.sender, amount);
        }
    }

    // ----- INTERNAL FUNCTIONS ----- //

    function _validateAssetData(CollarVaultState.AssetSpecifiers calldata assetData) internal {
        // verify cash & collateral assets against engine for validity
        if (!CollarEngine(engine).isSupportedCashAsset(assetData.cashAsset)) {
            revert("Unsupported cash asset");
        }

        if (!CollarEngine(engine).isSupportedCollateralAsset(assetData.collateralAsset)) {
            revert("Unsupported collateral asset");
        }

        // verify cash & collateral amounts are > 0
        if (assetData.cashAmount == 0) {
            revert("Cash amount must be > 0");
        }

        if (assetData.collateralAmount == 0) {
            revert("Collateral amount must be > 0");
        }
    }

    function _validateCollarOpts(CollarVaultState.CollarOpts calldata collarOpts) internal {
        // verify length is in the future
        if (collarOpts.length < block.timestamp) {
            revert("length must be in the future");
        }

        // verify length is exactly within a standard set of time blocks via the engine
        if (!CollarEngine(engine).isValidCollarLength(collarOpts.length)) {
            revert("Invalid length");
        }

        // verify ltv is within engine-allowed bounds
    }

    function _validateLiquidityOpts(CollarVaultState.LiquidityOpts calldata liquidityOpts) internal {
        // verify liquidity pool is a valid collar liquidity pool
        if (!CollarEngine(engine).isSupportedLiquidityPool(liquidityOpts.liquidityPool)) {
            revert("Unsupported liquidity pool");
        }
    }

    function _validateRequestedPoolAssets(
        CollarVaultState.AssetSpecifiers calldata assetData,
        CollarVaultState.LiquidityOpts calldata liquidityOpts
    ) internal pure {
        // calculate the amount of locked pool liquidity needed and ensure that exactly that much has been requested
    }

    function _swap(CollarVaultState.AssetSpecifiers calldata assets) internal returns (uint256 cashReceived) {
        // approve the dex router so we can swap the collateral to cash
        IERC20(assets.collateralAsset).approve(CollarEngine(engine).dexRouter(), assets.collateralAmount);

        // build the swap transaction
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

        // cache the amount of cash received
        cashReceived = ISwapRouter(payable(CollarEngine(engine).dexRouter())).exactInputSingle(swapParams);

        // revert if minimum not met
        if (cashReceived < assets.cashAmount) {
            revert("Insufficient cash received");
        }
    }

    function _mint(address account, uint256 id, uint256 amount) internal override {
        // update total supply of token
        totalTokenSupply[id] += amount;

        super._mint(account, id, amount);
    }

    function _burn(address account, uint256 id, uint256 amount) internal override {
        // update total supply of token
        totalTokenSupply[id] -= amount;

        super._burn(account, id, amount);
    }
}
