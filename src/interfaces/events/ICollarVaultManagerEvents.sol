// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

interface ICollarVaultManagerEvents {
    // regular user actions
    event VaultOpened(address indexed user, address indexed vaultManager, bytes32 indexed uuid);
    event VaultClosed(address indexed user, address indexed vaultManager, bytes32 indexed uuid);
    event Redemption(address indexed redeemer, bytes32 indexed uuid, uint256 amountRedeemed, uint256 amountReceived);
    event Withdrawal(
        address indexed user, address indexed vaultManager, bytes32 indexed uuid, uint256 amountWithdrawn, uint256 amountRemaining
    );
}
