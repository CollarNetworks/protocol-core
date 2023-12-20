// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

import { ERC6909 } from "@solmate/tokens/ERC6909.sol";

abstract contract ICollarPoolState {
    struct SlotState {
        uint256 liquidity;
        address[] providers;
        uint256[] amounts;
    }
}


abstract contract ICollarPool is ERC6909, ICollarPoolState {

    /// @notice This is the ID of the slot that is unallocated to any particular call strike percentage
    uint256 public constant UNALLOCATED_SLOT = type(uint256).max;

    /// @notice This is the factor by which the slot ID is scaled to get the actual bps value
    /// @dev A tick scale factor of 1 means that slot 10_000 = 100% = 1 bps per tick, and so on
    uint256 immutable public tickScaleFactor;

    /// @notice The address of the engine is set upon pool creation (and registered with the engine)
    address immutable public engine;

    /// @notice The address of the cash asset is set upon pool creation (and verified with the engine as allowed)
    address immutable public cashAsset;

    /// @notice Records whether or not a particular vault has minted tokens (only allowed once)
    mapping(bytes32 uuid => bool) public hasMinted;

    /// @notice Records whether or not a particular vault has been finalized (only allowed once)
    mapping(bytes32 uuid => bool vaultFinalized) public vaultStatus;
    
    /// @notice Records the state of each slot (see SlotState struct above)
    mapping(uint256 slotID => SlotState slot) public slots;

    /// @notice Records the total amount of liquidity in each slot
    mapping(uint256 slot => uint256 liquidity) public slotLiquidity;

    /// @notice Records the amount of liquidity provided by each provider in each slot
    mapping(address provider => mapping(uint256 slot => uint256 amount)) public providerLiquidityBySlot;

    /// @notice Records the total amount of tokens minted for each vault
    mapping(uint256 id => uint256) public totalTokenSupply;

    /// @notice Records the total amount of cash available for a corresponding vault token
    /// @dev Only set once vault is finalized
    mapping(bytes32 uuid => uint256 cash) public totalCashSupplyForToken;

    constructor(address _engine, uint256 _tickScaleFactor, address _cashAsset) {
        tickScaleFactor = _tickScaleFactor;
        engine = _engine;
        cashAsset = _cashAsset;
    }

    /// @notice Gets the state of a particular slot
    /// @param slotIndex The index of the slot to get the state of
    function getSlot(
        uint256 slotIndex
    ) external virtual returns (SlotState memory);

    /// @notice Adds liquidity to a given slot
    function addLiquidity(
        uint256 slot,
        uint256 amount
    ) external virtual;

    /// @notice Removes liquidity from a given slot
    function removeLiquidity(
        uint256 slot,
        uint256 amount
    ) external virtual;

    /// @notice Reallocates liquidity from one slot to another
    function reallocateLiquidity(
        uint256 sourceSlot,
        uint256 destinationSlot,
        uint256 amount
    ) external virtual;

    /// @notice Allows a valid vault to pull liquidity from the pool on finalization
    function vaultPullLiquidity(
        bytes32 uuid,
        address receiver,
        uint256 amount
    ) external virtual;

    /// @notice Allows a valid vault to push liquidity to the pool on finalization
    function vaultPushLiquidity(
        bytes32 uuid,
        address sender,
        uint256 amount
    ) external virtual;

    /// @notice Allows a vault to mint tokens once liquidity is locked upon vault creation
    function mint(
        bytes32 uuid, 
        uint256 slot, 
        uint256 amount
    ) external virtual;

    /// @notice Allows liquidity providers to redeem liquidity-pool tokens corresponding to a particular vault
    function redeem(
        bytes32 uuid, 
        uint256 amount
    ) external virtual;

    /// @notice Allows liquidity providers to preview the amount of cash they would receive upon redeeming for a particular vault token
    function previewRedeem(
        bytes32 uuid, 
        uint256 amount
    ) external virtual returns (uint256);

    /// @notice Allows valid valid to mark a vault as finalized
    function finalizeVault(
        bytes32 uuid
    ) external virtual;
}


