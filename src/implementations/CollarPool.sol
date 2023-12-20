// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

import { ICollarPool } from "../interfaces/ICollarPool.sol";
import { Constants, CollarVaultState } from "../libs/CollarLibs.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";


contract CollarPool is ICollarPool, Constants {

    constructor(address _engine, uint256 _tickScaleFactor, address _cashAsset) ICollarPool(_engine, _tickScaleFactor, _cashAsset) {}

    function getSlot(
        uint256 slotIndex
    ) external override view returns (SlotState memory) {
        return slots[slotIndex];
    }

    function addLiquidity(
        uint256 slotIndex,
        uint256 amount
    ) public virtual override {
        SlotState storage slot = slots[slotIndex];

        if (slot.providers.contains(msg.sender) || !isSlotFull(slotIndex)) {
            _allocate(slotID, msg.sender, amount);
        } else {
            address smallestProvider = getSmallestProvider(slotIndex);
            uint256 smallestAmount = slot.providers.get(smallestProvider);

            if (smallestAmount > amount) revert("Amount not high enough to kick out anyone from full slot.");
            
            _reAllocate(smallestProvider, slotIndex, UNALLOCATED_SLOT, smallestAmount);
            _allocate(slotIndex, msg.sender, amount);
        }

        // transfer collateral from provider to pool
        IERC20(cashAsset).transferFrom(msg.sender, address(this), amount);
    }

    function removeLiquidity(
        uint256 slot,
        uint256 amount
    ) public virtual override {
        // verify sender has enough liquidity in slot
        if (providerLiquidityBySlot[msg.sender][slot] < amount) {
            revert("Not enough liquidity");
        }
        
        _reAllocate(msg.sender, slot, UNALLOCATED_SLOT, amount);
    }

    function reallocateLiquidity(
        uint256 sourceSlotIndex,
        uint256 destinationSlotIndex,
        uint256 amount
    ) external virtual override {
        removeLiquidity(sourceSlotIndex, amount);
        addLiquidity(destinationSlotIndex, amount);
    }

    function mint(bytes32 uuid, uint256 slot, uint256 amount) external override {
        // ensure this is the first/only mint
        if (hasMinted[uuid]) {
            revert("Already minted");
        }

        // ensure this is a valid vault calling us - it must call through the engine
        if (msg.sender != engine) {
            revert("Only engine can mint");
        }

        // ensure there is enough liquidity available
        if (slotLiquidity[slot] < amount) {
            revert("Not enough liquidity");
        }

        // allocate evenly from all providers
        address[] memory providers = slots[slot].providers;

        uint256[] memory amounts = new uint256[](providers.length);

        uint256 totalSlotLiquidity = slotLiquidity[slot];

        for (uint256 i = 0; i < providers.length; i++) {
            // calculate how much to pull from provider based off of their proportional ownership of liquidity in this slot
            address thisProvider = providers[i];
            uint256 providerLiquidity = providerLiquidityBySlot[thisProvider][slot];

            // this provider's liquidity to pull = 
            // (provider's proportional ownership of slot liquidity) * (total amount needed)
            // (providerLiquidity / totalSlotLiquidity) * amount
            // (providerLiquidity * amount) / totalSlotLiquidity
            uint256 amountFromThisProvider = (providerLiquidity * amount) / totalSlotLiquidity;
            amounts[i] = amountFromThisProvider;
        }

        // mint tokens for this new vault to all providers in slot & decrement their liquidity amounts
        for (uint256 i = 0; i < providers.length; i++) {
            providerLiquidityBySlot[providers[i]][slot] -= amounts[i];
            _mint(providers[i], uint256(uuid), amounts[i]);
        }

        // decrement available liquidity in slot
        slotLiquidity[slot] -= amount;

        // mark this vault as having minted so that it can't be double-called
        hasMinted[uuid] = true;
    }

    function redeem(bytes32 uuid, uint256 amount) external override {
        // ensure vault is finalized
        if (!vaultStatus[uuid]) {
            revert("Vault not finalized");
        }

        // calculate cash redeem value
        uint256 redeemValue = previewRedeem(uuid, amount);

        // redeem to user & burn tokens
        _burn(msg.sender, uint256(uuid), amount);
        IERC20(cashAsset).transfer(msg.sender, redeemValue);
    }

    function previewRedeem(bytes32 uuid, uint256 amount) public override view returns (uint256 cashReceived) {
        bool finalized = !vaultStatus[uuid];

        if (finalized) {
            // if finalized, calculate final redeem value
            // grab collateral asset value @ exact vault expiration time

            uint256 _totalTokenCashSupply = totalCashSupplyForToken[uuid];
            uint256 _totalTokenSupply = totalTokenSupply[uint256(uuid)];

            cashReceived = (_totalTokenCashSupply * amount) / _totalTokenSupply;

        } else {
            revert("Not implemented");
        }
    }

    function vaultPullLiquidity(
        bytes32 uuid,
        address receiver,
        uint256 amount
    ) external override {
        // verify caller via engine
        if (msg.sender != engine) {
            revert("Only engine can pull liquidity");
        } 

        // update the amount of total cash tokens for that vault
        totalCashSupplyForToken[uuid] -= amount;

        // transfer liquidity
        IERC20(cashAsset).transferFrom(address(this), receiver, amount);
    }

    function vaultPushLiquidity(
        bytes32 uuid,
        address sender,
        uint256 amount
    ) external override {
        // verify caller via engine
        if (msg.sender != engine) {
            revert("Only engine can push liquidity");
        }

        // update the amount of total cash tokens for that vault
        totalCashSupplyForToken[uuid] += amount;

        // transfer liquidity
        IERC20(cashAsset).transferFrom(sender, address(this), amount);
    }

    function finalizeVault(
        bytes32 uuid
    ) external override {
        // ensure that this is a valid vault calling us - it must call through the engine
        if (msg.sender != engine) {
            revert("Only engine can finalize");
        }

        // ensure that this vault has not already been finalized
        if (vaultStatus[uuid]) {
            revert("Already finalized");
        }

        // finalize the vault
        vaultStatus[uuid] = true;
    }

    function isSlotFull(uint256 slotID) public view override returns (bool full) {
        if (slots[slotID].providers.length == 5) {
            return true;
        } else return false;
    }

    function getSmallestProvider(uint256 slotID) public view override returns (address smallestProvider) {
        if (!isSlotFull(slotID)) {
            return address(0);
        } else {
            SlotState slot = slots[slotID];
            address smallestProvider = address(0);
            uint256 smallestAmount = type(uint256).max;

            for (uint i=0; i < 5; i++) {
                (address _provider, address _amount) = slot.providers.at(i);

                if (_amount < smallestAmount) {
                    smallestAmount = _amount;
                    smallestProvider = _provider;
                }
            }

            return smallestProvider;
        }
    }

    function _allocate(uint256 slotID, address provider, uint256 amount) internal {
        SlotState storage slot = slots[slotID];

        if (slot.providers.contains(provider)) {
            uint256 providerAmount = slot.providers.get(provider);
            slot.providers.set(provider, providerAmount + amount);
        } else {
            slot.providers.set(provider, amount);
        }

        slot.liquidity += amount;
    }

    function _unallocate(uint256 slotID, address provider, uint256 amount) internal {
        SlotState storage slot = slots[slotID];

        uint256 sourceAmount = slot.providers.get(provider);
        
        if (sourceAmount == amount) slot.providers.remove(provider);
        else slot.providers.set(provider, sourceAmount - amount);

        slot.liquidity -= amount;
    }

    function _reAllocate(address provider, uint256 sourceSlotID, uint256 destinationSlotID, uint256 amount) internal {
        _unallocate(sourceSlotID, provider, amount);
        _allocate(destinationSlotID, provider, amount);
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