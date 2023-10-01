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

contract CollarVault_RollDown is Test, VaultUtils {
    uint256 laterTimestampForRolling = block.timestamp + (100 * 30 * 24 * 60 * 60);

    CollarEngine engine;
    CollarVault vault;

    function setUp() public override {
        super.setUp();

        engine = deployEngine();

        VaultDeployParams memory vaultParams = VaultDeployParams({
            admin: makeAddr("Owner"),
            rfqid: DEFAULT_RFQID,
            qty: DEFAULT_QTY,
            lendAsset: mockUni.tokenA,
            putStrikePct: DEFAULT_PUT_STRIKE_PCT,
            callStrikePct: DEFAULT_CALL_STRIKE_PCT,
            maturityTimestamp: block.timestamp + (3 * 24 * 60 * 60),
            dexRouter: mockUni.router,
            priceFeed: DEFAULT_ENGINE_PARAMS.ethUSDOracle
        });

        MockOracle(DEFAULT_ENGINE_PARAMS.ethUSDOracle).setLatestRoundData(117_227_595_982);

        startHoax(vaultParams.admin);

        vault = new CollarVault(
            vaultParams.admin,
            vaultParams.rfqid,
            vaultParams.qty,
            vaultParams.lendAsset,
            vaultParams.putStrikePct,
            vaultParams.callStrikePct,
            vaultParams.maturityTimestamp,
            vaultParams.dexRouter,
            vaultParams.priceFeed
        );

        vault.postTradeDetailsA(
            991_040_872 * 2, //lent
            1_165_995_893 * 2, //fill
            11_659_959 * 2, //collat
            13_991_950 * 2, //proceeds
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
        TestERC20(DEFAULT_ENGINE_PARAMS.usdc).mintTo(address(vault), 11_659_960 * 2);
        TestERC20(DEFAULT_ENGINE_PARAMS.usdc).mintTo(address(vault), 13_991_951 * 2);
        TestERC20(DEFAULT_ENGINE_PARAMS.usdc).mintTo(DEFAULT_ENGINE_PARAMS.trader, 99_109_651 * 2);
    }

    function test_rollUpPhysical() public {
        vault.requestRollPrice(85, laterTimestampForRolling);

        startHoax(DEFAULT_ENGINE_PARAMS.trader);

        IERC20(DEFAULT_ENGINE_PARAMS.usdc).approve(address(vault), 10_000 * 1e6);

        vault.setSettleType(2);
        vault.postPhysical{value: 0.1 ether}();

        startHoax(DEFAULT_ENGINE_PARAMS.marketMaker);

        vault.showRollPrice(110);

        startHoax(DEFAULT_ENGINE_PARAMS.trader);

        vault.giveRollOrder();

        startHoax(DEFAULT_ENGINE_PARAMS.marketMaker);

        IERC20(DEFAULT_ENGINE_PARAMS.usdc).approve(address(vault), 10_000 * 1e6);
        vault.executeRoll();

        (
            uint256 _qty,
            uint256 _lent,
            address _lendAsset,
            uint256 _putstrikePct,
            uint256 _callstrikePct,
            uint256 _maturityTimestamp,
            uint256 _fill,
            uint256 _mmCollateral,
            uint256 _proceeds,
            ,
            ,
            uint256 _rollCount
        ) = vault.getVaultDetails();

        assertEq(_qty, DEFAULT_QTY, "Vault quantity incorrect");

        assertEq(_lent, 99_643_456, "Vault lent amount incorrect");

        assertEq(_lendAsset, DEFAULT_ENGINE_PARAMS.usdc, "Vault lend asset incorrect");

        assertEq(_putstrikePct, DEFAULT_PUT_STRIKE_PCT, "Vault put strike pct incorrect");
        assertEq(_callstrikePct, DEFAULT_CALL_STRIKE_PCT, "Vault call strike pct incorrect");

        assertEq(_maturityTimestamp, laterTimestampForRolling, "Vault maturity timestamp incorrect");

        assertEq(_fill, 1_172_275_959, "Vault fill amount incorrect");

        assertEq(_mmCollateral, 11_722_759, "Vault mm collateral incorrect");

        assertEq(_proceeds, 14_067_311, "Vault proceeds incorrect");

        assertEq(_rollCount, 1, "Vault roll count incorrect");
    }

    function test_rollUpCash() public {
        vault.requestRollPrice(85, laterTimestampForRolling);

        startHoax(DEFAULT_ENGINE_PARAMS.trader);

        IERC20(DEFAULT_ENGINE_PARAMS.usdc).approve(address(vault), 10_000 * 1e6);

        vault.setSettleType(1);
        vault.postCash(100 * 1e6);

        startHoax(DEFAULT_ENGINE_PARAMS.marketMaker);

        vault.showRollPrice(110);

        startHoax(DEFAULT_ENGINE_PARAMS.trader);

        vault.giveRollOrder();

        startHoax(DEFAULT_ENGINE_PARAMS.marketMaker);

        IERC20(DEFAULT_ENGINE_PARAMS.usdc).approve(address(vault), 10_000 * 1e6);
        vault.executeRoll();

        (
            uint256 _qty,
            uint256 _lent,
            address _lendAsset,
            uint256 _putstrikePct,
            uint256 _callstrikePct,
            uint256 _maturityTimestamp,
            uint256 _fill,
            uint256 _mmCollateral,
            uint256 _proceeds,
            ,
            ,
            uint256 _rollCount
        ) = vault.getVaultDetails();

        assertEq(_qty, DEFAULT_QTY, "Vault quantity incorrect");

        assertEq(_lent, 99_643_456, "Vault lent amount incorrect");

        assertEq(_lendAsset, DEFAULT_ENGINE_PARAMS.usdc, "Vault lend asset incorrect");

        assertEq(_putstrikePct, DEFAULT_PUT_STRIKE_PCT, "Vault put strike pct incorrect");
        assertEq(_callstrikePct, DEFAULT_CALL_STRIKE_PCT, "Vault call strike pct incorrect");

        assertEq(_maturityTimestamp, laterTimestampForRolling, "Vault maturity timestamp incorrect");

        assertEq(_fill, 1_172_275_959, "Vault fill amount incorrect");

        assertEq(_mmCollateral, 11_722_759, "Vault mm collateral incorrect");

        assertEq(_proceeds, 14_067_311, "Vault proceeds incorrect");

        assertEq(_rollCount, 1, "Vault roll count incorrect");
    }
}
