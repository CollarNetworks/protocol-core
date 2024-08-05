// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { DeploymentUtils } from "../utils/deployment-exporter.s.sol";
import { ProviderPositionNFT } from "../../src/ProviderPositionNFT.sol";
import { CollarTakerNFT } from "../../src/CollarTakerNFT.sol";
import { Loans } from "../../src/Loans.sol";
import { Rolls } from "../../src/Rolls.sol";
import { BaseDeployment } from "../base.s.sol";
import { CollarOwnedERC20 } from "../../test/utils/CollarOwnedERC20.sol";

contract ExecuteAndVerifyRolls is Script, DeploymentUtils, BaseDeployment {
    int rollFee = 100 ether;
    int slippage = 300;
    CollarOwnedERC20 constant cashAsset = CollarOwnedERC20(0x5D01F1E59C188a2A9Afc376cF6627dd5F28DC28F);
    CollarOwnedERC20 constant collateralAsset = CollarOwnedERC20(0x9A6E1a5f94De0aD8ca15b55eA0d39bEaEc579434);

    function run() external {
        (, address user,,) = setup();

        AssetPairContracts memory pair = getByAssetPair(address(cashAsset), address(collateralAsset));

        uint loanId = 2; // Assuming this is the ID of the loan created in the previous step
        uint rollOfferId = 2; // Assuming this is the ID of the roll offer created in the previous step

        vm.startBroadcast(user);
        _executeRoll(user, pair, loanId, rollOfferId);
        vm.stopBroadcast();

        console.log("\nRoll executed and verified successfully");
    }

    function _executeRoll(address user, AssetPairContracts memory pair, uint loanId, uint rollOfferId)
        internal
    {
        uint initialUserCashBalance = pair.cashAsset.balanceOf(user);
        uint initialLoanAmount = pair.loansContract.getLoan(loanId).loanAmount;

        pair.cashAsset.approve(address(pair.loansContract), type(uint).max);
        pair.takerNFT.approve(address(pair.loansContract), loanId);

        uint currentPrice = pair.takerNFT.getReferenceTWAPPrice(block.timestamp);
        (int toTaker,,) = pair.rollsContract.calculateTransferAmounts(rollOfferId, currentPrice);
        (uint newTakerId, uint newLoanAmount, int actualTransferAmount) =
            pair.loansContract.rollLoan(loanId, pair.rollsContract, rollOfferId, toTaker);

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

        uint finalUserCashBalance = pair.cashAsset.balanceOf(user);
        int userBalanceChange = int(finalUserCashBalance) - int(initialUserCashBalance);

        console.log("initial user cash balance: ", initialUserCashBalance);

        console.log("final user cash balance: ", finalUserCashBalance);

        console.log("User balance change: ");
        console.logInt(userBalanceChange);

        console.log("Actual transfer amount: ");
        console.logInt(actualTransferAmount);

        console.log("To taker: ");
        console.logInt(toTaker);

        require(userBalanceChange == toTaker, "User balance change doesn't match expected transfer");
        require(actualTransferAmount == toTaker, "Actual transfer amount doesn't match calculated amount");

        int loanAmountChange = int(newLoanAmount) - int(initialLoanAmount);
        require(loanAmountChange == userBalanceChange + rollFee, "Loan amount change is incorrect");

        require(newPosition.expiration > block.timestamp, "New position expiration should be in the future");
        require(
            newPosition.initialPrice == currentPrice, "New position initial price should match current price"
        );
        require(newPosition.putStrikePrice < currentPrice, "Put strike price should be below current price");
        require(newPosition.callStrikePrice > currentPrice, "Call strike price should be above current price");

        console.log("Roll verification passed successfully");
    }
}
