// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

import { SubdividedLiquidityPool } from "./SubdividedLiquidityPool.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC1155 } from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";

/// @notice This contract builds on top of the SubdividedLiquidityPool to allow for *allocated* liquidity
/// to be converted into ERC1155 tokens which represent the holder's "put" optionality in a vault. Aside from
/// the "burn" function (which allows users to redeem liquidity once applicable), all methods are called by
/// the Engine only. The Engine will call "mint" to lock liquidity at a given tick when a vault is opened, and
/// will adjust the amount of liquidity the tokens can be redeemed for at vault finalization.
/// @dev The token UUID created for each vault is the vault UUID itself
contract ConvertibleLiquidityPool is SubdividedLiquidityPool, ERC1155 {
    using EnumerableMap for EnumerableMap.AddressToUintMap;

    // ----- EVENTS & ERRORS ----- //

    error NotAuthorizedAsEngine();

    // ----- MODIFIERS ----- //

    modifier onlyEngine() {
        if (msg.sender != Engine) revert NotAuthorizedAsEngine();
        _;
    }

    // ----- CONSTANTS & STATE VARS ----- //

    address immutable Engine;

    /// @notice this mapping stores how vaulable the liquidity tokens are for each vault
    /// @dev the value will always be 1 for a non-closed vault, and once the vault is closed,
    /// can zero or greater depending on the outcome of the vault
    mapping(bytes32 tokenUUID => uint256 liquidityAvailable) public liquiditySupplyForToken;

    /// @notice tracks the total supply of each liquidity token
    mapping(uint256 tokenId => uint256 totalSupply) public totalSupply;

    /// @notice tracks the tick for each liquidity / vault UUID
    mapping(bytes32 tokenUUID => uint24 tick) public uuidToTick;

    constructor(address _engine, address _asset, uint256 _scaleFactor) 
        SubdividedLiquidityPool(_asset, _scaleFactor) 
        ERC1155("Collar Liquidity Pool") {
        Engine = _engine;
    }

    // ----- PUBLIC AUTHED STATE CHANGING FUNCTIONS ----- //

    /// @notice applies a delta to the amount of liquidity corresponding to a given token
    /// @dev should only be callable by a vault via the engine
    /// @param tokenUUID the UUID of the token to apply the delta to (also the vault UUID)
    /// @param delta the amount to adjust the liquidity by
    function applyLiquidityDeltaForToken(bytes32 tokenUUID, int256 delta) public virtual onlyEngine {
        liquiditySupplyForToken[tokenUUID] = uint256(int256(liquiditySupplyForToken[tokenUUID]) + delta);
    }

    // ----- PUBLIC STATE CHANGING FUNCTIONS ----- //

    /// @notice locks liquidity at a given tick and mints "put" option tokens for locked liquidity
    /// @param uuid the UUID of the vault to mint tokens for (also the token UUID)
    /// @param tick the tick to lock liquidity at
    function mint(bytes32 uuid, uint256 amountToLock, uint24 tick) public virtual onlyEngine {
        uint256 tickTotalLiquidity = liquidityAtTick[tick];

        // cache liquidity provider amounts
        address[] memory providers = liquidity[tick].keys();

        // build an array of how much to lock for each liquidity provider
        uint256[] memory amountsToLock = new uint256[](providers.length);

        // calculate proportional contribution amounts for each liquidity provider
        // and decrement their liquidity balance
        for (uint256 i = 0; i < providers.length; i++) {
            address provider = providers[i];
            uint256 providerLiquidity = liquidity[tick].get(provider);
            uint256 providerLiquidityToLock = ((providerLiquidity * amountToLock * 1e18) / tickTotalLiquidity) / 1e18;

            liquidity[tick].set(provider, providerLiquidity - providerLiquidityToLock);

            amountsToLock[i] = providerLiquidityToLock;
        }

        // update the tick-global liquidity balance
        liquidityAtTick[tick] -= amountToLock;

        // mint liquidity tokens for each provider
        for (uint256 i = 0; i < providers.length; i++) {
            _mint(providers[i], uint256(uuid), amountsToLock[i], "");
        }

        // set the amount of liquidity that this token is redeeamble for (in relation to the total supply)
        liquiditySupplyForToken[uuid] = amountToLock;
    }

    /// @notice redeems liquidity tokens for the underlying cash asset, "unlocking" the liquidity
    /// @param uuid the UUID of the vault to redeem liquidity for (also the token UUID)
    /// @param amount the amount of liquidity tokens to redeem
    function burn(bytes32 uuid, uint256 amount) public {
        _burn(msg.sender, uint256(uuid), amount);

        // grab the total supply of the liquidity token for this vault
        uint256 totalRedeemTokenSupply = totalSupply[uint256(uuid)];

        // grab the total amount of liquidity available for this liquidity token
        uint256 totalLiquidtyAvailable = liquiditySupplyForToken[uuid];

        // calculate the amount of liquidity that the provided amount of tokens redeems for
        uint256 liquidityRedeemed = ((amount * totalLiquidtyAvailable * 1e18) / totalRedeemTokenSupply) / 1e18;

        // grab the tick that this token applies to
        uint24 tick = uuidToTick[uuid];

        // increment the balance of the redeemer
        liquidity[tick].set(msg.sender, liquidity[tick].get(msg.sender) + liquidityRedeemed);

        // increment the balance of the tick
        liquidityAtTick[tick] += liquidityRedeemed;
    }

    // ----- PRIVATE / INTERNAL FUNCTIONS ----- //

    /// @dev We override _mint (and also _burn) to track total supply of each token (not implemented by default for ERC1155)
    function _mint(address account, uint256 id, uint256 amount, bytes memory data) internal virtual override {
        super._mint(account, id, amount, data);

        totalSupply[id] += amount;
    }

    /// @dev We override _burn (and also _mint) to track total supply of each token (not implemented by default for ERC1155)
    function _burn(address account, uint256 id, uint256 amount) internal virtual override {
        super._burn(account, id, amount);

        totalSupply[id] -= amount;
    }
}