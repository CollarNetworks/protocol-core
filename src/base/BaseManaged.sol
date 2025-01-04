// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Ownable2Step, Ownable } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import { ConfigHub } from "../ConfigHub.sol";

/**
 * @title BaseManaged
 * @notice Base contract for managed contracts in the Collar Protocol
 * @dev This contract provides common functionality for contracts that are owned and managed
 * via the Collar Protocol's ConfigHub. It includes 2 step ownership, pause/unpause functionality,
 * pause guardian pausing, and an emergency function to rescue stuck tokens.
 *
 * @dev All contracts that inherit from BaseManaged must call `_setConfigHub` to set the
 * ConfigHub address.
 */
abstract contract BaseManaged is Ownable2Step, Pausable {
    // ----- State ----- //
    ConfigHub public configHub;

    // ----- Events ----- //
    event ConfigHubUpdated(ConfigHub previousConfigHub, ConfigHub newConfigHub);
    event PausedByGuardian(address guardian);
    event TokensRescued(address tokenContract, uint amountOrId);

    constructor(address _initialOwner, ConfigHub _configHub) Ownable(_initialOwner) {
        _setConfigHub(_configHub);
    }

    // ----- MUTATIVE ----- //

    // ----- Non-owner ----- //

    // @notice Pause method called from a guardian authorized by the ConfigHub
    // Reverts if sender is not guardian, or if owner is revoked (since unpausing would be impossible)
    function pauseByGuardian() external {
        require(configHub.isPauseGuardian(msg.sender), "not guardian");
        // if owner is renounced, no one will be able to call unpause.
        // Using Ownable2Step ensures the owner can only be renounced to address(0).
        require(owner() != address(0), "owner renounced");

        _pause(); // @dev also emits Paused
        emit PausedByGuardian(msg.sender);
    }

    // ----- owner ----- //

    /// @notice Pauses the contract when called by the contract owner
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unpauses the contract when called by the contract owner
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @notice Updates the address of the ConfigHub contract when called by the contract owner
    function setConfigHub(ConfigHub _newConfigHub) external onlyOwner {
        _setConfigHub(_newConfigHub);
    }

    /**
     * @notice Sends an amount of ERC-20, or an ID of ERC-721, to owner's address.
     * To be used in case of emergency, user mistakes, or irrecoverable bugs.
     * @dev Only callable by the contract owner
     * @param token The address of the token contract
     * @param amountOrId The amount of tokens to rescue (or token ID for NFTs)
     * @param isNFT Whether the token is an NFT (true) or an ERC-20 (false)
     */
    function rescueTokens(address token, uint amountOrId, bool isNFT) external onlyOwner {
        /// The transfer is to the owner so that only full owner compromise can steal tokens
        /// and not a single rescue transaction with bad params
        if (isNFT) {
            IERC721(token).transferFrom(address(this), owner(), amountOrId);
        } else {
            // for ERC-20 must use transfer, since most implementation won't allow transferFrom
            // without approve (even from owner)
            SafeERC20.safeTransfer(IERC20(token), owner(), amountOrId);
        }
        emit TokensRescued(token, amountOrId);
    }

    // ----- INTERNAL MUTATIVE ----- //

    function _setConfigHub(ConfigHub _newConfigHub) internal {
        // @dev this sanity-checks the contract and its expected interface
        require(bytes(_newConfigHub.VERSION()).length > 0, "invalid ConfigHub");

        emit ConfigHubUpdated(configHub, _newConfigHub); // emit before for the prev value
        configHub = _newConfigHub;
    }
}
