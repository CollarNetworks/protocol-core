// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import {CollarVault} from "../../src/CollarVault.sol";
import {AddressBook, DefaultConstants} from "./CommonUtils.sol";

abstract contract VaultUtils is Test, AddressBook, DefaultConstants {
    struct VaultDeployParams {
        address admin;
        uint256 rfqid;
        uint256 qty;
        address lendAsset;
        uint256 putStrikePct;
        uint256 callStrikePct;
        uint256 maturityTimestamp;
        address dexRouter;
        address priceFeed;
    }

    VaultDeployParams DEFAULT_VAULT_PARAMS = VaultDeployParams({
        admin: admin,
        rfqid: DEFAULT_RFQID,
        qty: DEFAULT_QTY,
        lendAsset: usdc,
        putStrikePct: DEFAULT_PUT_STRIKE_PCT,
        callStrikePct: DEFAULT_CALL_STRIKE_PCT,
        maturityTimestamp: DEFAULT_MATURITY_TIMESTAMP,
        dexRouter: testDex,
        priceFeed: ethUSDOracle
    });

    /// @dev Deploys a new CollarVault with default params (above)
    function deployVault() public returns (CollarVault vault) {
        // Explicit external call so that we can put the struct in calldata and not memory
        return VaultUtils(address(this)).deployVault(DEFAULT_VAULT_PARAMS);
    }

    /// @dev Deploys a new CollarVault with the given params as a struct
    /// @param params The params to use for the vault
    /// @return vault The deployed vault
    function deployVault(VaultDeployParams calldata params) public returns (CollarVault vault) {
        hoax(params.admin);

        vm.label(address(vault), "CollarVault");

        return vault;
    }
}
