// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import { Const } from "../utils/Const.sol";
import { BaseDeployer, ConfigHub, IERC20, EscrowSupplierNFT, BaseTakerOracle } from "./BaseDeployer.sol";
import { TWAPMockChainlinkFeed } from "../../test/utils/TWAPMockChainlinkFeed.sol";
import { FixedMockChainlinkFeed } from "../../test/utils/FixedMockChainlinkFeed.sol";

library ArbitrumSepoliaDeployer {
    address constant tUSDC = Const.ArbiSep_tUSDC;
    address constant tWETH = Const.ArbiSep_tWETH;
    address constant tWBTC = Const.ArbiSep_tWBTC;

    address constant sequencerFeed = address(0);
    uint24 constant swapFeeTier = 3000;
    int constant USDSTABLEPRICE = 100_000_000; // 1 * 10^8 since feed decimals is 8

    function defaultHubParams() internal pure returns (BaseDeployer.HubParams memory) {
        address[] memory pauseGuardians = new address[](1);
        pauseGuardians[0] = Const.ArbiSep_deployerAcc;
        return BaseDeployer.HubParams({
            minDuration: 5 minutes,
            maxDuration: 365 days,
            minLTV: 2500,
            maxLTV: 9900,
            feeAPR: 90,
            feeRecipient: Const.ArbiSep_feeRecipient,
            pauseGuardians: pauseGuardians
        });
    }

    function deployAndSetupFullProtocol(address thisSender, address finalOwner)
        internal
        returns (BaseDeployer.DeploymentResult memory result)
    {
        require(block.chainid == Const.ArbiSep_chainId, "wrong chainId");

        // hub
        result.configHub = BaseDeployer.deployConfigHub(thisSender);
        BaseDeployer.setupConfigHub(result.configHub, defaultHubParams());

        // pairs
        result.assetPairContracts = deployAllContractPairs(thisSender, result.configHub);
        for (uint i = 0; i < result.assetPairContracts.length; i++) {
            BaseDeployer.setupContractPair(result.configHub, result.assetPairContracts[i]);
        }

        // ownership
        BaseDeployer.nominateNewOwnerAll(finalOwner, result);
    }

    function deployMockOracleETHUSD() internal returns (BaseTakerOracle oracle) {
        // Deploy mock feed for WETH / USDC pair
        TWAPMockChainlinkFeed mockEthUsdFeed = new TWAPMockChainlinkFeed(
            tWETH, // base token
            tUSDC, // quote token
            swapFeeTier, // fee tier
            Const.ArbiSep_UniRouter, // UniV3 router
            8, // feed decimals (ETH/USD uses 8)
            "ETH / USD", // description
            18 // virtual USD decimals
        );
        BaseDeployer.ChainlinkFeed memory feedETH_USD =
            BaseDeployer.ChainlinkFeed(address(mockEthUsdFeed), "TWAPMock(ETH / USD)", 120, 8, 5);
        oracle = BaseDeployer.deployChainlinkOracle(tWETH, Const.VIRTUAL_ASSET, feedETH_USD, sequencerFeed);
    }

    function deployMockOracleBTCUSD() internal returns (BaseTakerOracle oracle) {
        TWAPMockChainlinkFeed mockBTCUSDFeed = new TWAPMockChainlinkFeed(
            tWBTC, // base token
            tUSDC, // quote token
            swapFeeTier, // fee tier
            Const.ArbiSep_UniRouter, // UniV3 router
            8, // feed decimals (ETH/USD uses 8)
            "BTC / USD", // description
            18 // virtual USD decimals
        );
        // no WBTC, only virtual-BTC
        BaseDeployer.ChainlinkFeed memory feedBTC_USD =
            BaseDeployer.ChainlinkFeed(address(mockBTCUSDFeed), "TWAPMock(BTC / USD)", 120, 8, 30);
        oracle = BaseDeployer.deployChainlinkOracle(tWBTC, Const.VIRTUAL_ASSET, feedBTC_USD, sequencerFeed);
    }

    function deployMockOracleUSDCUSD() internal returns (BaseTakerOracle oracle) {
        //  deploy mock feed for USDC/USD (since sepolia deployed one is unreliable)
        FixedMockChainlinkFeed mockUsdcUsdFeed = new FixedMockChainlinkFeed(USDSTABLEPRICE, 8, "USDC / USD");

        BaseDeployer.ChainlinkFeed memory feedUSDC_USD =
            BaseDeployer.ChainlinkFeed(address(mockUsdcUsdFeed), "FixedMock(USDC / USD)", 86_400, 8, 30);
        oracle = BaseDeployer.deployChainlinkOracle(tUSDC, Const.VIRTUAL_ASSET, feedUSDC_USD, sequencerFeed);
    }

    function deployAllContractPairs(address initialOwner, ConfigHub configHub)
        internal
        returns (BaseDeployer.AssetPairContracts[] memory assetPairContracts)
    {
        assetPairContracts = new BaseDeployer.AssetPairContracts[](2);

        /// https://docs.chain.link/data-feeds/price-feeds/addresses?network=arbitrum&page=1#sepolia-testnet
        // deploy direct oracles
        BaseTakerOracle oracletETH_USD = deployMockOracleETHUSD();
        BaseTakerOracle oracletWBTC_USD = deployMockOracleBTCUSD();
        BaseTakerOracle oracletUSDC_USD = deployMockOracleUSDCUSD();

        // if any escrowNFT contracts will be reused for multiple pairs, they should be deployed first
        assetPairContracts[0] = BaseDeployer.deployContractPair(
            initialOwner,
            configHub,
            BaseDeployer.PairConfig({
                name: "WETH/USDC",
                underlying: IERC20(tWETH),
                cashAsset: IERC20(tUSDC),
                oracle: BaseDeployer.deployCombinedOracle(
                    tWETH,
                    tUSDC,
                    oracletETH_USD,
                    oracletUSDC_USD,
                    true,
                    "Comb(CL(TWAPMock(ETH / USD))|inv(CL(FixedMock(USDC / USD))))"
                ),
                swapFeeTier: swapFeeTier,
                swapRouter: Const.ArbiSep_UniRouter,
                existingEscrowNFT: address(0)
            })
        );

        assetPairContracts[1] = BaseDeployer.deployContractPair(
            initialOwner,
            configHub,
            BaseDeployer.PairConfig({
                name: "WBTC/USDC",
                underlying: IERC20(tWBTC),
                cashAsset: IERC20(tUSDC),
                oracle: BaseDeployer.deployCombinedOracle(
                    tWBTC,
                    tUSDC,
                    oracletWBTC_USD,
                    oracletUSDC_USD,
                    true,
                    "Comb(CL(TWAPMock(BTC / USD))|inv(CL(FixedMock(USDC / USD))))"
                ),
                swapFeeTier: swapFeeTier,
                swapRouter: Const.ArbiSep_UniRouter,
                existingEscrowNFT: address(0)
            })
        );
    }
}
