// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity 0.8.22;

import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IPeripheryImmutableState } from
    "@uniswap/v3-periphery/contracts/interfaces/IPeripheryImmutableState.sol";
// internal imports
import { ICollarEngine } from "../interfaces/ICollarEngine.sol";
import { CollarPool } from "./CollarPool.sol";
import { CollarVaultManager } from "./CollarVaultManager.sol";
import { UniV3OracleLib } from "../libs/UniV3OracleLib.sol";

import "forge-std/console.sol";

contract CollarEngine is Ownable, ICollarEngine {
    // -- lib delcarations --
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.UintSet;

    // -- public state variables ---

    string public constant VERSION = "0.2.0";

    address public immutable univ3SwapRouter;

    uint public constant TWAP_BASE_TOKEN_AMOUNT = uint(UniV3OracleLib.BASE_TOKEN_AMOUNT);

    /// @notice This mapping stores the address of the vault contract per user (or market maker)
    /// @dev This will be zero if the user has not yet created a vault
    mapping(address => address) public addressToVaultManager;

    // -- internal state variables ---
    EnumerableSet.AddressSet internal vaultManagers;
    EnumerableSet.AddressSet internal collarLiquidityPools;
    EnumerableSet.AddressSet internal supportedCollateralAssets;
    EnumerableSet.AddressSet internal supportedCashAssets;
    EnumerableSet.UintSet internal validLTVs;
    EnumerableSet.UintSet internal validCollarDurations;

    mapping(address contractAddress => bool enabled) public isBorrowNFT;
    mapping(address contractAddress => bool enabled) public isProviderNFT;

    constructor(address _univ3SwapRouter) Ownable(msg.sender) {
        univ3SwapRouter = _univ3SwapRouter;
    }

    // ----- state-changing functions (see ICollarEngine for documentation) -----

    function setBorrowContractAuth(address contractAddress, bool enabled) external onlyOwner {
        isBorrowNFT[contractAddress] = enabled;
        emit BorrowNFTAuthSet(contractAddress, enabled);
    }

    function setProviderContractAuth(address contractAddress, bool enabled) external onlyOwner {
        isProviderNFT[contractAddress] = enabled;
        emit ProviderNFTAuthSet(contractAddress, enabled);
    }

    function createVaultManager() external override returns (address _vaultManager) {
        require(addressToVaultManager[msg.sender] == address(0), "manager exists for sender");

        address vaultManager = address(new CollarVaultManager(address(this), msg.sender));

        vaultManagers.add(vaultManager);
        addressToVaultManager[msg.sender] = vaultManager;

        emit VaultManagerCreated(vaultManager, msg.sender);

        return vaultManager;
    }

    // liquidity pools

    function addLiquidityPool(address pool) external override onlyOwner {
        require(!collarLiquidityPools.contains(pool), "already added");
        collarLiquidityPools.add(pool);
        emit LiquidityPoolAdded(pool);
    }

    function removeLiquidityPool(address pool) external override onlyOwner {
        require(collarLiquidityPools.contains(pool), "not found");
        collarLiquidityPools.remove(pool);
        emit LiquidityPoolRemoved(pool);
    }

    // collateral assets

    function addSupportedCollateralAsset(address asset) external override onlyOwner {
        require(!supportedCollateralAssets.contains(asset), "already added");
        supportedCollateralAssets.add(asset);
        emit CollateralAssetAdded(asset);
    }

    function removeSupportedCollateralAsset(address asset) external override onlyOwner {
        require(supportedCollateralAssets.contains(asset), "not found");
        supportedCollateralAssets.remove(asset);
        emit CollateralAssetRemoved(asset);
    }

    // cash assets

    function addSupportedCashAsset(address asset) external override onlyOwner {
        require(!supportedCashAssets.contains(asset), "already added");
        supportedCashAssets.add(asset);
        emit CashAssetAdded(asset);
    }

    function removeSupportedCashAsset(address asset) external override onlyOwner {
        require(supportedCashAssets.contains(asset), "not found");
        supportedCashAssets.remove(asset);
        emit CashAssetRemoved(asset);
    }

    // durations

    function addCollarDuration(uint duration) external override onlyOwner {
        require(!validCollarDurations.contains(duration), "already added");
        validCollarDurations.add(duration);
        emit CollarDurationAdded(duration);
    }

    function removeCollarDuration(uint duration) external override onlyOwner {
        require(validCollarDurations.contains(duration), "not found");
        validCollarDurations.remove(duration);
        emit CollarDurationRemoved(duration);
    }

    // ltvs

    function addLTV(uint ltv) external override onlyOwner {
        require(!validLTVs.contains(ltv), "already added");
        validLTVs.add(ltv);
        emit LTVAdded(ltv);
    }

    function removeLTV(uint ltv) external override onlyOwner {
        require(validLTVs.contains(ltv), "not found");
        validLTVs.remove(ltv);
        emit LTVRemoved(ltv);
    }

    // ----- view functions (see ICollarEngine for documentation) -----

    // vault managers

    function isVaultManager(address vaultManager) external view override returns (bool) {
        return vaultManagers.contains(vaultManager);
    }

    function vaultManagersLength() external view override returns (uint) {
        return vaultManagers.length();
    }

    function getVaultManager(uint index) external view override returns (address) {
        return vaultManagers.at(index);
    }

    // cash assets

    function isSupportedCashAsset(address asset) public view override returns (bool) {
        return supportedCashAssets.contains(asset);
    }

    function supportedCashAssetsLength() external view override returns (uint) {
        return supportedCashAssets.length();
    }

    function getSupportedCashAsset(uint index) external view override returns (address) {
        return supportedCashAssets.at(index);
    }

    // collateral assets

    function isSupportedCollateralAsset(address asset) public view override returns (bool) {
        return supportedCollateralAssets.contains(asset);
    }

    function supportedCollateralAssetsLength() external view override returns (uint) {
        return supportedCollateralAssets.length();
    }

    function getSupportedCollateralAsset(uint index) external view override returns (address) {
        return supportedCollateralAssets.at(index);
    }

    // liquidity pools

    function isSupportedLiquidityPool(address pool) external view override returns (bool) {
        return collarLiquidityPools.contains(pool);
    }

    function supportedLiquidityPoolsLength() external view override returns (uint) {
        return collarLiquidityPools.length();
    }

    function getSupportedLiquidityPool(uint index) external view override returns (address) {
        return collarLiquidityPools.at(index);
    }

    // collar durations

    function isValidCollarDuration(uint duration) external view override returns (bool) {
        return validCollarDurations.contains(duration);
    }

    function validCollarDurationsLength() external view override returns (uint) {
        return validCollarDurations.length();
    }

    function getValidCollarDuration(uint index) external view override returns (uint) {
        return validCollarDurations.at(index);
    }

    // ltvs

    function isValidLTV(uint ltv) external view override returns (bool) {
        return validLTVs.contains(ltv);
    }

    function validLTVsLength() external view override returns (uint) {
        return validLTVs.length();
    }

    function getValidLTV(uint index) external view override returns (uint) {
        return validLTVs.at(index);
    }

    // asset pricing

    function validateAssetsIsSupported(address token) internal view {
        bool isSupportedBase = isSupportedCashAsset(token) || isSupportedCollateralAsset(token);
        require(isSupportedBase, "not supported");
    }

    function getHistoricalAssetPriceViaTWAP(
        address baseToken,
        address quoteToken,
        uint32 twapEndTimestamp,
        uint32 twapLength
    ) external view virtual override returns (uint price) {
        validateAssetsIsSupported(baseToken);
        validateAssetsIsSupported(quoteToken);
        address uniV3Factory = IPeripheryImmutableState(univ3SwapRouter).factory();
        price = UniV3OracleLib.getTWAP(baseToken, quoteToken, twapEndTimestamp, twapLength, uniV3Factory);
    }
}
