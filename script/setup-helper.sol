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
        hub.setCanOpenPair(pair.underlying, pair.cashAsset, address(pair.takerNFT), true);
        hub.setCanOpenPair(pair.underlying, pair.cashAsset, address(pair.providerNFT), true);
        hub.setCanOpenPair(pair.underlying, pair.cashAsset, address(pair.loansContract), true);
        hub.setCanOpenPair(pair.underlying, pair.cashAsset, address(pair.rollsContract), true);
        pair.loansContract.setSwapperAllowed(address(pair.swapperUniV3), true, true);
        hub.setCanOpenPair(pair.underlying, hub.ANY_ASSET(), address(pair.escrowNFT), true);
        pair.escrowNFT.setLoansCanOpen(address(pair.loansContract), true);
    }

    function setupConfigHub(ConfigHub configHub, HubParams memory hubParams) internal {
        configHub.setLTVRange(hubParams.minLTV, hubParams.maxLTV);
        configHub.setCollarDurationRange(hubParams.minDuration, hubParams.maxDuration);
    }
}
