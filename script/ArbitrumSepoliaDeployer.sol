// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import { BaseDeployer, ConfigHub, IERC20, EscrowSupplierNFT, BaseTakerOracle } from "./BaseDeployer.sol";
import { TWAPMockChainlinkFeed } from "../test/utils/TWAPMockChainlinkFeed.sol";
import { FixedMockChainlinkFeed } from "../test/utils/FixedMockChainlinkFeed.sol";

contract ArbitrumSepoliaDeployer is BaseDeployer {
    address public constant swapRouterAddress = address(0x101F443B4d1b059569D643917553c771E1b9663E);

    address constant tUSDC = 0x69fC9D4d59843C6E55f00b5F66b263C963214C53; // CollarOwnedERC20 deployed on 12/11/2024
    address constant tWETH = 0xF17eb654885Afece15039a9Aa26F91063cC693E0; // CollarOwnedERC20 deployed on 12/11/2024
    address constant tWBTC = 0x19d87c960265C229D4b1429DF6F0C7d18F0611F3; // CollarOwnedERC20 deployed on 12/11/2024

    address constant sequencerFeed = address(0);
    uint24 constant swapFeeTier = 3000;
    uint constant USDSTABLEPRICE = 100_000_000; // 1 * 10^8 since feed decimals is 8

    constructor() {
        chainId = 421_614;
    }

    function defaultHubParams() pure override returns (HubParams memory) {
        return HubParams({ minDuration: 5 minutes, maxDuration: 365 days, minLTV: 2500, maxLTV: 9900 });
    }

    function _configureFeeds() internal {
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

        TWAPMockChainlinkFeed mockBTCUSDFeed = new TWAPMockChainlinkFeed(
            tWBTC, // base token
            tUSDC, // quote token
            3000, // fee tier
            swapRouterAddress, // UniV3 router
            8, // feed decimals (ETH/USD uses 8)
            "BTC / USD", // description
            18 // virtual USD decimals
        );

        //  deploy mock feed for USDC/USD (since sepolia deployed one is unreliable)
        FixedMockChainlinkFeed mockUsdcUsdFeed = new FixedMockChainlinkFeed(100_000_000, 8, "USDC / USD");
        //  deploy mock feed for USDT/USD (since sepolia deployed one is unreliable)
        FixedMockChainlinkFeed mockUsdtUsdFeed = new FixedMockChainlinkFeed(100_000_000, 8, "USDT / USD");

        /// https://docs.chain.link/data-feeds/price-feeds/addresses?network=arbitrum&page=1#sepolia-testnet
        // define feeds to be used in oracles
        configureFeed(ChainlinkFeed(address(mockEthUsdFeed), "TWAPMock(ETH / USD)", 120, 8, 5));
        // no WBTC, only virtual-BTC
        configureFeed(ChainlinkFeed(address(mockBTCUSDFeed), "TWAPMock(BTC / USD)", 120, 8, 30));
        configureFeed(ChainlinkFeed(address(mockUsdcUsdFeed), "FixedMock(USDC / USD)", 86_400, 8, 30));
        configureFeed(ChainlinkFeed(address(mockUsdtUsdFeed), "FixedMock(USDT / USD)", 3600, 8, 30));
    }

    function deployAllContractPairs(ConfigHub configHub, address owner)
        internal
        override
        returns (AssetPairContracts[] memory assetPairContracts)
    {
        assetPairContracts = new AssetPairContracts[](2);

        _configureFeeds();
        // deploy direct oracles
        BaseTakerOracle oracletETH_USD =
            deployChainlinkOracle(tWETH, VIRTUAL_ASSET, getFeed("TWAPMock(ETH / USD)"), sequencerFeed);
        BaseTakerOracle oracletWBTC_USD =
            deployChainlinkOracle(tWBTC, VIRTUAL_ASSET, getFeed("TWAPMock(BTC / USD)"), sequencerFeed);
        BaseTakerOracle oracletUSDC_USD =
            deployChainlinkOracle(tUSDC, VIRTUAL_ASSET, getFeed("FixedMock(USDC / USD)"), sequencerFeed);
        // if any escrowNFT contracts will be reused for multiple pairs, they should be deployed first
        assetPairContracts[0] = deployContractPair(
            configHub,
            PairConfig({
                name: "WETH/USDC",
                underlying: IERC20(tWETH),
                cashAsset: IERC20(tUSDC),
                oracle: deployCombinedOracle(
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
            }),
            owner
        );

        assetPairContracts[1] = deployContractPair(
            configHub,
            PairConfig({
                name: "WBTC/USDC",
                underlying: IERC20(tWBTC),
                cashAsset: IERC20(tUSDC),
                oracle: deployCombinedOracle(
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
            }),
            owner
        );
    }
}
