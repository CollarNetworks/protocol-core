// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { DeploymentUtils } from "../utils/deployment-exporter.s.sol";
import { ProviderPositionNFT } from "../../src/ProviderPositionNFT.sol";
import { CollarTakerNFT } from "../../src/CollarTakerNFT.sol";
import { Loans } from "../../src/Loans.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Rolls } from "../../src/Rolls.sol";
import { BaseDeployment } from "../BaseDeployment.s.sol";

contract VerifyRolls is Script, DeploymentUtils, BaseDeployment {
    int rollFee = 100e6; // 100USDC
    int slippage = 300;
    address USDC = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
    address WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

    function run() external {
        (, address user1,,) = setup();

        // Load deployed contract addresses
        AssetPairContracts memory pair = getByAssetPair(USDC, WETH);

        // You'll need to pass or retrieve the loanId and providerId from the previous step
        uint loanId = 2; /* retrieve or pass loanId */
        uint rollOfferId = 2; /* retrieve or pass rollOfferId */
        vm.startBroadcast(user1);
        _executeRoll(user1, pair, loanId, rollOfferId, slippage);
        vm.stopBroadcast();
        console.log("\nRoll executed and verified successfully");
    }
}
