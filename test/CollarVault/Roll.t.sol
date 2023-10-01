// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test} from "@forge-std/Test.sol";
import {CollarEngine} from "../../src/CollarEngine.sol";
import {CollarVault} from "../../src/CollarVault.sol";
import {EngineUtils} from "../utils/EngineUtils.sol";
import {VaultUtils} from "../utils/VaultUtils.sol";
import {IERC20} from "../../src/interfaces/external/IERC20.sol";
import {TestERC20} from "../utils/mocks/TestERC20.sol";
import {MockOracle} from "../utils/mocks/MockOracle.sol";

// Tests converted from ./old/test-vault-and-roll.js

contract CollarVault_Roll is Test, VaultUtils {
    CollarEngine engine;
    CollarVault vault;

    function setUp() public override {
        super.setUp();

        engine = deployEngine();

        MockOracle(DEFAULT_ENGINE_PARAMS.ethUSDOracle).setLatestRoundData(117_227_595_982);

        TestERC20(DEFAULT_ENGINE_PARAMS.usdc).mintTo(DEFAULT_ENGINE_PARAMS.trader, 1e24);
        TestERC20(DEFAULT_ENGINE_PARAMS.usdc).mintTo(DEFAULT_ENGINE_PARAMS.marketMaker, 1e24);

        startHoax(DEFAULT_ENGINE_PARAMS.trader);
        TestERC20(DEFAULT_ENGINE_PARAMS.usdc).approve(address(engine), 1e24);
        engine.requestPrice(DEFAULT_QTY, DEFAULT_LTV, DEFAULT_MATURITY_TIMESTAMP, "");

        startHoax(DEFAULT_ENGINE_PARAMS.marketMaker);
        TestERC20(DEFAULT_ENGINE_PARAMS.usdc).approve(address(engine), 1e24);
        engine.ackPrice(DEFAULT_ENGINE_PARAMS.trader);
        engine.showPrice(DEFAULT_ENGINE_PARAMS.trader, DEFAULT_CALL_STRIKE_PCT);

        startHoax(DEFAULT_ENGINE_PARAMS.trader);
        engine.clientGiveOrder{value: DEFAULT_QTY}();

        startHoax(DEFAULT_ENGINE_PARAMS.marketMaker);
        engine.executeTrade(DEFAULT_ENGINE_PARAMS.trader);

        vault = CollarVault(payable(engine.getLastTradeVault(DEFAULT_ENGINE_PARAMS.trader)));

        vm.label(address(vault), "CollarVault");
    }

    function test_Balances() public {
        assertGt(IERC20(DEFAULT_ENGINE_PARAMS.usdc).balanceOf(address(vault)), 25_656_733);
        assertEq(address(vault).balance, 0);
    }

    function test_setSettleType() public {
        assertEq(vault.checkSettleType(), 0);
        startHoax(DEFAULT_ENGINE_PARAMS.trader);
        vault.setSettleType(1);
        assertEq(vault.checkSettleType(), 1);
    }

    function test_setRollPref() public {
        assertEq(vault.checkRollType(), true);
        startHoax(DEFAULT_ENGINE_PARAMS.trader);
        vault.setRollPref(false);
        assertEq(vault.checkRollType(), false);
    }

    function test_getVaultDetails() public {
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
            address _engine,
            uint256 _rfqid,
            /*uint256 _rollcount*/
        ) = vault.getVaultDetails();

        assertEq(_qty, DEFAULT_QTY, "Vault quantity incorrect");

        assertGt(_lent, 99_100_000, "Vault lent amount too low");
        assertLt(_lent, 99_200_000, "Vault lent amount too high");

        assertEq(_lendAsset, DEFAULT_ENGINE_PARAMS.usdc, "Vault lend asset incorrect");

        assertEq(_putstrikePct, DEFAULT_PUT_STRIKE_PCT, "Vault put strike pct incorrect");
        assertEq(_callstrikePct, DEFAULT_CALL_STRIKE_PCT, "Vault call strike pct incorrect");

        assertEq(_maturityTimestamp, DEFAULT_MATURITY_TIMESTAMP, "Vault maturity timestamp incorrect");

        assertGt(_fill, 1_166_700_000, "Vault fill amount too low");
        assertLt(_fill, 1_166_800_000, "Vault fill amount too high");

        assertGt(_mmCollateral, 11_667_000, "Vault mm collateral too low");
        assertLt(_mmCollateral, 11_668_000, "Vault mm collateral too high");

        assertGt(_proceeds, 14_000_000, "Vault proceeds too low");
        assertLt(_proceeds, 14_010_000, "Vault proceeds too high");

        assertEq(_engine, address(engine), "Vault engine address incorrect");

        assertEq(_rfqid, DEFAULT_RFQID, "Vault rfqid incorrect");
    }
}
