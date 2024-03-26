// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

interface ICollarPoolEvents {
    
    // regular user actions
    event LiquidityAdded(address indexed provider, uint256 indexed slotIndex, uint256 liquidity);
    event LiquidityWithdrawn(address indexed provider, uint256 indexed slotIndex, uint256 liquidity);
    event LiquidityMoved(address indexed provider, uint256 indexed fromSlotIndex, uint256 indexed toSlotIndex, uint256 liquidity);
    event PositionOpened(address indexed provider, bytes32 indexed uuid, uint256 expiration, uint256 principal);
    event PositionFinalized(address indexed vaultManager, bytes32 indexed uuid, int256 positionNet);
    event Redemption(address indexed redeemer, bytes32 indexed uuid, uint256 amountRedeemed, uint256 amountReceived);

    // internal stuff that is good for us to emit
    event LiquidityProviderKicked(address indexed kickedProvider, uint256 indexed slotID, uint256 movedLiquidity);
    event PoolTokensIssued(address indexed provider, uint256 expiration, uint256 amount);
}
