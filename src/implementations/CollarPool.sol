// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { EnumerableMap } from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { ERC6909TokenSupply } from "@erc6909/ERC6909TokenSupply.sol";
// internal imports
import { CollarEngine } from "./CollarEngine.sol";
import { CollarVaultManager } from "./CollarVaultManager.sol";
import { ICollarPool } from "../interfaces/ICollarPool.sol";

import "forge-std/console.sol";

// TODO: this is a temp place, move / rename / refactor this somewhere where it makes sense
abstract contract BaseCollarPoolState {
    using EnumerableMap for EnumerableMap.AddressToUintMap;
    using EnumerableSet for EnumerableSet.UintSet;

    // represents one partitioned slice of the liquidity pool, its providers, and the amount they provide
    struct Slot {
        uint liquidity; // <-- total liquidity in the slot
        EnumerableMap.AddressToUintMap providers;
    }

    // 1 - user opens a vault against a single slot
    // 2 - provider liquidity is locked proportionally against user vaults,
    //     pro rata according to how much liquidity the provider has provided
    // 3 - for *EACH* provider that has had liquidity locked for said vault,
    //     we store a "Position" (see below)

    /*

        IMPORTANT: When a user opens a vault and chooses a slot to lock liquidity from,
        *all providers in the slot* have their liquidity locked (but proportionally to how much
        they have provided)

    */

    // a Position is a financial instrument that:
    //  - can be entered into, and eventually exited
    //  - can gain or lose value over time
    //  - has a static initial value (principal)
    //  - has a dynamic/calculable current value
    //  - has a defined time horizon
    //  - carries inherent risk
    struct Position {
        uint expiration; // <-- defined time horizon --- does not change
        uint principal; // <-- static initial value --- does not change
        uint withdrawable; // <-- zero until close, then set to settlement value
    }

    /// @notice Records the state of each slot (see Slot struct above)
    mapping(uint index => Slot) internal slots;

    /// @notice Records the state of each Position by their UUID
    mapping(bytes32 uuid => Position) public positions;

    /// @notice Records the set of all initialized slots
    EnumerableSet.UintSet internal initializedSlotIndices;
}

