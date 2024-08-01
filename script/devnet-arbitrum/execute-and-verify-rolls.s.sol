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
import { BaseDeployment } from "../base.s.sol";

contract VerifyRolls is Script, DeploymentUtils, BaseDeployment {
    int rollFee = 1e6;
    int rollDeltaFactor = 10_000;
    int slippage = 3000;
    address USDC = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
    address WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

    function run() external {
        (, address user1,, address liquidityProvider) = setup();

        // Load deployed contract addresses
        AssetPairContracts memory pair = getByAssetPair(USDC, WETH);

        // You'll need to pass or retrieve the loanId and providerId from the previous step
        uint loanId = 0; /* retrieve or pass loanId */
        uint providerId = 0; /* retrieve or pass providerId */

        _createAndExecuteRoll(liquidityProvider, user1, pair, loanId, providerId);

        console.log("\nRoll executed and verified successfully");
    }

    function _createAndExecuteRoll(
        address provider,
        address user,
        AssetPairContracts memory pair,
        uint loanId,
        uint providerId
    ) internal {
        // Record initial balances
        uint initialUserCashBalance = pair.cashAsset.balanceOf(user);
        uint initialLoanAmount = pair.loansContract.getLoan(loanId).loanAmount;

        vm.startBroadcast(provider);
        uint currentPrice = pair.takerNFT.getReferenceTWAPPrice(block.timestamp);
        pair.cashAsset.approve(address(pair.rollsContract), type(uint).max);
        pair.providerNFT.approve(address(pair.rollsContract), providerId);
        uint rollOfferId = pair.rollsContract.createRollOffer(
            loanId,
            rollFee, // Roll fee
            rollDeltaFactor, // Roll fee delta factor (100%)
            currentPrice * 90 / 100, // Min price (90% of current price)
            currentPrice * 110 / 100, // Max price (110% of current price)
            0, // Min to provider
            block.timestamp + 1 hours // Deadline
        );
        vm.stopBroadcast();

        vm.startBroadcast(user);
        pair.cashAsset.approve(address(pair.loansContract), type(uint).max);
        pair.takerNFT.approve(address(pair.loansContract), loanId);

        currentPrice = pair.takerNFT.getReferenceTWAPPrice(block.timestamp);
        console.log("current price: ", currentPrice);
        (int toTaker,,) = pair.rollsContract.calculateTransferAmounts(rollOfferId, currentPrice);
        console.log("to taker");
        console.logInt(toTaker);
        int minToUserSlippage = toTaker + (toTaker * slippage / 10_000);
        console.log("min to user");
        console.logInt(minToUserSlippage);
        (uint newTakerId, uint newLoanAmount, int actualTransferAmount) =
            pair.loansContract.rollLoan(loanId, pair.rollsContract, rollOfferId, minToUserSlippage);
        console.logInt(actualTransferAmount);
        vm.stopBroadcast();

        console.log("Roll executed:");
        console.log(" - New Taker ID: %d", newTakerId);
        console.log(" - New Loan Amount: %d", newLoanAmount);

        _verifyRollExecution(
            user,
            pair,
            newTakerId,
            newLoanAmount,
            initialUserCashBalance,
            initialLoanAmount,
            currentPrice,
            toTaker,
            actualTransferAmount
        );
    }

    function _verifyRollExecution(
        address user,
        AssetPairContracts memory pair,
        uint newTakerId,
        uint newLoanAmount,
        uint initialUserCashBalance,
        uint initialLoanAmount,
        uint currentPrice,
        int toTaker,
        int actualTransferAmount
    ) internal view {
        require(pair.takerNFT.ownerOf(newTakerId) == user, "New taker NFT not owned by user");
        require(newLoanAmount > 0, "Invalid new loan amount");
        CollarTakerNFT.TakerPosition memory newPosition = pair.takerNFT.getPosition(newTakerId);
        require(newPosition.settled == false, "New position should not be settled");
        require(newPosition.withdrawable == 0, "New position should have no withdrawable amount");
        require(newPosition.putLockedCash > 0, "New position should have put locked cash");
        require(newPosition.callLockedCash > 0, "New position should have call locked cash");

        // Check balance changes
        uint finalUserCashBalance = pair.cashAsset.balanceOf(user);
        int userBalanceChange = int(finalUserCashBalance) - int(initialUserCashBalance);

        require(userBalanceChange == toTaker, "User balance change doesn't match expected transfer");
        require(actualTransferAmount == toTaker, "Actual transfer amount doesn't match calculated amount");

        // Check loan amount change
        int loanAmountChange = int(newLoanAmount) - int(initialLoanAmount);
        require(loanAmountChange == userBalanceChange + rollFee, "Loan amount change is incorrect");

        // Additional checks
        require(newPosition.expiration > block.timestamp, "New position expiration should be in the future");
        require(
            newPosition.initialPrice == currentPrice, "New position initial price should match current price"
        );
        require(newPosition.putStrikePrice < currentPrice, "Put strike price should be below current price");
        require(newPosition.callStrikePrice > currentPrice, "Call strike price should be above current price");
    }
}
