// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";

interface SubdividedLiquidityPoolErrors {
    /// @notice Indicates that the sender does not have sufficient balance to withdraw
    error InsufficientBalance();
}

contract SubdividedLiquidityPool {
    using EnumerableMap for EnumerableMap.AddressToUintMap;

    // ----- CONSTANTS & STATE VARS ----- //

    uint256 constant MaxProvidersPerTick = 7;

    // the scale factor for this liquidity pool
    uint256 public immutable scaleFactor;

    // the asset that this liquidity pool is for
    address public immutable asset;

    // this data structure holds the amount of liquidity provided by each address at each tick
    // we use OpenZeppelin's EnumerableMap to allow for iteration over the addresses
    mapping(uint24 tick => EnumerableMap.AddressToUintMap amountsByAddress) internal liquidity;

    // tracks total liquidity at each tick
    mapping(uint24 => uint256) public liquidityAtTick;

    // tracks liquidity not allocated to a tick but owned by an address
    mapping(address => uint256) public unallocated;

    constructor(address _asset, uint256 _scaleFactor) {
        scaleFactor = _scaleFactor;
        asset = _asset;
    }

    // ----- PUBLIC STATE CHANGING FUNCTIONS ----- //

    function deposit(uint256 amountFromSender, uint256 amountFromUnallocated, uint24 tick) public virtual {
        // cache the total amount the sender wants to deposit
        uint256 total = amountFromSender + amountFromUnallocated;
        
        // ensure the sender has enough in their alocated balance to cover the amount indicated
        // and decrement their unallocated balance if they do have enough
        if (amountFromUnallocated > 0) {
            if (unallocated[msg.sender] < amountFromUnallocated) { revert SubdividedLiquidityPoolErrors.InsufficientBalance(); }
            else { unallocated[msg.sender] -= amountFromUnallocated; }
        }
        
        // if provider isn't an active market maker, ensure that their balance after deposit
        // would be greater than the current smallest market maker balance
        (bool active, uint256 currentBalance) = liquidity[tick].tryGet(msg.sender);

        if (!active) {
            uint256 smallestBalance = type(uint256).max;
            address smallestAddress = address(0);

            address[] memory providers = liquidity[tick].keys();

            if (liquidity[tick].length() == MaxProvidersPerTick){
                
                // iterate and find the smallest balance of the smallest market maker
                for (uint256 i = 0; i < providers.length; i++) {
                    address provider = providers[i];
                    uint256 providerBalance = liquidity[tick].get(provider);

                    if (providerBalance < smallestBalance) {
                        smallestBalance = providerBalance;
                        smallestAddress = provider;
                    }
                }

            }

            // if the smallest balance is greater than the amount being deposited, revert
            if (smallestBalance > total) { revert SubdividedLiquidityPoolErrors.InsufficientBalance(); }

            // kick out the smallest provider
            liquidity[tick].remove(smallestAddress);
            unallocated[smallestAddress] += smallestBalance;

            // add the new provider
            liquidity[tick].set(msg.sender, total);

        } else {
            // the provider is already active, so just update their balance
            liquidity[tick].set(msg.sender, currentBalance + total);
        }

        // transfer in the asset
        if (amountFromSender > 0) { IERC20(asset).transferFrom(msg.sender, address(this), amountFromSender); }

        // update the amount of liquidity at this tick
        liquidityAtTick[tick] += total;
    }

    /// @notice Withdraw liquidity from the pool at the given tick
    function withdraw(uint256 amount, uint24 tick) public virtual {
        // update the amount of liquidity available at this tick for the withdrawer
        (bool exists, uint256 currentAmount) = liquidity[tick].tryGet(msg.sender);
        if (!exists || currentAmount < amount) { revert SubdividedLiquidityPoolErrors.InsufficientBalance(); }
        else { liquidity[tick].set(msg.sender, currentAmount - amount); }

        // update the amount of liquidity at this tick
        liquidityAtTick[tick] -= amount;

        // transfer out the asset
        IERC20(asset).transfer(msg.sender, amount);
    }

    /// @notice Withdraw liquidity from the pool from the unallocated balance
    function withdraw(uint256 amount) public virtual {
        // update the amount of liquidity available for the withdrawer
        if (unallocated[msg.sender] < amount) { revert SubdividedLiquidityPoolErrors.InsufficientBalance(); }
        else { unallocated[msg.sender] -= amount; }

        // transfer out the asset
        IERC20(asset).transfer(msg.sender, amount);
    }

    /// @notice Moves liquidity from a specific tick to the unallocated pool
    function unallocate(uint24 tick, uint256 amount) public virtual {
        // update the amount of liquidity available at this tick for the withdrawer
        (bool exists, uint256 currentAmount) = liquidity[tick].tryGet(msg.sender);
        if (!exists || currentAmount < amount) { revert SubdividedLiquidityPoolErrors.InsufficientBalance(); }
        else { liquidity[tick].set(msg.sender, currentAmount - amount); }

        // update the amount of liquidity at this tick
        liquidityAtTick[tick] -= amount;

        // update the unallocated balance
        unallocated[msg.sender] += amount;
    }
}