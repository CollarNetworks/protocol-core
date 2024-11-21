// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import { BaseDeployer, ConfigHub, IERC20, EscrowSupplierNFT, BaseTakerOracle } from "./BaseDeployer.sol";

abstract contract ArbitrumMainnetDeployer is BaseDeployer {
    address constant USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    address constant USDT = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;
    address constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

    address constant WBTC = 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f;

    address constant swapRouterAddress = address(0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45);
    uint24 constant swapFeeTier = 500;

    address constant sequencerFeed = address(0xFdB631F5EE196F0ed6FAa767959853A9F217697D);

    constructor() {
        chainId = 42_161;
        minDuration = 5 minutes;
        maxDuration = 365 days;
        minLTV = 2500;
        maxLTV = 9900;
    }

    function _configureFeeds() internal {
        // https://docs.chain.link/data-feeds/price-feeds/addresses?network=arbitrum&page=1#ethereum-mainnet
        // define feeds to be used in oracles
        _configureFeed(ChainlinkFeed(0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612, "ETH / USD", 86_400, 8, 5));
        _configureFeed(ChainlinkFeed(0xd0C7101eACbB49F3deCcCc166d238410D6D46d57, "WBTC / USD", 86_400, 8, 5));
        _configureFeed(ChainlinkFeed(0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3, "USDC / USD", 86_400, 8, 10));
        _configureFeed(ChainlinkFeed(0x3f3f5dF88dC9F13eac63DF89EC16ef6e7E25DdE7, "USDT / USD", 86_400, 8, 10));
    }

    function _createContractPairs(ConfigHub configHub, address owner)
        internal
        override
        returns (AssetPairContracts[] memory assetPairContracts)
    {
        // 3 pairs below
        assetPairContracts = new AssetPairContracts[](3);

        _configureFeeds();

        // if any escrowNFT contracts will be reused for multiple pairs, they should be deployed first
        EscrowSupplierNFT wethEscrow = deployEscrowNFT(configHub, owner, IERC20(WETH), "WETH");

        // deploy direct oracles
        BaseTakerOracle oracleETH_USD =
            deployDirectFeedOracle(WETH, VIRTUAL_ASSET, _getFeed("ETH / USD"), sequencerFeed);
        BaseTakerOracle oracleWBTC_USD =
            deployDirectFeedOracle(WBTC, VIRTUAL_ASSET, _getFeed("WBTC / USD"), sequencerFeed);
        BaseTakerOracle oracleUSDC_USD =
            deployDirectFeedOracle(USDC, VIRTUAL_ASSET, _getFeed("USDC / USD"), sequencerFeed);
        BaseTakerOracle oracleUSDT_USD =
            deployDirectFeedOracle(USDT, VIRTUAL_ASSET, _getFeed("USDT / USD"), sequencerFeed);

        // deploy pairs
        assetPairContracts[0] = deployContractPair(
            configHub,
            PairConfig({
                name: "WETH/USDC",
                underlying: IERC20(WETH),
                cashAsset: IERC20(USDC),
                // ETH/USD -> invert(USDC/USD)
                oracle: deployCombinedOracle(WETH, USDC, oracleETH_USD, oracleUSDC_USD, true),
                swapFeeTier: swapFeeTier,
                swapRouter: swapRouterAddress,
                existingEscrowNFT: address(wethEscrow)
            }),
            owner
        );

        assetPairContracts[1] = deployContractPair(
            configHub,
            PairConfig({
                name: "WETH/USDT",
                underlying: IERC20(WETH),
                cashAsset: IERC20(USDT),
                // ETH/USD -> invert(USDT/USD)
                oracle: deployCombinedOracle(WETH, USDT, oracleETH_USD, oracleUSDT_USD, true),
                swapFeeTier: swapFeeTier,
                swapRouter: swapRouterAddress,
                existingEscrowNFT: address(wethEscrow)
            }),
            owner
        );

        assetPairContracts[2] = deployContractPair(
            configHub,
            PairConfig({
                name: "WBTC/USDT",
                underlying: IERC20(WBTC),
                cashAsset: IERC20(USDT),
                // WBTC/USD -> invert(USDT/USD)
                oracle: deployCombinedOracle(WBTC, USDT, oracleWBTC_USD, oracleUSDT_USD, true),
                swapFeeTier: swapFeeTier,
                swapRouter: swapRouterAddress,
                existingEscrowNFT: address(0)
            }),
            owner
        );
    }
}
