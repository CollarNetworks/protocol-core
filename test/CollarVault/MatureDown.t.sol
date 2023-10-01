// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import {CollarEngine} from "../../src/CollarEngine.sol";
import {CollarVault} from "../../src/CollarVault.sol";
import {EngineUtils} from "../utils/EngineUtils.sol";
import {VaultUtils} from "../utils/VaultUtils.sol";
import {IERC20} from "../../src/interfaces/external/IERC20.sol";
import {TestERC20} from "../utils/mocks/TestERC20.sol";
import {MockOracle} from "../utils/mocks/MockOracle.sol";

// Tests converted from ./old/test-vault-and-roll.js

contract CollarVault_MatureDown is Test, VaultUtils {
    CollarEngine engine;
    CollarVault vault;

    function setUp() public override {
        super.setUp();

        engine = deployEngine();

        MockOracle(DEFAULT_ENGINE_PARAMS.ethUSDOracle).setLatestRoundData(117_227_595_982);

        VaultDeployParams memory vaultParams = VaultDeployParams({
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
            991_040_872 * 2, //lent
            1_165_995_893 * 2, //fill
            116_599_590 * 2, //collat
            139_919_507 * 2, //proceeds
            DEFAULT_ENGINE_PARAMS.weth
        );

        vault.postTradeDetailsB(
            34_979_876 * 2, //fee
            DEFAULT_ENGINE_PARAMS.feeWallet, //feewallet
            DEFAULT_ENGINE_PARAMS.rake, //feerate
            DEFAULT_ENGINE_PARAMS.marketMaker, //mm
            DEFAULT_ENGINE_PARAMS.trader //client);
        );

        TestERC20(DEFAULT_ENGINE_PARAMS.usdc).mintTo(DEFAULT_ENGINE_PARAMS.trader, 1_000_000 * 1e6);
        TestERC20(DEFAULT_ENGINE_PARAMS.usdc).mintTo(DEFAULT_ENGINE_PARAMS.marketMaker, 1_000_000 * 1e6);
        TestERC20(DEFAULT_ENGINE_PARAMS.usdc).mintTo(address(vault), 116_599_590 * 2);
        TestERC20(DEFAULT_ENGINE_PARAMS.usdc).mintTo(address(vault), 139_919_507 * 2);
        TestERC20(DEFAULT_ENGINE_PARAMS.usdc).mintTo(DEFAULT_ENGINE_PARAMS.trader, 991_096_509 * 2);
    }

    function test_matureVaultDown() public {
        uint256 traderEthBalanceBefore = address(DEFAULT_ENGINE_PARAMS.trader).balance;
        uint256 marketMakerBalanceBefore =
            IERC20(DEFAULT_ENGINE_PARAMS.usdc).balanceOf(DEFAULT_ENGINE_PARAMS.marketMaker);

        startHoax(DEFAULT_ENGINE_PARAMS.marketMaker);
        vault.matureVault();

        uint256 traderEthBalanceAfter = address(DEFAULT_ENGINE_PARAMS.trader).balance;
        uint256 marketMakerBalanceAfter =
            IERC20(DEFAULT_ENGINE_PARAMS.usdc).balanceOf(DEFAULT_ENGINE_PARAMS.marketMaker);

        assertEq(marketMakerBalanceAfter - marketMakerBalanceBefore, 51_303_819);
        assertEq(traderEthBalanceAfter, traderEthBalanceBefore);
    }
}