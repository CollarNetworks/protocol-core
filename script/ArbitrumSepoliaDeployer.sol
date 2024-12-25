// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import { BaseDeployer, ConfigHub, IERC20, EscrowSupplierNFT, BaseTakerOracle } from "./BaseDeployer.sol";
import { MockChainlinkFeed } from "../test/utils/TWAPMockChainlinkFeed.sol";

abstract contract ArbitrumSepoliaDeployer is BaseDeployer {
    address constant tUSDC = 0x69fC9D4d59843C6E55f00b5F66b263C963214C53; // CollarOwnedERC20 deployed on 12/11/2024
    address constant tWETH = 0xF17eb654885Afece15039a9Aa26F91063cC693E0; // CollarOwnedERC20 deployed on 12/11/2024
    address constant tWBTC = 0x19d87c960265C229D4b1429DF6F0C7d18F0611F3; // CollarOwnedERC20 deployed on 12/11/2024

    address constant swapRouterAddress = address(0x101F443B4d1b059569D643917553c771E1b9663E);

    address constant sequencerFeed = address(0);
    uint24 constant swapFeeTier = 3000;

    constructor() {
        chainId = 421_614;
        minDuration = 5 minutes;
        maxDuration = 365 days;
        minLTV = 2500;
        maxLTV = 9900;
    }

    function _configureFeeds() internal {
        // Deploy mock feed for WETH / USDC pair
        MockChainlinkFeed mockEthUsdFeed = new MockChainlinkFeed(
            tWETH, // base token
            tUSDC, // quote token
            3000, // fee tier
            swapRouterAddress, // UniV3 router
            8, // feed decimals (ETH/USD uses 8)
            "ETH / USD", // description
            18 // virtual USD decimals
        );

        MockChainlinkFeed mockBTCUSDFeed = new MockChainlinkFeed(
            tWBTC, // base token
            tUSDC, // quote token
            3000, // fee tier
            swapRouterAddress, // UniV3 router
            8, // feed decimals (ETH/USD uses 8)
            "BTC / USD", // description
            18 // virtual USD decimals
        );

        /// https://docs.chain.link/data-feeds/price-feeds/addresses?network=arbitrum&page=1#sepolia-testnet
        // define feeds to be used in oracles
        _configureFeed(ChainlinkFeed(address(mockEthUsdFeed), "ETH / USD", 120, 8, 5));
        // no WBTC, only virtual-BTC
        _configureFeed(ChainlinkFeed(address(mockBTCUSDFeed), "BTC / USD", 120, 8, 30));
        _configureFeed(ChainlinkFeed(0x0153002d20B96532C639313c2d54c3dA09109309, "USDC / USD", 86_400, 8, 30));
        _configureFeed(ChainlinkFeed(0x80EDee6f667eCc9f63a0a6f55578F870651f06A4, "USDT / USD", 3600, 8, 30));
    }

    function _createContractPairs(ConfigHub configHub, address owner)
        internal
        override
        returns (AssetPairContracts[] memory assetPairContracts)
    {
        assetPairContracts = new AssetPairContracts[](2);

        _configureFeeds();
        // deploy direct oracles
        BaseTakerOracle oracletETH_USD =
            deployChainlinkOracle(tWETH, VIRTUAL_ASSET, _getFeed("ETH / USD"), sequencerFeed);
        BaseTakerOracle oracletWBTC_USD =
            deployChainlinkOracle(tWBTC, VIRTUAL_ASSET, _getFeed("BTC / USD"), sequencerFeed);
        BaseTakerOracle oracletUSDC_USD =
            deployChainlinkOracle(tUSDC, VIRTUAL_ASSET, _getFeed("USDC / USD"), sequencerFeed);

        // if any escrowNFT contracts will be reused for multiple pairs, they should be deployed first
        assetPairContracts[0] = deployContractPair(
            configHub,
            PairConfig({
                name: "WETH/USDC",
                underlying: IERC20(tWETH),
                cashAsset: IERC20(tUSDC),
                oracle: deployCombinedOracle(
                    tWETH, tUSDC, oracletETH_USD, oracletUSDC_USD, true, "Comb(CL(ETH / USD)|inv(CL(USDC / USD)))"
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
                    "Comb(CL(BTC / USD)|inv(CL(USDC / USD)))"
                ),
                swapFeeTier: swapFeeTier,
                swapRouter: swapRouterAddress,
                existingEscrowNFT: address(0)
            }),
            owner
        );
    }
}
