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
        vault = deployVault();
    }
}
