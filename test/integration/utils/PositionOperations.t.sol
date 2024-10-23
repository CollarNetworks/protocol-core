// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import { CollarBaseIntegrationTestConfig, ILoansNFT } from "./BaseIntegration.t.sol";
import { CollarProviderNFT } from "../../../src/CollarProviderNFT.sol";
import { CollarTakerNFT } from "../../../src/CollarTakerNFT.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

abstract contract PositionOperationsTest is CollarBaseIntegrationTestConfig {
    using SafeERC20 for IERC20;

    function createProviderOffer(uint callStrikePercent, uint amount) internal returns (uint offerId) {
        startHoax(provider);
        pair.cashAsset.forceApprove(address(pair.providerNFT), amount);
        offerId = pair.providerNFT.createOffer(callStrikePercent, amount, offerLTV, positionDuration, 0);
        vm.stopPrank();
    }

    function openTakerPositionAndCheckValues(uint underlyingAmount, uint minCashAmount, uint offerId)
        internal
        returns (uint borrowId, CollarTakerNFT.TakerPosition memory position)
    {
        startHoax(user);
        pair.underlying.forceApprove(address(pair.loansContract), underlyingAmount);
        (borrowId,,) = pair.loansContract.openLoan(
            underlyingAmount,
            0,
            ILoansNFT.SwapParams(minCashAmount, address(pair.loansContract.defaultSwapper()), ""),
            ILoansNFT.ProviderOffer(pair.providerNFT, offerId)
        );
        position = pair.takerNFT.getPosition(borrowId);
        vm.stopPrank();

        // Perform checks
        assertEq(address(position.providerNFT), address(pair.providerNFT));
        assertEq(position.duration, positionDuration);
        assertEq(position.expiration, block.timestamp + positionDuration);
        assertEq(position.putStrikePercent, offerLTV);
        assert(position.callStrikePercent > 10_000);
        assert(position.takerLocked > 0);
        assert(position.providerLocked > 0);
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
        pair.takerNFT.withdrawFromSettled(borrowId);
        uint userBalanceAfter = pair.cashAsset.balanceOf(user);
        userWithdrawnAmount = userBalanceAfter - userBalanceBefore;
        vm.stopPrank();

        // Provider withdrawal
        startHoax(provider);
        uint providerBalanceBefore = pair.cashAsset.balanceOf(provider);
        pair.providerNFT.withdrawFromSettled(position.providerId);
        uint providerBalanceAfter = pair.cashAsset.balanceOf(provider);
        providerWithdrawnAmount = providerBalanceAfter - providerBalanceBefore;
        vm.stopPrank();
    }

    function calculatePriceDownValues(CollarTakerNFT.TakerPosition memory position, uint finalPrice)
        internal
        pure
        returns (uint expectedUserWithdrawable, uint expectedProviderGain)
    {
        uint lpPart = position.startPrice - finalPrice;
        uint putStrikePrice = position.putStrikePercent * position.startPrice / 10_000;
        uint putRange = position.startPrice - putStrikePrice;
        expectedProviderGain = position.takerLocked * lpPart / putRange;
        expectedUserWithdrawable = position.takerLocked - expectedProviderGain;
    }

    function calculatePriceUpValues(CollarTakerNFT.TakerPosition memory position, uint finalPrice)
        internal
        pure
        returns (uint expectedUserWithdrawable, uint expectedProviderWithdrawable)
    {
        uint userPart = finalPrice - position.startPrice;
        uint callStrikePrice = position.callStrikePercent * position.startPrice / 10_000;
        uint callRange = callStrikePrice - position.startPrice;
        uint userGain = position.providerLocked * userPart / callRange;
        expectedUserWithdrawable = position.takerLocked + userGain;
        expectedProviderWithdrawable = position.providerLocked - userGain;
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

        uint expectedProviderWithdrawal = position.takerLocked + position.providerLocked;
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
        assertEq(providerWithdrawnAmount, expectedProviderGain + position.providerLocked);
        assertEq(
            providerBalanceAfter,
            providerCashBalanceBeforeSettle + expectedProviderGain + position.providerLocked
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
        uint expectedUserWithdrawal = position.takerLocked + position.providerLocked;
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
        uint[] memory callStrikePercents = new uint[](4);
        callStrikePercents[0] = 11_000; // 110%
        callStrikePercents[1] = 11_500; // 115%
        callStrikePercents[2] = 12_000; // 120%
        callStrikePercents[3] = 13_000; // 130%

        startHoax(provider);
        pair.cashAsset.forceApprove(address(pair.providerNFT), amountPerOffer * 4);

        for (uint i = 0; i < callStrikePercents.length; i++) {
            pair.providerNFT.createOffer(callStrikePercents[i], amountPerOffer, offerLTV, positionDuration, 0);
        }

        vm.stopPrank();
    }

    function _validateOfferSetup(uint amountPerOffer) internal view {
        uint[] memory callStrikePercents = new uint[](4);
        callStrikePercents[0] = 11_000; // 110%
        callStrikePercents[1] = 11_500; // 115%
        callStrikePercents[2] = 12_000; // 120%
        callStrikePercents[3] = 13_000; // 130%

        for (uint i = 0; i < callStrikePercents.length; i++) {
            CollarProviderNFT.LiquidityOffer memory offer = pair.providerNFT.getOffer(1 + i); // starts from 1
            assertEq(offer.provider, provider);
            assertEq(offer.available, amountPerOffer);
            assertEq(offer.putStrikePercent, offerLTV);
            assertEq(offer.callStrikePercent, callStrikePercents[i]);
            assertEq(offer.duration, positionDuration);
        }
    }
}
