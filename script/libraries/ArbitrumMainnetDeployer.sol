// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import { Const } from "../utils/Const.sol";
import { BaseDeployer, ConfigHub, IERC20, EscrowSupplierNFT, BaseTakerOracle } from "./BaseDeployer.sol";

library ArbitrumMainnetDeployer {
    address constant USDC = Const.ArbiMain_USDC;
    address constant USDT = Const.ArbiMain_USDT;
    address constant WETH = Const.ArbiMain_WETH;
    address constant WBTC = Const.ArbiMain_WBTC;
    address constant sequencerFeed = Const.ArbiMain_SeqFeed;

    uint24 constant swapFeeTier = 500;

    function defaultHubParams() internal pure returns (BaseDeployer.HubParams memory) {
        return BaseDeployer.HubParams({
            minDuration: 30 days,
            maxDuration: 365 days,
            minLTV: 2500,
            maxLTV: 9500,
            feeAPR: 90,
            feeRecipient: Const.ArbiMain_feeRecipient
        });
    }

    /// @param thisSender is the sender from the POV of outgoing calls
    function deployAndSetupFullProtocol(address thisSender, address finalOwner)
        internal
        returns (BaseDeployer.DeploymentResult memory result)
    {
        require(block.chainid == Const.ArbiMain_chainId, "wrong chainId");

        // hub
        result.configHub = BaseDeployer.deployConfigHub(thisSender);
        BaseDeployer.setupConfigHub(result.configHub, defaultHubParams());

        // pairs
        result.assetPairContracts = deployAllContractPairs(result.configHub);
        for (uint i = 0; i < result.assetPairContracts.length; i++) {
            BaseDeployer.setupContractPair(result.configHub, result.assetPairContracts[i]);
        }

        // ownership
        BaseDeployer.nominateNewHubOwner(finalOwner, result);
    }

    function deployAllContractPairs(ConfigHub configHub)
        internal
        returns (BaseDeployer.AssetPairContracts[] memory assetPairContracts)
    {
        // 3 pairs below
        assetPairContracts = new BaseDeployer.AssetPairContracts[](3);

        // https://docs.chain.link/data-feeds/price-feeds/addresses?network=arbitrum&page=1#ethereum-mainnet
        // deploy direct oracles
        BaseTakerOracle oracleETH_USD = BaseDeployer.deployChainlinkOracle(
            WETH,
            Const.VIRTUAL_ASSET,
            BaseDeployer.ChainlinkFeed(Const.ArbiMain_CLFeedETH_USD, "ETH / USD", 86_400, 8, 5),
            sequencerFeed
        );
        BaseTakerOracle oracleWBTC_USD = BaseDeployer.deployChainlinkOracle(
            WBTC,
            Const.VIRTUAL_ASSET,
            BaseDeployer.ChainlinkFeed(Const.ArbiMain_CLFeedWBTC_USD, "WBTC / USD", 86_400, 8, 5),
            sequencerFeed
        );
        BaseTakerOracle oracleUSDC_USD = BaseDeployer.deployChainlinkOracle(
            USDC,
            Const.VIRTUAL_ASSET,
            BaseDeployer.ChainlinkFeed(Const.ArbiMain_CLFeedUSDC_USD, "USDC / USD", 86_400, 8, 10),
            sequencerFeed
        );
        BaseTakerOracle oracleUSDT_USD = BaseDeployer.deployChainlinkOracle(
            USDT,
            Const.VIRTUAL_ASSET,
            BaseDeployer.ChainlinkFeed(Const.ArbiMain_CLFeedUSDT_USD, "USDT / USD", 86_400, 8, 10),
            sequencerFeed
        );

        // if any escrowNFT contracts will be reused for multiple pairs, they should be deployed first
        EscrowSupplierNFT wethEscrow = BaseDeployer.deployEscrowNFT(configHub, IERC20(WETH), "WETH");

        // deploy pairs
        assetPairContracts[0] = BaseDeployer.deployContractPair(
            configHub,
            BaseDeployer.PairConfig({
                name: "WETH/USDC",
                underlying: IERC20(WETH),
                cashAsset: IERC20(USDC),
                oracle: BaseDeployer.deployCombinedOracle(
                    WETH, USDC, oracleETH_USD, oracleUSDC_USD, true, "Comb(CL(ETH / USD)|inv(CL(USDC / USD)))"
                ),
                swapFeeTier: swapFeeTier,
                swapRouter: Const.ArbiMain_UniRouter,
                existingEscrowNFT: address(wethEscrow)
            })
        );

        assetPairContracts[1] = BaseDeployer.deployContractPair(
            configHub,
            BaseDeployer.PairConfig({
                name: "WETH/USDT",
                underlying: IERC20(WETH),
                cashAsset: IERC20(USDT),
                oracle: BaseDeployer.deployCombinedOracle(
                    WETH, USDT, oracleETH_USD, oracleUSDT_USD, true, "Comb(CL(ETH / USD)|inv(CL(USDT / USD)))"
                ),
                swapFeeTier: swapFeeTier,
                swapRouter: Const.ArbiMain_UniRouter,
                existingEscrowNFT: address(wethEscrow)
            })
        );

        assetPairContracts[2] = BaseDeployer.deployContractPair(
            configHub,
            BaseDeployer.PairConfig({
                name: "WBTC/USDT",
                underlying: IERC20(WBTC),
                cashAsset: IERC20(USDT),
                oracle: BaseDeployer.deployCombinedOracle(
                    WBTC, USDT, oracleWBTC_USD, oracleUSDT_USD, true, "Comb(CL(WBTC / USD)|inv(CL(USDT / USD)))"
                ),
                swapFeeTier: swapFeeTier,
                swapRouter: Const.ArbiMain_UniRouter,
                existingEscrowNFT: address(0)
            })
        );
    }
}
