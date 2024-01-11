// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

import {IERC6909WithSupply} from "../interfaces/IERC6909WithSupply.sol";
import {EnumerableMap} from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";

abstract contract ICollarPoolState {
    using EnumerableMap for EnumerableMap.AddressToUintMap;

    // represents one partitioned slice of the liquidity pool, its providers, and the amount they provide
    struct LiquiditySlot {
        uint256 liquidity;
        EnumerableMap.AddressToUintMap providers;
    }

    /// @notice Records the state of each slot (see LiquiditySlot struct above)
    mapping(uint256 slotId => LiquiditySlot slot) internal slots;

    // vToken = token representing an opened vault
    struct vToken {
        bool redeemable;
        uint256 totalRedeemableCash;
    }

    /// @notice Records the state of each vToken (see vToken struct above)
    mapping(bytes32 uuid => vToken vToken) public vTokens;
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

    constructor(address _engine, uint256 _tickScaleFactor, address _cashAsset) {
        tickScaleFactor = _tickScaleFactor;
        engine = _engine;
        cashAsset = _cashAsset;
    }

    /// @notice Gets the amount of liquidity in a particular slot
    /// @param slotIndex The index of the slot to get the state of
    function getSlotLiquidity(uint256 slotIndex) external virtual returns (uint256);

    /// @notice Gets the number of providers in a particular slot
    /// @param slotIndex The index of the slot to get the state of
    function getSlotProviderLength(uint256 slotIndex) external virtual returns (uint256);

    /// @notice Gets the address & liquidity amount of the provider at a particular index in a particular slot
    /// @param slotIndex The index of the slot to get the state of
    /// @param providerIndex The index of the provider to get the state of
    function getSlotProviderInfoAt(uint256 slotIndex, uint256 providerIndex) external virtual returns (address, uint256);

    /// @notice Gets the address & liquidity amount of the provider in a particular slot
    function getSlotProviderInfo(uint256 slotIndex, address provider) external virtual returns (uint256);

    /// @notice Adds liquidity to a given slot
    function addLiquidity(uint256 slot, uint256 amount) external virtual;

    /// @notice Removes liquidity from a given slot
    function removeLiquidity(uint256 slot, uint256 amount) external virtual;

    /// @notice Reallocates liquidity from one slot to another
    function reallocateLiquidity(uint256 sourceSlot, uint256 destinationSlot, uint256 amount) external virtual;

    /// @notice Allows a valid vault to pull liquidity from the pool on finalization
    function vaultPullLiquidity(bytes32 uuid, address receiver, uint256 amount) external virtual;

    /// @notice Allows a valid vault to push liquidity to the pool on finalization
    function vaultPushLiquidity(bytes32 uuid, address sender, uint256 amount) external virtual;

    /// @notice Allows a vault to mint tokens once liquidity is locked upon vault creation
    function mint(bytes32 uuid, uint256 slot, uint256 amount) external virtual;

    /// @notice Allows liquidity providers to redeem liquidity-pool tokens corresponding to a particular vault
    function redeem(bytes32 uuid, uint256 amount) external virtual;

    /// @notice Allows liquidity providers to preview the amount of cash they would receive upon redeeming for a particular vault token
    function previewRedeem(bytes32 uuid, uint256 amount) external virtual returns (uint256);
}
