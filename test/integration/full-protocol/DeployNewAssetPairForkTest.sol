// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "forge-std/console.sol";

import { Test } from "forge-std/Test.sol";
import { Const } from "../../../script/utils/Const.sol";
import { BaseDeployer } from "../../../script/libraries/BaseDeployer.sol";
import { DeployOPBaseSepoliaAssets_WithCashAsset } from "../../../script/deploy/deploy-testnet-assets.s.sol";
import { BaseAssetPairForkTest } from "./BaseAssetPairForkTest.sol";
import { ConfigHub } from "../../../src/ConfigHub.sol";
import { TWAPMockChainlinkFeed } from "../../utils/TWAPMockChainlinkFeed.sol";
import { FixedMockChainlinkFeed } from "../../utils/FixedMockChainlinkFeed.sol";
import { BaseTakerOracle } from "../../../src/ChainlinkOracle.sol";
import { CollarOwnedERC20 } from "../../utils/CollarOwnedERC20.sol";
import { IV3SwapRouter } from "@uniswap/swap-router-contracts/contracts/interfaces/IV3SwapRouter.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract AddNewAssetPairTest is BaseAssetPairForkTest {
    int constant USDSTABLEPRICE = 100_000_000;
    DeployOPBaseSepoliaAssets_WithCashAsset deployer;
    address cash;
    uint priceRatio;

    function deployMockOracleBTCUSD() internal returns (BaseTakerOracle oracle) {
        // Ensure addresses are not zero
        require(underlying != address(0), "underlying zero address");
        require(cash != address(0), "cash zero address");
        console.log("Full deployment trace:");
        console.log("1. Deployer address:", address(deployer));
        console.log("2. Newly deployed underlying:", underlying);
        console.log("3. Newly deployed cash:", cash);
        console.log("4. Router being used:", deployer.uniRouter());
        console.logBytes32(
            keccak256(abi.encode(underlying, cash, 500, deployer.uniRouter(), 8, "tWBTC / USD", 18))
        );
        TWAPMockChainlinkFeed mockBTCUSDFeed =
            new TWAPMockChainlinkFeed(underlying, cash, 500, deployer.uniRouter(), 8, "tWBTC / USD", 18);
        mockBTCUSDFeed.increaseCardinality(300);
        BaseDeployer.ChainlinkFeed memory feedBTC_USD =
            BaseDeployer.ChainlinkFeed(address(mockBTCUSDFeed), "TWAPMock(tWBTC / USD)", 120, 8, 30);
        oracle = BaseDeployer.deployChainlinkOracle(underlying, Const.VIRTUAL_ASSET, feedBTC_USD, address(0));
    }

    function deployMockOracleUSDCUSD() internal returns (BaseTakerOracle oracle) {
        // Ensure addresses are not zero
        require(cash != address(0), "cash zero address");
        FixedMockChainlinkFeed mockUsdcUsdFeed = new FixedMockChainlinkFeed(USDSTABLEPRICE, 8, "USDC / USD");

        BaseDeployer.ChainlinkFeed memory feedUSDC_USD =
            BaseDeployer.ChainlinkFeed(address(mockUsdcUsdFeed), "FixedMock(USDC / USD)", 86_400, 8, 30);
        oracle = BaseDeployer.deployChainlinkOracle(cash, Const.VIRTUAL_ASSET, feedUSDC_USD, address(0));
    }

    function getDeployedContracts()
        internal
        override
        returns (ConfigHub hub, BaseDeployer.AssetPairContracts[] memory pairs)
    {
        setupNewFork();

        // Deploy assets using existing script
        deployer = new DeployOPBaseSepoliaAssets_WithCashAsset();
        deployer.run();
        (string memory underlyingSymbol, string memory cashSymbol,,, uint ratio) = deployer.assetPairs(0); // WBTC is at index 0
        underlying = address(deployer.deployedAssets(underlyingSymbol));
        cash = address(deployer.deployedAssets(cashSymbol));
        priceRatio = ratio;
        // Use owner for deployment
        vm.startPrank(Const.OPBaseSep_owner);

        // Deploy mock oracles
        BaseTakerOracle oracletWBTC_USD = deployMockOracleBTCUSD();
        BaseTakerOracle oracletUSDC_USD = deployMockOracleUSDCUSD();

        // Deploy hub and configure
        hub = BaseDeployer.deployConfigHub(Const.OPBaseSep_owner);

        // Setup hub params
        address[] memory guardians = new address[](1);
        guardians[0] = Const.OPBaseSep_deployerAcc;

        BaseDeployer.HubParams memory hubParams = BaseDeployer.HubParams({
            minLTV: 5000,
            maxLTV: 9000,
            minDuration: 1 days,
            maxDuration: 30 days,
            feeRecipient: Const.OPBaseSep_feeRecipient,
            feeAPR: 90,
            pauseGuardians: guardians
        });

        BaseDeployer.setupConfigHub(hub, hubParams);

        // Deploy new pair
        BaseDeployer.PairConfig memory pairConfig = BaseDeployer.PairConfig({
            name: "tWBTC-USDC",
            underlying: IERC20(Const.OPBaseSep_tWBTC),
            cashAsset: IERC20(cash),
            oracle: BaseDeployer.deployCombinedOracle(
                underlying,
                cash,
                oracletWBTC_USD,
                oracletUSDC_USD,
                true,
                "Comb(CL(TWAPMock(tWBTC / USD))|inv(CL(FixedMock(USDC / USD))))"
            ),
            swapFeeTier: 500,
            swapRouter: deployer.uniRouter(),
            existingEscrowNFT: address(0)
        });

        pairs = new BaseDeployer.AssetPairContracts[](1);
        pairs[0] = BaseDeployer.deployContractPair(Const.OPBaseSep_owner, hub, pairConfig);
        BaseDeployer.setupContractPair(hub, pairs[0]);

        vm.stopPrank();
    }

    function setupNewFork() internal {
        vm.createSelectFork(vm.envString("OPBASE_SEPOLIA_RPC"));
    }

    function _setTestValues() internal override {
        owner = Const.OPBaseSep_owner;
        protocolFeeRecipient = Const.OPBaseSep_feeRecipient;
        pauseGuardians = new address[](1);
        pauseGuardians[0] = Const.OPBaseSep_deployerAcc;

        expectedNumPairs = 1;
        expectedPairIndex = 0;
        underlying = underlying;
        cashAsset = cash;
        oracleDescription = "Comb(CL(TWAPMock(tWBTC / USD))|inv(CL(FixedMock(USDC / USD))))";

        offerAmount = 100_000e6;
        underlyingAmount = 0.1e8;
        minLoanAmount = 0.3e6;
        rollFee = 100e6;
        rollDeltaFactor = 10_000;
        bigCashAmount = 1_000_000e6;
        bigUnderlyingAmount = 100e8;
        swapPoolFeeTier = 500;
        protocolFeeAPR = 90;

        slippage = 100;
        callstrikeToUse = 10_500;
        expectedOraclePrice = 10_000_000_000;
    }

    // function testSwapRatios() public {
    //     // Get the ratios from the deployed contract
    //     CollarOwnedERC20 underlyingToken = CollarOwnedERC20(underlying);
    //     uint amountIn = 10 ** underlyingToken.decimals();
    //     address tokenOwner = underlyingToken.owner();
    //     vm.startPrank(tokenOwner);
    //     underlyingToken.mint(tokenOwner, 10 * amountIn);
    //     IERC20(underlying).approve(deployer.uniRouter(), amountIn);

    //     IV3SwapRouter.ExactInputSingleParams memory params = IV3SwapRouter.ExactInputSingleParams({
    //         tokenIn: underlying,
    //         tokenOut: cashAsset,
    //         fee: swapPoolFeeTier,
    //         recipient: address(this),
    //         amountIn: amountIn,
    //         amountOutMinimum: 0,
    //         sqrtPriceLimitX96: 0
    //     });

    //     uint amountOut = IV3SwapRouter(deployer.uniRouter()).exactInputSingle(params);

    //     uint expectedOut = amountIn * priceRatio / 1e8;
    //     assertApproxEqRel(amountOut, expectedOut, 0.01e18); // 1% tolerance
    //     vm.stopPrank();
    // }
}
