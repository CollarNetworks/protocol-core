// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import { CollarBaseIntegrationTestConfig } from "./BaseIntegration.t.sol";
import { ProviderPositionNFT } from "../../../src/ProviderPositionNFT.sol";
import { CollarTakerNFT } from "../../../src/CollarTakerNFT.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

abstract contract PositionOperationsTest is CollarBaseIntegrationTestConfig {
    function createProviderOffer(uint callStrikeDeviation, uint amount) internal returns (uint offerId) {
        startHoax(provider);
        cashAsset.approve(address(providerNFT), amount);
        offerId = providerNFT.createOffer(callStrikeDeviation, amount, offerLTV, positionDuration);
        vm.stopPrank();
    }

    function openTakerPosition(uint collateralAmount, uint minCashAmount, uint offerId)
        internal
        returns (uint borrowId, CollarTakerNFT.TakerPosition memory position)
    {
        startHoax(user1);
        collateralAsset.approve(address(loanContract), collateralAmount);
        (borrowId,,) = loanContract.createLoan(collateralAmount, 0, minCashAmount, providerNFT, offerId);
        position = takerNFT.getPosition(borrowId);
        vm.stopPrank();

        // Perform checks
        assertEq(address(position.providerNFT), address(providerNFT));
        assertEq(position.openedAt, block.timestamp);
        assertEq(position.expiration, block.timestamp + positionDuration);
        assertEq(position.putStrikePrice, position.initialPrice * offerLTV / 10_000);
        assert(position.callStrikePrice > position.initialPrice);
        assert(position.putLockedCash > 0);
        assert(position.callLockedCash > 0);
        assertEq(position.settled, false);
        assertEq(position.withdrawable, 0);
    }

    function settleAndWithdraw(uint borrowId)
        internal
        returns (uint userWithdrawnAmount, uint providerWithdrawnAmount)
    {
        CollarTakerNFT.TakerPosition memory position = takerNFT.getPosition(borrowId);

        startHoax(user1);
        takerNFT.settlePairedPosition(borrowId);

        // User withdrawal
        uint userBalanceBefore = cashAsset.balanceOf(user1);
        takerNFT.withdrawFromSettled(borrowId, user1);
        uint userBalanceAfter = cashAsset.balanceOf(user1);
        userWithdrawnAmount = userBalanceAfter - userBalanceBefore;
        vm.stopPrank();

        // Provider withdrawal
        startHoax(provider);
        uint providerBalanceBefore = cashAsset.balanceOf(provider);
        providerNFT.withdrawFromSettled(position.providerPositionId, provider);
        uint providerBalanceAfter = cashAsset.balanceOf(provider);
        providerWithdrawnAmount = providerBalanceAfter - providerBalanceBefore;
        vm.stopPrank();
    }

    function calculatePriceDownValues(CollarTakerNFT.TakerPosition memory position, uint finalPrice)
        internal
        pure
        returns (uint expectedUserWithdrawable, uint expectedProviderGain)
    {
        uint lpPart = position.initialPrice - finalPrice;
        uint putRange = position.initialPrice - position.putStrikePrice;
        expectedProviderGain = position.putLockedCash * lpPart / putRange;
        expectedUserWithdrawable = position.putLockedCash - expectedProviderGain;
    }

    function calculatePriceUpValues(CollarTakerNFT.TakerPosition memory position, uint finalPrice)
        internal
        pure
        returns (uint expectedUserWithdrawable, uint expectedProviderWithdrawable)
    {
        uint userPart = finalPrice - position.initialPrice;
        uint callRange = position.callStrikePrice - position.initialPrice;
        uint userGain = position.callLockedCash * userPart / callRange;
        expectedUserWithdrawable = position.putLockedCash + userGain;
        expectedProviderWithdrawable = position.callLockedCash - userGain;
    }

    function checkPriceUnderPutStrikeValues(
        uint borrowId,
        uint userCashBalanceBeforeSettle,
        uint providerCashBalanceBeforeSettle
    ) internal {
        (uint userWithdrawnAmount, uint providerWithdrawnAmount) = settleAndWithdraw(borrowId);

        CollarTakerNFT.TakerPosition memory position = takerNFT.getPosition(borrowId);

        // Check position state after settlement
        assertEq(position.settled, true);
        assertEq(position.withdrawable, 0);

        // Check balances
        uint userBalanceAfter = cashAsset.balanceOf(user1);
        uint providerBalanceAfter = cashAsset.balanceOf(provider);

        // When price is under put strike, the user loses all locked cash
        // and the provider receives all locked cash from both sides
        assertEq(userWithdrawnAmount, 0, "User should not receive any cash when price is under put strike");
        assertEq(userBalanceAfter, userCashBalanceBeforeSettle, "User's balance should not change");

        uint expectedProviderWithdrawal = position.putLockedCash + position.callLockedCash;
        assertEq(
            providerWithdrawnAmount, expectedProviderWithdrawal, "Provider should receive all locked cash"
        );
        assertEq(
            providerBalanceAfter,
            providerCashBalanceBeforeSettle + expectedProviderWithdrawal,
            "Provider's balance should increase by the total locked cash amount"
        );
    }

    function checkPriceDownShortOfPutStrikeValues(
        uint borrowId,
        uint userCashBalanceBeforeSettle,
        uint providerCashBalanceBeforeSettle,
        uint finalPrice
    ) internal {
        (uint userWithdrawnAmount, uint providerWithdrawnAmount) = settleAndWithdraw(borrowId);

        CollarTakerNFT.TakerPosition memory position = takerNFT.getPosition(borrowId);

        (uint expectedUserWithdrawable, uint expectedProviderGain) =
            calculatePriceDownValues(position, finalPrice);
        // Check position state after settlement
        assertEq(position.settled, true);

        // Check balances after withdrawal
        uint userBalanceAfter = cashAsset.balanceOf(user1);
        uint providerBalanceAfter = cashAsset.balanceOf(provider);

        // When price is down but above put strike, the user gets a portion of the locked cash
        // and the provider gets the rest based on how close the price is to the put strike
        assertEq(
            userWithdrawnAmount,
            expectedUserWithdrawable,
            "User should receive a portion of the locked cash based on price movement"
        );
        assertEq(
            userBalanceAfter,
            userCashBalanceBeforeSettle + expectedUserWithdrawable,
            "User's balance should increase by the withdrawn amount"
        );
        assertEq(
            providerWithdrawnAmount,
            expectedProviderGain + position.callLockedCash,
            "Provider should receive a portion of the locked cash based on price movement + call locked cash"
        );
        assertEq(
            providerBalanceAfter,
            providerCashBalanceBeforeSettle + expectedProviderGain + position.callLockedCash,
            "Provider's balance should increase by the gained amount"
        );
    }

    function checkPriceUpPastCallStrikeValues(
        uint borrowId,
        uint userCashBalanceBeforeSettle,
        uint providerCashBalanceBeforeSettle
    ) internal {
        (uint userWithdrawnAmount, uint providerWithdrawnAmount) = settleAndWithdraw(borrowId);

        CollarTakerNFT.TakerPosition memory position = takerNFT.getPosition(borrowId);

        // Check position state after settlement
        assertEq(position.settled, true);

        // Check balances after withdrawal
        uint userBalanceAfter = cashAsset.balanceOf(user1);
        uint providerBalanceAfter = cashAsset.balanceOf(provider);

        // When price is up past call strike, the user receives all locked cash
        // and the provider receives nothing
        uint expectedUserWithdrawal = position.putLockedCash + position.callLockedCash;
        assertEq(
            userWithdrawnAmount,
            expectedUserWithdrawal,
            "User should receive all locked cash when price is above call strike"
        );
        assertEq(
            userBalanceAfter,
            userCashBalanceBeforeSettle + expectedUserWithdrawal,
            "User's balance should increase by the total locked cash amount"
        );

        assertEq(
            providerWithdrawnAmount, 0, "Provider should receive nothing when price is above call strike"
        );
        assertEq(
            providerBalanceAfter, providerCashBalanceBeforeSettle, "Provider's balance should not change"
        );
    }

    function checkPriceUpShortOfCallStrikeValues(
        uint borrowId,
        uint userCashBalanceBeforeSettle,
        uint providerCashBalanceBeforeSettle,
        uint finalPrice
    ) internal {
        (uint userWithdrawnAmount, uint providerWithdrawnAmount) = settleAndWithdraw(borrowId);

        CollarTakerNFT.TakerPosition memory position = takerNFT.getPosition(borrowId);

        (uint expectedUserWithdrawable, uint expectedProviderWithdrawable) =
            calculatePriceUpValues(position, finalPrice);
        // Check position state after settlement
        assertEq(position.settled, true);

        // Check balances after withdrawal
        uint userBalanceAfter = cashAsset.balanceOf(user1);
        uint providerBalanceAfter = cashAsset.balanceOf(provider);

        // When price is up but below call strike, the user gets their put locked cash
        // plus a portion of the call locked cash based on how close the price is to the call strike
        assertEq(
            userWithdrawnAmount,
            expectedUserWithdrawable,
            "User should receive put locked cash plus a portion of call locked cash based on price movement"
        );
        assertEq(
            userBalanceAfter,
            userCashBalanceBeforeSettle + expectedUserWithdrawable,
            "User's balance should increase by the withdrawn amount"
        );

        assertEq(
            providerWithdrawnAmount,
            expectedProviderWithdrawable,
            "Provider should receive the remaining portion of call locked cash"
        );
        assertEq(
            providerBalanceAfter,
            providerCashBalanceBeforeSettle + expectedProviderWithdrawable,
            "Provider's balance should increase by the withdrawn amount"
        );
    }

    function checkBalances(address account)
        internal
        view
        returns (uint cashBalance, uint collateralBalance)
    {
        cashBalance = cashAsset.balanceOf(account);
        collateralBalance = collateralAsset.balanceOf(account);
    }

    uint24[] public callStrikeTicks = [110, 115, 120, 130];

    function getOfferIndex(uint24 callStrikeTick) internal pure returns (uint) {
        if (callStrikeTick == 110) return 0;
        if (callStrikeTick == 115) return 1;
        if (callStrikeTick == 120) return 2;
        if (callStrikeTick == 130) return 3;
        revert("Invalid call strike tick");
    }

    function _setupOffers(uint amountPerOffer) internal {
        uint[] memory callStrikeDeviations = new uint[](4);
        callStrikeDeviations[0] = 11_000; // 110%
        callStrikeDeviations[1] = 11_500; // 115%
        callStrikeDeviations[2] = 12_000; // 120%
        callStrikeDeviations[3] = 13_000; // 130%

        startHoax(provider);
        cashAsset.approve(address(providerNFT), amountPerOffer * 4);

        for (uint i = 0; i < callStrikeDeviations.length; i++) {
            providerNFT.createOffer(callStrikeDeviations[i], amountPerOffer, offerLTV, positionDuration);
        }

        vm.stopPrank();
    }

    function _validateOfferSetup(uint amountPerOffer) internal view {
        uint[] memory callStrikeDeviations = new uint[](4);
        callStrikeDeviations[0] = 11_000; // 110%
        callStrikeDeviations[1] = 11_500; // 115%
        callStrikeDeviations[2] = 12_000; // 120%
        callStrikeDeviations[3] = 13_000; // 130%

        for (uint i = 0; i < callStrikeDeviations.length; i++) {
            ProviderPositionNFT.LiquidityOffer memory offer = providerNFT.getOffer(i);
            assertEq(offer.provider, provider, "Incorrect provider for offer");
            assertEq(offer.available, amountPerOffer, "Incorrect amount for offer");
            assertEq(offer.putStrikeDeviation, offerLTV, "Incorrect put strike deviation for offer");
            assertEq(
                offer.callStrikeDeviation,
                callStrikeDeviations[i],
                "Incorrect call strike deviation for offer"
            );
            assertEq(offer.duration, positionDuration, "Incorrect duration for offer");
        }
    }
}
