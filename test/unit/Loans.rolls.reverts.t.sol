// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

import "forge-std/Test.sol";
import { IERC721Errors } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { IERC20Errors } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { TestERC20 } from "../utils/TestERC20.sol";

import { LoansNFT, IEscrowSupplierNFT } from "../../src/LoansNFT.sol";
import { Rolls } from "../../src/Rolls.sol";

import { LoansRollTestBase } from "./Loans.rolls.effects.t.sol";

contract LoansRollsRevertsTest is LoansRollTestBase {
    int internal constant MIN_INT = type(int).min;

    function test_revert_rollLoan_contract_auth_checks() public {
        (uint loanId,,) = createAndCheckLoan();
        uint rollId = createRollOffer(loanId);

        // unsupported loans
        vm.startPrank(owner);
        configHub.setCanOpen(address(loans), false);
        vm.startPrank(user1);
        vm.expectRevert("unsupported loans contract");
        loans.rollLoan(loanId, rollId, MIN_INT, 0);

        // Rolls contract unset
        vm.startPrank(owner);
        configHub.setCanOpen(address(loans), true);
        loans.setContracts(Rolls(address(0)), providerNFT, escrowNFT);
        vm.startPrank(user1);
        vm.expectRevert("rolls contract unset");
        loans.rollLoan(loanId, rollId, MIN_INT, 0);
    }

    function test_revert_rollLoan_basic_checks() public {
        (uint loanId,,) = createAndCheckLoan();
        uint rollId = createRollOffer(loanId);

        // Non-existent roll offer
        vm.startPrank(user1);
        vm.expectRevert("invalid rollId");
        loans.rollLoan(loanId, rollId + 1, MIN_INT, 0);

        // cancelled roll offer
        vm.startPrank(provider);
        rolls.cancelOffer(rollId);
        vm.startPrank(user1);
        vm.expectRevert("invalid rollId");
        loans.rollLoan(loanId, rollId, MIN_INT, 0);

        rollId = createRollOffer(loanId);

        // Caller is not the loans NFT owner
        vm.startPrank(address(0xdead));
        vm.expectRevert("not NFT owner");
        loans.rollLoan(loanId, rollId, MIN_INT, 0);

        // Taker position already settled
        vm.startPrank(user1);
        skip(duration + 1);
        vm.expectRevert("loan expired");
        loans.rollLoan(loanId, rollId, MIN_INT, 0);

        // Roll already executed
        (uint newLoanId,,) = createAndCheckLoan();
        uint newRollId = createRollOffer(newLoanId);
        vm.startPrank(user1);
        cashAsset.approve(address(loans), type(uint).max);
        collateralAsset.approve(address(loans), escrowFee);
        loans.rollLoan(newLoanId, newRollId, MIN_INT, escrowOfferId);
        // token is burned
        expectRevertERC721Nonexistent(newLoanId);
        loans.rollLoan(newLoanId, newRollId, MIN_INT, 0);
    }

    function test_revert_rollLoan_IdTaken() public {
        (uint loanId,,) = createAndCheckLoan();

        // set roll fee to zero to avoid having to mock transfers
        rollFee = 0;
        uint rollId = createRollOffer(loanId);

        vm.startPrank(user1);
        collateralAsset.approve(address(loans), escrowFee);
        vm.mockCall(
            address(rolls),
            abi.encodeWithSelector(rolls.executeRoll.selector, rollId, 0),
            abi.encode(loanId, 0, 0, 0) // returns old taker ID
        );
        vm.expectRevert("loanId taken");
        loans.rollLoan(loanId, rollId, 0, escrowOfferId);
    }

    function test_revert_rollLoan_slippage() public {
        (uint loanId,,) = createAndCheckLoan();
        uint rollId = createRollOffer(loanId);

        vm.startPrank(user1);
        cashAsset.approve(address(loans), type(uint).max);

        // Calculate expected loan change
        (int loanChangePreview,,) = rolls.calculateTransferAmounts(rollId, twapPrice);

        // this reverts in Rolls
        vm.expectRevert("taker transfer slippage");
        loans.rollLoan(loanId, rollId, loanChangePreview + 1, 0); // expect more

        // this should revert in loan
        vm.mockCall(
            address(rolls),
            abi.encodeWithSelector(rolls.executeRoll.selector, rollId, loanChangePreview + 1),
            abi.encode(0, 0, loanChangePreview, 0) // return less than previewed
        );
        vm.expectRevert("roll transfer < minToUser");
        loans.rollLoan(loanId, rollId, loanChangePreview + 1, 0); // expect more

        // Mock the executeRoll function to return unexpected value (-1)
        vm.mockCall(
            address(rolls),
            abi.encodeWithSelector(rolls.executeRoll.selector, rollId, loanChangePreview),
            abi.encode(0, 0, loanChangePreview - 1, 0)
        );
        vm.expectRevert("unexpected transfer amount");
        loans.rollLoan(loanId, rollId, loanChangePreview, 0);

        // Mock the executeRoll function to return unexpected value (+1)
        vm.mockCall(
            address(rolls),
            abi.encodeWithSelector(rolls.executeRoll.selector, rollId, loanChangePreview),
            abi.encode(0, 0, loanChangePreview + 1, 0)
        );
        vm.expectRevert("unexpected transfer amount");
        loans.rollLoan(loanId, rollId, loanChangePreview, 0);
    }

    function test_revert_rollLoan_taker_approvals() public {
        (uint loanId,,) = createAndCheckLoan();
        uint rollId = createRollOffer(loanId);

        vm.startPrank(user1);

        // taker NFT approval
        cashAsset.approve(address(loans), type(uint).max);
        // cash approval (when taker needs to pay)
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
        loans.rollLoan(loanId, rollId, MIN_INT, 0);
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
        vm.expectRevert("not NFT owner");
        loans.rollLoan(loanId, rollId, MIN_INT, 0);
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
        vm.expectRevert("contract balance changed");
        loans.rollLoan(loanId, rollId, MIN_INT, 0);
    }

    function test_revert_rollLoan_repayment_larger_than_loan() public {
        (uint loanId,, uint loanAmount) = createAndCheckLoan();
        uint rollId = createRollOffer(loanId);

        vm.startPrank(user1);
        cashAsset.approve(address(loans), type(uint).max);

        // Mock the calculateTransferAmounts function to return a large negative value.
        // It's negative because paying to rolls is pulling from the user - repaying the loan.
        int largeRepayment = -int(loanAmount + 1);
        vm.mockCall(
            address(rolls),
            abi.encodeWithSelector(rolls.calculateTransferAmounts.selector, rollId, twapPrice),
            abi.encode(largeRepayment, 0, 0)
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
        vm.expectRevert("repayment larger than loan");
        loans.rollLoan(loanId, rollId, MIN_INT, 0);
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
        collateralAsset.approve(address(loans), escrowFee - 1);
        vm.expectRevert("insufficient allowance for escrow fee");
        loans.rollLoan(loanId, rollId, MIN_INT, escrowOfferId);

        // unsupported escrow
        vm.startPrank(owner);
        configHub.setCanOpen(address(escrowNFT), false);
        vm.startPrank(user1);
        vm.expectRevert("unsupported escrow contract");
        loans.rollLoan(loanId, rollId, MIN_INT, escrowOfferId);
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
        prepareSwapToCashAtTWAPPrice();
        cashAsset.approve(address(loans), type(uint).max);
        collateralAsset.approve(address(loans), collateralAmount + escrowFee);
        vm.expectRevert("duration mismatch");
        loans.rollLoan(loanId, rollId, MIN_INT, escrowOfferId);

        // loanId mismatch escrow
        IEscrowSupplierNFT.Escrow memory badEscrow;
        badEscrow.expiration = block.timestamp + duration + 1;
        vm.mockCall(
            address(escrowNFT),
            abi.encodeCall(escrowNFT.getEscrow, (takerNFT.nextPositionId())),
            abi.encode(badEscrow)
        );
        vm.expectRevert("unexpected loanId");
        loans.rollLoan(loanId, rollId, MIN_INT, escrowOfferId);
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
