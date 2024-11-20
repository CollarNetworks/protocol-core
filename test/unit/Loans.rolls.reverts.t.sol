// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

import "forge-std/Test.sol";
import { IERC721Errors } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { TestERC20 } from "../utils/TestERC20.sol";

import { LoansNFT, IEscrowSupplierNFT } from "../../src/LoansNFT.sol";
import { Rolls, IRolls, ICollarTakerNFT } from "../../src/Rolls.sol";

import { LoansRollTestBase } from "./Loans.rolls.effects.t.sol";

contract LoansRollsRevertsTest is LoansRollTestBase {
    int internal constant MIN_INT = type(int).min;

    function test_revert_rollLoan_contract_auth_checks() public {
        (uint loanId,,) = createAndCheckLoan();
        uint rollId = createRollOffer(loanId);

        // unsupported loans
        setCanOpen(address(loans), false);
        vm.startPrank(user1);
        vm.expectRevert("loans: unsupported loans");
        loans.rollLoan(loanId, rollOffer(rollId), MIN_INT, 0, 0);

        setCanOpen(address(loans), true);
        setCanOpen(address(rolls), false);
        vm.startPrank(user1);
        vm.expectRevert("loans: unsupported rolls");
        loans.rollLoan(loanId, rollOffer(rollId), MIN_INT, 0, 0);
    }

    function test_revert_rollLoan_basic_checks() public {
        (uint loanId,,) = createAndCheckLoan();
        uint rollId = createRollOffer(loanId);

        // Non-existent roll offer
        vm.startPrank(user1);
        vm.expectRevert("rolls: invalid rollId");
        loans.rollLoan(loanId, rollOffer(rollId + 1), MIN_INT, 0, 0);

        // cancelled roll offer
        vm.startPrank(provider);
        rolls.cancelOffer(rollId);
        vm.startPrank(user1);
        cashAsset.approve(address(loans), type(uint).max);
        vm.expectRevert("rolls: invalid offer");
        loans.rollLoan(loanId, rollOffer(rollId), MIN_INT, 0, 0);

        rollId = createRollOffer(loanId);

        // Caller is not the loans NFT owner
        vm.startPrank(address(0xdead));
        vm.expectRevert("loans: not NFT owner");
        loans.rollLoan(loanId, rollOffer(rollId), MIN_INT, 0, 0);

        // Taker position already settled
        vm.startPrank(user1);
        skip(duration + 1);
        vm.expectRevert("loans: loan expired");
        loans.rollLoan(loanId, rollOffer(rollId), MIN_INT, 0, 0);

        // Roll already executed
        (uint newLoanId,,) = createAndCheckLoan();
        uint newRollId = createRollOffer(newLoanId);
        vm.startPrank(user1);
        underlying.approve(address(loans), escrowFee);
        loans.rollLoan(newLoanId, rollOffer(newRollId), MIN_INT, escrowOfferId, escrowFee);
        // token is burned
        expectRevertERC721Nonexistent(newLoanId);
        loans.rollLoan(newLoanId, rollOffer(newRollId), MIN_INT, 0, 0);
    }

    function test_revert_rollLoan_IdTaken() public {
        (uint loanId,,) = createAndCheckLoan();

        // set roll fee to zero to avoid having to mock transfers
        rollFee = 0;
        uint rollId = createRollOffer(loanId);

        vm.startPrank(user1);
        underlying.approve(address(loans), escrowFee);
        vm.mockCall(
            address(rolls),
            abi.encodeWithSelector(rolls.executeRoll.selector, rollId, 0),
            abi.encode(loanId, 0, 0, 0) // returns old taker ID
        );
        vm.expectRevert("loans: loanId taken");
        loans.rollLoan(loanId, rollOffer(rollId), 0, escrowOfferId, 0);
    }

    function test_revert_rollLoan_slippage() public {
        (uint loanId,,) = createAndCheckLoan();
        uint rollId = createRollOffer(loanId);

        vm.startPrank(user1);
        cashAsset.approve(address(loans), type(uint).max);

        // Calculate expected loan change
        int loanChangePreview = rolls.previewRoll(rollId, oraclePrice).toTaker;

        // this reverts in Rolls
        vm.expectRevert("rolls: taker transfer slippage");
        loans.rollLoan(loanId, rollOffer(rollId), loanChangePreview + 1, 0, 0); // expect more

        // this should revert in loan
        vm.mockCall(
            address(rolls),
            abi.encodeWithSelector(rolls.executeRoll.selector, rollId, loanChangePreview + 1),
            abi.encode(0, 0, loanChangePreview, 0) // return less than previewed
        );
        vm.expectRevert("loans: roll transfer < minToUser");
        loans.rollLoan(loanId, rollOffer(rollId), loanChangePreview + 1, 0, 0); // expect more

        // Mock the executeRoll function to return unexpected value (-1)
        vm.mockCall(
            address(rolls),
            abi.encodeWithSelector(rolls.executeRoll.selector, rollId, loanChangePreview),
            abi.encode(0, 0, loanChangePreview - 1, 0)
        );
        vm.expectRevert("loans: unexpected transfer amount");
        loans.rollLoan(loanId, rollOffer(rollId), loanChangePreview, 0, 0);

        // Mock the executeRoll function to return unexpected value (+1)
        vm.mockCall(
            address(rolls),
            abi.encodeWithSelector(rolls.executeRoll.selector, rollId, loanChangePreview),
            abi.encode(0, 0, loanChangePreview + 1, 0)
        );
        vm.expectRevert("loans: unexpected transfer amount");
        loans.rollLoan(loanId, rollOffer(rollId), loanChangePreview, 0, 0);
    }

    function test_revert_rollLoan_taker_approvals() public {
        (uint loanId,,) = createAndCheckLoan();
        uint rollId = createRollOffer(loanId);

        vm.startPrank(user1);

        // taker NFT approval
        cashAsset.approve(address(loans), type(uint).max);
        // cash approval (when taker needs to pay)
        // Set price to ensure taker needs to pay
        uint lowPrice = oraclePrice * 95 / 100;
        updatePrice(lowPrice);

        // Calculate expected loan change
        int loanChangePreview = rolls.previewRoll(rollId, lowPrice).toTaker;

        require(loanChangePreview < 0, "loanChangePreview should be negative for this test");

        cashAsset.approve(address(loans), uint(-loanChangePreview) - 1);
        expectRevertERC20Allowance(address(loans), uint(-loanChangePreview) - 1, uint(-loanChangePreview));
        loans.rollLoan(loanId, rollOffer(rollId), MIN_INT, 0, 0);
    }

    function test_revert_rollLoan_keeper_cannot_roll() public {
        // Create a loan
        (uint loanId,,) = createAndCheckLoan();
        uint rollId = createRollOffer(loanId);
        vm.startPrank(owner);
        loans.setKeeper(keeper);

        // Allow the keeper to close the loan (but not roll)
        vm.startPrank(user1);
        loans.setKeeperApproved(true);

        // Attempt to roll the loan as the keeper
        vm.startPrank(keeper);
        vm.expectRevert("loans: not NFT owner");
        loans.rollLoan(loanId, rollOffer(rollId), MIN_INT, 0, 0);
    }

    function test_revert_rollLoan_contract_balance_changed() public {
        (uint loanId,,) = createAndCheckLoan();
        uint rollId = createRollOffer(loanId);

        vm.startPrank(user1);
        cashAsset.approve(address(loans), type(uint).max);

        // Set up the cash asset to perform a reentrancy attack
        DonatingAttacker attacker = new DonatingAttacker(loans, cashAsset);
        cashAsset.transfer(address(attacker), 1); // give the attacker some cash
        cashAsset.setAttacker(address(attacker));

        // Attempt to roll the loan, which should trigger the reentrancy attack
        vm.expectRevert("loans: contract balance changed");
        loans.rollLoan(loanId, rollOffer(rollId), MIN_INT, 0, 0);
    }

    function test_revert_rollLoan_repayment_larger_than_loan() public {
        (uint loanId,, uint loanAmount) = createAndCheckLoan();
        uint rollId = createRollOffer(loanId);

        vm.startPrank(user1);
        cashAsset.approve(address(loans), type(uint).max);

        // Mock the calculateTransferAmounts function to return a large negative value.
        // It's negative because paying to rolls is pulling from the user - repaying the loan.
        ICollarTakerNFT.TakerPosition memory emptyTakerPos;
        int largeRepayment = -int(loanAmount + 1);
        vm.mockCall(
            address(rolls),
            abi.encodeWithSelector(rolls.previewRoll.selector, rollId, oraclePrice),
            abi.encode(IRolls.PreviewResults(largeRepayment, 0, 0, emptyTakerPos, 0, 0, 0))
        );
        vm.mockCall(
            address(rolls),
            abi.encodeWithSelector(rolls.executeRoll.selector, rollId, MIN_INT),
            abi.encode(loanId + 1, 0, largeRepayment, 0)
        );
        vm.mockCall(
            address(cashAsset),
            abi.encodeWithSelector(
                cashAsset.transferFrom.selector, user1, address(loans), uint(-largeRepayment)
            ),
            abi.encode(true)
        );

        // Attempt to roll the loan, which should revert due to large repayment
        vm.expectRevert("loans: repayment larger than loan");
        loans.rollLoan(loanId, rollOffer(rollId), MIN_INT, 0, 0);
    }
}

