// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

import "forge-std/Test.sol";
import { IERC721Errors } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

import { LoansNFT, ILoansNFT } from "../../src/LoansNFT.sol";
import { CollarTakerNFT } from "../../src/CollarTakerNFT.sol";
import { Rolls } from "../../src/Rolls.sol";

import { LoansTestBase } from "./Loans.basic.effects.t.sol";

contract LoansRollTestBase is LoansTestBase {
    struct ExpectedRoll {
        uint newPutLocked;
        uint newCallLocked;
        int toTaker;
        int rollFee;
        uint newLoanAmount;
    }

    function calculateRollAmounts(uint rollId, uint newPrice)
        internal
        view
        returns (ExpectedRoll memory expected)
    {
        // roll transfers
        (expected.toTaker,, expected.rollFee) = rolls.calculateTransferAmounts(rollId, newPrice);

        uint takerId = rolls.getRollOffer(rollId).takerId;
        CollarTakerNFT.TakerPosition memory oldTakerPos = takerNFT.getPosition(takerId);

        // new position
        expected.newPutLocked = oldTakerPos.putLockedCash * newPrice / twapPrice;
        expected.newCallLocked =
            expected.newPutLocked * (callStrikeDeviation - BIPS_100PCT) / (BIPS_100PCT - ltv);

        // toTaker = userGain - rollFee, so userGain (loan increase) = toTaker + rollFee
        expected.newLoanAmount =
            uint(int(loans.getLoan(takerId).loanAmount) + expected.toTaker + expected.rollFee);

        return expected;
    }

    function createRollOffer(uint loanId) internal returns (uint rollId) {
        uint takerId = loanId;
        vm.startPrank(provider);
        uint providerId = takerNFT.getPosition(takerId).providerPositionId;
        providerNFT.approve(address(rolls), providerId);
        cashAsset.approve(address(rolls), type(uint).max);
        rollId = rolls.createRollOffer(
            takerId, rollFee, 0, 0, type(uint).max, -int(largeAmount), block.timestamp + duration
        );
    }

    function checkRollLoan(uint loanId, uint newPrice)
        internal
        returns (uint newTakerId, ExpectedRoll memory expected)
    {
        uint rollId = createRollOffer(loanId);

        // Calculate expected values
        expected = calculateRollAmounts(rollId, newPrice);

        // Update price
        updatePrice(newPrice);

        // Execute roll
        vm.startPrank(user1);
        cashAsset.approve(address(loans), type(uint).max);

        uint initialBalance = cashAsset.balanceOf(user1);
        uint initialLoanAmount = loans.getLoan(loanId).loanAmount;

        uint expectedLoanId = takerNFT.nextPositionId();
        vm.expectEmit(address(loans));
        emit ILoansNFT.LoanRolled(
            user1, loanId, rollId, expectedLoanId, initialLoanAmount, expected.newLoanAmount, expected.toTaker
        );
        // min change param
        int minToUser = int(expected.newLoanAmount) - int(initialLoanAmount) - rollFee;
        uint newLoanAmount;
        int toUser;
        (newTakerId, newLoanAmount, toUser) = loans.rollLoan(loanId, rollId, minToUser, 0, 0);

        // id
        assertEq(newTakerId, expectedLoanId);
        // new loanAmount
        assertEq(newLoanAmount, expected.newLoanAmount);

        // balance change matches roll output value
        assertEq(cashAsset.balanceOf(user1), uint(int(initialBalance) + expected.toTaker));
        // loan change matches balance change
        int loanChange = int(newLoanAmount) - int(initialLoanAmount);
        assertEq(expected.toTaker, toUser);
        assertEq(expected.toTaker + expected.rollFee, loanChange);

        // check loans and NFT views
        checkLoansAndNFT(loanId, newTakerId, expected, newPrice);
    }

    function checkLoansAndNFT(uint loanId, uint newLoanId, ExpectedRoll memory expected, uint newPrice)
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
        assertEq(newLoan.collateralAmount, loans.getLoan(loanId).collateralAmount);

        // new taker position
        CollarTakerNFT.TakerPosition memory newTakerPos = takerNFT.getPosition(newLoanId);
        assertEq(newTakerPos.putLockedCash, expected.newPutLocked);
        assertEq(newTakerPos.callLockedCash, expected.newCallLocked);
        assertEq(newTakerPos.initialPrice, newPrice);
    }

    function checkCloseRolledLoan(uint loanId, uint loanAmount) public returns (uint) {
        skip(duration);

        CollarTakerNFT.TakerPosition memory takerPosition = takerNFT.getPosition({ takerId: loanId });
        uint withdrawal = takerPosition.putLockedCash;
        uint swapOut = prepareSwapToCollateralAtTWAPPrice();
        closeAndCheckLoan(loanId, user1, loanAmount, withdrawal, swapOut);
        return loanId;
    }
}

