// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

import { ICollarCommonErrors } from "./ICollarCommonErrors.sol";

interface ICollarPoolErrors is ICollarCommonErrors {
    error NotEnoughLiquidity();
}