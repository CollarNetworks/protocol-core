// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import { IUniswapV3Factory } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import { IStaticOracle } from "@mean-finance/interfaces/IStaticOracle.sol";
import { StaticOracle } from "@mean-finance/implementations/StaticOracle.sol";

// Polygon Addresses for Uniswap V3

// UniswapV3Factory - - - - - - - - - - 0x1F98431c8aD98523631AE4a59f267346ea31F984
// QuoterV2 - - - - - - - - - - - - - - 0x61fFE014bA17989E743c5F6cB21bF9697530B21e
// SwapRouter02 - - - - - - - - - - - - 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45
// UniversalRouter  - - - - - - - - - - 0xec7BE89e9d109e7e3Fec59c222CF297125FEFda2
// NonFungiblePositionManager - - - - - 0xC36442b4a4522E871399CD717aBDD847Ab11FE88
// TickLens - - - - - - - - - - - - - - 0xbfd8137f7d1516D3ea5cA83523914859ec47F573
// WMatic - - - - - - - - - - - - - - - 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270
// USDC - - - - - - - - - - - - - - - - 0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359
// WMatic / USDC UniV3 Pool - - - - - - 0x2DB87C4831B2fec2E35591221455834193b50D1B
// Mean Finance Polygon Static Oracle - 0xB210CE856631EeEB767eFa666EC7C1C57738d438

contract MeanFinanceStaticOracleTest is Test {
    /*

    This contract is just to test the Mean Finance Static Oracle contract
    It probably has issues reading when we roll the fork, since no new 
    observations are being pushed into the oracle, but not sure.

    So this will test variations of the static oracle to see where it breaks,
    and help me figure out how to use it.

    Observation 1:  The static oracle was updated with the "offsets" feature, on github,
                    AFTER it was first deployed to Polgyon. Thus the version deployed to
                    Polygon does not have this feature, and the call to quote...offsettedTimePeriod
                    fails. Therefore we need to deploy the new version to mainnet ourselves,
                    but for now we'll just do it in the fork.

    */

    address wMatic = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;
    address usdc = 0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359;
    address uniV3Factory = 0x1F98431c8aD98523631AE4a59f267346ea31F984;

    //IStaticOracle oracle = IStaticOracle(0xB210CE856631EeEB767eFa666EC7C1C57738d438);

    function setUp() public {
        string memory forkRPC = vm.envString("POLYGON_MAINNET_RPC");
        vm.createSelectFork(forkRPC, 55_850_000);
        assertEq(block.number, 55_850_000);
    }

    function test_staticOracleAfterForking() public {
        // first, deploy the static oracle
        // two args: uni v3 factory and cardinality
        // the uni v3 factory on polygon is 0x1F98431c8aD98523631AE4a59f267346ea31F984
        // the cardinality used to deploy v1 is 30, so we'll just that for now

        IStaticOracle oracle = new StaticOracle(IUniswapV3Factory(uniV3Factory), 30);

        // tries to quote 1e18 of wMatic in USDC via pool with fee tier 0.3%,
        // via TWAP of 15 minutes long starting 30 minutes ago

        uint24[] memory feeTiers = new uint24[](1);
        feeTiers[0] = 3000;

        uint256 result;
        //address[] memory poolsQueried;

        (result, /*poolsQueried*/ ) = oracle.quoteSpecificFeeTiersWithOffsettedTimePeriod(
            1e18, wMatic, usdc, feeTiers, 15 minutes, 30 minutes
        );

        console.log("Amount of USDC received for 1e18 wMatic: ", result);
    }

    function test_staticOracleAfterForkingAndFastForwarding() public {
        // first, deploy the static oracle
        // two args: uni v3 factory and cardinality
        // the uni v3 factory on polygon is 0x1F98431c8aD98523631AE4a59f267346ea31F984
        // the cardinality used to deploy v1 is 30, so we'll just that for now

        IStaticOracle oracle = new StaticOracle(IUniswapV3Factory(uniV3Factory), 30);

        // tries to quote 1e18 of wMatic in USDC via pool with fee tier 0.3%,
        // via TWAP of 15 minutes long starting 30 minutes ago

        uint24[] memory feeTiers = new uint24[](1);
        feeTiers[0] = 3000;

        uint256 result;

        // this time we roll the blockchain forward a bit
        vm.roll(block.number + 450); // polygon block time = 2 seconds per block, so we skip forward (15
            // minutes in seconds / 2) blocks
        skip(15 minutes);

        (result, /*poolsQueried*/ ) = oracle.quoteSpecificFeeTiersWithOffsettedTimePeriod(
            1e18, wMatic, usdc, feeTiers, 15 minutes, 30 minutes
        );

        console.log("Amount of USDC received for 1e18 wMatic: ", result);
    }

    function test_staticOracleAfterForkingAndFastForwardingALot() public {
        // first, deploy the static oracle
        // two args: uni v3 factory and cardinality
        // the uni v3 factory on polygon is 0x1F98431c8aD98523631AE4a59f267346ea31F984
        // the cardinality used to deploy v1 is 30, so we'll just that for now

        IStaticOracle oracle = new StaticOracle(IUniswapV3Factory(uniV3Factory), 30);

        // tries to quote 1e18 of wMatic in USDC via pool with fee tier 0.3%,
        // via TWAP of 15 minutes long starting 30 minutes ago

        uint24[] memory feeTiers = new uint24[](1);
        feeTiers[0] = 3000;

        uint256 result;

        // this time we roll the blockchain forward a few days
        vm.roll(block.number + 129_600); // polygon block time = 2 seconds per block, so we skip forward (3
            // days in seconds / 2) blocks
        skip(3 days);

        (result, /*poolsQueried*/ ) = oracle.quoteSpecificFeeTiersWithOffsettedTimePeriod(
            1e18, wMatic, usdc, feeTiers, 15 minutes, 30 minutes
        );

        console.log("Amount of USDC received for 1e18 wMatic: ", result);
    }
}
