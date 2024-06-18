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
    event LiquidityAdded(address indexed provider, uint indexed slotIndex, uint liquidity);
    event LiquidityWithdrawn(address indexed provider, uint indexed slotIndex, uint liquidity);
    event LiquidityMoved(
        address indexed provider, uint indexed fromSlotIndex, uint indexed toSlotIndex, uint liquidity
    );
    event PositionOpened(address indexed provider, bytes32 indexed uuid, uint expiration, uint principal);
    event PositionFinalized(address indexed vaultManager, bytes32 indexed uuid, int positionNet);
    event Redemption(
        address indexed redeemer, bytes32 indexed uuid, uint amountRedeemed, uint amountReceived
    );

    // internal stuff that is good for us to emit
    event LiquidityProviderKicked(address indexed kickedProvider, uint indexed slotID, uint movedLiquidity);
    event PoolTokensIssued(address indexed provider, uint expiration, uint amount);

    // ----- VIEW FUNCTIONS ----- //

    /// @notice Gets the ids of initialized slots
    function getInitializedSlotIndices() external view returns (uint[] calldata);

    /// @notice Gets the liquidity for a set of slots
    /// @param slotIndices The indices of the slots to get the liquidity for
    function getLiquidityForSlots(uint[] calldata slotIndices)
        external
        view
        returns (uint[] calldata amounts);

    /// @notice Gets the amount of liquidity in a particular slot
    /// @param slotIndex The index of the slot to get the state of
    function getLiquidityForSlot(uint slotIndex) external returns (uint amount);

    /// @notice Gets the number of providers in a particular slot
    /// @param slotIndex The index of the slot to get the state of
    function getNumProvidersInSlot(uint slotIndex) external returns (uint amount);

    /// @notice Gets the address & free liquidity amount of the provider at a particular index in a particular
    /// slot
    /// @param slotIndex The index of the slot to get the state of
    /// @param providerIndex The index of the provider to get the state of within the overall slot
    function getSlotProviderInfoAtIndex(uint slotIndex, uint providerIndex)
        external
        returns (address provider, uint amount);

    /// @notice Gets the free liquidity amount of the specified provider in a particular slot
    /// @param slotIndex The index of the slot to get the state of
    /// @param provider The address of the provider to get the state of within the overall slot
    function getSlotProviderInfoForAddress(uint slotIndex, address provider) external returns (uint amount);

    /// @notice Allows previewing of what would be received when redeeming an amount of token for a Position
    /// @param uuid The unique identifier of the position, corresponds to the UUID of the vault
    /// @param amount The amount of liquidity to redeem
    function previewRedeem(bytes32 uuid, uint amount) external returns (uint);

    // ----- STATE CHANGING FUNCTIONS ----- //

    /// @notice Adds liquidity to a given slot
    /// @param slot The index of the slot to add liquidity to
    /// @param amount The amount of liquidity to add
    function addLiquidityToSlot(uint slot, uint amount) external;

    /// @notice Removes liquidity from a given slot
    /// @param slot The index of the slot to remove liquidity from
    /// @param amount The amount of liquidity to remove
    function withdrawLiquidityFromSlot(uint slot, uint amount) external;

    /// @notice Reallocates free liquidity from one slot to another
    /// @param source The index of the slot to remove liquidity from
    /// @param destination The index of the slot to add liquidity to
    /// @param amount The amount of liquidity to reallocate
    function moveLiquidityFromSlot(uint source, uint destination, uint amount) external;

    /// @notice Opens a new position (collar) in the pool (called by the vault manager)
    /// @param uuid The unique identifier of the position, corresponds to the UUID of the vault
    /// @param slotIndex The index of the slot to open the position in in the pool
    /// @param amount The amount of liquidity to open the position with
    /// @param expiration The expiration timestamp of the position
    function openPosition(bytes32 uuid, uint slotIndex, uint amount, uint expiration) external;

    /// @notice Allows the engine to finalize a position & mark as redeemable
    /// @dev Internally, the positionNet param allows us to decide whether or not to push or pull from a vault
    /// @param uuid The unique identifier of the position, corresponds to the UUID of the vault
    /// @param vaultManager The address of the vault manager
    /// @param positionNet The net pnl of the position, from the perspective of the vault
    function finalizePosition(bytes32 uuid, address vaultManager, int positionNet) external;

    /// @notice Allows liquidity providers to redeem tokens corresponding to a particular Position
    /// @param uuid The unique identifier of the position, corresponds to the UUID of the vault
    /// @param amount The amount of liquidity to redeem
    function redeem(bytes32 uuid, uint amount) external;
}
