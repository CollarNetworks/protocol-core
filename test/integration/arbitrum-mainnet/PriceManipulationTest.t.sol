// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "forge-std/Test.sol";
import "./DeploymentLoader.sol";
import { PriceManipulationLib } from "../utils/PriceManipulation.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract PriceManipulationTest is Test, DeploymentLoader {
    address constant USDC = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
    address constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    uint constant callStrikePercent = 11_500; // 115%
    uint constant putStrikePercent = 9000; // 90%
    uint24 constant POOL_FEE = 500;
    address constant swapRouterAddress = 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;

    address whale = makeAddr("whale");

    DeploymentHelper.AssetPairContracts internal pair;

    function setUp() public override {
        // Setup fork from arbitrum mainnet
        string memory ARBITRUM_RPC = vm.envString("ARBITRUM_MAINNET_RPC");
        vm.createSelectFork(ARBITRUM_RPC);

        // Get pair setup from DeploymentLoader
        super.setUp();
        pair = getPairByAssets(USDC, WETH);
        require(address(pair.loansContract) != address(0), "Pair not found");

        // Fund whale for swaps
        deal(address(pair.cashAsset), whale, 100_000_000e6); // 100M USDC
        deal(address(pair.underlying), whale, 100_000 ether); // 100000 ETH
    }

    function test_PriceUpPastCallStrike() public {
        uint initialPrice = pair.takerNFT.currentOraclePrice();
        console.log("Initial price:", initialPrice);

        uint priceAfterMove = PriceManipulationLib.movePriceUpPastCallStrike(
            vm,
            swapRouterAddress,
            whale,
            pair.cashAsset,
            pair.underlying,
            pair.oracle,
            callStrikePercent,
            POOL_FEE
        );

        console.log("Price after move:", priceAfterMove);
        uint targetPrice = initialPrice * callStrikePercent / 10_000;
        assertTrue(priceAfterMove > targetPrice, "Failed to move price up past call strike");
    }

    function test_PriceDownPastPutStrike() public {
        uint initialPrice = pair.takerNFT.currentOraclePrice();
        console.log("Initial price:", initialPrice);

        uint priceAfterMove = PriceManipulationLib.movePriceDownPastPutStrike(
            vm,
            swapRouterAddress,
            whale,
            pair.cashAsset,
            pair.underlying,
            pair.oracle,
            putStrikePercent,
            POOL_FEE
        );

        console.log("Price after move:", priceAfterMove);
        uint targetPrice = initialPrice * putStrikePercent / 10_000;
        assertTrue(priceAfterMove < targetPrice, "Failed to move price down past put strike");
    }

    function test_PriceUpPartially() public {
        uint initialPrice = pair.takerNFT.currentOraclePrice();
        console.log("Initial price:", initialPrice);

        // Calculate call strike price for bounds check
        uint callStrikePrice = (initialPrice * callStrikePercent) / 10_000;

        uint priceAfterMove = PriceManipulationLib.movePriceUpPartially(
            vm, swapRouterAddress, whale, pair.cashAsset, pair.underlying, pair.oracle, POOL_FEE
        );
        console.log("Price after move:", priceAfterMove);

        assertTrue(priceAfterMove > initialPrice, "Price should have increased");
        assertTrue(priceAfterMove < callStrikePrice, "Price should remain below call strike");
    }
}
