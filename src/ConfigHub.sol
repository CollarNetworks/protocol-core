// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import { Ownable2Step, Ownable } from "@openzeppelin/contracts/access/Ownable2Step.sol";

import { IConfigHub } from "./interfaces/IConfigHub.sol";

contract ConfigHub is Ownable2Step, IConfigHub {
    uint internal constant BIPS_BASE = 10_000;

    string public constant VERSION = "0.2.0";

    // configuration validation (validate on set)
    uint public constant MIN_CONFIGURABLE_LTV_BIPS = BIPS_BASE / 10; // 10%
    uint public constant MAX_CONFIGURABLE_LTV_BIPS = BIPS_BASE - 1; // avoid 0 range edge cases
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

    mapping(address unlderlyingAddress => bool isSupported) public isSupportedUnderlying;
    mapping(address cashAssetAddress => bool isSupported) public isSupportedCashAsset;
    /// @notice internal contracts auth, "canOpen" means different things within different contracts.
    /// "closing" already opened is allowed (unless paused).
    mapping(address contractAddress => bool enabled) public canOpen;

    constructor(address _initialOwner) Ownable(_initialOwner) { }

    // ----- Setters (only owner) -----

    /// @notice set the ability of an internal contract to "open" positions.
    /// "canOpen" means different things within different contracts, and is used both for auth
    /// and to allow a "close-only" migration route for contracts that are phased out.
    /// This is a low resolution flag, and each using contract should validate that
    /// the contract it is using matches its intention (e.g., assets, interface)
    function setCanOpen(address contractAddress, bool enabled) external onlyOwner {
        canOpen[contractAddress] = enabled;
        emit ContractCanOpenSet(contractAddress, enabled);
    }

    /// @notice Sets the LTV minimum and max values for the configHub
    /// @param min The new minimum LTV
    /// @param max The new maximum LTV
    function setLTVRange(uint min, uint max) external onlyOwner {
        require(min >= MIN_CONFIGURABLE_LTV_BIPS, "min too low");
        require(max <= MAX_CONFIGURABLE_LTV_BIPS, "max too high");
        require(min <= max, "min > max");
        minLTV = min;
        maxLTV = max;
        emit LTVRangeSet(min, max);
    }

    /// @notice Sets the minimum and maximum collar durations for the configHub
    /// @param min The new minimum collar duration
    /// @param max The new maximum collar duration
    function setCollarDurationRange(uint min, uint max) external onlyOwner {
        require(min >= MIN_CONFIGURABLE_DURATION, "min too low");
        require(max <= MAX_CONFIGURABLE_DURATION, "max too high");
        require(min <= max, "min > max");
        minDuration = min;
        maxDuration = max;
        emit CollarDurationRangeSet(min, max);
    }

    /// @notice Sets whether a particular underlying asset is supported
    /// @param underlying The address of the underlying asset
    /// @param enabled Whether the asset is supported
    function setUnderlyingSupport(address underlying, bool enabled) external onlyOwner {
        isSupportedUnderlying[underlying] = enabled;
        emit UnderlyingSupportSet(underlying, enabled);
    }

    /// @notice Sets whether a particular cash asset is supported
    /// @param cashAsset The address of the cash asset
    /// @param enabled Whether the asset is supported
    function setCashAssetSupport(address cashAsset, bool enabled) external onlyOwner {
        isSupportedCashAsset[cashAsset] = enabled;
        emit CashAssetSupportSet(cashAsset, enabled);
    }

    // pausing

    /// @notice Sets an address that can pause (but not unpause) any of the contracts that
    /// use this ConfigHub.
    /// @param newGuardian The address of the new guardian
    function setPauseGuardian(address newGuardian) external onlyOwner {
        emit PauseGuardianSet(pauseGuardian, newGuardian); // emit before for the prev-value
        pauseGuardian = newGuardian;
    }

    // protocol fee

    /// @notice Sets the APR in BIPs, and the address that receive the protocol fee.
    /// @param apr The APR in BIPs
    /// @param recipient The recipient address. Can be zero if APR is 0, to allow disabling.
    function setProtocolFeeParams(uint apr, address recipient) external onlyOwner {
        require(apr <= BIPS_BASE, "invalid fee"); // 100% max APR
        require(recipient != address(0) || apr == 0, "must set recipient for non-zero APR");
        emit ProtocolFeeParamsUpdated(protocolFeeAPR, apr, feeRecipient, recipient);
        protocolFeeAPR = apr;
        feeRecipient = recipient;
    }

    // ----- Views -----

    /// @notice Checks to see if a particular collar duration is supported
    /// @param duration The duration to check
    function isValidCollarDuration(uint duration) external view returns (bool) {
        return duration >= minDuration && duration <= maxDuration;
    }

    /// @notice Checks to see if a particular LTV is supported
    /// @param ltv The LTV to check
    function isValidLTV(uint ltv) external view returns (bool) {
        return ltv >= minLTV && ltv <= maxLTV;
    }
}
