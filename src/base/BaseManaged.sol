// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import { ConfigHub } from "../ConfigHub.sol";

/**
 * @title BaseManaged
 * @notice Base contract for managed contracts in the protocol
 * @dev This contract provides common functionality for contracts that are managed
 * via the a common ConfigHub. It includes a onlyConfigHubOwner that can control access to
 * configuration value setters in inheriting contracts, and a function to rescue stuck tokens.
 * @dev ConfigHub should be owned by a secure multi-sig due the sensitive onlyConfigHubOwner methods.
 */
abstract contract BaseManaged {
    // ----- State ----- //
    ConfigHub public configHub;

    /**
     * @notice a token address (ERC-20 or ERC-721) that configHub's owner can NOT rescue via `rescueTokens`.
     *  This should be the main asset that the contract holds at rest on behalf of its users.
     *  If this asset is sent to the contract by mistake, there is no way to rescue it.
     *  This exclusion reduces the centralisation risk, and reduces the impact, incentive, and
     *  thus also the likelihood of compromizing the configHub's owner.
     * @dev this is a single address because currently only a single asset is held by each contract
     *  at rest (except for Rolls).
     *  Other assets, that may be held by the contract in-transit (during a transaction), can be rescued.
     *  If more assets need to be unrescuable, this should become a Set.
     */
    address public immutable unrescuableAsset;

    // ----- Events ----- //
    event ConfigHubUpdated(ConfigHub previousConfigHub, ConfigHub newConfigHub);
    event TokensRescued(address tokenContract, uint amountOrId);

    constructor(ConfigHub _configHub, address _unrescuableAsset) {
        _setConfigHub(_configHub);
        unrescuableAsset = _unrescuableAsset;
    }

    // ----- Modifiers ----- //

    modifier onlyConfigHubOwner() {
        require(msg.sender == configHub.owner(), "BaseManaged: not configHub owner");
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

    /**
     * @notice Sends an amount of an ERC-20, or an ID of any ERC-721, to configHub owner's address.
     * Reverts if the `token` matches the `unrescuableAsset`.
     * To be used to rescue stuck assets that were sent to the contract by mistake.
     * @dev Only callable by the configHub's owner.
     * @param token The address of the token contract
     * @param amountOrId The amount of tokens to rescue (or token ID for NFTs)
     * @param isNFT Whether the token is an NFT (true) or an ERC-20 (false)
     */
    function rescueTokens(address token, uint amountOrId, bool isNFT) external onlyConfigHubOwner {
        require(token != unrescuableAsset, "unrescuable asset");
        if (isNFT) {
            IERC721(token).transferFrom(address(this), configHubOwner(), amountOrId);
        } else {
            // for ERC-20 must use transfer, since most implementation won't allow transferFrom
            // without approve (even from owner)
            SafeERC20.safeTransfer(IERC20(token), configHubOwner(), amountOrId);
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
