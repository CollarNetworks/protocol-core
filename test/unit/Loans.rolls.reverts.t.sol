// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

import "forge-std/Test.sol";
import { IERC721Errors } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { IERC20Errors } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { TestERC20 } from "../utils/TestERC20.sol";

import { LoansNFT } from "../../src/LoansNFT.sol";
import { Rolls } from "../../src/Rolls.sol";

import { LoansRollTestBase } from "./Loans.rolls.effects.t.sol";

contract LoansRollsRevertsTest is LoansRollTestBase {
    function test_revert_rollLoan_rolls_contract_checks() public {
        (uint takerId,,) = createAndCheckLoan();
        uint rollId = createRollOffer(takerId);

        // Rolls contract unset
        vm.startPrank(owner);
        loans.setRollsContract(Rolls(address(0)));
        vm.startPrank(user1);
        vm.expectRevert("rolls contract unset");
        loans.rollLoan(takerId, rolls, rollId, type(int).min);

        // Rolls contract mismatch
        Rolls newRolls = new Rolls(owner, takerNFT);
        vm.startPrank(owner);
        loans.setRollsContract(newRolls);
        vm.startPrank(user1);
        vm.expectRevert("rolls contract mismatch");
        loans.rollLoan(takerId, rolls, rollId, type(int).min);
    }

    function test_revert_rollLoan_basic_checks() public {
        (uint takerId,,) = createAndCheckLoan();
        uint rollId = createRollOffer(takerId);

        // Non-existent roll offer
        vm.startPrank(user1);
        vm.expectRevert("invalid rollId");
        loans.rollLoan(takerId, rolls, rollId + 1, type(int).min);

        // cancelled roll offer
        vm.startPrank(provider);
        rolls.cancelOffer(rollId);
        vm.startPrank(user1);
        vm.expectRevert("invalid rollId");
        loans.rollLoan(takerId, rolls, rollId, type(int).min);

        rollId = createRollOffer(takerId);

        // Caller is not the taker NFT owner
        vm.startPrank(address(0xdead));
        vm.expectRevert("not taker NFT owner");
        loans.rollLoan(takerId, rolls, rollId, type(int).min);

        // Taker position already settled
        vm.startPrank(user1);
        skip(duration);
        takerNFT.settlePairedPosition(takerId);
        cashAsset.approve(address(loans), type(uint).max);
        takerNFT.approve(address(loans), takerId);
        vm.expectRevert("taker position settled");
        loans.rollLoan(takerId, rolls, rollId, type(int).min);

        // Roll already executed
        (uint newTakerId,,) = createAndCheckLoan();
        uint newRollId = createRollOffer(newTakerId);
        vm.startPrank(user1);
        takerNFT.approve(address(loans), newTakerId);
        cashAsset.approve(address(loans), type(uint).max);
        loans.rollLoan(newTakerId, rolls, newRollId, type(int).min);
        // token is burned
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, newTakerId));
        loans.rollLoan(newTakerId, rolls, newRollId, type(int).min);
    }

    function test_revert_rollLoan_slippage() public {
        (uint takerId,,) = createAndCheckLoan();
        uint rollId = createRollOffer(takerId);

        vm.startPrank(user1);
        takerNFT.approve(address(loans), takerId);
        cashAsset.approve(address(loans), type(uint).max);

        // Calculate expected loan change
        (int loanChangePreview,,) = rolls.calculateTransferAmounts(rollId, twapPrice);

        // this reverts in Rolls
        vm.expectRevert("taker transfer slippage");
        loans.rollLoan(takerId, rolls, rollId, loanChangePreview + 1); // expect more

        // this should revert in loan
        vm.mockCall(
            address(rolls),
            abi.encodeWithSelector(rolls.executeRoll.selector, rollId, loanChangePreview + 1),
            abi.encode(0, 0, loanChangePreview, 0) // return less than previewed
        );
        vm.expectRevert("roll transfer < minToUser");
        loans.rollLoan(takerId, rolls, rollId, loanChangePreview + 1); // expect more

        // Mock the executeRoll function to return unexpected value (-1)
        vm.mockCall(
            address(rolls),
            abi.encodeWithSelector(rolls.executeRoll.selector, rollId, loanChangePreview),
            abi.encode(0, 0, loanChangePreview - 1, 0)
        );
        vm.expectRevert("unexpected transfer amount");
        loans.rollLoan(takerId, rolls, rollId, loanChangePreview);

        // Mock the executeRoll function to return unexpected value (+1)
        vm.mockCall(
            address(rolls),
            abi.encodeWithSelector(rolls.executeRoll.selector, rollId, loanChangePreview),
            abi.encode(0, 0, loanChangePreview + 1, 0)
        );
        vm.expectRevert("unexpected transfer amount");
        loans.rollLoan(takerId, rolls, rollId, loanChangePreview);
    }

    function test_revert_rollLoan_taker_approvals() public {
        (uint takerId,,) = createAndCheckLoan();
        uint rollId = createRollOffer(takerId);

        vm.startPrank(user1);

        // taker NFT approval
        cashAsset.approve(address(loans), type(uint).max);
        vm.expectRevert(
            abi.encodeWithSelector(IERC721Errors.ERC721InsufficientApproval.selector, address(loans), takerId)
        );
        loans.rollLoan(takerId, rolls, rollId, type(int).min);

        // cash approval (when taker needs to pay)
        takerNFT.approve(address(loans), takerId);
        // Set price to ensure taker needs to pay
        uint lowPrice = twapPrice * 95 / 100;
        updatePrice(lowPrice);

        // Calculate expected loan change
        (int loanChangePreview,,) = rolls.calculateTransferAmounts(rollId, lowPrice);
        require(loanChangePreview < 0, "loanChangePreview should be negative for this test");

        cashAsset.approve(address(loans), uint(-loanChangePreview) - 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector,
                address(loans),
                uint(-loanChangePreview) - 1,
                uint(-loanChangePreview)
            )
        );
        loans.rollLoan(takerId, rolls, rollId, type(int).min);
    }

    function test_revert_rollLoan_keeper_cannot_roll() public {
        // Create a loan
        (uint takerId,,) = createAndCheckLoan();
        uint rollId = createRollOffer(takerId);
        vm.startPrank(owner);
        loans.setKeeper(keeper);

        // Allow the keeper to close the loan (but not roll)
        vm.startPrank(user1);
        loans.setKeeperAllowedBy(takerId, true);

        // Attempt to roll the loan as the keeper
        vm.startPrank(keeper);
        vm.expectRevert("not taker NFT owner");
        loans.rollLoan(takerId, rolls, rollId, type(int).min);
    }

    function test_revert_rollLoan_not_active() public {
        (uint takerId,,) = createAndCheckLoan();
        uint rollId = createRollOffer(takerId);

        // Close the loan
        skip(duration);
        vm.startPrank(user1);
        takerNFT.approve(address(loans), takerId);
        cashAsset.approve(address(loans), type(uint).max);
        updatePrice();
        prepareSwapToCollateralAtTWAPPrice();
        loans.closeLoan(takerId, defaultSwapParams(0));

        // Mock the NFT ownerOf call to return the sender instead of reverting
        vm.mockCall(
            address(takerNFT), abi.encodeWithSelector(takerNFT.ownerOf.selector, takerId), abi.encode(user1)
        );
        // Attempt to roll the closed loan
        vm.expectRevert("not active");
        loans.rollLoan(takerId, rolls, rollId, type(int).min);
    }

    function test_revert_rollLoan_contract_balance_changed() public {
        (uint takerId,,) = createAndCheckLoan();
        uint rollId = createRollOffer(takerId);

        vm.startPrank(user1);
        takerNFT.approve(address(loans), takerId);
        cashAsset.approve(address(loans), type(uint).max);

        // Set up the cash asset to perform a reentrancy attack
        DonatingAttacker attacker = new DonatingAttacker(loans, cashAsset);
        cashAsset.transfer(address(attacker), 1); // give the attacker some cash
        cashAsset.setAttacker(address(attacker));

        // Attempt to roll the loan, which should trigger the reentrancy attack
        vm.expectRevert("contract balance changed");
        loans.rollLoan(takerId, rolls, rollId, type(int).min);
    }

    function test_revert_rollLoan_repayment_larger_than_loan() public {
        (uint takerId,, uint loanAmount) = createAndCheckLoan();
        uint rollId = createRollOffer(takerId);

        vm.startPrank(user1);
        takerNFT.approve(address(loans), takerId);
        cashAsset.approve(address(loans), type(uint).max);

        // Mock the calculateTransferAmounts function to return a large negative value
        int largeRepayment = -int(loanAmount + 1);
        vm.mockCall(
            address(rolls),
            abi.encodeWithSelector(rolls.calculateTransferAmounts.selector, rollId, twapPrice),
            abi.encode(largeRepayment, 0, 0)
        );

        // Attempt to roll the loan, which should revert due to large repayment
        vm.expectRevert("repayment larger than loan");
        loans.rollLoan(takerId, rolls, rollId, type(int).min);
    }
}

contract DonatingAttacker {
    LoansNFT loans;
    TestERC20 cashAsset;
    bool attacked;

    constructor(LoansNFT _loans, TestERC20 _cashAsset) {
        loans = _loans;
        cashAsset = _cashAsset;
    }

    fallback() external {
        if (!attacked) {
            attacked = true;
            cashAsset.transfer(address(loans), 1);
        }
    }
}
