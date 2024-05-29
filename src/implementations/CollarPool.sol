// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

import { ICollarPool } from "../interfaces/ICollarPool.sol";
import { ICollarPoolErrors } from "../interfaces/errors/ICollarPoolErrors.sol";
import { ICollarPoolEvents } from "../interfaces/events/ICollarPoolEvents.sol";
import { ICollarVaultState } from "../interfaces/ICollarVaultState.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { EnumerableMap } from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { CollarEngine } from "./CollarEngine.sol";
import { CollarVaultManager } from "./CollarVaultManager.sol";
import { ERC6909TokenSupply } from "@erc6909/ERC6909TokenSupply.sol";
import "forge-std/console.sol";

contract CollarPool is ICollarPool, ERC6909TokenSupply {
    using EnumerableMap for EnumerableMap.AddressToUintMap;
    using EnumerableSet for EnumerableSet.UintSet;

    // ----- CONSTRUCTOR ----- //

    constructor(address _engine, uint256 _tickScaleFactor, address _cashAsset, address _collateralAsset, uint256 _duration, uint256 _ltv)
        ICollarPool(_engine, _tickScaleFactor, _cashAsset, _collateralAsset, _duration, _ltv)
    {
        if (!CollarEngine(_engine).isValidLTV(_ltv)) {
            revert InvalidLTV();
        }
    }

    // ----- VIEW FUNCTIONS ----- //

    function getInitializedSlotIndices() external view override returns (uint256[] memory) {
        return initializedSlotIndices.values();
    }

    function getLiquidityForSlots(uint256[] calldata slotIndices) external view override returns (uint256[] memory) {
        uint256[] memory liquidity = new uint256[](slotIndices.length);

        for (uint256 i = 0; i < slotIndices.length; i++) {
            liquidity[i] = slots[slotIndices[i]].liquidity;
        }

        return liquidity;
    }

    function getLiquidityForSlot(uint256 slotIndex) external view override returns (uint256) {
        return slots[slotIndex].liquidity;
    }

    function getNumProvidersInSlot(uint256 slotIndex) external view override returns (uint256) {
        return slots[slotIndex].providers.length();
    }

    function getSlotProviderInfoAtIndex(uint256 slotIndex, uint256 providerIndex) external view override returns (address, uint256) {
        return slots[slotIndex].providers.at(providerIndex);
    }

    function getSlotProviderInfoForAddress(uint256 slotIndex, address provider) external view override returns (uint256) {
        return slots[slotIndex].providers.get(provider);
    }

    function previewRedeem(bytes32 uuid, uint256 amount) public view override returns (uint256 cashReceived) {
        // verify that the user has enough tokens for this to even work
        if (ERC6909TokenSupply(address(this)).balanceOf(msg.sender, uint256(uuid)) < amount) {
            revert InvalidAmount();
        }

        // grab the info for this particular Position
        Position storage _position = positions[uuid];

        if (_position.expiration <= block.timestamp) {
            // if finalized, calculate final redeem value
            // grab collateral asset value @ exact vault expiration time

            uint256 _totalTokenCashSupply = _position.withdrawable;
            uint256 _totalTokenSupply = totalSupply[uint256(uuid)];

            cashReceived = (_totalTokenCashSupply * amount) / _totalTokenSupply;
        } else {
            // calculate redeem value based on current price of asset
            // uint256 currentCollateralPrice = CollarEngine(engine).getCurrentAssetPrice(vaultsByUUID[uuid].collateralAsset);

            // this is very complicated to implement - basically have to recreate
            // the entire closeVault function, but without changing state

            revert VaultNotFinalized();
        }
    }

    // ----- STATE CHANGING FUNCTIONS ----- //

    function addLiquidityToSlot(uint256 slotIndex, uint256 amount) public virtual override {
        Slot storage slot = slots[slotIndex];

        // If this slot isn't initialized, add to the initialized list - we're initializing it now
        if (!_isSlotInitialized(slotIndex)) {
            initializedSlotIndices.add(slotIndex);
        }

        if (slot.providers.contains(msg.sender) || !_isSlotFull(slotIndex)) {
            _allocate(slotIndex, msg.sender, amount);
        } else {
            address smallestProvider = _getSmallestProvider(slotIndex);
            uint256 smallestAmount = slot.providers.get(smallestProvider);

            if (smallestAmount > amount) revert NoLiquiditySpace();

            _reAllocate(smallestProvider, slotIndex, UNALLOCATED_SLOT, smallestAmount);
            _allocate(slotIndex, msg.sender, amount);
        }

        // lockedLiquidity unchanged
        // redeemLiquidity unchanged
        freeLiquidity += amount;
        totalLiquidity += amount;

        emit LiquidityAdded(msg.sender, slotIndex, amount);

        // transfer CASH from provider to pool
        IERC20(cashAsset).transferFrom(msg.sender, address(this), amount);
    }

    function withdrawLiquidityFromSlot(uint256 slotIndex, uint256 amount) public virtual override {
        console.log("withdraw liquidity from slot %d , amount  %d", slotIndex, amount);
        Slot storage slot = slots[slotIndex];

        uint256 liquidity = slot.providers.get(msg.sender);

        // verify sender has enough liquidity in slot
        if (liquidity < amount) {
            revert InvalidAmount();
        }

        // lockedLiquidity unchanged
        // redeemLiquidity unchanged
        freeLiquidity -= amount;
        totalLiquidity -= amount;
        _unallocate(slotIndex, msg.sender, amount);
        // If slot has no more liquidity, remove from the initialized list
        if (slot.liquidity == 0) {
            initializedSlotIndices.remove(slotIndex);
        }

        emit LiquidityWithdrawn(msg.sender, slotIndex, amount);

        // finally, transfer the liquidity to the provider
        IERC20(cashAsset).transfer(msg.sender, amount);
    }

    function moveLiquidityFromSlot(uint256 sourceSlotIndex, uint256 destinationSlotIndex, uint256 amount) external virtual override {
        // lockedLiquidity unchanged
        // redeemLiquidity unchanged
        // freeLiquidity unchanged
        // totalLiquidity unchanged

        // withdrawLiquidityFromSlot(sourceSlotIndex, amount);
        // verify sender has enough liquidity in slot
        Slot storage sourceSlot = slots[sourceSlotIndex];
        uint256 liquidity = sourceSlot.providers.get(msg.sender);
        if (liquidity < amount) {
            revert InvalidAmount();
        }
        _unallocate(sourceSlotIndex, msg.sender, amount);
        // If slot has no more liquidity, remove from the initialized list
        if (sourceSlot.liquidity == 0) {
            initializedSlotIndices.remove(sourceSlotIndex);
        }
        // add
        Slot storage destinationSlot = slots[destinationSlotIndex];

        // If this slot isn't initialized, add to the initialized list - we're initializing it now
        if (!_isSlotInitialized(destinationSlotIndex)) {
            initializedSlotIndices.add(destinationSlotIndex);
        }
        if (destinationSlot.providers.contains(msg.sender) || !_isSlotFull(destinationSlotIndex)) {
            _allocate(destinationSlotIndex, msg.sender, amount);
        } else {
            address smallestProvider = _getSmallestProvider(destinationSlotIndex);
            uint256 smallestAmount = destinationSlot.providers.get(smallestProvider);

            if (smallestAmount > amount) revert NoLiquiditySpace();

            _reAllocate(smallestProvider, destinationSlotIndex, UNALLOCATED_SLOT, smallestAmount);
            _allocate(destinationSlotIndex, msg.sender, amount);
        }
        emit LiquidityMoved(msg.sender, sourceSlotIndex, destinationSlotIndex, amount);
    }

    function openPosition(bytes32 uuid, uint256 slotIndex, uint256 amount, uint256 expiration) external override {
        // ensure this is a valid vault calling us - it must call through the engine
        if (!CollarEngine(engine).isVaultManager(msg.sender)) {
            revert NotCollarVaultManager();
        }

        // grab the slot
        Slot storage slot = slots[slotIndex];
        uint256 numProviders = slot.providers.length();

        // if no providers, revert
        if (numProviders == 0) {
            revert InvalidAmount();
        }

        // if not enough liquidity, revert
        if (slot.liquidity < amount) {
            revert InvalidAmount();
        }

        for (uint256 i = 0; i < numProviders; i++) {
            // calculate how much to pull from provider based off of their proportional ownership of liquidity in this slot

            (address thisProvider, uint256 thisLiquidity) = slot.providers.at(i);

            // this provider's liquidity to pull =
            // (provider's proportional ownership of slot liquidity) * (total amount needed)
            // (providerLiquidity / totalSlotLiquidity) * amount
            // (providerLiquidity * amount) / totalSlotLiquidity
            uint256 amountFromThisProvider = (thisLiquidity * amount) / slot.liquidity;

            // decrement the amount of free liquidity that this provider has, in this slot
            slot.providers.set(thisProvider, thisLiquidity - amountFromThisProvider);

            // mint tokens representing the provider's share in this vault to this provider
            _mint(thisProvider, uint256(uuid), amountFromThisProvider);

            emit PoolTokensIssued(thisProvider, expiration, amountFromThisProvider);
        }

        // decrement available liquidity in slot
        slot.liquidity -= amount;

        // update global liquidity amounts
        // total liquidity unchanged
        // redeemable liquidity unchanged
        lockedLiquidity += amount;
        freeLiquidity -= amount;

        /*

            ! IMPORTANTLY: THERE IS *ONE* POSITION PER VAULT (1:1) !

        */

        // finally, store the info about the Position
        positions[uuid] = Position({ expiration: expiration, principal: amount, withdrawable: 0 });

        // also, check to see if we need to un-initalize this slot
        if (slot.liquidity == 0) {
            initializedSlotIndices.remove(slotIndex);
        }

        emit PositionOpened(msg.sender, uuid, expiration, amount);
    }

    function finalizePosition(bytes32 uuid, address vaultManager, int256 positionNet) external override {
        // verify caller via engine
        if (!CollarEngine(engine).isVaultManager(msg.sender)) {
            revert NotCollarVaultManager();
        }

        // either case, we need to set the withdrawable amount to principle + positionNet
        positions[uuid].withdrawable = uint256(int256(positions[uuid].principal) + positionNet);

        // update global liquidity amounts
        // free liquidity unchanged

        totalLiquidity = uint256(int256(totalLiquidity) + positionNet);

        lockedLiquidity -= positions[uuid].principal;

        redeemableLiquidity += uint256(int256(positions[uuid].principal) + positionNet);

        if (positionNet < 0) {
            // we owe the vault some tokens
            IERC20(cashAsset).transfer(vaultManager, uint256(-positionNet));
        } else if (positionNet > 0) {
            // the vault owes us some tokens
            IERC20(cashAsset).transferFrom(vaultManager, address(this), uint256(positionNet));
        } else {
            // impressive. most impressive.
        }

        emit PositionFinalized(vaultManager, uuid, positionNet);
    }

    function redeem(bytes32 uuid, uint256 amount) external override {
        if (positions[uuid].expiration > block.timestamp) {
            revert VaultNotFinalized();
        }

        // ensure that the user has enough tokens
        if (ERC6909TokenSupply(address(this)).balanceOf(msg.sender, uint256(uuid)) < amount) {
            revert InvalidAmount();
        }

        // calculate cash redeem value
        uint256 redeemValue = previewRedeem(uuid, amount);

        // adjust total redeemable cash
        positions[uuid].withdrawable -= redeemValue;

        // update global liquidity amounts
        // locked liquidity unchanged
        // free liquidity unchangedd
        totalLiquidity -= redeemValue;

        redeemableLiquidity -= redeemValue;

        emit Redemption(msg.sender, uuid, amount, redeemValue);

        // redeem to user & burn tokens
        _burn(msg.sender, uint256(uuid), amount);
        IERC20(cashAsset).transfer(msg.sender, redeemValue);
    }

    // ----- INTERNAL FUNCTIONS ----- //

    function _isSlotInitialized(uint256 slotID) internal view returns (bool) {
        return initializedSlotIndices.contains(slotID);
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
            Slot storage slot = slots[slotID];
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
        Slot storage slot = slots[slotID];

        if (slot.providers.contains(provider)) {
            uint256 providerAmount = slot.providers.get(provider);
            slot.providers.set(provider, providerAmount + amount);
        } else {
            slot.providers.set(provider, amount);
        }

        slot.liquidity += amount;
    }

    function _unallocate(uint256 slotID, address provider, uint256 amount) internal {
        Slot storage slot = slots[slotID];

        uint256 sourceAmount = slot.providers.get(provider);

        if (sourceAmount == amount) slot.providers.remove(provider);
        else slot.providers.set(provider, sourceAmount - amount);

        slot.liquidity -= amount;
    }

    function _reAllocate(address provider, uint256 sourceSlotID, uint256 destinationSlotID, uint256 amount) internal {
        _unallocate(sourceSlotID, provider, amount);
        _allocate(destinationSlotID, provider, amount);
    }

    function _mint(address account, uint256 id, uint256 amount) internal {
        balanceOf[account][id] += amount;
        totalSupply[id] += amount;
    }

    function _burn(address account, uint256 id, uint256 amount) internal {
        balanceOf[account][id] -= amount;
        totalSupply[id] -= amount;
    }
}
