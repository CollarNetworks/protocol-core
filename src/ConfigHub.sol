// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import { Ownable2Step, Ownable } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { IConfigHub } from "./interfaces/IConfigHub.sol";

/**
 * @title ConfigHub
 * @custom:security-contact security@collarprotocol.xyz
 *
 * Main Functionality:
 * 1. Manages system-wide configuration and intern-contract authorization for the Collar Protocol.
 * 2. Controls which contracts are allowed to open positions for specific asset pairs.
 * 3. Sets valid ranges for key parameters like LTV and position duration.
 * 4. Manages protocol fee parameters.
 *
 * Post-Deployment Configuration:
 * - This Contract: Set valid LTV range for protocol
 * - This Contract: Set valid collar duration range for protocol
 * - This Contract: Set protocol fee parameters if fees are used
 */
contract ConfigHub is Ownable2Step, IConfigHub {
    using EnumerableSet for EnumerableSet.AddressSet;

    uint internal constant BIPS_BASE = 10_000;
    uint internal constant YEAR = 365 days;

    string public constant VERSION = "0.3.0";
    /// @notice placeholder value for using canOpenPair for auth when only one asset is specified
    address public constant ANY_ASSET = address(type(uint160).max); // 0xff..ff

    // configuration validation (validate on set)
    uint public constant MAX_PROTOCOL_FEE_BIPS = BIPS_BASE / 100; // 1%
    uint public constant MIN_CONFIGURABLE_LTV_BIPS = BIPS_BASE / 10; // 10%
    uint public constant MAX_CONFIGURABLE_LTV_BIPS = BIPS_BASE - 1; // avoid 0 range edge cases
    uint public constant MIN_CONFIGURABLE_DURATION = 5 minutes;
    uint public constant MAX_CONFIGURABLE_DURATION = 5 * YEAR;

    // -- state variables ---
    // one slot (previous is owner)
    uint16 public minLTV; // uint16 max 650%, but cannot be over 100%
    uint16 public maxLTV; // uint16 max 650%, but cannot be over 100%
    uint32 public minDuration;
    uint32 public maxDuration;
    // next slot
    uint16 public protocolFeeAPR; // uint16 max 650%, but cannot be over MAX_PROTOCOL_FEE_BIPS
    address public feeRecipient;
    // next slots

    /**
     * @notice main auth for system contracts calling each other during opening of positions:
     * Assets would typically be: 'underlying -> cash -> Set<address>', but if the auth is
     * for a single asset (not a pair), ANY_ASSET will be used as a placeholder for the second asset.
     */
    mapping(address => mapping(address => EnumerableSet.AddressSet)) internal canOpenSets;

    constructor(address _initialOwner) Ownable(_initialOwner) { }

    // ----- Setters (only owner) -----

    /**
     * @notice set the ability of an internal contract to "open" positions for a specific pair
     * of assets. This view is checked for auth (allowlist) in interactions between contracts, and by
     * contracts on themselves to check if opening positions is allowed.
     * This enables a "close-only" migration route for contracts that are phased out.
     * This is a low resolution flag, and each using contract should validate that
     * the contract it is using matches its intention (e.g., assets, interface)
     *  @param assetA First asset in the mapping
     *  @param assetB Second asset in the mapping
     *  @param target The contract in the system for which the flag is being set
     *  @param enabled Whether opening position is enabled
     */
    function setCanOpenPair(address assetA, address assetB, address target, bool enabled)
        external
        onlyOwner
    {
        EnumerableSet.AddressSet storage pairSet = canOpenSets[assetA][assetB];
        // contains / return value is not checked
        enabled ? pairSet.add(target) : pairSet.remove(target);
        emit ContractCanOpenSet(assetA, assetB, target, enabled);
    }

    /// @notice Sets the LTV minimum and max values
    /// @param min The new minimum LTV in basis points
    /// @param max The new maximum LTV in basis points
    function setLTVRange(uint min, uint max) external onlyOwner {
        require(min >= MIN_CONFIGURABLE_LTV_BIPS, "LTV min too low");
        require(max <= MAX_CONFIGURABLE_LTV_BIPS, "LTV max too high");
        require(min <= max, "LTV min > max");
        minLTV = SafeCast.toUint16(min);
        maxLTV = SafeCast.toUint16(max);
        emit LTVRangeSet(min, max);
    }

    /// @notice Sets the minimum and maximum collar durations
    /// @param min The new minimum collar duration
    /// @param max The new maximum collar duration
    function setCollarDurationRange(uint min, uint max) external onlyOwner {
        require(min >= MIN_CONFIGURABLE_DURATION, "duration min too low");
        require(max <= MAX_CONFIGURABLE_DURATION, "duration max too high");
        require(min <= max, "duration min > max");
        minDuration = SafeCast.toUint32(min);
        maxDuration = SafeCast.toUint32(max);
        emit CollarDurationRangeSet(min, max);
    }

    // protocol fee

    /// @notice Sets the APR in BIPs, and the address that receive the protocol fee.
    /// @param apr The APR in BIPs
    /// @param recipient The recipient address. Can be zero if APR is 0, to allow disabling.
    function setProtocolFeeParams(uint apr, address recipient) external onlyOwner {
        require(apr <= MAX_PROTOCOL_FEE_BIPS, "protocol fee APR too high");
        require(recipient != address(0) || apr == 0, "must set recipient for non-zero APR");
        emit ProtocolFeeParamsUpdated(protocolFeeAPR, apr, feeRecipient, recipient);
        protocolFeeAPR = SafeCast.toUint16(apr);
        feeRecipient = recipient;
    }

    // ----- Views -----

    /// @notice main auth for system contracts calling each other during opening of positions for a pair.
    /// @dev note that assets A/B aren't necessarily external ERC20, and can be internal contracts as well
    /// e.g, escrow may query (underlying, escrow, loans) to check a loans contract is enabled for it
    function canOpenPair(address assetA, address assetB, address target)
        external
        view
        returns (bool)
    {
        return canOpenSets[assetA][assetB].contains(target);
    }

    /// @notice equivalent to `canOpenPair` view when the second asset is ANY_ASSET placeholder
    function canOpenSingle(address asset, address target) external view returns (bool) {
        return canOpenSets[asset][ANY_ASSET].contains(target);
    }

    /// @notice Returns all the addresses that are allowed for a pair of assets.
    /// @dev should be used to validate that only expected contracts are in the Set.
    /// assetB can be ANY_ASSET placeholder for "single asset" authorization type.
    function allCanOpenPair(address assetA, address assetB) external view returns (address[] memory) {
        return canOpenSets[assetA][assetB].values();
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
