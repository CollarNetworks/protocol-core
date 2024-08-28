// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { DeploymentUtils } from "../utils/deployment-exporter.s.sol";
import { ShortProviderNFT } from "../../src/ShortProviderNFT.sol";
import { CollarTakerNFT } from "../../src/CollarTakerNFT.sol";
import { Loans } from "../../src/Loans.sol";
import { Rolls } from "../../src/Rolls.sol";
import { BaseDeployment } from "../BaseDeployment.s.sol";
import { CollarOwnedERC20 } from "../../test/utils/CollarOwnedERC20.sol";

contract ExecuteAndVerifyRolls is Script, DeploymentUtils, BaseDeployment {
    int rollFee = 100 ether;
    int slippage = 300;
    CollarOwnedERC20 constant cashAsset = CollarOwnedERC20(0x5D01F1E59C188a2A9Afc376cF6627dd5F28DC28F);
    CollarOwnedERC20 constant collateralAsset = CollarOwnedERC20(0x9A6E1a5f94De0aD8ca15b55eA0d39bEaEc579434);

    function run() external {
        (, address user,,) = setup();

        AssetPairContracts memory pair = getByAssetPair(address(cashAsset), address(collateralAsset));

        uint loanId = 0; // Assuming this is the ID of the loan created in the previous step
        uint rollOfferId = 0; // Assuming this is the ID of the roll offer created in the previous step

        vm.startBroadcast(user);
        _executeRoll(user, pair, loanId, rollOfferId, slippage);
        vm.stopBroadcast();

        console.log("\nRoll executed and verified successfully");
    }
}
