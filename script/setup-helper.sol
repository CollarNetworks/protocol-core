// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import { ConfigHub } from "../src/ConfigHub.sol";
import { LoansNFT, EscrowSupplierNFT } from "../src/LoansNFT.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Rolls } from "../src/Rolls.sol";
import { SwapperUniV3 } from "../src/SwapperUniV3.sol";
import { DeploymentHelper } from "./deployment-helper.sol";

library SetupHelper {
    struct HubParams {
        address[] cashAssets;
        address[] underlyings;
        uint minLTV;
        uint maxLTV;
        uint minDuration;
        uint maxDuration;
    }

    function setupContractPair(ConfigHub hub, DeploymentHelper.AssetPairContracts memory pair) internal {
        hub.setCanOpen(address(pair.takerNFT), true);
        hub.setCanOpen(address(pair.providerNFT), true);
        hub.setCanOpen(address(pair.loansContract), true);
        pair.loansContract.setContracts(pair.rollsContract, pair.providerNFT, EscrowSupplierNFT(address(0)));
        pair.loansContract.setSwapperAllowed(address(pair.swapperUniV3), true, true);
    }

    function setupConfigHub(ConfigHub configHub, HubParams memory hubParams) internal {
        for (uint i = 0; i < hubParams.cashAssets.length; i++) {
            configHub.setCashAssetSupport(hubParams.cashAssets[i], true);
        }
        for (uint i = 0; i < hubParams.underlyings.length; i++) {
            configHub.setUnderlyingSupport(hubParams.underlyings[i], true);
        }
        configHub.setLTVRange(hubParams.minLTV, hubParams.maxLTV);
        configHub.setCollarDurationRange(hubParams.minDuration, hubParams.maxDuration);
    }
}
