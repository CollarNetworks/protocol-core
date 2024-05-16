// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { ICollarEngine } from "../interfaces/ICollarEngine.sol";
import { ICollarEngineEvents } from "../interfaces/events/ICollarEngineEvents.sol";
import { CollarPool } from "./CollarPool.sol";
import { CollarVaultManager } from "./CollarVaultManager.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import { PoolAddress } from "@uniswap/v3-periphery/contracts/libraries/PoolAddress.sol";
import { OracleLibrary } from "@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol";
import "forge-std/console.sol";

contract CollarEngine is ICollarEngine, Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.UintSet;

    constructor(address _dexRouter, address _uniswapV3Factory) ICollarEngine(_dexRouter, _uniswapV3Factory) Ownable(msg.sender) { }

    // ----- state-changing functions (see ICollarEngine for documentation) -----

    function createVaultManager() external override returns (address _vaultManager) {
        if (addressToVaultManager[msg.sender] != address(0)) {
            revert VaultManagerAlreadyExists(msg.sender, addressToVaultManager[msg.sender]);
        }

        address vaultManager = address(new CollarVaultManager(address(this), msg.sender));

        vaultManagers.add(vaultManager);
        addressToVaultManager[msg.sender] = vaultManager;

        emit VaultManagerCreated(vaultManager, msg.sender);

        return vaultManager;
    }

    // liquidity pools

    function addLiquidityPool(address pool) external override onlyOwner ensureLiquidityPoolIsNotValid(pool) {
        emit LiquidityPoolAdded(pool);
        collarLiquidityPools.add(pool);
    }

    function removeLiquidityPool(address pool) external override onlyOwner ensureLiquidityPoolIsValid(pool) {
        emit LiquidityPoolRemoved(pool);
        collarLiquidityPools.remove(pool);
    }

    // collateral assets

    function addSupportedCollateralAsset(address asset) external override onlyOwner ensureCollateralAssetIsNotValid(asset) {
        emit CollateralAssetAdded(asset);
        supportedCollateralAssets.add(asset);
    }

    function removeSupportedCollateralAsset(address asset) external override onlyOwner ensureCollateralAssetIsValid(asset) {
        emit CollateralAssetRemoved(asset);
        supportedCollateralAssets.remove(asset);
    }

    // cash assets

    function addSupportedCashAsset(address asset) external override onlyOwner ensureCashAssetIsNotValid(asset) {
        emit CashAssetAdded(asset);
        supportedCashAssets.add(asset);
    }

    function removeSupportedCashAsset(address asset) external override onlyOwner ensureCashAssetIsValid(asset) {
        emit CashAssetRemoved(asset);
        supportedCashAssets.remove(asset);
    }

    // durations

    function addCollarDuration(uint256 duration) external override onlyOwner ensureDurationIsNotValid(duration) {
        emit CollarDurationAdded(duration);
        validCollarDurations.add(duration);
    }

    function removeCollarDuration(uint256 duration) external override onlyOwner ensureDurationIsValid(duration) {
        emit CollarDurationRemoved(duration);
        validCollarDurations.remove(duration);
    }

    // ltvs

    function addLTV(uint256 ltv) external override onlyOwner ensureLTVIsNotValid(ltv) {
        emit LTVAdded(ltv);
        validLTVs.add(ltv);
    }

    function removeLTV(uint256 ltv) external override onlyOwner ensureLTVIsValid(ltv) {
        emit LTVRemoved(ltv);
        validLTVs.remove(ltv);
    }

    // ----- view functions (see ICollarEngine for documentation) -----

    // vault managers

    function isVaultManager(address vaultManager) external view override returns (bool) {
        return vaultManagers.contains(vaultManager);
    }

    function vaultManagersLength() external view override returns (uint256) {
        return vaultManagers.length();
    }

    function getVaultManager(uint256 index) external view override returns (address) {
        return vaultManagers.at(index);
    }

    // cash assets

    function isSupportedCashAsset(address asset) external view override returns (bool) {
        return supportedCashAssets.contains(asset);
    }

    function supportedCashAssetsLength() external view override returns (uint256) {
        return supportedCashAssets.length();
    }

    function getSupportedCashAsset(uint256 index) external view override returns (address) {
        return supportedCashAssets.at(index);
    }

    // collateral assets

    function isSupportedCollateralAsset(address asset) external view override returns (bool) {
        return supportedCollateralAssets.contains(asset);
    }

    function supportedCollateralAssetsLength() external view override returns (uint256) {
        return supportedCollateralAssets.length();
    }

    function getSupportedCollateralAsset(uint256 index) external view override returns (address) {
        return supportedCollateralAssets.at(index);
    }

    // liquidity pools

    function isSupportedLiquidityPool(address pool) external view override returns (bool) {
        return collarLiquidityPools.contains(pool);
    }

    function supportedLiquidityPoolsLength() external view override returns (uint256) {
        return collarLiquidityPools.length();
    }

    function getSupportedLiquidityPool(uint256 index) external view override returns (address) {
        return collarLiquidityPools.at(index);
    }

    // collar durations

    function isValidCollarDuration(uint256 duration) external view override returns (bool) {
        return validCollarDurations.contains(duration);
    }

    function validCollarDurationsLength() external view override returns (uint256) {
        return validCollarDurations.length();
    }

    function getValidCollarDuration(uint256 index) external view override returns (uint256) {
        return validCollarDurations.at(index);
    }

    // ltvs

    function isValidLTV(uint256 ltv) external view override returns (bool) {
        return validLTVs.contains(ltv);
    }

    function validLTVsLength() external view override returns (uint256) {
        return validLTVs.length();
    }

    function getValidLTV(uint256 index) external view override returns (uint256) {
        return validLTVs.at(index);
    }

    // asset pricing

    function getHistoricalAssetPriceViaTWAP(address baseToken, address quoteToken, uint32 twapStartTimestamp, uint32 twapLength)
        external
        view
        virtual
        override
        returns (uint256 price)
    {
        address poolToUse = _getPoolForTokenPair(baseToken, quoteToken);
        IUniswapV3Pool pool = IUniswapV3Pool(poolToUse);
        int24 tick;
        if (twapLength == 0) {
            // return the current price if twapInterval == 0
            (, tick,,,,,) = pool.slot0();
        } else {
            uint32[] memory _secondsAgos = new uint32[](2);
            // Calculate *how long ago* the timestamp passed in as a parameter is,
            // so that we can use this in the "offset" part
            // First, we calculate what the offset is to the *end* of the twap (aka offset to timeStampStart)
            // THEN, we factor in the twapLength to the timestamp that we actually want to start the twap from
            uint32 offset = (uint32(block.timestamp) - twapStartTimestamp) + twapLength;
            _secondsAgos[0] = twapLength + offset;
            _secondsAgos[1] = offset;
            (int56[] memory tickCumulatives,) = pool.observe(_secondsAgos);
            console.log("Tick Cumulatives[0]: ");
            console.logInt(tickCumulatives[0]);
            int56 tickCumulativesDelta = tickCumulatives[1] - tickCumulatives[0];
            int56 period = int56(int32(twapLength));
            // Always round to negative infinity
            if (tickCumulativesDelta < 0 && (tickCumulativesDelta % period != 0)) tick--;
            tick = int24(tickCumulativesDelta / period);
        }

        price = OracleLibrary.getQuoteAtTick(tick, 1e18, baseToken, quoteToken);
        console.log("Price of baseToken in quoteToken: ", price);
    }

    function getCurrentAssetPrice(address /*asset*/ ) external view virtual override returns (uint256) {
        revert("Method not yet implemented");
    }

    /**
     * pulled from mean finance static oracle
     */

    /// @notice Takes a pair and some fee tiers, and returns pool
    function _getPoolForTokenPair(address _tokenA, address _tokenB) internal view virtual returns (address _pool) {
        _pool = PoolAddress.computeAddress(address(uniswapV3Factory), PoolAddress.getPoolKey(_tokenA, _tokenB, 3000));
        console.log("Computed pool address: ", _pool);
    }
}
