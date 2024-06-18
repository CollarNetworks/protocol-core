// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IV3SwapRouter } from "@uniswap/v3-swap-contracts/interfaces/IV3SwapRouter.sol";
import { ERC6909TokenSupply } from "@erc6909/ERC6909TokenSupply.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
// internal imports
import { ICollarVaultManager } from "../interfaces/ICollarVaultManager.sol";
import { CollarPool } from "./CollarPool.sol";
import { CollarEngine } from "../implementations/CollarEngine.sol";
import { TickCalculations } from "../libs/TickCalculations.sol";

import "forge-std/console.sol";

contract CollarVaultManager is Ownable, ERC6909TokenSupply, ICollarVaultManager {
    using SafeERC20 for IERC20;
    // ----- IMMUTABLES ----- //

    address public immutable user;
    address public immutable engine;

    // ----- SO THAT THE ABI PICKS UP THE VAULT STRUCT ----- //
    event VaultForABI(Vault vault);

    // ----- STATE VARIABLES ----- //

    uint public vaultCount;

    mapping(bytes32 uuid => Vault vault) internal vaultsByUUID;
    mapping(uint vaultNonce => bytes32 UUID) public vaultsByNonce;
    mapping(bytes32 => uint) public vaultTokenCashSupply;

    // ----- CONSTRUCTOR ----- //

    constructor(address _engine, address _owner) Ownable(_owner) {
        user = _owner;
        engine = _engine;
        vaultCount = 0;
    }

    // ----- VIEW FUNCTIONS ----- //

    function isVaultExpired(bytes32 uuid) external view override returns (bool) {
        return vaultsByUUID[uuid].expiresAt < block.timestamp;
    }

    function vaultInfo(bytes32 uuid) external view override returns (bytes memory) {
        if (vaultsByUUID[uuid].openedAt == 0) {
            revert InvalidVault();
        }

        return abi.encode(vaultsByUUID[uuid]);
    }

    function vaultInfoByNonce(uint vaultNonce) external view override returns (bytes memory) {
        bytes32 uuid = vaultsByNonce[vaultNonce];
        if (vaultsByUUID[uuid].openedAt == 0) {
            revert InvalidVault();
        }

        return abi.encode(vaultsByUUID[uuid]);
    }

    function getVaultUUID(uint vaultNonce) external view override returns (bytes32 uuid) {
        return vaultsByNonce[vaultNonce];
    }

    function previewRedeem(bytes32 uuid, uint amount) public view override returns (uint cashReceived) {
        if (amount == 0) revert AmountCannotBeZero();
        if (vaultsByUUID[uuid].openedAt == 0) revert InvalidVault();

        bool finalized = !vaultsByUUID[uuid].active;

        if (finalized) {
            // if finalized, calculate final redeem value
            // grab collateral asset value @ exact vault expiration time

            uint vaultCash = vaultTokenCashSupply[uuid];
            uint tokenSupply = totalSupply[uint(uuid)];

            if (vaultCash == 0) {
                return 0;
            }

            if (tokenSupply < amount) {
                revert InvalidAmount();
            }

            cashReceived = (vaultCash * amount) / tokenSupply;
        } else {
            // calculate redeem value based on current price of asset
            // uint256 currentCollateralPrice =
            // CollarEngine(engine).getCurrentAssetPrice(vaultsByUUID[uuid].collateralAsset);

            // this is very complicated to implement - basically have to recreate
            // the entire closeVault function, but without changing state

            revert VaultNotFinalized();
        }
    }

    // ----- STATE CHANGING FUNCTIONS ----- //

    function openVault(
        AssetSpecifiers calldata assetData, // addresses & amounts of collateral & cash assets
        CollarOpts calldata collarOpts, // length & ltv
        LiquidityOpts calldata liquidityOpts, // pool address, callstrike & amount to lock there, putstrike
        bool withdrawLoan
    ) public override returns (bytes32 uuid) {
        // only user is allowed to open vaults
        if (msg.sender != user) {
            revert NotCollarVaultOwner();
        }

        // validate parameter data
        _validateAssetData(assetData);
        _validateCollarOpts(collarOpts);
        _validateLiquidityOpts(liquidityOpts);

        // generate vault (and token) nonce
        uuid = keccak256(abi.encodePacked(user, vaultCount));

        vaultsByNonce[vaultCount] = keccak256(abi.encodePacked(user, vaultCount));

        // increment vault
        vaultCount++;

        // set Basic Vault Info
        vaultsByUUID[uuid].active = true;
        vaultsByUUID[uuid].openedAt = uint32(block.timestamp);
        vaultsByUUID[uuid].expiresAt = uint32(block.timestamp + collarOpts.duration);
        vaultsByUUID[uuid].duration = uint32(collarOpts.duration);
        vaultsByUUID[uuid].ltv = collarOpts.ltv;

        // set Asset Specific Info
        vaultsByUUID[uuid].collateralAsset = assetData.collateralAsset;
        vaultsByUUID[uuid].collateralAmount = assetData.collateralAmount;
        vaultsByUUID[uuid].cashAsset = assetData.cashAsset;

        // transfer collateral from user to vault
        IERC20(assetData.collateralAsset).safeTransferFrom(user, address(this), assetData.collateralAmount);

        // swap collateral for cash & record cash amount
        uint cashReceivedFromSwap = _swap(assetData);
        vaultsByUUID[uuid].cashAmount = cashReceivedFromSwap;

        // calculate exactly how much cash to lock from the liquidity pool
        // this is equal to (callstrikePercent - 100%) * totalCashReceivedFromSwap
        // first, grab the call strike percent from the call strike tick supplied
        uint tickScaleFactor = CollarPool(liquidityOpts.liquidityPool).tickScaleFactor();
        uint callStrikePercentBps = TickCalculations.tickToBps(liquidityOpts.callStrikeTick, tickScaleFactor);
        uint poolLiquidityToLock =
            ((callStrikePercentBps - 10_000) * cashReceivedFromSwap * 1e18) / (10_000) / 1e18;

        // calculate the initial collateral price from the swap execution fill
        // this is stored as "unit price times 1e18"
        uint initialCollateralPrice = (cashReceivedFromSwap * 1e18) / (assetData.collateralAmount);

        // set Liquidity Pool Stuff
        vaultsByUUID[uuid].liquidityPool = liquidityOpts.liquidityPool;
        vaultsByUUID[uuid].lockedPoolCash = poolLiquidityToLock;
        vaultsByUUID[uuid].initialCollateralPrice = initialCollateralPrice;
        vaultsByUUID[uuid].putStrikePrice =
            TickCalculations.tickToPrice(liquidityOpts.putStrikeTick, tickScaleFactor, initialCollateralPrice);
        vaultsByUUID[uuid].callStrikePrice = TickCalculations.tickToPrice(
            liquidityOpts.callStrikeTick, tickScaleFactor, initialCollateralPrice
        );
        vaultsByUUID[uuid].putStrikeTick = liquidityOpts.putStrikeTick;
        vaultsByUUID[uuid].callStrikeTick = liquidityOpts.callStrikeTick;

        // mint vault tokens (equal to the amount of cash received from swap)
        _mint(user, uint(uuid), cashReceivedFromSwap);

        // mint liquidity pool tokens
        CollarPool(liquidityOpts.liquidityPool).openPosition(
            uuid, liquidityOpts.callStrikeTick, poolLiquidityToLock, vaultsByUUID[uuid].expiresAt
        );

        // set vault specific stuff
        vaultsByUUID[uuid].loanBalance = (collarOpts.ltv * cashReceivedFromSwap) / 10_000;
        vaultsByUUID[uuid].lockedVaultCash = ((10_000 - collarOpts.ltv) * cashReceivedFromSwap) / 10_000;

        emit VaultOpened(msg.sender, address(this), uuid);

        // approve the pool
        IERC20(assetData.cashAsset).forceApprove(
            liquidityOpts.liquidityPool, vaultsByUUID[uuid].lockedVaultCash
        );

        if (withdrawLoan) {
            withdraw(uuid, vaultsByUUID[uuid].loanBalance);
        }
    }

    function closeVault(bytes32 uuid) external override {
        // ensure vault exists
        if (vaultsByUUID[uuid].openedAt == 0) {
            revert InvalidVault();
        }

        // ensure vault is active (not finalized) and finalizable (past length)
        if (!vaultsByUUID[uuid].active) {
            revert VaultNotActive();
        }

        if (vaultsByUUID[uuid].expiresAt > block.timestamp) {
            revert VaultNotFinalizable();
        }

        // cache vault storage pointer
        Vault storage vault = vaultsByUUID[uuid];

        // grab all price info
        uint startingPrice = vault.initialCollateralPrice;
        uint putStrikePrice = vault.putStrikePrice;
        uint callStrikePrice = vault.callStrikePrice;

        uint finalPrice = CollarEngine(engine).getHistoricalAssetPriceViaTWAP(
            vault.collateralAsset, vault.cashAsset, vault.expiresAt, 15 minutes
        );

        if (finalPrice == 0) revert InvalidAssetPrice();

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

        uint cashNeededFromPool = 0;
        uint cashToSendToPool = 0;

        // CASE 1 - all vault cash to liquidity pool
        if (finalPrice <= putStrikePrice) {
            cashToSendToPool = vault.lockedVaultCash;

            console.log("CollarVaultManager::closeVault - CASE 1 ALL VAULT CASH TO LIQUIDITY POOL");
            console.log("CollarVaultManager::closeVault - cashToSendToPool: ", cashToSendToPool);

            // CASE 2 - all vault cash to user, all locked pool cash to user
        } else if (finalPrice >= callStrikePrice) {
            cashNeededFromPool = vault.lockedPoolCash;

            console.log(
                "CollarVaultManager::closeVault - CASE 2 ALL VAULT CASH TO USER, ALL LOCKED POOL CASH TO USER"
            );
            console.log("CollarVaultManager::closeVault - cashNeededFromPool: ", cashNeededFromPool);

            // CASE 3 - all vault cash to user
        } else if (finalPrice == startingPrice) {
            // no need to update any vars here

            console.log("CollarVaultManager::closeVault - CASE 3 ALL VAULT CASH TO USER");

            // CASE 4 - proportional vault cash to user
        } else if (putStrikePrice < finalPrice && finalPrice < startingPrice) {
            uint vaultCashToPool = (
                (vault.lockedVaultCash * (startingPrice - finalPrice) * 1e32)
                    / (startingPrice - putStrikePrice)
            ) / 1e32;

            cashToSendToPool = vaultCashToPool;

            console.log("CollarVaultManager::closeVault - CASE 4 PROPORTIONAL VAULT CASH TO USER");
            console.log("CollarVaultManager::closeVault - cashToSendToPool: ", cashToSendToPool);

            // CASE 5 - all vault cash to user, proportional locked pool cash to user
        } else if (callStrikePrice > finalPrice && finalPrice > startingPrice) {
            uint poolCashToUser = (
                (vault.lockedPoolCash * (finalPrice - startingPrice) * 1e32)
                    / (callStrikePrice - startingPrice)
            ) / 1e32;

            cashNeededFromPool = poolCashToUser;

            console.log(
                "CollarVaultManager::closeVault - CASE 5 ALL VAULT CASH TO USER, PROPORTIONAL LOCKED POOL CASH TO USER"
            );
            console.log("CollarVaultManager::closeVault - cashNeededFromPool: ", cashNeededFromPool);

            // ???
        } else {
            revert InvalidState();
        }

        // sanity check
        if (cashNeededFromPool > 0 && cashToSendToPool > 0) {
            revert InvalidState();
        }

        int poolProfit = cashToSendToPool > 0 ? int(cashToSendToPool) : -int(cashNeededFromPool);

        if (cashToSendToPool > 0) {
            vault.lockedVaultCash -= cashToSendToPool;
            IERC20(vault.cashAsset).forceApprove(vault.liquidityPool, cashToSendToPool);
        }

        CollarPool(vault.liquidityPool).finalizePosition(uuid, address(this), poolProfit);

        // set total redeem value for vault tokens to locked vault cash + cash pulled from pool
        // also null out the locked vault cash
        vaultTokenCashSupply[uuid] = vault.lockedVaultCash + cashNeededFromPool;
        vault.lockedVaultCash = 0;

        // mark vault as finalized
        vault.active = false;

        emit VaultClosed(msg.sender, address(this), uuid);
    }

    function redeem(bytes32 uuid, uint amount) external override {
        // ensure vault exists
        if (vaultsByUUID[uuid].openedAt == 0) {
            revert InvalidVault();
        }

        // ensure vault is finalized
        if (vaultsByUUID[uuid].active) {
            revert VaultNotFinalized();
        }

        // calculate cash redeem value
        uint redeemValue = previewRedeem(uuid, amount);

        emit Redemption(msg.sender, uuid, amount, redeemValue);

        // redeem to user & burn tokens
        _burn(msg.sender, uint(uuid), amount);
        IERC20(vaultsByUUID[uuid].cashAsset).safeTransfer(msg.sender, redeemValue);
    }

    function withdraw(bytes32 uuid, uint amount) public override {
        if (msg.sender != user) revert NotCollarVaultOwner();
        if (vaultsByUUID[uuid].openedAt == 0) revert InvalidVault();

        uint loanBalance = vaultsByUUID[uuid].loanBalance;

        // withdraw from user's loan balance
        if (amount > loanBalance) {
            revert InvalidAmount();
        } else {
            vaultsByUUID[uuid].loanBalance -= amount;
            IERC20(vaultsByUUID[uuid].cashAsset).safeTransfer(msg.sender, amount);
        }

        emit Withdrawal(user, address(this), uuid, amount, vaultsByUUID[uuid].loanBalance);
    }

    // ----- INTERNAL FUNCTIONS ----- //

    function _validateAssetData(AssetSpecifiers calldata assetData) internal view {
        // verify cash & collateral assets against engine for validity
        if (!CollarEngine(engine).isSupportedCashAsset(assetData.cashAsset)) {
            revert InvalidCashAsset();
        }

        if (!CollarEngine(engine).isSupportedCollateralAsset(assetData.collateralAsset)) {
            revert InvalidCollateralAsset();
        }

        // verify cash & collateral amounts are > 0
        if (assetData.cashAmount == 0) {
            revert InvalidCashAmount();
        }

        if (assetData.collateralAmount == 0) {
            revert InvalidCollateralAmount();
        }
    }

    function _validateCollarOpts(CollarOpts calldata collarOpts) internal view {
        // verify length is valid per engine
        if (!CollarEngine(engine).isValidCollarDuration(collarOpts.duration)) {
            revert InvalidDuration();
        }

        // verify ltv is valid
        if (!CollarEngine(engine).isValidLTV(collarOpts.ltv)) {
            revert InvalidLTV();
        }
    }

    function _validateLiquidityOpts(LiquidityOpts calldata liquidityOpts) internal view {
        // verify liquidity pool is a valid collar liquidity pool
        if (!CollarEngine(engine).isSupportedLiquidityPool(liquidityOpts.liquidityPool)) {
            revert InvalidLiquidityPool();
        }

        // verify the put strike tick matches the put strike tick of the pool
        if (
            CollarPool(liquidityOpts.liquidityPool).ltv()
                != (liquidityOpts.putStrikeTick * CollarPool(liquidityOpts.liquidityPool).tickScaleFactor())
        ) {
            revert InvalidPutStrike();
        }

        // verify the call strike tick is > 100%
        if (
            TickCalculations.tickToBps(
                liquidityOpts.callStrikeTick, CollarPool(liquidityOpts.liquidityPool).tickScaleFactor()
            ) < 10_000
        ) {
            revert InvalidCallStrike();
        }
    }

    function _swap(AssetSpecifiers calldata assets) internal returns (uint cashReceived) {
        // approve the dex router so we can swap the collateral to cash
        IERC20(assets.collateralAsset).forceApprove(CollarEngine(engine).dexRouter(), assets.collateralAmount);

        // build the swap transaction
        IV3SwapRouter.ExactInputSingleParams memory swapParams = IV3SwapRouter.ExactInputSingleParams({
            tokenIn: assets.collateralAsset,
            tokenOut: assets.cashAsset,
            fee: 3000,
            recipient: address(this),
            amountIn: assets.collateralAmount,
            amountOutMinimum: assets.cashAmount,
            sqrtPriceLimitX96: 0
        });

        // cache the amount of cash received
        cashReceived = IV3SwapRouter(payable(CollarEngine(engine).dexRouter())).exactInputSingle(swapParams);
        // revert if minimum not met
        if (cashReceived < assets.cashAmount) {
            revert TradeNotViable();
        }
    }

    function _mint(address account, uint id, uint amount) internal {
        balanceOf[account][id] += amount;
        totalSupply[id] += amount;
    }

    function _burn(address account, uint id, uint amount) internal {
        balanceOf[account][id] -= amount;
        totalSupply[id] -= amount;
    }
}
