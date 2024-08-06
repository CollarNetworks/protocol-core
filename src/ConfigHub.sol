// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity 0.8.22;

import { Ownable2Step, Ownable } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { IPeripheryImmutableState } from
    "@uniswap/v3-periphery/contracts/interfaces/IPeripheryImmutableState.sol";
// internal imports
import { IConfigHub } from "./interfaces/IConfigHub.sol";
import { IProviderPositionNFT } from "./interfaces/IProviderPositionNFT.sol";
import { ICollarTakerNFT } from "./interfaces/ICollarTakerNFT.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract ConfigHub is Ownable2Step, IConfigHub {
    // -- public state variables ---

    string public constant VERSION = "0.2.0";

    // configuration validation (validate on set)
    uint public constant MIN_CONFIGURABLE_LTV = 1000;
    uint public constant MAX_CONFIGURABLE_LTV = 9999;
    uint public constant MIN_CONFIGURABLE_DURATION = 300;
    uint public constant MAX_CONFIGURABLE_DURATION = 5 * 365 days;
    // configured values (set by owner)
    uint public minLTV;
    uint public maxLTV;
    uint public minDuration;
    uint public maxDuration;
    // pause guardian for other contracts
    address public uniV3SwapRouter;
    address public pauseGuardian;

    // -- internal state variables ---
    mapping(address collateralAssetAddress => bool isSupported) public isSupportedCollateralAsset;
    mapping(address cashAssetAddress => bool isSupported) public isSupportedCashAsset;
    mapping(address contractAddress => bool enabled) public isCollarTakerNFT;
    mapping(address contractAddress => bool enabled) public isProviderNFT;

    constructor(address _initialOwner) Ownable(_initialOwner) { }

    // ----- state-changing functions (see IConfigHub for documentation) -----

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

    // ltv

    function setLTVRange(uint min, uint max) external onlyOwner {
        require(min >= MIN_CONFIGURABLE_LTV, "min too low");
        require(max <= MAX_CONFIGURABLE_LTV, "max too high");
        require(min <= max, "min > max");
        minLTV = min;
        maxLTV = max;
        emit LTVRangeSet(min, max);
    }

    // collar durations

    function setCollarDurationRange(uint min, uint max) external onlyOwner {
        require(min <= max, "min > max");
        require(min >= MIN_CONFIGURABLE_DURATION, "min too low");
        require(max <= MAX_CONFIGURABLE_DURATION, "max too high");
        minDuration = min;
        maxDuration = max;
        emit CollarDurationRangeSet(min, max);
    }

    // collateral assets

    function setCollateralAssetSupport(address collateralAsset, bool enabled) external onlyOwner {
        isSupportedCollateralAsset[collateralAsset] = enabled;
        emit CollateralAssetSupportSet(collateralAsset, enabled);
    }

    // cash assets

    function setCashAssetSupport(address cashAsset, bool enabled) external onlyOwner {
        isSupportedCashAsset[cashAsset] = enabled;
        emit CashAssetSupportSet(cashAsset, enabled);
    }

    // pausing

    function setPauseGuardian(address newGuardian) external onlyOwner {
        emit PauseGuardianSet(pauseGuardian, newGuardian); // emit before for the prev-value
        pauseGuardian = newGuardian;
    }

    // swap router

    function setUniV3Router(address _uniV3SwapRouter) external onlyOwner {
        require(IPeripheryImmutableState(_uniV3SwapRouter).factory() != address(0), "invalid router");
        emit UniV3RouterSet(uniV3SwapRouter, _uniV3SwapRouter); // emit before for the prev-value
        uniV3SwapRouter = _uniV3SwapRouter;
    }

    // ----- view functions (see IConfigHub for documentation) -----

    // collar durations

    function isValidCollarDuration(uint duration) external view returns (bool) {
        return duration >= minDuration && duration <= maxDuration;
    }

    // ltvs

    function isValidLTV(uint ltv) external view returns (bool) {
        return ltv >= minLTV && ltv <= maxLTV;
    }
}
