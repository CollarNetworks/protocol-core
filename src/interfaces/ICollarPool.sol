// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

// ----- IMPORTS

import { IERC6909WithSupply } from "../interfaces/IERC6909WithSupply.sol";
import { EnumerableMap } from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

abstract contract ICollarPoolState {
    using EnumerableMap for EnumerableMap.AddressToUintMap;
    using EnumerableSet for EnumerableSet.UintSet;

    // represents one partitioned slice of the liquidity pool, its providers, and the amount they provide
    struct Slot {
        uint256 liquidity;      // <-- total liquidity in the slot
        EnumerableMap.AddressToUintMap providers;
    }
        
    // a Position is a financial instrument that:
    //  - can be entered into, and eventually exited
    //  - can gain or lose value over time
    //  - has a static initial value (principal)
    //  - has a dynamic/calculable current value
    //  - has a defined time horizon
    //  - carries inherent risk
    struct Position {
        uint256 expiration;   // <-- defined time horizon --- does not change
        uint256 principal;    // <-- static initial value --- does not change
        uint256 withdrawable; // <-- zero until close, then set to settlement value
    }

    /// @notice Records the state of each slot (see Slot struct above)
    mapping(uint256 index => Slot) internal slots;

    /// @notice Records the state of each Position by their UUID
    mapping(bytes32 uuid => Position) public Positions;

    /// @notice Records the set of all initialized slots
    EnumerableSet.UintSet internal initializedSlotIndices;
}

abstract contract ICollarPool is IERC6909WithSupply, ICollarPoolState {
    using EnumerableMap for EnumerableMap.AddressToUintMap;

    /// @notice This is the ID of the slot that is unallocated to any particular call strike percentage
    uint256 public constant UNALLOCATED_SLOT = type(uint256).max;

    /// @notice This is the factor by which the slot ID is scaled to get the actual bps value
    /// @dev A tick scale factor of 1 means that slot 10_000 = 100% = 1 bps per tick, and so on
    uint256 public immutable tickScaleFactor;

    /// @notice The address of the engine is set upon pool creation (and registered with the engine)
    address public immutable engine;

    /// @notice The address of the cash asset is set upon pool creation (and verified with the engine as allowed)
    address public immutable cashAsset;

    /// @notice The total amount of liquidity in the pool
    uint256 public totalLiquidity;

    /// @notice The amount of locked liquidity in the pool
    uint256 public lockedLiquidity;

    /// @notice The amount of free liquidity in the pool
    uint256 public freeLiquidity;

    constructor(address _engine, uint256 _tickScaleFactor, address _cashAsset) {
        tickScaleFactor = _tickScaleFactor;
        engine = _engine;
        cashAsset = _cashAsset;
    }

    /// @notice Gets the ids of initialized slots
    function getInitializedSlotIndices() external view virtual returns (uint256[] calldata);

    /// @notice Gets the liquidity for a set of slots
    /// @param slotIndices The indices of the slots to get the liquidity for
    function getLiquidityForSlots(uint256[] calldata slotIndices) external view virtual returns (uint256[] calldata amounts);

    /// @notice Gets the amount of liquidity in a particular slot
    /// @param slotIndex The index of the slot to get the state of
    function getLiquidityForSlot(uint256 slotIndex) external virtual returns (uint256 amount);

    /// @notice Gets the number of providers in a particular slot
    /// @param slotIndex The index of the slot to get the state of
    function getNumProvidersInSlot(uint256 slotIndex) external virtual returns (uint256 amount);

    /// @notice Gets the address & free liquidity amount of the provider at a particular index in a particular slot
    /// @param slotIndex The index of the slot to get the state of
    /// @param providerIndex The index of the provider to get the state of within the overall slot
    function getSlotProviderInfoAtIndex(uint256 slotIndex, uint256 providerIndex) external virtual returns (address provider, uint256 amount);

    /// @notice Gets the free liquidity amount of the specified provider in a particular slot
    /// @param slotIndex The index of the slot to get the state of
    /// @param provider The address of the provider to get the state of within the overall slot
    function getSlotProviderInfoForAddress(uint256 slotIndex, address provider) external virtual returns (uint256 amount);

    /// @notice Adds liquidity to a given slot
    /// @param slot The index of the slot to add liquidity to
    /// @param amount The amount of liquidity to add
    function addLiquidity(uint256 slot, uint256 amount) external virtual;

    /// @notice Removes liquidity from a given slot
    /// @param slot The index of the slot to remove liquidity from
    /// @param amount The amount of liquidity to remove
    function removeLiquidity(uint256 slot, uint256 amount) external virtual;

    /// @notice Reallocates free liquidity from one slot to another
    /// @param source The index of the slot to remove liquidity from
    /// @param destination The index of the slot to add liquidity to
    /// @param amount The amount of liquidity to reallocate
    function moveLiquidity(uint256 source, uint256 destination, uint256 amount) external virtual;

    /// @TODO refactor stopped here 3/5/24
    /// @TODO plz continue from here. kthxbye.

    /// @notice Allows a valid vault to pull liquidity from the pool on finalization
    function pullLiquidity(bytes32 uuid, address receiver, uint256 amount) external virtual;

    /// @notice Allows a valid vault to push liquidity to the pool on finalization
    function pushLiquidity(bytes32 uuid, address sender, uint256 amount) external virtual;

    /// @notice Allows a vault to mint tokens once liquidity is locked upon vault creation
    function mint(bytes32 uuid, uint256 slot, uint256 amount) external virtual;

    /// @notice Allows liquidity providers to redeem liquidity-pool tokens corresponding to a particular vault
    function redeem(bytes32 uuid, uint256 amount) external virtual;

    /// @notice Allows the engine to finalize a vault token
    function finalizeToken(bytes32 uuid) external virtual;

    /// @notice Allows liquidity providers to preview the amount of cash they would receive upon redeeming for a particular vault token
    function previewRedeem(bytes32 uuid, uint256 amount) external virtual returns (uint256);
}
