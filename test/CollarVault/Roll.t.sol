// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import {CollarEngine} from "../../src/CollarEngine.sol";
import {CollarVault} from "../../src/CollarVault.sol";
import {EngineUtils} from "../utils/EngineUtils.sol";
import {VaultUtils} from "../utils/VaultUtils.sol";
import {IERC20} from "../../src/interfaces/external/IERC20.sol";

// Tests converted from ./old/test-vault-and-roll.js

contract CollarVault_RollTest is Test, EngineUtils, VaultUtils {
    CollarEngine engine;
    CollarVault vault;

    function setUp() public {
        engine = deployEngine();

        startHoax(averageJoe);
        engine.requestPrice(DEFAULT_QTY, DEFAULT_LTV, DEFAULT_MATURITY_TIMESTAMP, "");

        startHoax(marketMakerMike);
        engine.ackPrice(averageJoe);
        engine.showPrice(averageJoe, DEFAULT_CALL_STRIKE_PCT);

        startHoax(averageJoe);
        engine.clientGiveOrder{value: DEFAULT_QTY}();

        startHoax(marketMakerMike);
        engine.executeTrade(averageJoe);

        vault = CollarVault(payable(engine.getLastTradeVault(averageJoe)));
        vm.label(address(vault), "CollarVault");
    }

    function test_Balances() public {
        assertGt(IERC20(usdc).balanceOf(address(vault)), 25656733);
        assertEq(address(vault).balance, 0);
    }

    function test_setSettleType() public {
        assertEq(vault.checkSettleType(), 0);
        startHoax(averageJoe);
        vault.setSettleType(1);
        assertEq(vault.checkSettleType(), 1);
    }

    function test_setRollPref() public {
        assertEq(vault.checkRollType(), true);
        startHoax(averageJoe);
        vault.setRollPref(false);
        assertEq(vault.checkRollType(), true);
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

        assertEq(_qty, DEFAULT_QTY);

        assertGt(_lent, 99100000);
        assertLt(_lent, 99200000);

        assertEq(_lendAsset, usdc);

        assertEq(_putstrikePct, DEFAULT_PUT_STRIKE_PCT);
        assertEq(_callstrikePct, DEFAULT_CALL_STRIKE_PCT);

        assertEq(_maturityTimestamp, DEFAULT_MATURITY_TIMESTAMP);

        assertGt(_fill, 1166700000);
        assertLt(_fill, 1166800000);

        assertGt(_mmCollateral, 11667000);
        assertLt(_mmCollateral, 11668000);

        assertGt(_proceeds, 14000000);
        assertLt(_proceeds, 14010000);

        assertEq(_engine, address(engine));

        assertEq(_rfqid, DEFAULT_RFQID);
    }
}
