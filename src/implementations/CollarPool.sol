// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity 0.8.22;

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
        bool finalized; // <-- true when the vault manager has finalized the vault
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

    string public constant VERSION = "0.1.0";

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
        require(CollarEngine(_engine).isValidLTV(_ltv), "invalid LTV");

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

    function previewRedeem(bytes32 uuid, uint amount) public view override returns (uint) {
        Position storage _position = positions[uuid];
        require(amount <= balanceOf[msg.sender][uint(uuid)], "insufficient balance");
        require(_position.expiration <= block.timestamp, "vault not finalized");
        return _redeemAmount(_position.withdrawable, amount, totalSupply[uint(uuid)]);
    }

    // ----- STATE CHANGING FUNCTIONS ----- //

    function addLiquidityToSlot(uint slotIndex, uint amount) external {
        _addLiquidityToSlot(slotIndex, amount);
        // transfer CASH from provider to pool
        IERC20(cashAsset).safeTransferFrom(msg.sender, address(this), amount);
    }

    function withdrawLiquidityFromSlot(uint slotIndex, uint amount) external {
        _withdrawLiquidityFromSlot(slotIndex, amount);
        // transfer the liquidity to the provider
        IERC20(cashAsset).safeTransfer(msg.sender, amount);
    }

    function moveLiquidityFromSlot(uint sourceSlotIndex, uint destinationSlotIndex, uint amount)
        external
        virtual
        override
    {
        _withdrawLiquidityFromSlot(sourceSlotIndex, amount);
        _addLiquidityToSlot(destinationSlotIndex, amount);
        // @dev no transfers, only internal accounting changes
    }

    function openPosition(bytes32 uuid, uint slotIndex, uint requestedAmount, uint expiration)
        external
        override
        returns (uint amountLocked)
    {
        require(expiration >= block.timestamp, "expiration cannot be in the past");
        require(positions[uuid].expiration == 0, "Position already exists");
        // ensure this is a valid vault calling us - it must call through the engine
        require(CollarEngine(engine).isVaultManager(msg.sender), "caller not vault");

        // grab the slot
        Slot storage slot = slots[slotIndex];
        uint numProviders = slot.providers.length();

        require(numProviders != 0, "no providers");

        require(requestedAmount <= slot.liquidity, "insufficient liquidity");
        for (uint i = 0; i < numProviders; i++) {
            // calculate how much to pull from provider based off of their proportional ownership of liquidity
            // in this slot

            (address thisProvider, uint thisLiquidity) = slot.providers.at(i);

            // this provider's liquidity to pull =
            // (provider's proportional ownership of slot liquidity) * (total amount needed)
            // (providerLiquidity / totalSlotLiquidity) * amount
            // (providerLiquidity * amount) / totalSlotLiquidity
            uint amountFromThisProvider = (thisLiquidity * requestedAmount) / slot.liquidity;

            // decrement the amount of free liquidity that this provider has, in this slot
            slot.providers.set(thisProvider, thisLiquidity - amountFromThisProvider);

            // mint tokens representing the provider's share in this vault to this provider
            _mint(thisProvider, uint(uuid), amountFromThisProvider);
            amountLocked += amountFromThisProvider;
            emit PoolTokensIssued(thisProvider, expiration, amountFromThisProvider);
        }

        // decrement available liquidity in slot
        slot.liquidity -= amountLocked;

        // update global liquidity amounts
        // total liquidity unchanged
        // redeemable liquidity unchanged
        lockedLiquidity += amountLocked;
        freeLiquidity -= amountLocked;

        /*

            ! IMPORTANTLY: THERE IS *ONE* POSITION PER VAULT (1:1) !

        */

        // finally, store the info about the Position
        positions[uuid] =
            Position({ expiration: expiration, principal: amountLocked, withdrawable: 0, finalized: false });

        // also, check to see if we need to un-initalize this slot
        if (slot.liquidity == 0) {
            initializedSlotIndices.remove(slotIndex);
        }

        emit PositionOpened(msg.sender, uuid, expiration, amountLocked);
    }

    function finalizePosition(bytes32 uuid, int positionNet) external override {
        // verify caller via engine
        address vaultManager = msg.sender;
        require(CollarEngine(engine).isVaultManager(vaultManager), "caller not vault");
        require(block.timestamp >= positions[uuid].expiration, "position is not finalizable");
        require(!positions[uuid].finalized, "position already finalized");
        positions[uuid].finalized = true;

        uint principal = positions[uuid].principal;
        uint withdrawable;
        if (positionNet > 0) {
            // Positive case: positionNet is non-negative
            uint amountToAdd = uint(positionNet);

            // Update position withdrawable amount
            withdrawable = principal + amountToAdd;

            // Update global liquidity amounts
            totalLiquidity += amountToAdd;

            // The vault owes us some tokens

            IERC20(cashAsset).safeTransferFrom(vaultManager, address(this), amountToAdd);
        } else {
            // Negative case: positionNet is negative
            uint amountToSubstract = uint(-positionNet);

            // Ensure principal is greater or equal to negative positionNet to prevent underflow
            require(principal >= amountToSubstract, "Insufficient principal to cover negative positionNet");

            // Update position withdrawable amount
            withdrawable = principal - amountToSubstract;

            // Update global liquidity amounts
            totalLiquidity -= amountToSubstract;

            // We owe the vault some tokens
            IERC20(cashAsset).safeTransfer(vaultManager, amountToSubstract);
        }
        positions[uuid].withdrawable = withdrawable;
        redeemableLiquidity += withdrawable;
        lockedLiquidity -= principal;
        emit PositionFinalized(vaultManager, uuid, positionNet);
    }

    function redeem(bytes32 uuid, uint amount) external {
        Position storage position = positions[uuid];
        uint _id = uint(uuid);

        require(position.expiration != 0, "no position");
        require(block.timestamp >= position.expiration, "vault not finalized");
        require(amount <= balanceOf[msg.sender][_id], "insufficient balance");
        require(position.finalized, "position not finalized");

        // calculate cash redeem value
        uint redeemValue = _redeemAmount(position.withdrawable, amount, totalSupply[_id]);

        // adjust total redeemable cash
        position.withdrawable -= redeemValue;

        // update global liquidity amounts
        // locked liquidity unchanged
        // free liquidity unchangedd
        totalLiquidity -= redeemValue;

        redeemableLiquidity -= redeemValue;

        emit Redemption(msg.sender, uuid, amount, redeemValue);

        // redeem to user & burn tokens
        _burn(msg.sender, _id, amount);
        IERC20(cashAsset).safeTransfer(msg.sender, redeemValue);
    }

    // ----- INTERNAL VIEWS ----- //

    function _redeemAmount(uint withdrawable, uint amount, uint supply) internal view returns (uint) {
        return withdrawable * amount / supply;
    }

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

    // ----- INTERNAL MUTATIVE ----- //

    /// @dev does the checks and accounting updates, but not the token transfer
    function _addLiquidityToSlot(uint slotIndex, uint amount) internal {
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

            require(amount > smallestAmount, "no smaller slot available");

            _reAllocate(smallestProvider, slotIndex, UNALLOCATED_SLOT, smallestAmount);
            _allocate(slotIndex, msg.sender, amount);
        }

        // lockedLiquidity unchanged
        // redeemLiquidity unchanged
        freeLiquidity += amount;
        totalLiquidity += amount;

        emit LiquidityAdded(msg.sender, slotIndex, amount);
    }

    /// @dev does the checks and accounting updates, but not the token transfer
    function _withdrawLiquidityFromSlot(uint slotIndex, uint amount) internal {
        Slot storage slot = slots[slotIndex];

        uint liquidity = slot.providers.get(msg.sender);

        // verify sender has enough liquidity in slot
        require(amount <= liquidity, "amount too large");

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
