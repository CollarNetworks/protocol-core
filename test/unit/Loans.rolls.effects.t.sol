// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

import "forge-std/Test.sol";
import { IERC721Errors } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

import { LoansNFT, ILoansNFT } from "../../src/LoansNFT.sol";
import { CollarTakerNFT } from "../../src/CollarTakerNFT.sol";
import { Rolls, IRolls } from "../../src/Rolls.sol";

import { LoansTestBase } from "./Loans.basic.effects.t.sol";

contract LoansRollTestBase is LoansTestBase {
    struct ExpectedRoll {
        uint newTakerLocked;
        uint newProviderLocked;
        int toTaker;
        int rollFee;
        uint newLoanAmount;
        uint newLoanId;
        bool isEscrowLoan;
        uint newEscrowId;
        uint escrowFeeRefund;
    }

    function calculateRollAmounts(uint rollId, uint newPrice, ILoansNFT.Loan memory prevLoan)
        internal
        view
        returns (ExpectedRoll memory expected)
    {
        // roll transfers
        IRolls.PreviewResults memory preview = rolls.previewRoll(rollId, newPrice);
        (expected.toTaker, expected.rollFee) = (preview.toTaker, preview.rollFee);

        uint takerId = rolls.getRollOffer(rollId).takerId;
        CollarTakerNFT.TakerPosition memory oldTakerPos = takerNFT.getPosition(takerId);

        // new position
        expected.newTakerLocked = oldTakerPos.takerLocked * newPrice / oraclePrice;
        expected.newProviderLocked =
            expected.newTakerLocked * (callStrikePercent - BIPS_100PCT) / (BIPS_100PCT - ltv);

        // toTaker = userGain - rollFee, so userGain (loan increase) = toTaker + rollFee
        expected.newLoanAmount =
            uint(int(loans.getLoan(takerId).loanAmount) + expected.toTaker + expected.rollFee);

        expected.newLoanId = takerNFT.nextPositionId();

        expected.isEscrowLoan = prevLoan.usesEscrow;
        if (expected.isEscrowLoan) {
            expected.newEscrowId = escrowNFT.nextEscrowId();
            (,, expected.escrowFeeRefund) = escrowNFT.previewRelease(prevLoan.escrowId, 0);
        } else {
            // default to 0
        }

        return expected;
    }

    function createRollOffer(uint loanId) internal returns (uint rollId) {
        uint takerId = loanId;
        vm.startPrank(provider);
        uint providerId = takerNFT.getPosition(takerId).providerId;
        providerNFT.approve(address(rolls), providerId);
        cashAsset.approve(address(rolls), type(uint).max);
        rollId = rolls.createOffer(
            takerId, rollFee, 0, 0, type(uint).max, -int(largeAmount), block.timestamp + duration
        );
    }

    function checkRollLoan(uint loanId, uint newPrice)
        internal
        returns (uint newLoanId, ExpectedRoll memory expected)
    {
        // Update price
        updatePrice(newPrice);

        uint rollId = createRollOffer(loanId);

        maybeCreateEscrowOffer();

        // Calculate expected values
        ILoansNFT.Loan memory prevLoan = loans.getLoan(loanId);
        expected = calculateRollAmounts(rollId, newPrice, prevLoan);

        // Execute roll
        vm.startPrank(user1);
        cashAsset.approve(address(loans), type(uint).max);
        underlying.approve(address(loans), escrowFee);

        uint userCash = cashAsset.balanceOf(user1);
        uint userUnderlying = underlying.balanceOf(user1);

        vm.expectEmit(address(loans));
        emit ILoansNFT.LoanRolled(
            user1,
            loanId,
            rollId,
            expected.newLoanId,
            prevLoan.loanAmount,
            expected.newLoanAmount,
            expected.toTaker
        );
        // min change param
        int minToUser = int(expected.newLoanAmount) - int(prevLoan.loanAmount) - rollFee;
        uint newLoanAmount;
        int toUser;
        (newLoanId, newLoanAmount, toUser) =
            loans.rollLoan(loanId, rollOffer(rollId), minToUser, escrowOfferId, escrowFee);
        if (expected.isEscrowLoan) {
            // sanity checks for test values
            assertGt(escrowOfferId, 0);
            assertGt(escrowFee, 0);
            // check new escrow
            _checkEscrowViews(newLoanId, expected.newEscrowId, escrowFee);
            // old released
            assertTrue(escrowNFT.getEscrow(prevLoan.escrowId).released);
        } else {
            // sanity checks for test values
            assertEq(escrowOfferId, 0);
            assertEq(escrowFee, 0);
        }

        // id
        assertEq(newLoanId, expected.newLoanId);
        // new loanAmount
        assertEq(newLoanAmount, expected.newLoanAmount);

        // check loans and NFT views
        _checkLoansAndNFTs(loanId, newLoanId, expected, newPrice);

        // balance change matches roll output value
        assertEq(cashAsset.balanceOf(user1), uint(int(userCash) + expected.toTaker));
        assertEq(underlying.balanceOf(user1), userUnderlying + expected.escrowFeeRefund - escrowFee);
        // loan change matches balance change
        int loanChange = int(newLoanAmount) - int(prevLoan.loanAmount);
        assertEq(expected.toTaker, toUser);
        assertEq(expected.toTaker + expected.rollFee, loanChange);
    }

    function _checkLoansAndNFTs(uint loanId, uint newLoanId, ExpectedRoll memory expected, uint newPrice)
        internal
    {
        // old loans NFT burned
        expectRevertERC721Nonexistent(loanId);
        loans.ownerOf(loanId);
        // old taker NFT burned
        uint takerId = loanId;
        expectRevertERC721Nonexistent(takerId);
        takerNFT.ownerOf(takerId);

        // user has new loan NFT
        assertEq(loans.ownerOf(newLoanId), user1);
        // Loans has the taker NFT
        uint newTakerId = newLoanId;
        assertEq(takerNFT.ownerOf(newTakerId), address(loans));

        // new loan state
        ILoansNFT.Loan memory newLoan = loans.getLoan(newLoanId);
        assertEq(newLoan.loanAmount, expected.newLoanAmount);
        assertEq(newLoan.underlyingAmount, loans.getLoan(loanId).underlyingAmount);
        assertEq(newLoan.usesEscrow, expected.isEscrowLoan);
        assertEq(address(newLoan.escrowNFT), address(expected.isEscrowLoan ? escrowNFT : NO_ESCROW));
        assertEq(newLoan.escrowId, expected.newEscrowId);

        // new taker position
        CollarTakerNFT.TakerPosition memory newTakerPos = takerNFT.getPosition(newLoanId);
        assertEq(newTakerPos.takerLocked, expected.newTakerLocked);
        assertEq(newTakerPos.providerLocked, expected.newProviderLocked);
        assertEq(newTakerPos.startPrice, newPrice);
    }

    function checkCloseRolledLoan(uint loanId, uint loanAmount) public returns (uint) {
        skip(duration);

        CollarTakerNFT.TakerPosition memory takerPosition = takerNFT.getPosition({ takerId: loanId });
        uint withdrawal = takerPosition.takerLocked;
        uint swapOut = prepareSwapToUnderlyingAtOraclePrice();
        closeAndCheckLoan(loanId, user1, loanAmount, withdrawal, swapOut);
        return loanId;
    }
}

