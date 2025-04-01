// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "forge-std/console.sol";

import { IERC20, IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { Const } from "../../../script/utils/Const.sol";
import { OPBaseSepoliaDeployer, BaseDeployer } from "../../../script/libraries/OPBaseSepoliaDeployer.sol";
import { BaseAssetPairForkTest } from "./BaseAssetPairForkTest.sol";
import { ConfigHub } from "../../../src/ConfigHub.sol";
import { TWAPMockChainlinkFeed } from "../../utils/TWAPMockChainlinkFeed.sol";
import { FixedMockChainlinkFeed } from "../../utils/FixedMockChainlinkFeed.sol";
import { BaseTakerOracle } from "../../../src/ChainlinkOracle.sol";
import { CollarOwnedERC20 } from "../../utils/CollarOwnedERC20.sol";

import { DeployOPBaseSepoliaAssets_WithCashAsset } from "../../../script/deploy/deploy-testnet-assets.s.sol";

contract AssetDeployForkTest is BaseAssetPairForkTest {
    int constant USDSTABLEPRICE = 100_000_000;

    function setupNewFork() internal {
        vm.createSelectFork(vm.envString("OPBASE_SEPOLIA_RPC"));
    }

    function _setTestValues() internal override {
        protocolFeeRecipient = Const.OPBaseSep_feeRecipient;

        expectedNumPairs = 1;
        expectedPairIndex = 0;
        oracleDescription = "Comb(CL(TWAPMock(tWBTC / USD))|inv(CL(FixedMock(tUSDC / USD))))";

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
        expectedOraclePrice = 100_000_000_000; // 100k 1e6
    }

    function getDeployedContracts()
        internal
        override
        returns (ConfigHub hub, BaseDeployer.AssetPairContracts[] memory pairs)
    {
        setupNewFork();

        // Deploy assets using existing script
        DeployOPBaseSepoliaAssets_WithCashAsset deployer = new DeployOPBaseSepoliaAssets_WithCashAsset();
        deployer.run();

        // get the new asset addresses
        cashAsset = deployer.deployedAssets("tUSDC");
        underlying = deployer.deployedAssets("tWBTC");

        // draw the rest of the owl
        return deployerProtocolForNewPair();
    }

    function deployerProtocolForNewPair()
        internal
        returns (ConfigHub hub, BaseDeployer.AssetPairContracts[] memory pairs)
    {
        // Deploy mock oracles (no CL feeds)
        BaseTakerOracle oracletWBTC_USD = deployMockOracleBTCUSD();
        BaseTakerOracle oracletUSDC_USD = deployMockOracleUSDCUSD();

        // wait for the initial observations to be old enough for the TWAP mock oracle
        skip(300);

        // protocol deployment

        // Use owner for protocol deployment to avoid the need for ownership transfer
        owner = Const.OPBaseSep_owner;
        vm.startPrank(owner);

        // deploy hub and configure
        hub = BaseDeployer.deployConfigHub(owner);
        BaseDeployer.setupConfigHub(hub, OPBaseSepoliaDeployer.defaultHubParams());

        // deploy and configure new pair
        pairs = new BaseDeployer.AssetPairContracts[](1);
        pairs[0] = BaseDeployer.deployContractPair(
            hub,
            BaseDeployer.PairConfig({
                name: "tWBTC-tUSDC",
                underlying: IERC20(underlying),
                cashAsset: IERC20(cashAsset),
                oracle: BaseDeployer.deployCombinedOracle(
                    underlying,
                    cashAsset,
                    oracletWBTC_USD,
                    oracletUSDC_USD,
                    true,
                    "Comb(CL(TWAPMock(tWBTC / USD))|inv(CL(FixedMock(tUSDC / USD))))"
                ),
                swapFeeTier: 500,
                swapRouter: Const.OPBaseSep_UniRouter,
                existingEscrowNFT: address(0)
            })
        );
        BaseDeployer.setupContractPair(hub, pairs[0]);

        vm.stopPrank();
    }

    function deployMockOracleBTCUSD() internal returns (BaseTakerOracle oracle) {
        TWAPMockChainlinkFeed mockBTCUSDFeed = new TWAPMockChainlinkFeed(
            underlying, cashAsset, 500, Const.OPBaseSep_UniRouter, 8, "tWBTC / USD", 18
        );
        mockBTCUSDFeed.increaseCardinality(300);
        BaseDeployer.ChainlinkFeed memory feedBTC_USD =
            BaseDeployer.ChainlinkFeed(address(mockBTCUSDFeed), "TWAPMock(tWBTC / USD)", 120, 8, 30);
        oracle = BaseDeployer.deployChainlinkOracle(underlying, Const.VIRTUAL_ASSET, feedBTC_USD, address(0));
    }

    function deployMockOracleUSDCUSD() internal returns (BaseTakerOracle oracle) {
        FixedMockChainlinkFeed mockUsdcUsdFeed = new FixedMockChainlinkFeed(USDSTABLEPRICE, 8, "tUSDC / USD");
        BaseDeployer.ChainlinkFeed memory feedUSDC_USD =
            BaseDeployer.ChainlinkFeed(address(mockUsdcUsdFeed), "FixedMock(tUSDC / USD)", 86_400, 8, 30);
        oracle = BaseDeployer.deployChainlinkOracle(cashAsset, Const.VIRTUAL_ASSET, feedUSDC_USD, address(0));
    }

    // added tests

    function testSwapRatio() public {
        // 1 unit of underlying
        uint amountIn = 10 ** IERC20Metadata(underlying).decimals();
        deal(underlying, address(this), amountIn);

        // use the default swapper
        IERC20(underlying).approve(address(pair.swapperUniV3), amountIn);
        uint amountOut = pair.swapperUniV3.swap(IERC20(underlying), IERC20(cashAsset), amountIn, 0, "");

        uint feeBasis = 1e6; // uniswap's fee basis is PPM
        // because these assets were just deployed and we just initialized the pools
        // we expect to be exactly at oracle price minus swap fee, minus some slippage
        uint expectedOut = expectedOraclePrice * (feeBasis - swapPoolFeeTier) / feeBasis;
        assertApproxEqRel(amountOut, expectedOut, 0.0001e18); // tolerance is 1e18 fraction
    }
}
