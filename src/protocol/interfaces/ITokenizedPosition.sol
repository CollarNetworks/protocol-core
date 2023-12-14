// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;


interface ITokenizedPosition {


    function mint(bytes32, uint256, uint24) external;
    function burn(bytes32, uint256) external;
}

// function mint(bytes32 uuid, uint256 amountToLock, uint24 tick)
// function burn(bytes32 uuid, uint256 amount)