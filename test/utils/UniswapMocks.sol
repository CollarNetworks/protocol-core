// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import {IERC20} from "../../src/interfaces/external/IERC20.sol";
import {SwapRouter} from "@uniswap/v3-periphery/contracts/SwapRouter.sol";

// Mocks for Uniswap contracts

interface WETH9 is IERC20 {
    function deposit() external payable;
}

// Base fixture deploying V3 Factory, V3 Router and WETH9
contract V3RouterFixture is Test {
    IUniswapV3Factory public factory;
    WETH9 public weth9;
    SwapRouter public router;

    // Deploys WETH9 and V3 Core's Factory contract, and then
    // hooks them on the router
    function setUp() public virtual {
        address _weth9 = deployCode(weth9Artifact);
        weth9 = WETH9(_weth9);

        address _factory = deployCode(v3FactoryArtifact);
        factory = IUniswapV3Factory(_factory);

        router = new SwapRouter(_factory, _weth9);
    }
}
