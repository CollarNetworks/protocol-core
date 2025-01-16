// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import { BaseDeployer, ConfigHub, IERC20, EscrowSupplierNFT, BaseTakerOracle } from "./BaseDeployer.sol";
import { TWAPMockChainlinkFeed } from "../test/utils/TWAPMockChainlinkFeed.sol";
import { FixedMockChainlinkFeed } from "../test/utils/FixedMockChainlinkFeed.sol";

library ArbitrumSepoliaDeployer {
    address public constant swapRouterAddress = address(0x101F443B4d1b059569D643917553c771E1b9663E);

    uint constant chainId = 421_614;

    address constant tUSDC = 0x69fC9D4d59843C6E55f00b5F66b263C963214C53; // CollarOwnedERC20 deployed on 12/11/2024
    address constant tWETH = 0xF17eb654885Afece15039a9Aa26F91063cC693E0; // CollarOwnedERC20 deployed on 12/11/2024
    address constant tWBTC = 0x19d87c960265C229D4b1429DF6F0C7d18F0611F3; // CollarOwnedERC20 deployed on 12/11/2024

    address constant sequencerFeed = address(0);
    uint24 constant swapFeeTier = 3000;
    int constant USDSTABLEPRICE = 100_000_000; // 1 * 10^8 since feed decimals is 8

    function defaultHubParams() internal pure returns (BaseDeployer.HubParams memory) {
        return BaseDeployer.HubParams({
            minDuration: 5 minutes,
            maxDuration: 365 days,
            minLTV: 2500,
            maxLTV: 9900
        });
    }

    function deployAndSetupFullProtocol(address owner)
        internal
        returns (BaseDeployer.DeploymentResult memory result)
    {
        require(chainId == block.chainid, "wrong chainId");

        // hub
        result.configHub = BaseDeployer.deployConfigHub();
        BaseDeployer.setupConfigHub(result.configHub, defaultHubParams());

        // pairs
        result.assetPairContracts = deployAllContractPairs(result.configHub);
        for (uint i = 0; i < result.assetPairContracts.length; i++) {
            BaseDeployer.setupContractPair(result.configHub, result.assetPairContracts[i]);
        }

        // ownership
        BaseDeployer.nominateNewOwnerAll(owner, result);
    }

    function deployMockOracleETHUSD() internal returns (BaseTakerOracle oracle) {
        // Deploy mock feed for WETH / USDC pair
        TWAPMockChainlinkFeed mockEthUsdFeed = new TWAPMockChainlinkFeed(
            tWETH, // base token
            tUSDC, // quote token
            3000, // fee tier
            swapRouterAddress, // UniV3 router
            8, // feed decimals (ETH/USD uses 8)
            "ETH / USD", // description
            18 // virtual USD decimals
        );
        BaseDeployer.ChainlinkFeed memory feedETH_USD =
            BaseDeployer.ChainlinkFeed(address(mockEthUsdFeed), "TWAPMock(ETH / USD)", 120, 8, 5);
        oracle =
            BaseDeployer.deployChainlinkOracle(tWETH, BaseDeployer.VIRTUAL_ASSET, feedETH_USD, sequencerFeed);
    }

    function deployMockOracleBTCUSD() internal returns (BaseTakerOracle oracle) {
        TWAPMockChainlinkFeed mockBTCUSDFeed = new TWAPMockChainlinkFeed(
            tWBTC, // base token
            tUSDC, // quote token
            3000, // fee tier
            swapRouterAddress, // UniV3 router
            8, // feed decimals (ETH/USD uses 8)
            "BTC / USD", // description
            18 // virtual USD decimals
        );
        // no WBTC, only virtual-BTC
        BaseDeployer.ChainlinkFeed memory feedBTC_USD =
            BaseDeployer.ChainlinkFeed(address(mockBTCUSDFeed), "TWAPMock(BTC / USD)", 120, 8, 30);
        oracle =
            BaseDeployer.deployChainlinkOracle(tWBTC, BaseDeployer.VIRTUAL_ASSET, feedBTC_USD, sequencerFeed);
    }

    function deployMockOracleUSDCUSD() internal returns (BaseTakerOracle oracle) {
        //  deploy mock feed for USDC/USD (since sepolia deployed one is unreliable)
        FixedMockChainlinkFeed mockUsdcUsdFeed = new FixedMockChainlinkFeed(USDSTABLEPRICE, 8, "USDC / USD");

        BaseDeployer.ChainlinkFeed memory feedUSDC_USD =
            BaseDeployer.ChainlinkFeed(address(mockUsdcUsdFeed), "FixedMock(USDC / USD)", 86_400, 8, 30);
        oracle =
            BaseDeployer.deployChainlinkOracle(tUSDC, BaseDeployer.VIRTUAL_ASSET, feedUSDC_USD, sequencerFeed);
    }

    function deployAllContractPairs(ConfigHub configHub)
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
                swapRouter: swapRouterAddress,
                existingEscrowNFT: address(0)
            })
        );

        assetPairContracts[1] = BaseDeployer.deployContractPair(
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
                swapRouter: swapRouterAddress,
                existingEscrowNFT: address(0)
            })
        );
    }
}
