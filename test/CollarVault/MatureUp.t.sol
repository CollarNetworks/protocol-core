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

contract CollarVault_MatureUp is Test, VaultUtils {
    CollarEngine engine;
    CollarVault vault;

    function setUp() public override {
        super.setUp();

        engine = deployEngine();

        VaultDeployParams memory vaultParams = VaultDeployParams({
            admin: makeAddr("Owner"),
            rfqid: DEFAULT_RFQID,
            qty: DEFAULT_QTY,
            lendAsset: mocks.tokenA(),
            putStrikePct: DEFAULT_PUT_STRIKE_PCT,
            callStrikePct: DEFAULT_CALL_STRIKE_PCT,
            maturityTimestamp: block.timestamp - 1,
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
            991_040_872 / 2, //lent
            1_165_995_894 / 2, //fill
            116_599_590 / 2, //collat
            139_919_508 / 2, //proceeds
            DEFAULT_ENGINE_PARAMS.weth
        );

        vault.postTradeDetailsB(
            34_979_876 / 2, //fee
            DEFAULT_ENGINE_PARAMS.feeWallet, //feewallet
            DEFAULT_ENGINE_PARAMS.rake, //feerate
            DEFAULT_ENGINE_PARAMS.marketMaker, //mm
            DEFAULT_ENGINE_PARAMS.trader //client);
        );

        TestERC20(DEFAULT_ENGINE_PARAMS.usdc).mintTo(DEFAULT_ENGINE_PARAMS.trader, 1_000_000 * 1e6);
        TestERC20(DEFAULT_ENGINE_PARAMS.usdc).mintTo(DEFAULT_ENGINE_PARAMS.marketMaker, 1_000_000 * 1e6);
        TestERC20(DEFAULT_ENGINE_PARAMS.usdc).mintTo(address(vault), 116_599_590 / 2);
        TestERC20(DEFAULT_ENGINE_PARAMS.usdc).mintTo(address(vault), 139_919_508 / 2);
        TestERC20(DEFAULT_ENGINE_PARAMS.usdc).mintTo(DEFAULT_ENGINE_PARAMS.trader, 991_096_510 / 2);
    }

    function test_matureVaultUp() public {
        MockOracle(DEFAULT_ENGINE_PARAMS.ethUSDOracle).setLatestRoundData(125_227_595_982);

        uint256 marketMakerBalanceBefore = IERC20(DEFAULT_ENGINE_PARAMS.usdc).balanceOf(DEFAULT_ENGINE_PARAMS.marketMaker);

        uint256 traderBalanceBefore = (DEFAULT_ENGINE_PARAMS.trader).balance;

        vault.matureVault();

        uint256 marketMakerBalanceAfter = IERC20(DEFAULT_ENGINE_PARAMS.usdc).balanceOf(DEFAULT_ENGINE_PARAMS.marketMaker);

        uint256 traderBalanceAfter = (DEFAULT_ENGINE_PARAMS.trader).balance;

        assertEq(marketMakerBalanceAfter, marketMakerBalanceBefore);
        console2.log("traderBalanceBefore: %s", traderBalanceBefore);
        console2.log("traderBalanceAfter: %s", traderBalanceAfter);
        assertEq(traderBalanceAfter - traderBalanceBefore, 10_925_865_100_534_294);
    }
}