contract LoansRollsHappyPathsTest is LoansRollTestBase {
    function test_rollLoan_no_change() public {
        (uint loanId,,) = createAndCheckLoan();
        CollarTakerNFT.TakerPosition memory takerPosition = takerNFT.getPosition({ takerId: loanId });
        (uint newTakerId, ExpectedRoll memory expected) = checkRollLoan(loanId, twapPrice);

        // no change in locked amounts
        assertEq(expected.newPutLocked, takerPosition.putLockedCash);
        assertEq(expected.newCallLocked, takerPosition.callLockedCash);
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
        for (uint i; i < 10; ++i) {
            (newLoanId, expected) = checkRollLoan(newLoanId, twapPrice);
        }
        // no change in locked amounts
        assertEq(expected.newPutLocked, takerPosition.putLockedCash);
        assertEq(expected.newCallLocked, takerPosition.callLockedCash);
        // only fee paid
        assertEq(expected.toTaker, -rollFee); // single fee
        // paid the rollFee 10 times
        assertEq(cashAsset.balanceOf(user1), balanceBefore - (10 * uint(rollFee)));
        assertEq(expected.newLoanAmount, loans.getLoan(loanId).loanAmount);
        assertEq(expected.newLoanAmount, loans.getLoan(newLoanId).loanAmount);

        checkCloseRolledLoan(newLoanId, expected.newLoanAmount);
    }

    function test_rollLoan_setKeeperAllowed_preserved() public {
        (uint loanId,,) = createAndCheckLoan();
        loans.setKeeperAllowed(true);
        // checked to correspond to previous value in checkRollLoan
        checkRollLoan(loanId, twapPrice);
    }

    function test_rollLoan_price_increase() public {
        (uint loanId,,) = createAndCheckLoan();
        // +5%
        uint newPrice = twapPrice * 105 / 100;
        (uint newLoanId, ExpectedRoll memory expected) = checkRollLoan(loanId, newPrice);

        assertEq(expected.newPutLocked, 105 ether); // scaled by price
        assertEq(expected.newCallLocked, 210 ether); // scaled by price
        assertEq(expected.toTaker, 44 ether); // 45 (+5% * 90% LTV) - 1 (fee)

        // LTV & collateral relationship maintained (because within collar bounds)
        assertEq(collateralAmount * newPrice * ltv / 1e18 / BIPS_100PCT, expected.newLoanAmount);

        twapPrice = newPrice;
        checkCloseRolledLoan(newLoanId, expected.newLoanAmount);
    }

    function test_rollLoan_price_decrease() public {
        (uint loanId,,) = createAndCheckLoan();
        // -5%
        uint newPrice = twapPrice * 95 / 100;
        (uint newLoanId, ExpectedRoll memory expected) = checkRollLoan(loanId, newPrice);

        assertEq(expected.newPutLocked, 95 ether); // scaled by price
        assertEq(expected.newCallLocked, 190 ether); // scaled by price
        assertEq(expected.toTaker, -46 ether); // -45 (-5% * 90% LTV) - 1 (fee)

        // LTV & collateral relationship maintained (because within collar bounds)
        assertEq(collateralAmount * newPrice * ltv / 1e18 / BIPS_100PCT, expected.newLoanAmount);

        twapPrice = newPrice;
        checkCloseRolledLoan(newLoanId, expected.newLoanAmount);
    }

    function test_rollLoan_price_increase_large() public {
        (uint loanId,,) = createAndCheckLoan();
        // +50%
        uint newPrice = twapPrice * 150 / 100;
        (uint newLoanId, ExpectedRoll memory expected) = checkRollLoan(loanId, newPrice);

        assertEq(expected.newPutLocked, 150 ether); // scaled by price
        assertEq(expected.newCallLocked, 300 ether); // scaled by price
        assertEq(expected.toTaker, 149 ether); // 150 (300 collar settle - 150 collar open) - 1 fee

        // LTV & collateral relationship NOT maintained because outside of collar bounds
        assertTrue(expected.newLoanAmount < collateralAmount * newPrice * ltv / 1e18 / BIPS_100PCT);

        twapPrice = newPrice;
        checkCloseRolledLoan(newLoanId, expected.newLoanAmount);
    }

    function test_rollLoan_price_decrease_large() public {
        (uint loanId,,) = createAndCheckLoan();
        // -50%
        uint newPrice = twapPrice * 50 / 100;
        (uint newLoanId, ExpectedRoll memory expected) = checkRollLoan(loanId, newPrice);

        assertEq(expected.newPutLocked, 50 ether); // scaled by price
        assertEq(expected.newCallLocked, 100 ether); // scaled by price
        assertEq(expected.toTaker, -51 ether); // -50 (0 collar settle - 50 collar open) - 1 fee

        // LTV & collateral relationship NOT maintained because outside of collar bounds
        assertTrue(expected.newLoanAmount > collateralAmount * newPrice * ltv / 1e18 / BIPS_100PCT);

        twapPrice = newPrice;
        checkCloseRolledLoan(newLoanId, expected.newLoanAmount);
    }
}
