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
import { UniV3OracleLib } from "../libs/UniV3OracleLib.sol";
import { IProviderPositionNFT } from "../interfaces/IProviderPositionNFT.sol";
import { ICollarTakerNFT } from "../interfaces/ICollarTakerNFT.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "forge-std/console.sol";

contract CollarEngine is Ownable, ICollarEngine {
    // -- lib delcarations --
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.UintSet;

    // -- public state variables ---

    string public constant VERSION = "0.2.0";

    address public immutable univ3SwapRouter;

    uint public constant TWAP_BASE_TOKEN_AMOUNT = uint(UniV3OracleLib.BASE_TOKEN_AMOUNT);
    uint public constant MIN_LTV = 1000;
    uint public constant MAX_LTV = 9999;
    uint public constant MIN_COLLAR_DURATION = 300;
    uint public constant MAX_COLLAR_DURATION = 365 days;
    // -- internal state variables ---
    mapping(address collateralAssetAddress => bool isSupported) public isSupportedCollateralAsset;
    mapping(address cashAssetAddress => bool isSupported) public isSupportedCashAsset;
    mapping(address contractAddress => bool enabled) public isCollarTakerNFT;
    mapping(address contractAddress => bool enabled) public isProviderNFT;

    constructor(address _univ3SwapRouter) Ownable(msg.sender) {
        univ3SwapRouter = _univ3SwapRouter;
    }

    // ----- state-changing functions (see ICollarEngine for documentation) -----

    function setCollarTakerContractAuth(address contractAddress, bool enabled) external onlyOwner {
        isCollarTakerNFT[contractAddress] = enabled;
        IERC20 cashAsset = ICollarTakerNFT(contractAddress).cashAsset();
        IERC20 collateralAsset = ICollarTakerNFT(contractAddress).collateralAsset();
        emit CollarTakerNFTAuthSet(contractAddress, enabled, address(cashAsset), address(collateralAsset));
    }

    function setProviderContractAuth(address contractAddress, bool enabled) external onlyOwner {
        isProviderNFT[contractAddress] = enabled;
        IERC20 cashAsset = IProviderPositionNFT(contractAddress).cashAsset();
        IERC20 collateralAsset = IProviderPositionNFT(contractAddress).collateralAsset();
        address collarTakerNFT = IProviderPositionNFT(contractAddress).collarTakerContract();
        emit ProviderNFTAuthSet(
            contractAddress, enabled, address(cashAsset), address(collateralAsset), collarTakerNFT
        );
    }

    // collateral assets

    function addSupportedCollateralAsset(address asset) external override onlyOwner {
        isSupportedCollateralAsset[asset] = true;
        emit CollateralAssetAdded(asset);
    }

    function removeSupportedCollateralAsset(address asset) external override onlyOwner {
        isSupportedCollateralAsset[asset] = false;
        emit CollateralAssetRemoved(asset);
    }

    // cash assets

    function addSupportedCashAsset(address asset) external override onlyOwner {
        isSupportedCashAsset[asset] = true;
        emit CashAssetAdded(asset);
    }

    function removeSupportedCashAsset(address asset) external override onlyOwner {
        isSupportedCashAsset[asset] = false;
        emit CashAssetRemoved(asset);
    }

    // ----- view functions (see ICollarEngine for documentation) -----

    // collar durations

    function isValidCollarDuration(uint duration) external pure override returns (bool) {
        if (duration < MIN_COLLAR_DURATION || duration > MAX_COLLAR_DURATION) {
            return false;
        }
        return true;
    }

    // ltvs

    function isValidLTV(uint ltv) external pure override returns (bool) {
        if (ltv < MIN_LTV || ltv > MAX_LTV) {
            return false;
        }
        return true;
    }

    // asset pricing

    function validateAssetsIsSupported(address token) internal view {
        bool isSupportedBase = isSupportedCashAsset[token] || isSupportedCollateralAsset[token];
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
