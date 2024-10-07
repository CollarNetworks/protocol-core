// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import { CollarBaseIntegrationTestConfig, ILoansNFT } from "./BaseIntegration.t.sol";
import { ShortProviderNFT } from "../../../src/ShortProviderNFT.sol";
import { CollarTakerNFT } from "../../../src/CollarTakerNFT.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

abstract contract PositionOperationsTest is CollarBaseIntegrationTestConfig {
    using SafeERC20 for IERC20;

    function createProviderOffer(uint callStrikeDeviation, uint amount) internal returns (uint offerId) {
        startHoax(provider);
        pair.cashAsset.forceApprove(address(pair.providerNFT), amount);
        offerId = pair.providerNFT.createOffer(callStrikeDeviation, amount, offerLTV, positionDuration);
        vm.stopPrank();
    }

    function openTakerPositionAndCheckValues(uint collateralAmount, uint minCashAmount, uint offerId)
        internal
        returns (uint borrowId, CollarTakerNFT.TakerPosition memory position)
    {
        startHoax(user);
        pair.collateralAsset.forceApprove(address(pair.loansContract), collateralAmount);
        (borrowId,,) = pair.loansContract.openLoan(
            collateralAmount,
            0,
            ILoansNFT.SwapParams(minCashAmount, address(pair.loansContract.defaultSwapper()), ""),
            offerId
        );
        position = pair.takerNFT.getPosition(borrowId);
        vm.stopPrank();

        // Perform checks
        assertEq(address(position.providerNFT), address(pair.providerNFT));
        assertEq(position.duration, positionDuration);
        assertEq(position.expiration, block.timestamp + positionDuration);
        assertEq(position.putStrikePrice, position.initialPrice * offerLTV / 10_000);
        assert(position.callStrikePrice > position.initialPrice);
        assert(position.takerLocked > 0);
        assert(position.callLockedCash > 0);
        assertEq(position.settled, false);
        assertEq(position.withdrawable, 0);
    }

    function settleAndWithdraw(uint borrowId)
        internal
        returns (uint userWithdrawnAmount, uint providerWithdrawnAmount)
    {
        CollarTakerNFT.TakerPosition memory position = pair.takerNFT.getPosition(borrowId);

        startHoax(user);
        pair.takerNFT.settlePairedPosition(borrowId);

        // unwrap the taker position (send to user)
        pair.loansContract.unwrapAndCancelLoan(borrowId);

        // User withdrawal
        uint userBalanceBefore = pair.cashAsset.balanceOf(user);
        pair.takerNFT.withdrawFromSettled(borrowId, user);
        uint userBalanceAfter = pair.cashAsset.balanceOf(user);
        userWithdrawnAmount = userBalanceAfter - userBalanceBefore;
        vm.stopPrank();

        // Provider withdrawal
        startHoax(provider);
        uint providerBalanceBefore = pair.cashAsset.balanceOf(provider);
        pair.providerNFT.withdrawFromSettled(position.providerId, provider);
        uint providerBalanceAfter = pair.cashAsset.balanceOf(provider);
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
        expectedProviderGain = position.takerLocked * lpPart / putRange;
        expectedUserWithdrawable = position.takerLocked - expectedProviderGain;
    }

    function calculatePriceUpValues(CollarTakerNFT.TakerPosition memory position, uint finalPrice)
        internal
        pure
        returns (uint expectedUserWithdrawable, uint expectedProviderWithdrawable)
    {
        uint userPart = finalPrice - position.initialPrice;
        uint callRange = position.callStrikePrice - position.initialPrice;
        uint userGain = position.callLockedCash * userPart / callRange;
        expectedUserWithdrawable = position.takerLocked + userGain;
        expectedProviderWithdrawable = position.callLockedCash - userGain;
    }

    function checkPriceUnderPutStrikeValues(
        uint borrowId,
        uint userCashBalanceBeforeSettle,
        uint providerCashBalanceBeforeSettle
    ) internal {
        (
            uint userWithdrawnAmount,
            uint providerWithdrawnAmount,
            uint userBalanceAfter,
            uint providerBalanceAfter,
            CollarTakerNFT.TakerPosition memory position
        ) = _settleAndGetBalances(borrowId);

        assertEq(position.withdrawable, 0);
        // When price is under put strike, the user loses all locked cash
        // and the provider receives all locked cash from both sides
        assertEq(userWithdrawnAmount, 0);
        assertEq(userBalanceAfter, userCashBalanceBeforeSettle);

        uint expectedProviderWithdrawal = position.takerLocked + position.callLockedCash;
        assertEq(providerWithdrawnAmount, expectedProviderWithdrawal);
        assertEq(providerBalanceAfter, providerCashBalanceBeforeSettle + expectedProviderWithdrawal);
    }

    function checkPriceDownShortOfPutStrikeValues(
        uint borrowId,
        uint userCashBalanceBeforeSettle,
        uint providerCashBalanceBeforeSettle,
        uint finalPrice
    ) internal {
        (
            uint userWithdrawnAmount,
            uint providerWithdrawnAmount,
            uint userBalanceAfter,
            uint providerBalanceAfter,
            CollarTakerNFT.TakerPosition memory position
        ) = _settleAndGetBalances(borrowId);
        (uint expectedUserWithdrawable, uint expectedProviderGain) =
            calculatePriceDownValues(position, finalPrice);
        // When price is down but above put strike, the user gets a portion of the locked cash
        // and the provider gets the rest based on how close the price is to the put strike
        assertEq(userWithdrawnAmount, expectedUserWithdrawable);
        assertEq(userBalanceAfter, userCashBalanceBeforeSettle + expectedUserWithdrawable);
        assertEq(providerWithdrawnAmount, expectedProviderGain + position.callLockedCash);
        assertEq(
            providerBalanceAfter,
            providerCashBalanceBeforeSettle + expectedProviderGain + position.callLockedCash
        );
    }

    function checkPriceUpPastCallStrikeValues(
        uint borrowId,
        uint userCashBalanceBeforeSettle,
        uint providerCashBalanceBeforeSettle
    ) internal {
        (
            uint userWithdrawnAmount,
            uint providerWithdrawnAmount,
            uint userBalanceAfter,
            uint providerBalanceAfter,
            CollarTakerNFT.TakerPosition memory position
        ) = _settleAndGetBalances(borrowId);

        // When price is up past call strike, the user receives all locked cash
        // and the provider receives nothing
        uint expectedUserWithdrawal = position.takerLocked + position.callLockedCash;
        assertEq(userWithdrawnAmount, expectedUserWithdrawal);
        assertEq(userBalanceAfter, userCashBalanceBeforeSettle + expectedUserWithdrawal);

        assertEq(providerWithdrawnAmount, 0);
        assertEq(providerBalanceAfter, providerCashBalanceBeforeSettle);
    }

    function checkPriceUpShortOfCallStrikeValues(
        uint borrowId,
        uint userCashBalanceBeforeSettle,
        uint providerCashBalanceBeforeSettle,
        uint finalPrice
    ) internal {
        (
            uint userWithdrawnAmount,
            uint providerWithdrawnAmount,
            uint userBalanceAfter,
            uint providerBalanceAfter,
            CollarTakerNFT.TakerPosition memory position
        ) = _settleAndGetBalances(borrowId);
        (uint expectedUserWithdrawable, uint expectedProviderWithdrawable) =
            calculatePriceUpValues(position, finalPrice);

        // When price is up but below call strike, the user gets their put locked cash
        // plus a portion of the call locked cash based on how close the price is to the call strike
        assertEq(userWithdrawnAmount, expectedUserWithdrawable);
        assertEq(userBalanceAfter, userCashBalanceBeforeSettle + expectedUserWithdrawable);

        assertEq(providerWithdrawnAmount, expectedProviderWithdrawable);
        assertEq(providerBalanceAfter, providerCashBalanceBeforeSettle + expectedProviderWithdrawable);
    }

    function getOfferIndex(uint24 callStrikeTick) internal pure returns (uint) {
        if (callStrikeTick == 110) return 1;
        if (callStrikeTick == 115) return 2;
        if (callStrikeTick == 120) return 3;
        if (callStrikeTick == 130) return 4;
        revert("Invalid call strike tick");
    }

    function _settleAndGetBalances(uint borrowId)
        internal
        returns (
            uint userWithdrawnAmount,
            uint providerWithdrawnAmount,
            uint userBalanceAfter,
            uint providerBalanceAfter,
            CollarTakerNFT.TakerPosition memory position
        )
    {
        (userWithdrawnAmount, providerWithdrawnAmount) = settleAndWithdraw(borrowId);

        position = pair.takerNFT.getPosition(borrowId);

        // Check position state after settlement
        assertEq(position.settled, true);
        assertEq(position.withdrawable, 0);

        // Check balances
        userBalanceAfter = pair.cashAsset.balanceOf(user);
        providerBalanceAfter = pair.cashAsset.balanceOf(provider);
    }

    function _setupOffers(uint amountPerOffer) internal {
        uint[] memory callStrikeDeviations = new uint[](4);
        callStrikeDeviations[0] = 11_000; // 110%
        callStrikeDeviations[1] = 11_500; // 115%
        callStrikeDeviations[2] = 12_000; // 120%
        callStrikeDeviations[3] = 13_000; // 130%

        startHoax(provider);
        pair.cashAsset.forceApprove(address(pair.providerNFT), amountPerOffer * 4);

        for (uint i = 0; i < callStrikeDeviations.length; i++) {
            pair.providerNFT.createOffer(callStrikeDeviations[i], amountPerOffer, offerLTV, positionDuration);
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
            ShortProviderNFT.LiquidityOffer memory offer = pair.providerNFT.getOffer(1 + i); // starts from 1
            assertEq(offer.provider, provider);
            assertEq(offer.available, amountPerOffer);
            assertEq(offer.putStrikeDeviation, offerLTV);
            assertEq(offer.callStrikeDeviation, callStrikeDeviations[i]);
            assertEq(offer.duration, positionDuration);
        }
    }
}
