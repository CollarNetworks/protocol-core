// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test, console2} from "@forge-std/Test.sol";
import {CollarEngine} from "../../src/CollarEngine.sol";
import {CollarVault} from "../../src/CollarVault.sol";
import {EngineUtils} from "../utils/EngineUtils.sol";
import {VaultUtils} from "../utils/VaultUtils.sol";
import {IERC20} from "../../src/interfaces/external/IERC20.sol";
import {TestERC20} from "../utils/mocks/TestERC20.sol";
import {MockOracle} from "../utils/mocks/MockOracle.sol";

// Tests converted from ./old/test-vault-and-roll.js

contract CollarVault_MatureFlat is Test, VaultUtils {
    CollarEngine engine;
    CollarVault vault;

    function setUp() public override {
        super.setUp();

        engine = deployEngine();

        VaultDeployParams memory vaultParams = VaultDeployParams({
            admin: makeAddr("Owner"),
            rfqid: DEFAULT_RFQID,
            qty: 1 ether,
            lendAsset: mocks.tokenA(),
            putStrikePct: DEFAULT_PUT_STRIKE_PCT,
            callStrikePct: DEFAULT_CALL_STRIKE_PCT,
            maturityTimestamp: DEFAULT_MATURITY_TIMESTAMP,
            dexRouter: mocks.router(),
            priceFeed: DEFAULT_ENGINE_PARAMS.ethUSDOracle
        });

        startHoax(vaultParams.admin);

        vault = new CollarVault(
            vaultParams.admin,
            vaultParams.rfqid,
            vaultParams.qty,
            vaultParams.lendAsset,
            vaultParams.putStrikePct,
            vaultParams.callStrikePct,
            block.timestamp - 1,
            vaultParams.dexRouter,
            vaultParams.priceFeed
        );

        vault.postTradeDetailsA(
            991_040_872, //lent
            1_165_995_893, //fill
            116_599_590, //collat
            139_919_507, //proceeds
            DEFAULT_ENGINE_PARAMS.weth
        );

        vault.postTradeDetailsB(
            34_979_876, //fee
            DEFAULT_ENGINE_PARAMS.feeWallet, //feewallet
            DEFAULT_ENGINE_PARAMS.rake, //feerate
            DEFAULT_ENGINE_PARAMS.marketMaker, //mm
            DEFAULT_ENGINE_PARAMS.trader //client);
        );

        TestERC20(DEFAULT_ENGINE_PARAMS.usdc).mintTo(DEFAULT_ENGINE_PARAMS.trader, 1_000_000 * 1e6);
        TestERC20(DEFAULT_ENGINE_PARAMS.usdc).mintTo(DEFAULT_ENGINE_PARAMS.marketMaker, 1_000_000 * 1e6);
        TestERC20(DEFAULT_ENGINE_PARAMS.usdc).mintTo(address(vault), 116_599_590);
        TestERC20(DEFAULT_ENGINE_PARAMS.usdc).mintTo(address(vault), 139_919_507);
        TestERC20(DEFAULT_ENGINE_PARAMS.usdc).mintTo(DEFAULT_ENGINE_PARAMS.trader, 991_096_509);
    }

    function test_matureVaultFlat() public {
        MockOracle(DEFAULT_ENGINE_PARAMS.ethUSDOracle).setLatestRoundData(125_360_435_265);
        assertEq(vault.getOraclePriceExternal(), 1_253_604_352_650_000_000_000);
        assertTrue(vault.checkMatured());
        assertEq(IERC20(DEFAULT_ENGINE_PARAMS.usdc).balanceOf(address(vault)), 256_519_097);
    }
}
