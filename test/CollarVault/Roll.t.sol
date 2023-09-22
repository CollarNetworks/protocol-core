// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import {CollarEngine} from "../../src/CollarEngine.sol";
import {CollarVault} from "../../src/CollarVault.sol";
import {EngineUtils} from "../utils/EngineUtils.sol";
import {VaultUtils} from "../utils/VaultUtils.sol";
import {IERC20} from "../../src/interfaces/external/IERC20.sol";

contract CollarVault_RollTest is Test, EngineUtils, VaultUtils {
    CollarEngine engine;
    CollarVault vault;

    function setUp() public {
        engine = deployEngine();

        hoax(averageJoe);
        engine.requestPrice(DEFAULT_QTY, DEFAULT_LTV, DEFAULT_MATURITY_TIMESTAMP, "");

        startHoax(marketMakerMike);
        engine.ackPrice(averageJoe);
        engine.showPrice(averageJoe, DEFAULT_CALL_STRIKE_PCT);

        hoax(averageJoe);
        engine.clientGiveOrder{value: DEFAULT_QTY}();

        hoax(marketMakerMike);
        engine.executeTrade(averageJoe);

        vault = CollarVault(payable(engine.getLastTradeVault(averageJoe)));
        vm.label(address(vault), "CollarVault");
    }

    function test_Balances() public {
        assertGt(IERC20(usdc).balanceOf(address(vault)), 25656733);
        assertEq(address(vault).balance, 0);
    }
}
