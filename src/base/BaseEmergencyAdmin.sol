// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity 0.8.22;

import { Ownable2Step, Ownable } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
// internal
import { ConfigHub } from "../ConfigHub.sol";

abstract contract BaseEmergencyAdmin is Ownable, Pausable {
    ConfigHub public configHub;

    constructor(address _initialOwner, ConfigHub _configHub) Ownable(_initialOwner) {
        configHub = _configHub;
    }

    // ----- MUTATIVE ----- //

    // ----- owner ----- //

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    // TODO: test and doc
    function setConfigHub() public onlyOwner { }

    // TODO: test and doc
    function rescueTokens(address token, uint amountOrId) public onlyOwner { }

    // ----- Non-owner ----- //

    // TODO: test and doc
    function pauseFromGuardian() public { }
}
