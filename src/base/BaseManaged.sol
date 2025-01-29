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
 * pause guardian pausing, and a function to rescue stuck tokens.
 * @dev all inheriting contracts that hold funds should be owned by a secure multi-sig due
 * the sensitive onlyOwner methods.
 */
abstract contract BaseManaged is Ownable2Step, Pausable {
    // ----- State ----- //
    ConfigHub public configHub;

    /**
     * @notice a token address (ERC-20 or ERC-721) that the owner can NOT rescue via `rescueTokens`.
     *  This should be the main asset that the contract holds at rest on behalf of its users.
     *  If this asset is sent to the contract by mistake, there is no way to rescue it.
     *  This exclusion reduces the centralisation risk, and reduces the impact, incentive, and
     *  thus also the likelihood of compromizing the owner.
     * @dev this is a single address because currently only a single asset is held by each contract
     *  at rest (except for Rolls).
     *  Other assets, that may be held by the contract in-transit (during a transaction), can be rescued.
     *  If further reduction of centralization risk is required, this should become a Set.
     */
    address public immutable unrescuableAsset;

    // ----- Events ----- //
    event ConfigHubUpdated(ConfigHub previousConfigHub, ConfigHub newConfigHub);
    event PausedByGuardian(address guardian);
    event TokensRescued(address tokenContract, uint amountOrId);

    constructor(address _initialOwner, ConfigHub _configHub, address _unrescuableAsset)
        Ownable(_initialOwner)
    {
        _setConfigHub(_configHub);
        unrescuableAsset = _unrescuableAsset;
    }

    // ----- MUTATIVE ----- //

    // ----- Non-owner ----- //

    // @notice Pause method called from a guardian authorized by the ConfigHub in case of emergency
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

    /// @notice Pauses the contract when called by the contract owner in case of emergency.
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
     * @notice Sends an amount of an ERC-20, or an ID of any ERC-721, to owner's address.
     * Revers if the `token` matches the `unrescuableAsset`.
     * To be used to rescue stuck assets that were sent to the contract by mistake.
     * @dev Only callable by the contract owner.
     * @param token The address of the token contract
     * @param amountOrId The amount of tokens to rescue (or token ID for NFTs)
     * @param isNFT Whether the token is an NFT (true) or an ERC-20 (false)
     */
    function rescueTokens(address token, uint amountOrId, bool isNFT) external onlyOwner {
        require(token != unrescuableAsset, "unrescuable asset");
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
