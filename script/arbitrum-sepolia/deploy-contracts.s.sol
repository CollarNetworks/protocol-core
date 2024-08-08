// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import { ConfigHub } from "../../src/ConfigHub.sol";
import { ProviderPositionNFT } from "../../src/ProviderPositionNFT.sol";
import { CollarTakerNFT } from "../../src/CollarTakerNFT.sol";
import { Loans } from "../../src/Loans.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Rolls } from "../../src/Rolls.sol";
import { DeploymentUtils } from "../utils/deployment-exporter.s.sol";
import { BaseDeployment } from "../base.s.sol";
import { IUniswapV3Factory } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import { IV3SwapRouter } from "@uniswap/swap-router-contracts/contracts/interfaces/IV3SwapRouter.sol";
import { CollarOwnedERC20 } from "../../test/utils/CollarOwnedERC20.sol";
import "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import { IPeripheryImmutableState } from
    "@uniswap/v3-periphery/contracts/interfaces/IPeripheryImmutableState.sol";
import { OracleUniV3TWAP } from "../../src/OracleUniV3TWAP.sol";

contract DeployContracts is Script, DeploymentUtils, BaseDeployment {
    uint chainId = 421_614; // Arbitrum Sepolia chain ID
    IV3SwapRouter constant SWAP_ROUTER = IV3SwapRouter(0x101F443B4d1b059569D643917553c771E1b9663E);
    CollarOwnedERC20 constant cashAsset = CollarOwnedERC20(0x5D01F1E59C188a2A9Afc376cF6627dd5F28DC28F);
    CollarOwnedERC20 constant collateralAsset = CollarOwnedERC20(0x9A6E1a5f94De0aD8ca15b55eA0d39bEaEc579434);
    INonfungiblePositionManager constant POSITION_MANAGER =
        INonfungiblePositionManager(0x6b2937Bde17889EDCf8fbD8dE31C3C2a70Bc4d65);
    uint duration = 300;
    uint ltv = 9000;
    uint amountToProvideToPool = 10_000_000 ether;

    function run() external {
        require(chainId == block.chainid, "chainId does not match the chainId in config");
        (address deployer,,, address provider) = setup();
        deployerAddress = deployer;

        vm.startBroadcast(deployer);
        address[] memory collateralAssets = new address[](1);
        collateralAssets[0] = address(collateralAsset);
        address[] memory cashAssets = new address[](1);
        cashAssets[0] = address(cashAsset);
        _deployandSetupConfigHub(
            address(SWAP_ROUTER), collateralAssets, cashAssets, ltv, ltv, duration, duration
        );
        _createOrValidateUniswapPool(provider);
        uint[] memory durations = new uint[](1);
        durations[0] = duration;
        uint[] memory ltvs = new uint[](1);
        ltvs[0] = ltv;
        AssetPairContracts memory contracts = _createContractPair(
            IERC20(cashAsset), IERC20(collateralAsset), "COLLATERAL/CASH", durations, ltvs
        );
        _verifyDeployment(configHub, contracts);
        vm.stopBroadcast();

        AssetPairContracts[] memory contractsArray = new AssetPairContracts[](1);
        contractsArray[0] = contracts;
        exportDeployment("collar_protocol_deployment", address(configHub), router, contractsArray);

        console.log("\nDeployment completed successfully");
    }

    function _verifyDeployment(ConfigHub configHub, AssetPairContracts memory contracts) internal view {
        require(configHub.isCollarTakerNFT(address(contracts.takerNFT)), "TakerNFT not authorized");
        require(configHub.isProviderNFT(address(contracts.providerNFT)), "ProviderNFT not authorized");
        require(configHub.isSupportedCashAsset(address(contracts.cashAsset)), "Cash asset not supported");
        require(
            configHub.isSupportedCollateralAsset(address(contracts.collateralAsset)),
            "Collateral asset not supported"
        );
        require(configHub.isValidLTV(ltv), "LTV  not supported");
        require(configHub.isValidCollarDuration(duration), "duration not supported");
        console.log("Deployment verified successfully");
    }

    function _createOrValidateUniswapPool(address provider) internal {
        IUniswapV3Factory factory = IUniswapV3Factory(IPeripheryImmutableState(router).factory());
        address pool = factory.getPool(address(cashAsset), address(collateralAsset), FEE_TIER);

        if (pool == address(0)) {
            console.log("Creating new Uniswap V3 pool");
            pool = factory.createPool(address(cashAsset), address(collateralAsset), FEE_TIER);
            IUniswapV3Pool(pool).initialize(79_228_162_514_264_337_593_543_950_336); // sqrt(1) * 2^96
                // Approve tokens
            collateralAsset.approve(address(POSITION_MANAGER), type(uint).max);
            cashAsset.approve(address(POSITION_MANAGER), type(uint).max);
            // Get current tick
            (, int24 currentTick,,,,,) = IUniswapV3Pool(pool).slot0();

            // Set price range
            int24 tickLower = currentTick - 600;
            int24 tickUpper = currentTick + 600;
            INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
                token1: address(collateralAsset),
                token0: address(cashAsset),
                fee: FEE_TIER,
                tickLower: tickLower,
                tickUpper: tickUpper,
                amount0Desired: amountToProvideToPool,
                amount1Desired: amountToProvideToPool,
                amount0Min: 0,
                amount1Min: 0,
                recipient: provider,
                deadline: block.timestamp + 15 minutes
            });

            // Add liquidity
            POSITION_MANAGER.mint(params);
        } else {
            console.log("Uniswap V3 pool already exists");
        }

        console.log("Uniswap V3 Pool: ", pool);
    }
}