contract LoansRollsEscrowRevertsTest is LoansRollsRevertsTest {
    function setUp() public virtual override {
        super.setUp();
        openEscrowLoan = true;
    }

    // all rolls reverts tests from LoansRollsRevertsTest are repeated for rolls with escrow

    // common reverts with regular loans are tested in test_revert_rollLoan_basic_checks
    // this tests additional reverting branches for escrow
    function test_revert_rollLoan_escrowLoans() public {
        (uint loanId,,) = createAndCheckLoan();
        uint rollId = createRollOffer(loanId);

        // new escrow offer
        maybeCreateEscrowOffer();

        // not enough approval for fee
        vm.startPrank(user1);
        cashAsset.approve(address(loans), escrowFee - 1);
        cashAsset.approve(address(loans), type(uint).max);
        underlying.approve(address(loans), escrowFee - 1);
        expectRevertERC20Allowance(address(loans), escrowFee - 1, escrowFee);
        loans.rollLoan(loanId, rollOffer(rollId), MIN_INT, escrowOfferId, escrowFee);

        // unsupported escrow
        setCanOpenSingle(address(escrowNFT), false);
        vm.startPrank(user1);
        vm.expectRevert("loans: unsupported escrow");
        loans.rollLoan(loanId, rollOffer(rollId), MIN_INT, escrowOfferId, escrowFee);
    }

    function test_revert_rollLoan_escrowValidations() public {
        (uint loanId,,) = createAndCheckLoan();
        uint rollId = createRollOffer(loanId);

        vm.startPrank(owner);
        configHub.setCollarDurationRange(duration, duration + 1);
        // different durations between escrow and collar
        duration += 1;

        maybeCreateEscrowOffer();

        vm.startPrank(user1);
        prepareSwapToCashAtOraclePrice();
        cashAsset.approve(address(loans), type(uint).max);
        underlying.approve(address(loans), underlyingAmount + escrowFee);
        vm.expectRevert("loans: duration mismatch");
        loans.rollLoan(loanId, rollOffer(rollId), MIN_INT, escrowOfferId, escrowFee);

        // loanId mismatch escrow
        IEscrowSupplierNFT.Escrow memory badEscrow;
        badEscrow.expiration = block.timestamp + duration + 1;
        vm.mockCall(
            address(escrowNFT),
            abi.encodeCall(escrowNFT.getEscrow, (escrowNFT.nextEscrowId())),
            abi.encode(badEscrow)
        );
        vm.expectRevert("loans: unexpected loanId");
        loans.rollLoan(loanId, rollOffer(rollId), MIN_INT, escrowOfferId, escrowFee);
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
