// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import { Ownable2Step, Ownable } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { IConfigHub, IERC20 } from "./interfaces/IConfigHub.sol";

contract ConfigHub is Ownable2Step, IConfigHub {
    uint internal constant BIPS_BASE = 10_000;

    string public constant VERSION = "0.2.0";
    /// @notice sentinel value for using canOpenPair for auth when only one asset is specified
    IERC20 public constant ANY_ASSET = IERC20(address(type(uint160).max)); // 0xff..ff

    // configuration validation (validate on set)
    uint public constant MAX_PROTOCOL_FEE_BIPS = BIPS_BASE / 100; // 1%
    uint public constant MIN_CONFIGURABLE_LTV_BIPS = BIPS_BASE / 10; // 10%
    uint public constant MAX_CONFIGURABLE_LTV_BIPS = BIPS_BASE - 1; // avoid 0 range edge cases
    uint public constant MIN_CONFIGURABLE_DURATION = 300; // 5 minutes
    uint public constant MAX_CONFIGURABLE_DURATION = 5 * 365 days; // 5 years

    // -- state variables ---
    // one slot (previous is owner)
    uint16 public minLTV; // max 650%, but cannot be over 100%
    uint16 public maxLTV; // max 650%, but cannot be over 100%
    uint32 public minDuration;
    uint32 public maxDuration;
    // next slot
    uint16 public protocolFeeAPR; // max 650%, but cannot be over 100%
    address public feeRecipient;
    // next slot
    // pause guardian for other contracts
    address public pauseGuardian;

    /* @notice main auth for system contracts calling each other during opening of positions:
        Assets would typically be: 'underlying -> cash -> someContract -> enabled', but if the auth is
        for a single asset (not a pair), ANY_ASSET will be used as a placeholder for the second asset.
    */
    mapping(IERC20 => mapping(IERC20 => mapping(address target => bool enabled))) public canOpenPair;

    constructor(address _initialOwner) Ownable(_initialOwner) { }

    // ----- Setters (only owner) -----

    /* @notice set the ability of an internal contract to "open" positions for a specific pair
    of assets. This view is checked for auth (allowlist) in interactions between contracts, and by
    contracts on themselves to check if opening positions is allowed.
    This enables a "close-only" migration route for contracts that are phased out.
    This is a low resolution flag, and each using contract should validate that
    the contract it is using matches its intention (e.g., assets, interface)
    */
    function setCanOpenPair(IERC20 assetA, IERC20 assetB, address target, bool enabled) external onlyOwner {
        canOpenPair[assetA][assetB][target] = enabled;
        emit ContractCanOpenSet(assetA, assetB, target, enabled);
    }

    /// @notice Sets the LTV minimum and max values for the configHub
    /// @param min The new minimum LTV
    /// @param max The new maximum LTV
    function setLTVRange(uint min, uint max) external onlyOwner {
        require(min >= MIN_CONFIGURABLE_LTV_BIPS, "min too low");
        require(max <= MAX_CONFIGURABLE_LTV_BIPS, "max too high");
        require(min <= max, "min > max");
        minLTV = SafeCast.toUint16(min);
        maxLTV = SafeCast.toUint16(max);
        emit LTVRangeSet(min, max);
    }

    /// @notice Sets the minimum and maximum collar durations for the configHub
    /// @param min The new minimum collar duration
    /// @param max The new maximum collar duration
    function setCollarDurationRange(uint min, uint max) external onlyOwner {
        require(min >= MIN_CONFIGURABLE_DURATION, "min too low");
        require(max <= MAX_CONFIGURABLE_DURATION, "max too high");
        require(min <= max, "min > max");
        minDuration = SafeCast.toUint32(min);
        maxDuration = SafeCast.toUint32(max);
        emit CollarDurationRangeSet(min, max);
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
        require(apr <= MAX_PROTOCOL_FEE_BIPS, "fee APR too high");
        require(recipient != address(0) || apr == 0, "must set recipient for non-zero APR");
        emit ProtocolFeeParamsUpdated(protocolFeeAPR, apr, feeRecipient, recipient);
        protocolFeeAPR = SafeCast.toUint16(apr);
        feeRecipient = recipient;
    }

    // ----- Views -----

    /// @notice equivalent to, and uses canOpenPair, when the second asset is expected to be ANY_ASSET
    function canOpenSingle(IERC20 asset, address target) external view returns (bool) {
        return canOpenPair[asset][ANY_ASSET][target];
    }

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
