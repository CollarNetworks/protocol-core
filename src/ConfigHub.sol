// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity 0.8.22;

import { Ownable2Step, Ownable } from "@openzeppelin/contracts/access/Ownable2Step.sol";

import { IConfigHub } from "./interfaces/IConfigHub.sol";

contract ConfigHub is Ownable2Step, IConfigHub {
    uint internal constant BIPS_BASE = 10_000;

    string public constant VERSION = "0.2.0";

    // configuration validation (validate on set)
    uint public constant MIN_CONFIGURABLE_LTV = BIPS_BASE / 10; // 10%
    uint public constant MAX_CONFIGURABLE_LTV = BIPS_BASE - 1; // avoid 0 range edge cases
    uint public constant MIN_CONFIGURABLE_DURATION = 300; // 5 minutes
    uint public constant MAX_CONFIGURABLE_DURATION = 5 * 365 days; // 5 years

    // -- state variables ---
    uint public minLTV;
    uint public maxLTV;
    uint public minDuration;
    uint public maxDuration;
    uint public protocolFeeAPR; // bips
    // pause guardian for other contracts
    address public pauseGuardian;
    address public feeRecipient;

    mapping(address collateralAssetAddress => bool isSupported) public isSupportedCollateralAsset;
    mapping(address cashAssetAddress => bool isSupported) public isSupportedCashAsset;
    /// @notice internal contracts auth, "canOpen" means different things within different contracts.
    /// "closing" already opened is allowed (unless paused).
    mapping(address contractAddress => bool enabled) public canOpen;

    constructor(address _initialOwner) Ownable(_initialOwner) { }

    // ----- state-changing functions (see IConfigHub for documentation) -----

    function setCanOpen(address contractAddress, bool enabled) external onlyOwner {
        canOpen[contractAddress] = enabled;
        emit ContractCanOpenSet(contractAddress, enabled);
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

    // protocol fee

    function setProtocolFeeParams(uint _apr, address _recipient) external onlyOwner {
        require(_apr <= BIPS_BASE, "invalid fee");
        require(_recipient != address(0) || _apr == 0, "must set recipient for non-zero APR");
        emit ProtocolFeeParamsUpdated(protocolFeeAPR, _apr, feeRecipient, _recipient);
        protocolFeeAPR = _apr;
        feeRecipient = _recipient;
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
