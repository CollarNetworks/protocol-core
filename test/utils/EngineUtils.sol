// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import {CollarEngine} from "../../src/CollarEngine.sol";
import {AddressBook, DefaultConstants} from "./CommonUtils.sol";

/// @dev Inherit this contract into a test contract to get access to the deployEngine function
abstract contract EngineUtils is Test, AddressBook, DefaultConstants {
    struct EngineDeployParams {
        uint256 rake;
        address feeWallet;
        address marketMakerMike;
        address usdc;
        address testDex;
        address ethUSDOracle;
        address weth;
        address averageJoe;
        address owner;
    }

    EngineDeployParams DEFAULT_ENGINE_PARAMS = EngineDeployParams({
        rake: DEFAULT_RAKE,
        feeWallet: feeWallet,
        marketMakerMike: marketMakerMike,
        usdc: usdc,
        testDex: testDex,
        ethUSDOracle: ethUSDOracle,
        weth: weth,
        averageJoe: averageJoe,
        owner: owner
    });

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
            params.marketMakerMike,
            params.usdc,
            params.testDex,
            params.ethUSDOracle,
            params.weth
        );

        vm.label(address(engine), "CollarEngine");

        return engine;
    }
}
