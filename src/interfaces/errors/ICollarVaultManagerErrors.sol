// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

import { ICollarCommonErrors } from "./ICollarCommonErrors.sol";

interface ICollarVaultManagerErrors is ICollarCommonErrors {
    /// @notice Indicates that, upon attempting to open a vault, a trade was not able to be executed
    error TradeNotViable();

    /// @notice Indicates that the LTV parameter provided is not valid per the Engine
    error InvalidLTV();
}
