// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test} from "@forge-std/Test.sol";
import {CollarVault} from "../../src/CollarVault.sol";
import {DefaultConstants} from "./CommonUtils.sol";
import {UniswapV3Mocks} from "./UniswapV3Utils.sol";
import {MockOracle} from "./mocks/MockOracle.sol";
import {EngineUtils} from "./EngineUtils.sol";

/// @dev Inherit this contract into a test contract to get access to the deployEngine function
abstract contract VaultUtils is Test, DefaultConstants, EngineUtils {
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

    VaultDeployParams DEFAULT_VAULT_PARAMS;

    function setUp() public virtual override {
        super.setUp();

        DEFAULT_VAULT_PARAMS = VaultDeployParams({
            admin: makeAddr("Owner"),
            rfqid: DEFAULT_RFQID,
            qty: DEFAULT_QTY,
            lendAsset: mockUni.tokenA,
            putStrikePct: DEFAULT_PUT_STRIKE_PCT,
            callStrikePct: DEFAULT_CALL_STRIKE_PCT,
            maturityTimestamp: DEFAULT_MATURITY_TIMESTAMP,
            dexRouter: mockUni.router,
            priceFeed: DEFAULT_ENGINE_PARAMS.ethUSDOracle
        });
    }
}
