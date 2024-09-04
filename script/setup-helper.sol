// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import { ConfigHub } from "../src/ConfigHub.sol";
import { Loans } from "../src/Loans.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Rolls } from "../src/Rolls.sol";
import { SwapperUniV3 } from "../src/SwapperUniV3.sol";
import { DeploymentHelper } from "./deployment-helper.sol";

contract SetupHelper {
    struct HubParams {
        address[] cashAssets;
        address[] collateralAssets;
        uint minLTV;
        uint maxLTV;
        uint minDuration;
        uint maxDuration;
    }

    function setupContractPair(ConfigHub hub, DeploymentHelper.AssetPairContracts memory pair) public {
        hub.setCanOpen(address(pair.takerNFT), true);
        hub.setCanOpen(address(pair.providerNFT), true);
        pair.loansContract.setRollsContract(pair.rollsContract);
        pair.loansContract.setSwapperAllowed(address(pair.swapperUniV3), true, true);
    }

    function setupConfigHub(ConfigHub configHub, HubParams memory hubParams) public {
        for (uint i = 0; i < hubParams.cashAssets.length; i++) {
            configHub.setCashAssetSupport(hubParams.cashAssets[i], true);
        }
        for (uint i = 0; i < hubParams.collateralAssets.length; i++) {
            configHub.setCollateralAssetSupport(hubParams.collateralAssets[i], true);
        }
        configHub.setLTVRange(hubParams.minLTV, hubParams.maxLTV);
        configHub.setCollarDurationRange(hubParams.minDuration, hubParams.maxDuration);
    }
}
