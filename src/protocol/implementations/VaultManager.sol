// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SwapRouter } from "@uni-v3-periphery/SwapRouter.sol";
import { ISwapRouter } from "@uni-v3-periphery/interfaces/ISwapRouter.sol";
import { ICollarEngine, ICollarEngineErrors } from "../interfaces/IEngine.sol";
import { ICollarVaultManager, CollarVaultManagerErrors, CollarVaultManagerEvents } from "../interfaces/IVaultManager.sol";
import { CollarLiquidityPool } from "../../liquidity/implementations/CollarLiquidityPool.sol";
import { ICollarLiquidityPoolManager } from "../interfaces/ICollarLiquidityPoolManager.sol";

contract CollarVaultManager is ICollarVaultManager, ICollarEngineErrors {
    modifier vaultExists(bytes32 vaultUUID) {
        if (vaultIndexByUUID[vaultUUID] == 0) revert CollarVaultManagerErrors.NonExistentVault(vaultUUID);
        _;
    }

    constructor(address owner) ICollarVaultManager() {
        user = owner;
    }

    function isActive(
        bytes32 vaultUUID
    ) public override view vaultExists(vaultUUID) returns (bool) {
        return vaultsByUUID[vaultUUID].active;
    }

    function isExpired(
        bytes32 vaultUUID
    ) public override view vaultExists(vaultUUID) returns (bool) {
        return vaultsByUUID[vaultUUID].collarOpts.expiry > block.timestamp;
    }

    function getExpiry(
        bytes32 vaultUUID
    ) public override view vaultExists(vaultUUID) returns (uint256) {
        return vaultsByUUID[vaultUUID].collarOpts.expiry;
    }

    function timeRemaining(
        bytes32 vaultUUID
    ) public override view vaultExists(vaultUUID) returns (uint256) {
        uint256 expiry = getExpiry(vaultUUID);

        if (expiry < block.timestamp) return 0;

        return expiry - block.timestamp;
    }

    function depositCash(
        bytes32 vaultUUID, 
        uint256 amount, 
        address from
    ) external override vaultExists(vaultUUID) returns (uint256 newCashBalance) {
        // grab reference to the vault
        Vault storage vault = vaultsByUUID[vaultUUID];
        
        // cache the token address
        address cashToken = vault.assetSpecifiers.cashAsset;

        // increment the cash balance of this vault
        vault.assetSpecifiers.cashAmount += amount;

        // update the total balance tracker
        tokenTotalBalance[cashToken] += amount;

        // transfer in the cash
        IERC20(cashToken).transferFrom(from, address(this), amount);

        return vault.assetSpecifiers.cashAmount;
    }

    function withrawCash(
        bytes32 vaultUUID, 
        uint256 amount, 
        address to
    ) external override vaultExists(vaultUUID) returns (uint256 newCashBalance) {
        // grab refernce to the vault 
        Vault storage vault = vaultsByUUID[vaultUUID];

        // cache the token address
        address cashToken = vault.assetSpecifiers.cashAsset;

        // decrement the token balance of the vault
        vault.assetSpecifiers.cashAmount -= amount;

        // update the total balance tracker
        tokenTotalBalance[cashToken] -= amount;

        // transfer out the cash
        IERC20(cashToken).transfer(to, amount);

        // calculate & cache the ltv of the vault
        uint256 ltv = getLTV(vault);

        // revert if too low
        if (ltv < vault.collarOpts.ltv) revert CollarVaultManagerErrors.ExceedsMinLTV(ltv, vault.collarOpts.ltv);

        return vault.assetSpecifiers.cashAmount;
    }

    function openVault(
        AssetSpecifiers calldata assetSpecifiers,
        CollarOpts calldata collarOpts,
        LiquidityOpts calldata liquidityOpts
    ) external override returns (bytes32 vaultUUID) {
        // cache asset addresses
        address cashAsset = assetSpecifiers.cashAsset;
        address collateralAsset = assetSpecifiers.collateralAsset;

        // verify validity of assets
        if (!(ICollarEngine(engine)).isSupportedCashAsset(cashAsset)) revert CashAssetNotSupported(cashAsset);    
        if (!(ICollarEngine(engine)).isSupportedCollateralAsset(collateralAsset)) revert CollateralAssetNotSupported(collateralAsset);  

        // cache amounts
        uint256 cashAmount = assetSpecifiers.cashAmount;
        uint256 collateralAmount = assetSpecifiers.collateralAmount;

        // verify non-zero amounts
        if (cashAmount == 0) revert InvalidCashAmount(cashAmount);
        if (collateralAmount == 0) revert InvalidCollateralAmount(collateralAmount);

        // cache collar opts
        uint256 callStrike = collarOpts.callStrike;
        uint256 putStrike = collarOpts.putStrike;
        uint256 expiry = collarOpts.expiry;
        uint256 ltv = collarOpts.ltv;

        // very expiry / length
        uint256 collarLength = expiry - block.timestamp; // calculate how long the collar will be
        if (!(ICollarEngine(engine)).isValidCollarLength(collarLength)) revert CollarLengthNotSupported(collarLength);

        // verify call & strike
        if (callStrike <= putStrike) revert CollarVaultManagerErrors.InvalidStrikeOpts(callStrike, putStrike);
        if (callStrike < MIN_CALL_STRIKE) revert CollarVaultManagerErrors.InvalidCallStrike(callStrike);
        if (putStrike > MAX_PUT_STRIKE) revert CollarVaultManagerErrors.InvalidPutStrike(putStrike);

        // verify ltv (reminder: denominated in bps)
        if (ltv > MAX_LTV) revert CollarVaultManagerErrors.InvalidLTV(ltv); // ltv must be less than 100%
        if (ltv == 0) revert CollarVaultManagerErrors.InvalidLTV(ltv); // ltv cannot be zero

        // very liquidity pool validity
        address pool = liquidityOpts.liquidityPool;
        if (!ICollarLiquidityPoolManager(ICollarEngine(pool).liquidityPoolManager()).isCollarLiquidityPool(pool) || pool == address(0)) revert InvalidLiquidityPool(pool);

        // verify amounts & ticks are equal; specific ticks and amoutns verified in transfer step
        uint256[] calldata amounts = liquidityOpts.amounts;
        uint24[] calldata ticks =  liquidityOpts.ticks;

        if (amounts.length != ticks.length) revert InvalidLiquidityOpts();

        // attempt to lock the liquidity (to pay out max call strike)
        CollarLiquidityPool(pool).lockLiquidityAtTicks(amounts, ticks);

        // calculate price to swap collateral for
        uint256 collateralPriceInitial = 1;

        // swap entire amount of collateral for cash
        ISwapRouter.ExactInputSingleParams memory swapParams = ISwapRouter.ExactInputSingleParams({
            tokenIn: collateralAsset,
            tokenOut: cashAsset,
            fee: 3000,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: collateralAmount,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        uint256 cashReceived = ISwapRouter(payable(ICollarEngine(engine).DEX())).exactInputSingle(swapParams);

        // mark LTV as withdrawable and the rest as locked
        uint256 maxWithdrawable = (cashReceived * ltv) / 10000;
        uint256 withdrawn = 0;
        uint256 nonWithdrawable = cashReceived - maxWithdrawable;

        // generate UUID and set vault storage
        vaultUUID = keccak256(abi.encodePacked(user, vaultCount));

        vaultsByUUID[vaultUUID] = Vault(
            assetSpecifiers.collateralAmount,
            collateralPriceInitial,
            cashReceived,
            withdrawn,
            maxWithdrawable,
            nonWithdrawable,
            true,
            assetSpecifiers,
            collarOpts,
            liquidityOpts
        );

        vaultUUIDsByIndex[vaultCount] = vaultUUID;
        vaultIndexByUUID[vaultUUID] = vaultCount;

        tokenVaultCount[cashAsset]++;
        tokenTotalBalance[cashAsset] += collateralAmount;

        // increment vault count
        vaultCount++;

        // emit event
        emit CollarVaultManagerEvents.VaultOpened(vaultUUID);

        return vaultUUID;
    }

    function finalizeVault(
        bytes32 vaultUUID
    ) external override
    vaultExists(vaultUUID) returns (int256 net) {
        // get vault info
        Vault storage vault = vaultsByUUID[vaultUUID];

        // cache vault options
        uint256 putStrike = vault.collarOpts.putStrike;
        uint256 callStrike = vault.collarOpts.callStrike;
        uint256 collateralPriceInitial = vault.collateralPriceInitial;
        uint256 collateralAmountInitial = vault.collateralAmountInitial;

        // retrieve final price values
        uint256 collateralPriceFinal = 1;

        // calculate payouts to user and market maker
        (
            uint256 amountToUser, 
            uint256 amountToMarketMaker, 
            uint256 liquidityToMoveToVault,
            uint256 callScaleFactor
        ) = calcPayouts(
            putStrike,
            callStrike,
            collateralPriceInitial,
            collateralAmountInitial,
            collateralPriceFinal
        );

        // unlock liquidity
        address pool = vault.liquidityOpts.liquidityPool;
        uint24[] memory ticks = vault.liquidityOpts.ticks;
        uint256[] memory amounts = vault.liquidityOpts.amounts;

        CollarLiquidityPool(pool).unlockLiquidityAtTicks(amounts, ticks);

        // move liquidity to vault, if applicable
        if (liquidityToMoveToVault > 0 ) {
            // if liquidity to move < total liquidity, we need to scale down the amounts by the proportional difference
            if (callScaleFactor > 0) {
                for (uint256 amountIndex = 0; amountIndex < amounts.length; amountIndex++) {
                    amounts[amountIndex] = (amounts[amountIndex] * callScaleFactor) / 10_000;
                }
            }

            // CollarLiquidityPool(pool).transferLiquidity(amounts, ticks);
        }

        // swap, if necessary
        // for now we just assume the settlement type is cash - no swap required

        // mark vault as finalized
        vault.active = false;

        // emit event
        //emit CollarVaultManagerEvents.VaultClosed(vaultUUID);

        return net;
    }

    function getLTV(bytes32 vaultUUID) public override view returns (uint256) {
        Vault storage _vault = vaultsByUUID[vaultUUID];
        return getLTV(_vault);
    }

    function getLTV(Vault storage _vault) internal override view returns (uint256) {
        uint256 cashValue = _vault.assetSpecifiers.cashAmount;
        uint256 referenceValue = _vault.collateralValueInitial;

        return calcLTV(cashValue, referenceValue);
    }

    function calcLTV(uint256 currentValue, uint256 referenceValue) internal pure returns (uint256) {
        return (currentValue * 10000) / referenceValue;
    }

    function calcPayouts(
        uint256 callStrike,
        uint256 putStrike,
        uint256 collateralPriceInitial,
        uint256 collateralAmountInitial,
        uint256 collateralPriceFinal
    ) internal pure returns (
        uint256 amountToUser,
        uint256 amountToMarketMaker,
        uint256 liquidityToMoveToVault,
        uint256 callScaleFactor
    ) {
        // convert call and put strike bps --> price
        uint256 putStrikePrice = (collateralPriceInitial * putStrike) / 10_000;
        uint256 callStrikePrice = (collateralPriceFinal * callStrike) / 10_000;

        amountToUser = 0;
        amountToMarketMaker = 0;
        liquidityToMoveToVault = 0;

        if (collateralPriceFinal < putStrikePrice) {
            // if price < put strike, user gets only the put strike amount
            amountToUser = (putStrike * collateralPriceInitial * collateralAmountInitial) / 10_000;

            // market maker gets nothing (but keeps their locked liquidity)
        } else if (collateralPriceFinal > callStrikePrice) {
            // if price > call strike, pull all locked liquidity from liquidity pool and give to user
            amountToUser = (callStrike * collateralPriceInitial * collateralAmountInitial) / 10_000;

            // liquidity to move to the vault is all of the liquidity locked for this vault from the market maker
            liquidityToMoveToVault = ((10_000 - callStrike) * collateralPriceInitial * collateralAmountInitial) / 10_000;
        } else { 
            // if put strike < price < call strike, user gets their collateral value, market maker keeps the rest
            amountToUser = collateralPriceFinal * collateralAmountInitial;

            if (collateralPriceFinal > collateralPriceInitial) {    
                liquidityToMoveToVault = (collateralPriceFinal - collateralPriceInitial) * collateralAmountInitial;
                callScaleFactor = ((callStrikePrice - collateralPriceFinal) * 10000) / callStrikePrice;
            } else {
                amountToMarketMaker = (collateralPriceInitial - collateralPriceFinal) * collateralAmountInitial;
            }
        }
    }
}