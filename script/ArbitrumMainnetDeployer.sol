// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import { BaseDeployer, ConfigHub, IERC20, EscrowSupplierNFT, BaseTakerOracle } from "./BaseDeployer.sol";

library ArbitrumMainnetDeployer {
    address public constant swapRouterAddress = address(0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45);

    uint constant chainId = 42_161;

    address constant USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    address constant USDT = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;
    address constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address constant WBTC = 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f;

    uint24 constant swapFeeTier = 500;

    address constant sequencerFeed = address(0xFdB631F5EE196F0ed6FAa767959853A9F217697D);

    function defaultHubParams() internal pure returns (BaseDeployer.HubParams memory) {
        return BaseDeployer.HubParams({
            minDuration: 30 days,
            maxDuration: 365 days,
            minLTV: 2500,
            maxLTV: 9000
        });
    }

    function deployAndSetupFullProtocol(address owner)
        internal
        returns (BaseDeployer.DeploymentResult memory result)
    {
        require(chainId == block.chainid, "wrong chainId");

        // hub
        result.configHub = BaseDeployer.deployConfigHub(owner);
        BaseDeployer.setupConfigHub(result.configHub, defaultHubParams());

        // pairs
        result.assetPairContracts = deployAllContractPairs(owner, result.configHub);
        for (uint i = 0; i < result.assetPairContracts.length; i++) {
            BaseDeployer.setupContractPair(result.configHub, result.assetPairContracts[i]);
        }

        // ownership
        BaseDeployer.nominateNewOwnerAll(owner, result);
    }

    function deployAllContractPairs(address owner, ConfigHub configHub)
        internal
        returns (BaseDeployer.AssetPairContracts[] memory assetPairContracts)
    {
        // 3 pairs below
        assetPairContracts = new BaseDeployer.AssetPairContracts[](3);

        // https://docs.chain.link/data-feeds/price-feeds/addresses?network=arbitrum&page=1#ethereum-mainnet
        // define feeds to be used in oracles
        BaseDeployer.ChainlinkFeed memory feedETH_USD =
            BaseDeployer.ChainlinkFeed(0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612, "ETH / USD", 86_400, 8, 5);
        BaseDeployer.ChainlinkFeed memory feedWBTC_USD =
            BaseDeployer.ChainlinkFeed(0xd0C7101eACbB49F3deCcCc166d238410D6D46d57, "WBTC / USD", 86_400, 8, 5);
        BaseDeployer.ChainlinkFeed memory feedUSDC_USD = BaseDeployer.ChainlinkFeed(
            0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3, "USDC / USD", 86_400, 8, 10
        );
        BaseDeployer.ChainlinkFeed memory feedUSDT_USD = BaseDeployer.ChainlinkFeed(
            0x3f3f5dF88dC9F13eac63DF89EC16ef6e7E25DdE7, "USDT / USD", 86_400, 8, 10
        );

        // deploy direct oracles
        BaseTakerOracle oracleETH_USD =
            BaseDeployer.deployChainlinkOracle(WETH, BaseDeployer.VIRTUAL_ASSET, feedETH_USD, sequencerFeed);
        BaseTakerOracle oracleWBTC_USD =
            BaseDeployer.deployChainlinkOracle(WBTC, BaseDeployer.VIRTUAL_ASSET, feedWBTC_USD, sequencerFeed);
        BaseTakerOracle oracleUSDC_USD =
            BaseDeployer.deployChainlinkOracle(USDC, BaseDeployer.VIRTUAL_ASSET, feedUSDC_USD, sequencerFeed);
        BaseTakerOracle oracleUSDT_USD =
            BaseDeployer.deployChainlinkOracle(USDT, BaseDeployer.VIRTUAL_ASSET, feedUSDT_USD, sequencerFeed);

        // if any escrowNFT contracts will be reused for multiple pairs, they should be deployed first
        EscrowSupplierNFT wethEscrow = BaseDeployer.deployEscrowNFT(owner, configHub, IERC20(WETH), "WETH");

        // deploy pairs
        assetPairContracts[0] = BaseDeployer.deployContractPair(
            owner,
            configHub,
            BaseDeployer.PairConfig({
                name: "WETH/USDC",
                underlying: IERC20(WETH),
                cashAsset: IERC20(USDC),
                oracle: BaseDeployer.deployCombinedOracle(
                    WETH, USDC, oracleETH_USD, oracleUSDC_USD, true, "Comb(CL(ETH / USD)|inv(CL(USDC / USD)))"
                ),
                swapFeeTier: swapFeeTier,
                swapRouter: swapRouterAddress,
                existingEscrowNFT: address(wethEscrow)
            })
        );

        assetPairContracts[1] = BaseDeployer.deployContractPair(
            owner,
            configHub,
            BaseDeployer.PairConfig({
                name: "WETH/USDT",
                underlying: IERC20(WETH),
                cashAsset: IERC20(USDT),
                oracle: BaseDeployer.deployCombinedOracle(
                    WETH, USDT, oracleETH_USD, oracleUSDT_USD, true, "Comb(CL(ETH / USD)|inv(CL(USDT / USD)))"
                ),
                swapFeeTier: swapFeeTier,
                swapRouter: swapRouterAddress,
                existingEscrowNFT: address(wethEscrow)
            })
        );

        assetPairContracts[2] = BaseDeployer.deployContractPair(
            owner,
            configHub,
            BaseDeployer.PairConfig({
                name: "WBTC/USDT",
                underlying: IERC20(WBTC),
                cashAsset: IERC20(USDT),
                oracle: BaseDeployer.deployCombinedOracle(
                    WBTC, USDT, oracleWBTC_USD, oracleUSDT_USD, true, "Comb(CL(WBTC / USD)|inv(CL(USDT / USD)))"
                ),
                swapFeeTier: swapFeeTier,
                swapRouter: swapRouterAddress,
                existingEscrowNFT: address(0)
            })
        );
    }
}
