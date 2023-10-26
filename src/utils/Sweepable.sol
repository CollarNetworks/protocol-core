// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

import { StandardConstants } from "../utils/StandardConstants.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice This contract provides a way to sweep tokens to a destination
/// @dev This contract is abstract and should be inherited; you must implement canSweep
abstract contract Sweepable is StandardConstants {
    error NotSweepable(address token, address destination, uint256 amount);

    /// @notice Determines if the caller can transfer amount of token to destination, otherwise reverts
    /// @dev This should be overriden in whatever contract it is inherited in
    /// @param caller The address of the caller
    /// @param token The address of the token to sweep
    /// @param destination The address of the destination to sweep to
    /// @param amount The amount of the token to sweep
    function canSweep(address caller, address token, address destination, uint256 amount) public virtual view returns (bool);

    /// @notice Transfers amount of token to destination
    /// @dev Uses the proposed EIP-7528 0xEeeeEEeeEEeee convention to indicate ETH
    /// @param token The address of the token to sweep
    /// @param destination The address of the destination to sweep to
    /// @param amount The amount of the token to sweep
    function sweep(address token, address destination, uint256 amount) public {
        if (!canSweep(msg.sender, token, destination, amount)) revert NotSweepable(token, destination, amount);

        if (token == ADDRESS_ETH) {
            payable(destination).transfer(amount);
        } else {
            IERC20(token).transfer(destination, amount);
        }
    }
}