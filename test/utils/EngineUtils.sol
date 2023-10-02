// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test} from "@forge-std/Test.sol";
import {CollarEngine} from "../../src/CollarEngine.sol";
import {DefaultConstants} from "./CommonUtils.sol";
import {UniswapV3Mocks} from "./mocks/MockUniV3.sol";
import {MockOracle} from "./mocks/MockOracle.sol";

/// @dev Inherit this contract into a test contract to get access to the deployEngine function
abstract contract EngineUtils is Test, DefaultConstants {
    UniswapV3Mocks mocks;

    struct EngineDeployParams {
        uint256 rake;
        address feeWallet;
        address marketMaker;
        address usdc;
        address testDex;
        address ethUSDOracle;
        address weth;
        address trader;
        address owner;
    }

    EngineDeployParams DEFAULT_ENGINE_PARAMS;

    function setUp() public virtual {
        mocks = new UniswapV3Mocks();

        DEFAULT_ENGINE_PARAMS = EngineDeployParams({
            rake: DEFAULT_RAKE,
            feeWallet: makeAddr("FeeWallet"),
            marketMaker: makeAddr("MarketMaker"),
            usdc: mocks.tokenA(),
            testDex: mocks.router(),
            ethUSDOracle: deployMockOracle(),
            weth: mocks.weth(),
            trader: makeAddr("Trader"),
            owner: makeAddr("Owner")
        });

        vm.label(DEFAULT_ENGINE_PARAMS.feeWallet, "FeeWallet");
        vm.label(DEFAULT_ENGINE_PARAMS.marketMaker, "MarketMaker");
        vm.label(DEFAULT_ENGINE_PARAMS.usdc, "USDC");
        vm.label(DEFAULT_ENGINE_PARAMS.testDex, "TestDex");
        vm.label(DEFAULT_ENGINE_PARAMS.ethUSDOracle, "EthUSDOracle");
        vm.label(DEFAULT_ENGINE_PARAMS.weth, "WETH");
        vm.label(DEFAULT_ENGINE_PARAMS.trader, "Trader");
        vm.label(DEFAULT_ENGINE_PARAMS.owner, "Owner");
    }

    function deployMockOracle() public returns (address) {
        return address(new MockOracle());
    }

    /// @dev Deploys a new CollarEngine with default params (above)
    function deployEngine() public returns (CollarEngine engine) {
        // Explicit external call so that we can put the struct in calldata and not memory
        return EngineUtils(address(this)).deployEngine(DEFAULT_ENGINE_PARAMS);
    }

    /// @dev Deploys a new CollarEngine with the given params as a struct
    /// @param params The params to use for the engine
    /// @return engine The deployed engine
    function deployEngine(EngineDeployParams calldata params) public returns (CollarEngine engine) {
        hoax(params.owner);

        engine = new CollarEngine(
            params.rake,
            params.feeWallet,
            params.marketMaker,
            params.usdc,
            params.testDex,
            params.ethUSDOracle,
            params.weth
        );

        vm.label(address(engine), "CollarEngine");

        return engine;
    }
}
