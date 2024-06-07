// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

import { ICollarPoolErrors } from "./errors/ICollarPoolErrors.sol";
import { ERC6909TokenSupply } from "@erc6909/ERC6909TokenSupply.sol";
import { EnumerableMap } from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

interface ICollarPool is ICollarPoolErrors {
    // ----- EVENTS ----- //

    // regular user actions
    event LiquidityAdded(address indexed provider, uint256 indexed slotIndex, uint256 liquidity);
    event LiquidityWithdrawn(address indexed provider, uint256 indexed slotIndex, uint256 liquidity);
    event LiquidityMoved(
        address indexed provider,
        uint256 indexed fromSlotIndex,
        uint256 indexed toSlotIndex,
        uint256 liquidity
    );
    event PositionOpened(
        address indexed provider, bytes32 indexed uuid, uint256 expiration, uint256 principal
    );
    event PositionFinalized(address indexed vaultManager, bytes32 indexed uuid, int256 positionNet);
    event Redemption(
        address indexed redeemer, bytes32 indexed uuid, uint256 amountRedeemed, uint256 amountReceived
    );

    // internal stuff that is good for us to emit
    event LiquidityProviderKicked(
        address indexed kickedProvider, uint256 indexed slotID, uint256 movedLiquidity
    );
    event PoolTokensIssued(address indexed provider, uint256 expiration, uint256 amount);

    // ----- VIEW FUNCTIONS ----- //

    /// @notice Gets the ids of initialized slots
    function getInitializedSlotIndices() external view virtual returns (uint256[] calldata);

    /// @notice Gets the liquidity for a set of slots
    /// @param slotIndices The indices of the slots to get the liquidity for
    function getLiquidityForSlots(uint256[] calldata slotIndices)
        external
        view
        virtual
        returns (uint256[] calldata amounts);

    /// @notice Gets the amount of liquidity in a particular slot
    /// @param slotIndex The index of the slot to get the state of
    function getLiquidityForSlot(uint256 slotIndex) external virtual returns (uint256 amount);

    /// @notice Gets the number of providers in a particular slot
    /// @param slotIndex The index of the slot to get the state of
    function getNumProvidersInSlot(uint256 slotIndex) external virtual returns (uint256 amount);

    /// @notice Gets the address & free liquidity amount of the provider at a particular index in a particular
    /// slot
    /// @param slotIndex The index of the slot to get the state of
    /// @param providerIndex The index of the provider to get the state of within the overall slot
    function getSlotProviderInfoAtIndex(
        uint256 slotIndex,
        uint256 providerIndex
    )
        external
        virtual
        returns (address provider, uint256 amount);

    /// @notice Gets the free liquidity amount of the specified provider in a particular slot
    /// @param slotIndex The index of the slot to get the state of
    /// @param provider The address of the provider to get the state of within the overall slot
    function getSlotProviderInfoForAddress(
        uint256 slotIndex,
        address provider
    )
        external
        virtual
        returns (uint256 amount);

    /// @notice Allows previewing of what would be received when redeeming an amount of token for a Position
    /// @param uuid The unique identifier of the position, corresponds to the UUID of the vault
    /// @param amount The amount of liquidity to redeem
    function previewRedeem(bytes32 uuid, uint256 amount) external virtual returns (uint256);

    // ----- STATE CHANGING FUNCTIONS ----- //

    /// @notice Adds liquidity to a given slot
    /// @param slot The index of the slot to add liquidity to
    /// @param amount The amount of liquidity to add
    function addLiquidityToSlot(uint256 slot, uint256 amount) external virtual;

    /// @notice Removes liquidity from a given slot
    /// @param slot The index of the slot to remove liquidity from
    /// @param amount The amount of liquidity to remove
    function withdrawLiquidityFromSlot(uint256 slot, uint256 amount) external virtual;

    /// @notice Reallocates free liquidity from one slot to another
    /// @param source The index of the slot to remove liquidity from
    /// @param destination The index of the slot to add liquidity to
    /// @param amount The amount of liquidity to reallocate
    function moveLiquidityFromSlot(uint256 source, uint256 destination, uint256 amount) external virtual;

    /// @notice Opens a new position (collar) in the pool (called by the vault manager)
    /// @param uuid The unique identifier of the position, corresponds to the UUID of the vault
    /// @param slotIndex The index of the slot to open the position in in the pool
    /// @param amount The amount of liquidity to open the position with
    /// @param expiration The expiration timestamp of the position
    function openPosition(
        bytes32 uuid,
        uint256 slotIndex,
        uint256 amount,
        uint256 expiration
    )
        external
        virtual;

    /// @notice Allows the engine to finalize a position & mark as redeemable
    /// @dev Internally, the positionNet param allows us to decide whether or not to push or pull from a vault
    /// @param uuid The unique identifier of the position, corresponds to the UUID of the vault
    /// @param vaultManager The address of the vault manager
    /// @param positionNet The net pnl of the position, from the perspective of the vault
    function finalizePosition(bytes32 uuid, address vaultManager, int256 positionNet) external virtual;

    /// @notice Allows liquidity providers to redeem tokens corresponding to a particular Position
    /// @param uuid The unique identifier of the position, corresponds to the UUID of the vault
    /// @param amount The amount of liquidity to redeem
    function redeem(bytes32 uuid, uint256 amount) external virtual;
}
