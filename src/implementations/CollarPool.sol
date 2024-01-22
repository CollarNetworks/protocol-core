// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

import { ICollarPool } from "../interfaces/ICollarPool.sol";
import { Constants, CollarVaultState } from "../libs/CollarLibs.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { EnumerableMap } from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";

contract CollarPool is ICollarPool, Constants {
    using EnumerableMap for EnumerableMap.AddressToUintMap;

    constructor(address _engine, uint256 _tickScaleFactor, address _cashAsset) ICollarPool(_engine, _tickScaleFactor, _cashAsset) { }

    function getSlotLiquidity(uint256 slotIndex) external view override returns (uint256) {
        return slots[slotIndex].liquidity;
    }

    function getSlotProviderLength(uint256 slotIndex) external view override returns (uint256) {
        return slots[slotIndex].providers.length();
    }

    function getSlotProviderInfoAt(uint256 slotIndex, uint256 providerIndex) external view override returns (address, uint256) {
        return slots[slotIndex].providers.at(providerIndex);
    }

    function getSlotProviderInfo(uint256 slotIndex, address provider) external view override returns (uint256) {
        return slots[slotIndex].providers.get(provider);
    }

    function addLiquidity(uint256 slotIndex, uint256 amount) public virtual override {
        LiquiditySlot storage slot = slots[slotIndex];

        if (slot.providers.contains(msg.sender) || !_isSlotFull(slotIndex)) {
            _allocate(slotIndex, msg.sender, amount);
        } else {
            address smallestProvider = _getSmallestProvider(slotIndex);
            uint256 smallestAmount = slot.providers.get(smallestProvider);

            if (smallestAmount > amount) revert("Amount not high enough to kick out anyone from full slot.");

            _reAllocate(smallestProvider, slotIndex, UNALLOCATED_SLOT, smallestAmount);
            _allocate(slotIndex, msg.sender, amount);
        }

        // transfer collateral from provider to pool
        IERC20(cashAsset).transferFrom(msg.sender, address(this), amount);
    }

    function removeLiquidity(uint256 slot, uint256 amount) public virtual override {
        // verify sender has enough liquidity in slot
        uint256 liquidity = slots[slot].providers.get(msg.sender);

        if (liquidity < amount) {
            revert("Not enough liquidity");
        }

        _reAllocate(msg.sender, slot, UNALLOCATED_SLOT, amount);
    }

    function reallocateLiquidity(uint256 sourceSlotIndex, uint256 destinationSlotIndex, uint256 amount) external virtual override {
        removeLiquidity(sourceSlotIndex, amount);
        addLiquidity(destinationSlotIndex, amount);
    }

    function mint(bytes32 uuid, uint256 slotId, uint256 amount) external override {
        // ensure this is a valid vault calling us - it must call through the engine
        if (msg.sender != engine) {
            //revert("Only engine can mint");
        }

        // grab the slot
        LiquiditySlot storage slot = slots[slotId];
        uint256 numProviders = slot.providers.length();

        for (uint256 i = 0; i < numProviders; i++) {
            // calculate how much to pull from provider based off of their proportional ownership of liquidity in this slot

            (address thisProvider, uint256 thisLiquidity) = slot.providers.at(i);

            // this provider's liquidity to pull =
            // (provider's proportional ownership of slot liquidity) * (total amount needed)
            // (providerLiquidity / totalSlotLiquidity) * amount
            // (providerLiquidity * amount) / totalSlotLiquidity
            uint256 amountFromThisProvider = (thisLiquidity * amount) / slot.liquidity;

            // pull liquidity from provider
            slot.providers.set(thisProvider, thisLiquidity - amountFromThisProvider);

            // mint to this provider
            _mint(thisProvider, uint256(uuid), amountFromThisProvider);
        }

        // decrement available liquidity in slot
        slot.liquidity -= amount;

        // finally, store the info about the pToken
        pTokens[uuid] = pToken({ redeemable: false, totalRedeemableCash: amount });
    }

    function redeem(bytes32 uuid, uint256 amount) external override {
        // ensure vault is finalized

        // calculate cash redeem value
        uint256 redeemValue = previewRedeem(uuid, amount);

        // adjust total redeemable cash
        pTokens[uuid].totalRedeemableCash -= redeemValue;

        // redeem to user & burn tokens
        _burn(msg.sender, uint256(uuid), amount);
        IERC20(cashAsset).transfer(msg.sender, redeemValue);
    }

    function previewRedeem(bytes32 uuid, uint256 amount) public view override returns (uint256 cashReceived) {
        // grab the info for this particular pToken
        pToken storage pToken = pTokens[uuid];

        if (pToken.redeemable) {
            // if finalized, calculate final redeem value
            // grab collateral asset value @ exact vault expiration time

            uint256 _totalTokenCashSupply = pToken.totalRedeemableCash;
            uint256 _totalTokenSupply = totalTokenSupply[uint256(uuid)];

            cashReceived = (_totalTokenCashSupply * amount) / _totalTokenSupply;
        } else {
            revert("Not implemented");
        }
    }

    function pullLiquidity(bytes32 uuid, address receiver, uint256 amount) external override {
        // verify caller via engine
        if (msg.sender != engine) {
            //revert("Only engine can pull liquidity");
        }

        // update the amount of total cash tokens for that vault
        pTokens[uuid].totalRedeemableCash -= amount;

        // transfer liquidity
        IERC20(cashAsset).transfer(receiver, amount);
    }

    function pushLiquidity(bytes32 uuid, address sender, uint256 amount) external override {
        // verify caller via engine
        if (msg.sender != engine) {
            //revert("Only engine can push liquidity");
        }

        // update the amount of total cash tokens for that vault
        pTokens[uuid].totalRedeemableCash += amount;

        // transfer liquidity
        IERC20(cashAsset).transferFrom(sender, address(this), amount);
    }

    function _isSlotFull(uint256 slotID) internal view returns (bool full) {
        if (slots[slotID].providers.length() == 5) {
            return true;
        } else {
            return false;
        }
    }

    function _getSmallestProvider(uint256 slotID) internal view returns (address smallestProvider) {
        if (!_isSlotFull(slotID)) {
            return address(0);
        } else {
            LiquiditySlot storage slot = slots[slotID];
            uint256 smallestAmount = type(uint256).max;

            for (uint256 i = 0; i < 5; i++) {
                (address _provider, uint256 _amount) = slot.providers.at(i);

                if (_amount < smallestAmount) {
                    smallestAmount = _amount;
                    smallestProvider = _provider;
                }
            }
        }
    }

    function _allocate(uint256 slotID, address provider, uint256 amount) internal {
        LiquiditySlot storage slot = slots[slotID];

        if (slot.providers.contains(provider)) {
            uint256 providerAmount = slot.providers.get(provider);
            slot.providers.set(provider, providerAmount + amount);
        } else {
            slot.providers.set(provider, amount);
        }

        slot.liquidity += amount;
    }

    function _unallocate(uint256 slotID, address provider, uint256 amount) internal {
        LiquiditySlot storage slot = slots[slotID];

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
