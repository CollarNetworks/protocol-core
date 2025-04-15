// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import { ConfigHub } from "../ConfigHub.sol";

/**
 * @title BaseManaged
 * @notice Base contract for managed contracts in the protocol
 * @dev This contract provides common functionality for contracts that are managed
 * via the a common ConfigHub. It includes a onlyConfigHubOwner that can control access to
 * configuration value setters in inheriting contracts, and a function to update the configHub address.
 * @dev ConfigHub should be owned by a secure multi-sig due its values being used in inheriting contracts.
 */
abstract contract BaseManaged {
    // ----- State ----- //
    ConfigHub public configHub;

    // ----- Events ----- //
    event ConfigHubUpdated(ConfigHub previousConfigHub, ConfigHub newConfigHub);

    constructor(ConfigHub _configHub) {
        _setConfigHub(_configHub);
    }

    // ----- Modifiers ----- //

    modifier onlyConfigHubOwner() {
        require(msg.sender == configHubOwner(), "BaseManaged: not configHub owner");
        _;
    }

    // ----- Views ----- //

    function configHubOwner() public view returns (address) {
        return configHub.owner();
    }

    // ----- MUTATIVE ----- //

    // ----- onlyConfigHubOwner ----- //

    /// @notice Updates the address of the ConfigHub contract when called by the current configHub's owner.
    /// Only allows switching to a new configHub whose owner is the same as current configHub's owner.
    /// @dev To renounce access to specific contracts use setConfigHub to set a new configHub controlled
    /// by the same owner, and then renounce its ownership.
    function setConfigHub(ConfigHub _newConfigHub) external onlyConfigHubOwner {
        // check owner view exists and returns same address to prevent accidentally getting locked out.
        require(_newConfigHub.owner() == configHubOwner(), "BaseManaged: new configHub owner mismatch");
        _setConfigHub(_newConfigHub);
    }

    // ----- INTERNAL MUTATIVE ----- //

    function _setConfigHub(ConfigHub _newConfigHub) internal {
        // @dev this sanity-checks the contract and its expected interface
        require(bytes(_newConfigHub.VERSION()).length > 0, "invalid ConfigHub");

        emit ConfigHubUpdated(configHub, _newConfigHub); // emit before for the prev value
        configHub = _newConfigHub;
    }
}