contract CollarPool is BaseCollarPoolState, ERC6909TokenSupply, ICollarPool {
    using SafeERC20 for IERC20;
    using EnumerableMap for EnumerableMap.AddressToUintMap;
    using EnumerableSet for EnumerableSet.UintSet;

    using EnumerableMap for EnumerableMap.AddressToUintMap;

    // ----- IMMUTABLES ----- //

    /// @notice This is the ID of the slot that is unallocated to any particular call strike percentage
    uint public constant UNALLOCATED_SLOT = type(uint).max;

    /// @notice This is the factor by which the slot ID is scaled to get the actual bps value
    /// @dev A tick scale factor of 1 means that slot 10_000 = 100% = 1 bps per tick, and so on

    uint public immutable tickScaleFactor;

    /// @notice The address of the engine is set upon pool creation (and registered with the engine)
    address public immutable engine;

    /// @notice The address of the cash asset is set upon pool creation (and verified with the engine as
    /// allowed)
    address public immutable cashAsset;

    /// @notice The address of the collateral asset is set upon pool creation (and verified with the engine as
    /// allowed)
    address public immutable collateralAsset;

    /// @notice The duration of collars to be opened against this pool
    uint public immutable duration;

    /// @notice The LTV of collars to be opened against this pool
    uint public immutable ltv;

    // ----- STATE VARIABLES ----- //

    /// @notice The total amount of liquidity in the pool
    /// @dev Total liquidity = locked + free + redeemable
    uint public totalLiquidity;

    /// @notice The amount of locked liquidity in the pool
    uint public lockedLiquidity;

    /// @notice The amount of free liquidity in the pool
    uint public freeLiquidity;

    /// @notice The amount of redeemable liquidity in the pool
    uint public redeemableLiquidity;

    // ----- CONSTRUCTOR ----- //

    constructor(
        address _engine,
        uint _tickScaleFactor,
        address _cashAsset,
        address _collateralAsset,
        uint _duration,
        uint _ltv
    ) {
        if (!CollarEngine(_engine).isValidLTV(_ltv)) {
            revert InvalidLTV();
        }

        tickScaleFactor = _tickScaleFactor;
        engine = _engine;
        cashAsset = _cashAsset;
        collateralAsset = _collateralAsset;
        duration = _duration;
        ltv = _ltv;
    }

    // ----- VIEW FUNCTIONS ----- //

    function getInitializedSlotIndices() external view override returns (uint[] memory) {
        return initializedSlotIndices.values();
    }

    function getLiquidityForSlots(uint[] calldata slotIndices)
        external
        view
        override
        returns (uint[] memory)
    {
        uint[] memory liquidity = new uint[](slotIndices.length);

        for (uint i = 0; i < slotIndices.length; i++) {
            liquidity[i] = slots[slotIndices[i]].liquidity;
        }

        return liquidity;
    }

    function getLiquidityForSlot(uint slotIndex) external view override returns (uint) {
        return slots[slotIndex].liquidity;
    }

    function getNumProvidersInSlot(uint slotIndex) external view override returns (uint) {
        return slots[slotIndex].providers.length();
    }

    function getSlotProviderInfoAtIndex(uint slotIndex, uint providerIndex)
        external
        view
        override
        returns (address, uint)
    {
        return slots[slotIndex].providers.at(providerIndex);
    }

    function getSlotProviderInfoForAddress(uint slotIndex, address provider)
        external
        view
        override
        returns (uint)
    {
        return slots[slotIndex].providers.get(provider);
    }

    function previewRedeem(bytes32 uuid, uint amount) public view override returns (uint cashReceived) {
        // verify that the user has enough tokens for this to even work
        if (ERC6909TokenSupply(address(this)).balanceOf(msg.sender, uint(uuid)) < amount) {
            revert InvalidAmount();
        }

        // grab the info for this particular Position
        Position storage _position = positions[uuid];

        if (_position.expiration <= block.timestamp) {
            // if finalized, calculate final redeem value
            // grab collateral asset value @ exact vault expiration time

            uint _totalTokenCashSupply = _position.withdrawable;
            uint _totalTokenSupply = totalSupply[uint(uuid)];

            cashReceived = (_totalTokenCashSupply * amount) / _totalTokenSupply;
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

    function addLiquidityToSlot(uint slotIndex, uint amount) public virtual override {
        Slot storage slot = slots[slotIndex];

        // If this slot isn't initialized, add to the initialized list - we're initializing it now
        if (!_isSlotInitialized(slotIndex)) {
            initializedSlotIndices.add(slotIndex);
        }

        if (slot.providers.contains(msg.sender) || !_isSlotFull(slotIndex)) {
            _allocate(slotIndex, msg.sender, amount);
        } else {
            address smallestProvider = _getSmallestProvider(slotIndex);
            uint smallestAmount = slot.providers.get(smallestProvider);

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
        IERC20(cashAsset).safeTransferFrom(msg.sender, address(this), amount);
    }

    function withdrawLiquidityFromSlot(uint slotIndex, uint amount) public virtual override {
        console.log("withdraw liquidity from slot %d , amount  %d", slotIndex, amount);
        Slot storage slot = slots[slotIndex];

        uint liquidity = slot.providers.get(msg.sender);

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
        IERC20(cashAsset).safeTransfer(msg.sender, amount);
    }

    function moveLiquidityFromSlot(uint sourceSlotIndex, uint destinationSlotIndex, uint amount)
        external
        virtual
        override
    {
        // lockedLiquidity unchanged
        // redeemLiquidity unchanged
        // freeLiquidity unchanged
        // totalLiquidity unchanged

        // withdrawLiquidityFromSlot(sourceSlotIndex, amount);
        // verify sender has enough liquidity in slot
        Slot storage sourceSlot = slots[sourceSlotIndex];
        uint liquidity = sourceSlot.providers.get(msg.sender);
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
            uint smallestAmount = destinationSlot.providers.get(smallestProvider);

            if (smallestAmount > amount) revert NoLiquiditySpace();

            _reAllocate(smallestProvider, destinationSlotIndex, UNALLOCATED_SLOT, smallestAmount);
            _allocate(destinationSlotIndex, msg.sender, amount);
        }
        emit LiquidityMoved(msg.sender, sourceSlotIndex, destinationSlotIndex, amount);
    }

    function openPosition(bytes32 uuid, uint slotIndex, uint amount, uint expiration) external override {
        // ensure this is a valid vault calling us - it must call through the engine
        if (!CollarEngine(engine).isVaultManager(msg.sender)) {
            revert NotCollarVaultManager();
        }

        // grab the slot
        Slot storage slot = slots[slotIndex];
        uint numProviders = slot.providers.length();

        // if no providers, revert
        if (numProviders == 0) {
            revert InvalidAmount();
        }

        // if not enough liquidity, revert
        if (slot.liquidity < amount) {
            revert InvalidAmount();
        }

        for (uint i = 0; i < numProviders; i++) {
            // calculate how much to pull from provider based off of their proportional ownership of liquidity
            // in this slot

            (address thisProvider, uint thisLiquidity) = slot.providers.at(i);

            // this provider's liquidity to pull =
            // (provider's proportional ownership of slot liquidity) * (total amount needed)
            // (providerLiquidity / totalSlotLiquidity) * amount
            // (providerLiquidity * amount) / totalSlotLiquidity
            uint amountFromThisProvider = (thisLiquidity * amount) / slot.liquidity;

            // decrement the amount of free liquidity that this provider has, in this slot
            slot.providers.set(thisProvider, thisLiquidity - amountFromThisProvider);

            // mint tokens representing the provider's share in this vault to this provider
            _mint(thisProvider, uint(uuid), amountFromThisProvider);

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

    function finalizePosition(bytes32 uuid, address vaultManager, int positionNet) external override {
        // verify caller via engine
        if (!CollarEngine(engine).isVaultManager(msg.sender)) {
            revert NotCollarVaultManager();
        }

        // either case, we need to set the withdrawable amount to principle + positionNet
        positions[uuid].withdrawable = uint(int(positions[uuid].principal) + positionNet);

        // update global liquidity amounts
        // free liquidity unchanged

        totalLiquidity = uint(int(totalLiquidity) + positionNet);

        lockedLiquidity -= positions[uuid].principal;

        redeemableLiquidity += uint(int(positions[uuid].principal) + positionNet);

        if (positionNet < 0) {
            // we owe the vault some tokens
            IERC20(cashAsset).safeTransfer(vaultManager, uint(-positionNet));
        } else if (positionNet > 0) {
            // the vault owes us some tokens
            IERC20(cashAsset).safeTransferFrom(vaultManager, address(this), uint(positionNet));
        } else {
            // impressive. most impressive.
        }

        emit PositionFinalized(vaultManager, uuid, positionNet);
    }

    function redeem(bytes32 uuid, uint amount) external override {
        // validate position exists
        if (positions[uuid].expiration == 0) {
            revert InvalidVault();
        }

        if (positions[uuid].expiration > block.timestamp) {
            revert VaultNotFinalized();
        }

        // ensure that the user has enough tokens
        if (ERC6909TokenSupply(address(this)).balanceOf(msg.sender, uint(uuid)) < amount) {
            revert InvalidAmount();
        }

        // calculate cash redeem value
        uint redeemValue = previewRedeem(uuid, amount);

        // adjust total redeemable cash
        positions[uuid].withdrawable -= redeemValue;

        // update global liquidity amounts
        // locked liquidity unchanged
        // free liquidity unchangedd
        totalLiquidity -= redeemValue;

        redeemableLiquidity -= redeemValue;

        emit Redemption(msg.sender, uuid, amount, redeemValue);

        // redeem to user & burn tokens
        _burn(msg.sender, uint(uuid), amount);
        IERC20(cashAsset).safeTransfer(msg.sender, redeemValue);
    }

    // ----- INTERNAL FUNCTIONS ----- //

    function _isSlotInitialized(uint slotID) internal view returns (bool) {
        return initializedSlotIndices.contains(slotID);
    }

    function _isSlotFull(uint slotID) internal view returns (bool full) {
        if (slots[slotID].providers.length() == 5) {
            return true;
        } else {
            return false;
        }
    }

    function _getSmallestProvider(uint slotID) internal view returns (address smallestProvider) {
        if (!_isSlotFull(slotID)) {
            return address(0);
        } else {
            Slot storage slot = slots[slotID];
            uint smallestAmount = type(uint).max;

            for (uint i = 0; i < 5; i++) {
                (address _provider, uint _amount) = slot.providers.at(i);

                if (_amount < smallestAmount) {
                    smallestAmount = _amount;
                    smallestProvider = _provider;
                }
            }
        }
    }

    function _allocate(uint slotID, address provider, uint amount) internal {
        Slot storage slot = slots[slotID];

        if (slot.providers.contains(provider)) {
            uint providerAmount = slot.providers.get(provider);
            slot.providers.set(provider, providerAmount + amount);
        } else {
            slot.providers.set(provider, amount);
        }

        slot.liquidity += amount;
    }

    function _unallocate(uint slotID, address provider, uint amount) internal {
        Slot storage slot = slots[slotID];

        uint sourceAmount = slot.providers.get(provider);

        if (sourceAmount == amount) slot.providers.remove(provider);
        else slot.providers.set(provider, sourceAmount - amount);

        slot.liquidity -= amount;
    }

    function _reAllocate(address provider, uint sourceSlotID, uint destinationSlotID, uint amount) internal {
        _unallocate(sourceSlotID, provider, amount);
        _allocate(destinationSlotID, provider, amount);
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
