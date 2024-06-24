// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity 0.8.21;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IV3SwapRouter } from "@uniswap/swap-router-contracts/contracts/interfaces/IV3SwapRouter.sol";
// internal imports
import { LiquidityPositionNFT } from "./LiquidityPositionNFT.sol";
import { BaseGovernedNFT } from "./base/BaseGovernedNFT.sol";
import { CollarEngine } from "./implementations/CollarEngine.sol";
import { TickCalculations } from "./libs/TickCalculations.sol";

contract BorrowPositionNFT is BaseGovernedNFT {
    using SafeERC20 for IERC20;

    uint24 internal constant FEE_TIER_30_BIPS = 3000;
    uint internal constant BIPS_BASE = 10_000;

    uint32 public constant TWAP_LENGTH = 15 minutes;
    uint public constant MAX_SWAP_TWAP_DEVIATION_BIPS = 100;

    // ----- IMMUTABLES ----- //
    CollarEngine public immutable engine;
    IERC20 public immutable cashAsset;
    IERC20 public immutable collateralAsset;

    // ----- STATE VARIABLES ----- //
    // TODO: Consider trimming down this struct, since some of the fields aren't needed on-chain,
    //      and are stored for FE / usability since the assumption is that this is used on L2.
    struct BorrowPosition {
        LiquidityPositionNFT providerContract;
        uint providerPositionId;
        uint openedAt;
        uint expiration;
        uint initialPrice;
        uint putStrikePrice;
        uint callStrikePrice;
        uint collateralAmount;
        uint loanAmount;
        uint putLockedCash;
        uint callLockedCash;
    }
    // terms

    mapping(uint positionId => BorrowPosition) public positions;

    // ----- CONSTRUCTOR ----- //

    constructor(
        address initialOwner,
        CollarEngine _engine,
        IERC20 _cashAsset,
        IERC20 _collateralAsset,
        string memory _name,
        string memory _symbol
    )
        BaseGovernedNFT(initialOwner, _name, _symbol)
    {
        engine = _engine;
        cashAsset = _cashAsset;
        collateralAsset = _collateralAsset;
        // check params are supported
        validateConfig();
    }

    /// @dev used by openPosition, and can be used externally to check this is available
    function validateConfig() public view {
        require(engine.isSupportedCashAsset(address(cashAsset)), "unsupported asset");
        require(engine.isSupportedCollateralAsset(address(collateralAsset)), "unsupported asset");
    }

    // ----- VIEW FUNCTIONS ----- //

    // ----- STATE CHANGING FUNCTIONS ----- //
    function openPosition(
        uint collateralAmount,
        uint minCashAmount, // slippage control
        LiquidityPositionNFT providerContract, // @dev implies ltv & put deviation, duration
        uint offerId // @dev imply specific offer with provider and strike price
            // TODO: optional user validation struct for ltv, expiry, put, call deviation
    )
        external
        returns (uint borrowPositionId, uint providerPositionId, BorrowPosition memory borrowPosition)
    {
        _openPositionValidations(providerContract);

        // get TWAP price
        uint twapPrice = _getTWAPPrice(block.timestamp);

        // transfer and swap collateral first to handle reentrancy
        // TODO: double-check this actually handles it, or add a reentrancy guard
        uint cashFromSwap = _pullAndSwap(msg.sender, collateralAmount, minCashAmount);

        // @dev note that TWAP price is used for payout decision later, and swap price should
        // only affect the "pot sizing" (so does not affect the provider, only the borrower)
        _checkSwapPrice(twapPrice, cashFromSwap, collateralAmount);

        (borrowPosition, providerPositionId) =
            _openPositionInternal(twapPrice, collateralAmount, cashFromSwap, providerContract, offerId);

        borrowPositionId = nextTokenId++;
        // store position data
        positions[borrowPositionId] = borrowPosition;
        // mint the NFT to the sender
        // @dev does not use _safeMint to avoid reentrancy
        _mint(msg.sender, borrowPositionId);

        // transfer the full loan amount on open
        cashAsset.safeTransfer(msg.sender, borrowPosition.loanAmount);
    }

    // ----- INTERNAL FUNCTIONS ----- //

    function _openPositionInternal(
        uint twapPrice,
        uint collateralAmount,
        uint cashFromSwap,
        LiquidityPositionNFT providerContract,
        uint offerId
    )
        internal
        returns (BorrowPosition memory borrowPosition, uint providerPositionId)
    {
        uint loanAmount = cashFromSwap * providerContract.ltv() / BIPS_BASE;
        // LTV === put strike price (explicitly assigned here for clarity)
        uint putStrikeDeviation = providerContract.ltv();

        // open the provider position with duration and callLockedCash locked liquidity (reverts if can't)
        // and sends the provider NFT to the provider
        uint callStrikeDeviation = providerContract.getOffer(offerId).strikeDeviation;
        uint callLockedCash = (callStrikeDeviation - BIPS_BASE) * cashFromSwap / BIPS_BASE;
        (providerPositionId,) = providerContract.takeLiquidityOffer(offerId, callLockedCash);

        borrowPosition = BorrowPosition({
            providerContract: providerContract,
            providerPositionId: providerPositionId,
            openedAt: block.timestamp,
            expiration: providerContract.getPosition(providerPositionId).expiration,
            initialPrice: twapPrice,
            putStrikePrice: twapPrice * putStrikeDeviation / BIPS_BASE,
            callStrikePrice: twapPrice * callStrikeDeviation / BIPS_BASE,
            collateralAmount: collateralAmount,
            loanAmount: loanAmount,
            putLockedCash: cashFromSwap - loanAmount, // this assumes LTV === put strike price
            callLockedCash: callLockedCash
        });
    }

    function _openPositionValidations(LiquidityPositionNFT providerContract) internal view {
        validateConfig();

        // check self (provider will check too)
        require(engine.isBorrowNFT(address(this)), "unsupported borrow contract");

        // check provider
        require(engine.isProviderNFT(address(providerContract)), "unsupported provider contract");
        // check assets match
        require(providerContract.collateralAsset() == collateralAsset, "asset mismatch");
        require(providerContract.cashAsset() == cashAsset, "asset mismatch");

        // checking LTV and duration (from provider contract) is redundant since provider contract
        // is trusted by user (passed in input), and trusted by engine (was checked vs. engine above)
    }

    function _getTWAPPrice(uint twapEndTime) internal view returns (uint price) {
        return engine.getHistoricalAssetPriceViaTWAP(
            address(collateralAsset), address(cashAsset), uint32(twapEndTime), TWAP_LENGTH
        );
    }

    /// TODO: establish if this is needed or not, since the swap price is only used for "pot sizing",
    ///     but not for pot division on expiry (initialPrice is twap price).
    ///     still makes sense as a precaution, as long as the deviation is not too restrictive.
    function _checkSwapPrice(uint twapPrice, uint cashFromSwap, uint collateralAmount) internal view {
        // TODO: sort out the mess with using or not using exact amounts / BASE_TOKEN_AMOUNT
        uint swapPrice = cashFromSwap * engine.BASE_TOKEN_AMOUNT() / collateralAmount;
        uint diff = swapPrice > twapPrice ? swapPrice - twapPrice : twapPrice - swapPrice;
        uint deviation = diff * BIPS_BASE / twapPrice;
        require(deviation <= MAX_SWAP_TWAP_DEVIATION_BIPS, "swap and twap price too different");
    }

    function _pullAndSwap(
        address sender,
        uint amountIn,
        uint minAmountOut
    )
        internal
        returns (uint amountReceived)
    {
        collateralAsset.safeTransferFrom(sender, address(this), amountIn);

        // approve the dex router so we can swap the collateral to cash
        collateralAsset.forceApprove(engine.dexRouter(), amountIn);

        // build the swap transaction
        IV3SwapRouter.ExactInputSingleParams memory swapParams = IV3SwapRouter.ExactInputSingleParams({
            tokenIn: address(collateralAsset),
            tokenOut: address(cashAsset),
            fee: FEE_TIER_30_BIPS,
            recipient: address(this),
            amountIn: amountIn,
            amountOutMinimum: minAmountOut,
            sqrtPriceLimitX96: 0
        });

        uint balanceBefore = cashAsset.balanceOf(address(this));
        IV3SwapRouter(payable(engine.dexRouter())).exactInputSingle(swapParams);
        // Calculate the actual amount of cash received
        amountReceived = cashAsset.balanceOf(address(this)) - balanceBefore;
        // revert if minimum not met
        require(amountReceived >= minAmountOut, "slippage exceeded");
    }

    //    function closeVault(bytes32 uuid) external override {
    //        require(vaultsByUUID[uuid].openedAt != 0, "invalid vault");
    //
    //        // ensure vault is active (not finalized) and finalizable (past length)
    //        require(vaultsByUUID[uuid].active, "not active");
    //        require(block.timestamp >= vaultsByUUID[uuid].expiresAt, "not finalizable");
    //
    //        // cache vault storage pointer
    //        Vault storage vault = vaultsByUUID[uuid];
    //
    //        // grab all price info
    //        uint startingPrice = vault.initialCollateralPrice;
    //        uint putStrikePrice = vault.putStrikePrice;
    //        uint callStrikePrice = vault.callStrikePrice;
    //
    //        uint finalPrice = _getTWAPPrice(vault.expiresAt);
    //
    //        require(finalPrice != 0, "invalid price");
    //
    //        // vault can finalze in 4 possible states, depending on where the final price (P_1) ends up
    //        // relative to the put strike (PUT), the call strike (CAL), and the starting price (P_0)
    //        //
    //        // (CASE 1) final price < put strike
    //        //  - P_1 --- PUT --- P_0 --- CAL
    //        //  - locked vault cash is rewarded to the liquidity provider
    //        //  - locked pool liquidity is entirely returned to the liquidity provider
    //        //
    //        // (CASE 2) final price > call strike
    //        //  - PUT --- P_0 --- CAL --- P_1
    //        //  - locked vault cash is given to the user to cover collateral appreciation
    //        //  - locked pool liquidity is entirely used to cover collateral appreciation
    //        //
    //        // (CASE 3) put strike < final price < starting price
    //        //  - PUT --- P_1 --- P_0 --- CAL
    //        //  - locked vault cash is partially given to the user to cover some collateral appreciation
    //        //  - locked pool liquidity is entirely returned to the liquidity provider
    //        //
    //        // (CASE 4) call strike > final price > starting price
    //        //  - PUT --- P_0 --- P_1 --- CAL
    //        //  - locked vault cash is given to the user to cover collateral appreciation
    //        //  - locked pool liquidity is partially used to cover some collateral appreciation
    //
    //        uint cashNeededFromPool = 0;
    //        uint cashToSendToPool = 0;
    //
    //        // CASE 1 - all vault cash to liquidity pool
    //        if (finalPrice <= putStrikePrice) {
    //            cashToSendToPool = vault.lockedVaultCash;
    //
    //            console.log("CollarVaultManager::closeVault - CASE 1 ALL VAULT CASH TO LIQUIDITY POOL");
    //            console.log("CollarVaultManager::closeVault - cashToSendToPool: ", cashToSendToPool);
    //
    //            // CASE 2 - all vault cash to user, all locked pool cash to user
    //        } else if (finalPrice >= callStrikePrice) {
    //            cashNeededFromPool = vault.lockedPoolCash;
    //
    //            console.log(
    //                "CollarVaultManager::closeVault - CASE 2 ALL VAULT CASH TO USER, ALL LOCKED POOL CASH TO
    // USER"
    //            );
    //            console.log("CollarVaultManager::closeVault - cashNeededFromPool: ", cashNeededFromPool);
    //
    //            // CASE 3 - all vault cash to user
    //        } else if (finalPrice == startingPrice) {
    //            // no need to update any vars here
    //
    //            console.log("CollarVaultManager::closeVault - CASE 3 ALL VAULT CASH TO USER");
    //
    //            // CASE 4 - proportional vault cash to user
    //        } else if (putStrikePrice < finalPrice && finalPrice < startingPrice) {
    //            uint vaultCashToPool = (
    //                (vault.lockedVaultCash * (startingPrice - finalPrice) * 1e32)
    //                / (startingPrice - putStrikePrice)
    //            ) / 1e32;
    //
    //            cashToSendToPool = vaultCashToPool;
    //
    //            console.log("CollarVaultManager::closeVault - CASE 4 PROPORTIONAL VAULT CASH TO USER");
    //            console.log("CollarVaultManager::closeVault - cashToSendToPool: ", cashToSendToPool);
    //
    //            // CASE 5 - all vault cash to user, proportional locked pool cash to user
    //        } else if (callStrikePrice > finalPrice && finalPrice > startingPrice) {
    //            uint poolCashToUser = (
    //                (vault.lockedPoolCash * (finalPrice - startingPrice) * 1e32)
    //                / (callStrikePrice - startingPrice)
    //            ) / 1e32;
    //
    //            cashNeededFromPool = poolCashToUser;
    //
    //            console.log(
    //                "CollarVaultManager::closeVault - CASE 5 ALL VAULT CASH TO USER, PROPORTIONAL LOCKED
    // POOL CASH TO USER"
    //            );
    //            console.log("CollarVaultManager::closeVault - cashNeededFromPool: ", cashNeededFromPool);
    //
    //            // ???
    //        } else {
    //            revert();
    //        }
    //        // mark vault as finalized
    //        vault.active = false;
    //
    //        // sanity check
    //        assert(cashNeededFromPool == 0 || cashToSendToPool == 0);
    //
    //        int poolProfit = cashToSendToPool > 0 ? int(cashToSendToPool) : -int(cashNeededFromPool);
    //
    //        if (cashToSendToPool > 0) {
    //            vault.lockedVaultCash -= cashToSendToPool;
    //            IERC20(vault.cashAsset).forceApprove(vault.liquidityPool, cashToSendToPool);
    //        }
    //
    //        CollarPool(vault.liquidityPool).finalizePosition(uuid, poolProfit);
    //
    //        // set total redeem value for vault tokens to locked vault cash + cash pulled from pool
    //        // also null out the locked vault cash
    //        vaultTokenCashSupply[uuid] = vault.lockedVaultCash + cashNeededFromPool;
    //        vault.lockedVaultCash = 0;
    //
    //        emit VaultClosed(msg.sender, address(this), uuid);
    //    }
    //
    //    function redeem(bytes32 uuid, uint amount) external override {
    //        require(vaultsByUUID[uuid].openedAt != 0, "invalid vault");
    //        require(!vaultsByUUID[uuid].active, "vault not finalized");
    //
    //        // calculate cash redeem value
    //        uint redeemValue = previewRedeem(uuid, amount);
    //
    //        emit Redemption(msg.sender, uuid, amount, redeemValue);
    //
    //        // redeem to user & burn tokens
    //        _burn(msg.sender, uint(uuid), amount);
    //        IERC20(vaultsByUUID[uuid].cashAsset).safeTransfer(msg.sender, redeemValue);
    //    }
}
