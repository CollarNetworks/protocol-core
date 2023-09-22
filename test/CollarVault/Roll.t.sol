// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import {CollarEngine} from "../../src/CollarEngine.sol";
import {IERC20} from "../../src/interfaces/external/IERC20.sol";

contract CollarEngine_RollTest is Test {
    CollarEngine engine;

    uint256 rake;
    address owner;
    address feeWallet;
    address marketMakerMike;
    address averageJoe;
    address usdc;
    address testDex;
    address ethUSDOracle;
    address weth;

    uint256 constant testQTY = 0.1 ether;
    uint256 constant testLTV = 85;
    uint256 constant maturityTimestamp = 1670337200;

    function setUp() public {
        rake = 3;

        owner = makeAddr("owner");
        feeWallet = makeAddr("fee");
        marketMakerMike = makeAddr("mike");
        averageJoe = makeAddr("joe");
        usdc = makeAddr("usdc");
        testDex = makeAddr("dex");
        ethUSDOracle = makeAddr("oracle");
        weth = makeAddr("weth");

        hoax(owner);

        engine = new CollarEngine(
            rake,
            feeWallet,
            marketMakerMike,
            usdc,
            testDex,
            ethUSDOracle,
            weth
        );

        vm.label(address(engine), "CollarEngine");
    }
}