contract LoansRollsEffectsTest is LoansRollTestBase {
    function test_rollLoan_no_change() public {
        (uint loanId,,) = createAndCheckLoan();
        CollarTakerNFT.TakerPosition memory takerPosition = takerNFT.getPosition({ takerId: loanId });
        (uint newTakerId, ExpectedRoll memory expected) = checkRollLoan(loanId, oraclePrice);

        // no change in locked amounts
        assertEq(expected.newTakerLocked, takerPosition.takerLocked);
        assertEq(expected.newProviderLocked, takerPosition.providerLocked);
        // only fee paid
        assertEq(expected.toTaker, -rollFee);
        assertEq(expected.newLoanAmount, loans.getLoan(loanId).loanAmount);
        assertEq(expected.newLoanAmount, loans.getLoan(newTakerId).loanAmount);

        checkCloseRolledLoan(newTakerId, expected.newLoanAmount);
    }

    function test_rollLoan_no_change_multiple() public {
        (uint loanId,,) = createAndCheckLoan();
        CollarTakerNFT.TakerPosition memory takerPosition = takerNFT.getPosition({ takerId: loanId });

        ExpectedRoll memory expected;
        uint newLoanId = loanId;
        uint balanceBefore = cashAsset.balanceOf(user1);
        // roll 10 times
        for (uint i; i < 5; ++i) {
            (newLoanId, expected) = checkRollLoan(newLoanId, oraclePrice);
        }
        // no change in locked amounts
        assertEq(expected.newTakerLocked, takerPosition.takerLocked);
        assertEq(expected.newProviderLocked, takerPosition.providerLocked);
        // only fee paid
        assertEq(expected.toTaker, -rollFee); // single fee
        // paid the rollFee 10 times
        assertEq(cashAsset.balanceOf(user1), balanceBefore - (5 * uint(rollFee)));
        assertEq(expected.newLoanAmount, loans.getLoan(loanId).loanAmount);
        assertEq(expected.newLoanAmount, loans.getLoan(newLoanId).loanAmount);

        checkCloseRolledLoan(newLoanId, expected.newLoanAmount);
    }

    function test_rollLoan_setKeeperAllowed_preserved() public {
        (uint loanId,,) = createAndCheckLoan();
        loans.setKeeperApproved(true);
        // checked to correspond to previous value in checkRollLoan
        checkRollLoan(loanId, oraclePrice);
    }

    function test_rollLoan_price_increase() public {
        (uint loanId,,) = createAndCheckLoan();
        // +5%
        uint newPrice = oraclePrice * 105 / 100;
        (uint newLoanId, ExpectedRoll memory expected) = checkRollLoan(loanId, newPrice);

        assertEq(expected.newTakerLocked, 105 ether); // scaled by price
        assertEq(expected.newProviderLocked, 210 ether); // scaled by price
        assertEq(expected.toTaker, 44 ether); // 45 (+5% * 90% LTV) - 1 (fee)

        // LTV & underlying relationship maintained (because within collar bounds)
        assertEq(underlyingAmount * newPrice * ltv / 1e18 / BIPS_100PCT, expected.newLoanAmount);

        oraclePrice = newPrice;
        checkCloseRolledLoan(newLoanId, expected.newLoanAmount);
    }

    function test_rollLoan_price_decrease() public {
        (uint loanId,,) = createAndCheckLoan();
        // -5%
        uint newPrice = oraclePrice * 95 / 100;
        (uint newLoanId, ExpectedRoll memory expected) = checkRollLoan(loanId, newPrice);

        assertEq(expected.newTakerLocked, 95 ether); // scaled by price
        assertEq(expected.newProviderLocked, 190 ether); // scaled by price
        assertEq(expected.toTaker, -46 ether); // -45 (-5% * 90% LTV) - 1 (fee)

        // LTV & underlying relationship maintained (because within collar bounds)
        assertEq(underlyingAmount * newPrice * ltv / 1e18 / BIPS_100PCT, expected.newLoanAmount);

        oraclePrice = newPrice;
        checkCloseRolledLoan(newLoanId, expected.newLoanAmount);
    }

    function test_rollLoan_price_increase_large() public {
        (uint loanId,,) = createAndCheckLoan();
        // +50%
        uint newPrice = oraclePrice * 150 / 100;
        (uint newLoanId, ExpectedRoll memory expected) = checkRollLoan(loanId, newPrice);

        assertEq(expected.newTakerLocked, 150 ether); // scaled by price
        assertEq(expected.newProviderLocked, 300 ether); // scaled by price
        assertEq(expected.toTaker, 149 ether); // 150 (300 collar settle - 150 collar open) - 1 fee

        // LTV & underlying relationship NOT maintained because outside of collar bounds
        assertTrue(expected.newLoanAmount < underlyingAmount * newPrice * ltv / 1e18 / BIPS_100PCT);

        oraclePrice = newPrice;
        checkCloseRolledLoan(newLoanId, expected.newLoanAmount);
    }

    function test_rollLoan_price_decrease_large() public {
        (uint loanId,,) = createAndCheckLoan();
        // -50%
        uint newPrice = oraclePrice * 50 / 100;
        (uint newLoanId, ExpectedRoll memory expected) = checkRollLoan(loanId, newPrice);

        assertEq(expected.newTakerLocked, 50 ether); // scaled by price
        assertEq(expected.newProviderLocked, 100 ether); // scaled by price
        assertEq(expected.toTaker, -51 ether); // -50 (0 collar settle - 50 collar open) - 1 fee

        // LTV & underlying relationship NOT maintained because outside of collar bounds
        assertTrue(expected.newLoanAmount > underlyingAmount * newPrice * ltv / 1e18 / BIPS_100PCT);

        oraclePrice = newPrice;
        checkCloseRolledLoan(newLoanId, expected.newLoanAmount);
    }
}

contract LoansRollsEscrowEffectsTest is LoansRollsEffectsTest {
    function setUp() public virtual override {
        super.setUp();
        openEscrowLoan = true;
    }

    // all rolls effect tests from LoansRollsEffectsTest are repeated for rolls with escrow

    function test_rollLoan_escrowRefund() public {
        (uint loanId,,) = createAndCheckLoan();
        uint prevFee = escrowFee;
        (, ExpectedRoll memory expected) = checkRollLoan(loanId, oraclePrice);
        // max refund
        uint maxRefund = escrowNFT.MAX_FEE_REFUND_BIPS() * prevFee / BIPS_100PCT;
        assertEq(expected.escrowFeeRefund, maxRefund);

        (loanId,,) = createAndCheckLoan();
        skip(duration / 2);
        prevFee = escrowFee;
        (, expected) = checkRollLoan(loanId, oraclePrice);
        // half refund for half duration
        assertEq(expected.escrowFeeRefund, prevFee / 2);

        (loanId,,) = createAndCheckLoan();
        skip(duration);
        prevFee = escrowFee;
        (, expected) = checkRollLoan(loanId, oraclePrice);
        // no refund for full duraion
        assertEq(expected.escrowFeeRefund, 0);
    }
}
