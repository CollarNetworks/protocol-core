// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {ICollarEngine} from "./ICollarEngine.sol";

abstract contract ICollarEngineGetters is ICollarEngine {
    function getAdmin() external view returns (address) {
        return admin;
    }

    function getDexRouter() external view returns (address) {
        return address(dexRouter);
    }

    function getMarketmaker() external view returns (address) {
        return marketmaker;
    }

    function getFeerate() external view returns (uint256) {
        return feeRatePct;
    }

    function getFeewallet() external view returns (address) {
        return feeWallet;
    }

    function getLendAsset() external view returns (address) {
        return lendAsset;
    }

    function getCurrRfqid() external view returns (uint256) {
        return rfqid;
    }

        function getLastTradeVault(address client) external view returns (address) {
        return userVaults[client][nextUserVaultId[client] - 1];
    }

    function getLastTradeVaultMarketmaker(address _marketmaker) external view returns (address) {
        return marketmakerVaults[_marketmaker][nextMarketmakerVaultId[marketmaker] - 1];
    }

    function getClientEscrow(address client) external view returns (uint256) {
        return clientEscrow[client];
    }

    function getNextUserVaultId(address _client) external view returns (uint256) {
        return nextUserVaultId[_client];
    }

    function getNextMarketmakerVaultId(address _marketmaker) external view returns (uint256) {
        return nextMarketmakerVaultId[_marketmaker];
    }

    function getClientVaultById(address _client, uint256 _id) external view returns (address) {
        return userVaults[_client][_id];
    }

    function getMarketmakerVaultById(address _marketmaker, uint256 _id) external view returns (address) {
        return marketmakerVaults[_marketmaker][_id];
    }

    function getPricingByClient(address client) external view returns (Pricing memory) {
        return pricings[client];
    }

    function getStateByClient(address client) external view returns (PxState) {
        return pricings[client].state;
    }

        /// @notice Used by the UI to display latest vaults for clients
    function getLastThreeClientVaults(address _client) external view returns (address[3] memory) {
        require(_client != address(0), "error - no zero inputs");
        address[3] memory out;
        uint256 next = nextUserVaultId[_client];
        if (next < 3) {
            next = 3;
        }
        for (uint256 i = next - 3; i < next; i++) {
            out[i] = userVaults[_client][i];
        }
        return (out);
    }

    /// @notice Used by the UI to display latest vaults for marketmakers
    function getLastThreeMarketmakerVaults(address _marketmaker) external view returns (address[3] memory) {
        address[3] memory out;
        uint256 next = nextMarketmakerVaultId[_marketmaker];
        if (next < 3) {
            next = 3;
        }
        for (uint256 i = next - 3; i < next; i++) {
            out[i] = marketmakerVaults[_marketmaker][i];
        }
        return (out);
    }
}