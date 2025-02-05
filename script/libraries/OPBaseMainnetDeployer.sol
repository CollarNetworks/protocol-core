// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import { Const } from "../utils/Const.sol";
import { BaseDeployer, ConfigHub, IERC20, EscrowSupplierNFT, BaseTakerOracle } from "./BaseDeployer.sol";

library OPBaseMainnetDeployer {
    address constant USDC = Const.OPBaseMain_USDC;
    address constant WETH = Const.OPBaseMain_WETH;
    address constant sequencerFeed = Const.OPBaseMain_SeqFeed;

    uint24 constant swapFeeTier = 500;

    function defaultHubParams() internal pure returns (BaseDeployer.HubParams memory) {
        address[] memory pauseGuardians = new address[](1);
        pauseGuardians[0] = Const.OPBaseMain_deployerAcc;
        return BaseDeployer.HubParams({
            minDuration: 30 days,
            maxDuration: 365 days,
            minLTV: 2500,
            maxLTV: 9500,
            feeAPR: 90,
            feeRecipient: Const.OPBaseMain_deployerAcc,
            pauseGuardians: pauseGuardians
        });
    }

    function deployAndSetupFullProtocol(address thisSender, address finalOwner)
        internal
        returns (BaseDeployer.DeploymentResult memory result)
    {
        require(block.chainid == Const.OPBaseMain_chainId, "wrong chainId");

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

    function deployAllContractPairs(address initialOwner, ConfigHub configHub)
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
            BaseDeployer.ChainlinkFeed(Const.OPBaseMain_CLFeedETH_USD, "ETH / USD", 86_400, 8, 15),
            sequencerFeed
        );
        BaseTakerOracle oracleUSDC_USD = BaseDeployer.deployChainlinkOracle(
            USDC,
            Const.VIRTUAL_ASSET,
            BaseDeployer.ChainlinkFeed(Const.OPBaseMain_CLFeedUSDC_USD, "USDC / USD", 86_400, 8, 30),
            sequencerFeed
        );

        // deploy pairs
        assetPairContracts[0] = BaseDeployer.deployContractPair(
            initialOwner,
            configHub,
            BaseDeployer.PairConfig({
                name: "WETH/USDC",
                underlying: IERC20(WETH),
                cashAsset: IERC20(USDC),
                oracle: BaseDeployer.deployCombinedOracle(
                    WETH, USDC, oracleETH_USD, oracleUSDC_USD, true, "Comb(CL(ETH / USD)|inv(CL(USDC / USD)))"
                ),
                swapFeeTier: swapFeeTier,
                swapRouter: Const.OPBaseMain_UniRouter,
                existingEscrowNFT: address(0)
            })
        );
    }
}
