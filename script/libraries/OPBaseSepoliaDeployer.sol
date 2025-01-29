// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import { Const } from "../utils/Const.sol";
import { BaseDeployer, ConfigHub, IERC20, EscrowSupplierNFT, BaseTakerOracle } from "./BaseDeployer.sol";

library OPBaseSepoliaDeployer {
    address constant USDC = Const.OPBaseSep_USDC;
    address constant WETH = Const.OPBaseSep_WETH;
    address constant sequencerFeed = address(0);

    uint24 constant swapFeeTier = 500;

    function defaultHubParams() internal pure returns (BaseDeployer.HubParams memory) {
        address[] memory pauseGuardians = new address[](1);
        pauseGuardians[0] = Const.OPBaseSep_deployerAcc;
        return BaseDeployer.HubParams({
            minDuration: 5 minutes,
            maxDuration: 365 days,
            minLTV: 2500,
            maxLTV: 9900,
            feeAPR: 75,
            feeRecipient: Const.OPBaseSep_deployerAcc,
            pauseGuardians: pauseGuardians
        });
    }

    function deployAndSetupFullProtocol(address owner)
        internal
        returns (BaseDeployer.DeploymentResult memory result)
    {
        require(block.chainid == Const.OPBaseSep_chainId, "wrong chainId");

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
        // 1 pair below
        assetPairContracts = new BaseDeployer.AssetPairContracts[](1);

        // https://docs.chain.link/data-feeds/price-feeds/addresses?network=base&page=1
        // deploy direct oracles
        BaseTakerOracle oracleETH_USD = BaseDeployer.deployChainlinkOracle(
            WETH,
            Const.VIRTUAL_ASSET,
            BaseDeployer.ChainlinkFeed(Const.OPBaseSep_CLFeedETH_USD, "ETH / USD", 86_400, 8, 15),
            sequencerFeed
        );
        BaseTakerOracle oracleUSDC_USD = BaseDeployer.deployChainlinkOracle(
            USDC,
            Const.VIRTUAL_ASSET,
            BaseDeployer.ChainlinkFeed(Const.OPBaseSep_CLFeedUSDC_USD, "USDC / USD", 86_400, 8, 10),
            sequencerFeed
        );

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
                swapRouter: Const.OPBaseSep_UniRouter,
                existingEscrowNFT: address(0)
            })
        );
    }
}
