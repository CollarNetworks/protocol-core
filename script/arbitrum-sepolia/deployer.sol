// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import { ConfigHub } from "../../src/ConfigHub.sol";
import { EscrowSupplierNFT } from "../../src/EscrowSupplierNFT.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SetupHelper } from "../setup-helper.sol";
import { DeploymentHelper } from "../deployment-helper.sol";

library ArbitrumSepoliaDeployer {
    uint constant chainId = 421_614; // id for arbitrum sepolia
    address constant USDC = 0x69fC9D4d59843C6E55f00b5F66b263C963214C53; // CollarOwnedERC20 deployed on 12/11/2024
    address constant WETH = 0xF17eb654885Afece15039a9Aa26F91063cC693E0; // CollarOwnedERC20 deployed on 12/11/2024
    address constant WBTC = 0x19d87c960265C229D4b1429DF6F0C7d18F0611F3; // CollarOwnedERC20 deployed on 12/11/2024
    address constant swapRouterAddress = address(0x101F443B4d1b059569D643917553c771E1b9663E);

    address constant sequencerUptimeFeed = address(0);

    uint24 constant oracleFeeTier = 3000;
    uint24 constant swapFeeTier = 3000;
    uint32 constant twapWindow = 15 minutes;
    uint8 constant pairsToDeploy = 2; // change for the number of pairs to be deployed by the _createContractPairs function

    uint constant minDuration = 5 minutes;
    uint constant maxDuration = 365 days;
    uint constant minLTV = 2500;
    uint constant maxLTV = 9900;


    struct DeploymentResult {
        ConfigHub configHub;
        DeploymentHelper.AssetPairContracts[] assetPairContracts;
    }

    function deployAndSetupProtocol(address owner) internal returns (DeploymentResult memory result) {
        require(chainId == block.chainid, "chainId does not match the chainId in config");

        result.configHub = DeploymentHelper.deployConfigHub(owner);

        address[] memory underlyings = new address[](3);
        underlyings[0] = WETH;
        underlyings[1] = WBTC;
        address[] memory cashAssets = new address[](3);
        cashAssets[0] = USDC;

        SetupHelper.setupConfigHub(
            result.configHub,
            SetupHelper.HubParams({
                cashAssets: cashAssets,
                underlyings: underlyings,
                minLTV: minLTV,
                maxLTV: maxLTV,
                minDuration: minDuration,
                maxDuration: maxDuration
            })
        );

        result.assetPairContracts = _createContractPairs(result.configHub, owner);

        for (uint i = 0; i < result.assetPairContracts.length; i++) {
            SetupHelper.setupContractPair(result.configHub, result.assetPairContracts[i]);
        }
    }

    function _createContractPairs(ConfigHub configHub, address owner)
        internal
        returns (DeploymentHelper.AssetPairContracts[] memory assetPairContracts)
    {
        assetPairContracts = new DeploymentHelper.AssetPairContracts[](pairsToDeploy);

        // if any escrowNFT contracts will be reused for multiple pairs, they should be deployed first

        DeploymentHelper.PairConfig memory USDCWETHPairConfig = DeploymentHelper.PairConfig({
            name: "USDC/WETH",
            cashAsset: IERC20(USDC),
            underlying: IERC20(WETH),
            oracleFeeTier: oracleFeeTier,
            swapFeeTier: swapFeeTier,
            twapWindow: twapWindow,
            swapRouter: swapRouterAddress,
            sequencerUptimeFeed: sequencerUptimeFeed,
            existingEscrowNFT: address(0)
        });
        assetPairContracts[0] = DeploymentHelper.deployContractPair(configHub, USDCWETHPairConfig, owner);

        DeploymentHelper.PairConfig memory USDCWBTCPairConfig = DeploymentHelper.PairConfig({
            name: "USDC/WBTC",
            cashAsset: IERC20(USDC),
            underlying: IERC20(WBTC),
            oracleFeeTier: oracleFeeTier,
            swapFeeTier: swapFeeTier,
            twapWindow: twapWindow,
            swapRouter: swapRouterAddress,
            sequencerUptimeFeed: sequencerUptimeFeed,
            existingEscrowNFT: address(0)
        });

        assetPairContracts[1] = DeploymentHelper.deployContractPair(configHub, USDCWBTCPairConfig, owner);
    }
}
