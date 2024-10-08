// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Ownable2Step, Ownable } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";

import { ConfigHub } from "../ConfigHub.sol";

abstract contract BaseManaged is Ownable2Step, Pausable {
    // ----- State ----- //
    ConfigHub public configHub;

    // ----- Events ----- //
    event ConfigHubUpdated(ConfigHub previousConfigHub, ConfigHub newConfigHub);
    event PausedByGuardian(address guardian);
    event TokensRescued(address tokenContract, uint amount);

    // @dev use _setConfigHub() in child contract to initialize the configHub on construction
    constructor(address _initialOwner) Ownable(_initialOwner) { }

    // ----- MUTATIVE ----- //

    // ----- Non-owner ----- //

    // @notice Pause method called from the guardian authorized by the ConfigHub
    // Reverts if sender is not guardian, or if owner is revoked (since unpausing would be impossible)
    function pauseByGuardian() external {
        require(msg.sender == configHub.pauseGuardian(), "not guardian");
        // if owner is renounced, no one will be able to call unpause.
        // Using Ownable2Step ensures the owner can only be renounced to address(0).
        require(owner() != address(0), "owner renounced");

        _pause(); // @dev also emits Paused
        emit PausedByGuardian(msg.sender);
    }

    // ----- owner ----- //

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function setConfigHub(ConfigHub _newConfigHub) external onlyOwner {
        _setConfigHub(_newConfigHub);
    }

    /// @notice sends any ERC-20 tokens to owner's address, required for funds recovery
    /// in case of emergency
    function rescueTokens(address token, uint amount) external onlyOwner {
        /// The transfer is to the owner so that only full owner compromise can steal tokens
        /// and not a single rescue transaction with bad params
        SafeERC20.safeTransfer(IERC20(token), owner(), amount);
        emit TokensRescued(token, amount);
    }

    // ----- INTERNAL MUTATIVE ----- //

    function _setConfigHub(ConfigHub _newConfigHub) internal {
        // @dev this sanity-checks the contract and its expected interface
        require(bytes(_newConfigHub.VERSION()).length > 0, "invalid ConfigHub");

        emit ConfigHubUpdated(configHub, _newConfigHub); // emit before for the prev value
        configHub = _newConfigHub;
    }
}
