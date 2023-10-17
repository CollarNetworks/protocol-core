// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

import {ICollarVault} from "./IVault.sol";

abstract contract IRollableVault is ICollarVault {
    /// @todo: functions that enable this vault to be rolled
}