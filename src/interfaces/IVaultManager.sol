// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

import { Sweepable } from "../utils/Sweepable.sol";

abstract contract ICollarVaultManager is Sweepable {
    /// @notice Indicates that a vault has been opened
    event VaultOpened(bytes32 vaultId);

    /// @notice Indicates that a vault has been closed
    event VaultClosed(bytes32 vaultId);

    /// @notice Indicates that a loan withdrawal has been made
    event LoanWithdrawal(bytes32 vaultId, uint256 amount);

    /// @notice Indicates that a loan repayment has been made
    event LoanRepayment(bytes32 vaultId, uint256 amount);

    /// @notice Indicates that the vault specified does not exist
    error NonExistentVault(bytes32 vaultUUID);

    /// @notice Indicates that the caller is not the owner of the contract, but should be
    error NotOwner(address who);

    /// @notice Indicates that the ltv provided on vault open is not valid
    error InvalidLTV(uint256 providedLTV);

    /// @notice Indicates that the provided call and strike parameters on vault open are not valid
    error InvalidStrikeOpts(uint256 callStrike, uint256 putStrike);

    /// @notice Indicates that the provided call strike prarameter is not valid
    error InvalidCallStrike(uint256 callStrike);

    /// @notice Indicates that the provided put strike parameter is not valid
    error InvalidPutStrike(uint256 putStrike);

    /// @notice Indicates that there is not sufficient unlocked liquidity to open a vault with the provided parameters
    error InsufficientLiquidity(uint24 tick, uint256 amount, uint256 available);

    /// @notice Indicates that the ltv would be too low if the action were to be executed
    error ExceedsMinLTV(uint256 ltv, uint256 minLTV);

    /// @notice This struct contains information about which assests (and how much of them) are in each vault
    /// @param collateralAsset The address of the collateral asset
    /// @param collateralAmount The amount of the collateral asset
    /// @param cashAsset The address of the cash asset
    /// @param cashAmount The amount of the cash asset
    struct AssetSpecifiers {
        address collateralAsset;
        uint256 collateralAmount;
        address cashAsset;
        uint256 cashAmount;
    }

    /// @notice This struct contains information about the collar options for each vault
    /// @param putStrike The strike price of the put option expressed as bps of starting price
    /// @param callStrike The strike price of the call option expressed as bps of starting price
    /// @param expiry The expiry of the options express as a unix timestamp
    /// @param ltv The maximjum loan-to-value ratio of loans taken out of this vault, expressed as bps of the collateral value
    struct CollarOpts {
        uint256 putStrike;
        uint256 callStrike;
        uint256 expiry;
        uint256 ltv;
    }

    /// @notice This struct contains information about how to source the liquidity for each vault
    /// @param liquidityPool The address of the liquidity pool to draw from
    /// @param ticks The ticks from which to draw liquidity
    /// @param amounts The amounts of liquidity to draw from each tick
    struct LiquidityOpts {
        address liquidityPool;
        uint24[] ticks;
        uint256[] amounts;
    }

    /// @notice This struct represents each individual vault as a whole
    /// @dev We use a mapping below to store each vault by unique identifier (UUID)
    /// @param collateralAmountInitial The amount of collateral deposited into the vault at the time of creation
    /// @param collateralPriceInitial The price of the collateral asset at the time of creation
    /// @param withdrawn The amount of cash withdrawn as a loan
    /// @param maxWithdrawable The maximum amount of cash withdrawable as a loan
    /// @param nonWithdrawable The amount of cash that is not withdrawable as part of the loan
    /// @param active Whether or not the vault is active (if true, it has not been finalized)
    /// @param assetSpecifiers The asset specifiers for the vault
    /// @param collarOpts The collar options for the vault
    /// @param liquidityOpts The liquidity options for the vault
    struct Vault {
        uint256 collateralAmountInitial;
        uint256 collateralPriceInitial;
        uint256 collateralValueInitial;

        uint256 withdrawn;
        uint256 maxWithdrawable;
        uint256 nonWithdrawable;

        bool active;

        AssetSpecifiers assetSpecifiers;
        CollarOpts collarOpts;
        LiquidityOpts liquidityOpts;
    }

    /// @notice The maximum global ltv, not changeable; set to 100% for now (in bps)
    uint256 constant public MAX_LTV = 10_000;

    /// @notice The minimum call strike, not changeable; set to 150% for now (in bps)
    uint256 constant public MIN_CALL_STRIKE = 100_000;

    /// @notice The maximum put strike, not changeable; set to 100% for now (in bps)
    uint256 constant public MAX_PUT_STRIKE = 100_000;

    /// @notice The address of the collar engine, which is what creates the Vault Manager contract per user
    address immutable public engine;

    /// @notice The user that owns the vault
    address user;

    /// @notice The number of vaults a user has opened
    uint256 public vaultCount;

    /// @notice Retrieves the vault details by UUID
    mapping(bytes32 UUID => Vault) public vaultsByUUID;

    /// @notice Gives UUID of vault by index (order of creation)
    mapping(uint256 index => bytes32 UUID) public vaultUUIDsByIndex;

    /// @notice Reverse mapping of UUID to index
    mapping(bytes32 UUID => uint256 index) public vaultIndexByUUID;

    /// @notice Count of how many vaults have any particular token as cash
    mapping(address token => uint256 count) public tokenVaultCount;

    /// @notice Total balance of any particular token across all vaults (cash)
    mapping(address token => uint256 totalBalance) public tokenTotalBalance;

    constructor() {
        engine = msg.sender;
    }

    /// @notice Whether or not the vault has been finalized (requires a transaction)
    /// @param vaultUUID The UUID of the vault to check
    function isActive(bytes32 vaultUUID) external virtual view returns (bool);

    /// @notice Whether or not the vault CAN be finalized
    /// @param vaultUUID The UUID of the vault to check
    function isExpired(bytes32 vaultUUID) external virtual view returns (bool);

    /// @notice Unix timestamp of when the vault expires (or when it expired)
    /// @param vaultUUID The UUID of the vault to check
    function getExpiry(bytes32 vaultUUID) external virtual view returns (uint256);

    /// @notice Time remaining in seconds until the vault expires - 0 if already expired
    /// @param vaultUUID The UUID of the vault to check
    function timeRemaining(bytes32 vaultUUID) external virtual view returns (uint256);

    /// @notice Allows a user to deposit cash (repay their loan) into a particular vault
    /// @param vaultUUID The UUID of the vault to deposit into
    /// @param amount The amount of cash to deposit
    /// @param from The address to send the cash from
    function depositCash(bytes32 vaultUUID, uint256 amount, address from) external virtual returns (uint256);
    
    /// @notice Allows a user to withdraw cash (take out a loan) from a particular vault
    /// @param vaultUUID The UUID of the vault to withdraw from
    /// @param amount The amount of cash to withdraw
    /// @param to The address to send the cash to
    function withrawCash(bytes32 vaultUUID, uint256 amount, address to) external virtual returns (uint256);

    /// @notice Opens a vault with the given asset specifiers and collar options and liquidity sources, if possible
    /// @dev We'll need to make sure the frontend handles all the setup here and passes in correct options
    /// @param assetSpecifiers The asset specifiers for the vault
    /// @param collarOpts The collar options for the vault
    /// @param liquidityOpts The liquidity options for the vault
    function openVault(
        AssetSpecifiers calldata assetSpecifiers,
        CollarOpts calldata collarOpts,
        LiquidityOpts calldata liquidityOpts
    ) external virtual returns (bytes32);

    /// @notice Closes a vault and returns the collateral to the user or market maker
    /// @dev This function will revert if the vault is not finalizable
    /// @param vaultUUID The UUID of the vault to close
    function finalizeVault(
        bytes32 vaultUUID
    ) external virtual returns (int256);

    /// @notice Returns the bps of the LTV ratio of the vault
    /// @param vaultUUID The UUID of the vault to check
    function getLTV(bytes32 vaultUUID) public virtual view returns (uint256);

    /// @notice Returns the bps of the LTV ratio of the vault
    /// @param _vault The vault to check (as a storage reference)
    function getLTV(Vault storage _vault) internal virtual view returns (uint256);
}