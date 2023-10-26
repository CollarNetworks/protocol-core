// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

import { ICollarVaultManager } from "../interfaces/IVaultManager.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract CollarVaultManager is ICollarVaultManager {
    modifier vaultExists(bytes32 vaultUUID) {
        if (vaultIndexByUUID[vaultUUID] == 0) revert NonExistentVault(vaultUUID);
        _;
    }

    constructor(address owner) ICollarVaultManager() {
        user = owner;
    }

    function isActive(bytes32 vaultUUID) public override view
    vaultExists(vaultUUID) returns (bool) {
        return vaultsByUUID[vaultUUID].active;
    }

    function isExpired(bytes32 vaultUUID) public override view
    vaultExists(vaultUUID) returns (bool) {
        return vaultsByUUID[vaultUUID].collarOpts.expiry > block.timestamp;
    }

    function getExpiry(bytes32 vaultUUID) public override view
    vaultExists(vaultUUID) returns (uint256) {
        return vaultsByUUID[vaultUUID].collarOpts.expiry;
    }

    function timeRemaining(bytes32 vaultUUID) public override view
    vaultExists(vaultUUID) returns (uint256) {
        uint256 expiry = getExpiry(vaultUUID);

        if (expiry < block.timestamp) return 0;

        return expiry - block.timestamp;
    }

    function depositCash(bytes32 vaultUUID, uint256 amount, address from) external override
    vaultExists(vaultUUID) returns (uint256) {
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
    }

    function withrawCash(bytes32 vaultUUID, uint256 amount, address to) external override
    vaultExists(vaultUUID) returns (uint256) {
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

        // erc20 flashloan callback?
        revert("Todo: figure out flashloan callback");

        // calculate & cache the ltv of the vault; revert if too low
        uint256 ltv = getLTV(vault);
        if (ltv < vault.collarOpts.ltv) revert ExceedsMinLTV(ltv, vault.collarOpts.ltv);
    }

    /// @notice This function should allow the user to sweep any tokens or ETH accidentally sent to the contract
    /// @dev We calculate the excess tokens or ETH via the simple formula: Excess = Balances - ∑(Vault Balances)
    /// @dev Raw ETH is represented via EIP-7528 (0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE)
    function canSweep(address caller, address token, address destination, uint256 amount) public override view returns (bool) {
        if (caller != user) revert NotOwner(caller);

        // If the token is not supported by any vaults, we can automatically approve the sweep
        // We leave the edge case of "not enough of the token" to the user to handle
        if (tokenVaultCount[token] == 0) return true;

        // We don't care about the destination; we even allow the zero address in case a burn is desired
        // Calculate how much extra of the token we have, if any
        uint256 excess = IERC20(token).balanceOf(address(this)) - tokenTotalBalance[token];

        return amount <= excess;
    }

    function openVault(
        AssetSpecifiers calldata assetSpecifiers,
        CollarOpts calldata collarOpts,
        LiquidityOpts calldata liquidityOpts
    ) external override returns (bytes32) {
        // verify asset specifiers

        // very collar opts

        // very liquidity opts

        // tranfer collateral

        // swap, if necessary

        // lock liquidity

        // set storage struct

        revert("Not implemented");
    }

    function finalizeVault(
        bytes32 vaultUUID
    ) external override
    vaultExists(vaultUUID) returns (int256) {
        // retrieve final price values

        // calculate payouts

        // unlock liquidity

        // swap, if necessary

        // transfer user payout to this contract, if any

        // mark vault as finalized

        // set storage struct

        revert("Not implemented");
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
}