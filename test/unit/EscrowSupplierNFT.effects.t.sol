// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

import "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Strings } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

import { TestERC20 } from "../utils/TestERC20.sol";
import { BaseAssetPairTestSetup } from "./BaseAssetPairTestSetup.sol";

import { EscrowSupplierNFT, IEscrowSupplierNFT } from "../../src/EscrowSupplierNFT.sol";

contract BaseEscrowSupplierNFTTest is BaseAssetPairTestSetup {
    EscrowSupplierNFT escrowNFT;
    TestERC20 asset;

    address loans = makeAddr("loans");
    address supplier1 = makeAddr("supplier");
    address supplier2 = makeAddr("supplier2");

    uint interestAPR = 500; // 5%
    uint maxGracePeriod = 7 days;
    uint lateFeeAPR = 10_000; // 100%
    uint minEscrow = 0;

    function setUp() public override {
        super.setUp();
        asset = underlying;
        escrowNFT = new EscrowSupplierNFT(owner, configHub, asset, "ES Test", "ES Test");

        setCanOpenSingle(address(escrowNFT), true);
        setCanOpen(loans, true);
        vm.startPrank(owner);
        escrowNFT.setLoansCanOpen(loans, true);
        vm.stopPrank();

        asset.mint(loans, largeAmount * 10);
        asset.mint(supplier1, largeAmount * 10);
        asset.mint(supplier2, largeAmount * 10);
        // mint dust (as in mintDustToContracts)
        asset.mint(address(escrowNFT), 1);
    }

    function createAndCheckOffer(address supplier, uint amount)
        public
        returns (uint offerId, EscrowSupplierNFT.Offer memory offer)
    {
        startHoax(supplier);
        asset.approve(address(escrowNFT), amount);
        uint balance = asset.balanceOf(supplier);
        uint expectedId = escrowNFT.nextOfferId();

        vm.expectEmit(address(escrowNFT));
        emit IEscrowSupplierNFT.OfferCreated(
            supplier, interestAPR, duration, maxGracePeriod, lateFeeAPR, amount, expectedId, minEscrow
        );
        offerId = escrowNFT.createOffer(amount, duration, interestAPR, maxGracePeriod, lateFeeAPR, minEscrow);

        // offer ID
        assertEq(offerId, expectedId);
        assertEq(escrowNFT.nextOfferId(), expectedId + 1);
        // offer
        offer = escrowNFT.getOffer(offerId);
        assertEq(offer.supplier, supplier);
        assertEq(offer.available, amount);
        assertEq(offer.duration, duration);
        assertEq(offer.interestAPR, interestAPR);
        assertEq(offer.maxGracePeriod, maxGracePeriod);
        assertEq(offer.lateFeeAPR, lateFeeAPR);
        // balance
        assertEq(asset.balanceOf(supplier), balance - amount);
        // fee view
        uint expectedMinFee = divUp(amount * interestAPR * duration, BIPS_100PCT * 365 days);
        uint actualMinFee = escrowNFT.interestFee(offerId, amount);
        assertEq(actualMinFee, expectedMinFee);
    }

    function checkUpdateOfferAmount(int delta) internal {
        (uint offerId,) = createAndCheckOffer(supplier1, largeAmount);

        asset.approve(address(escrowNFT), largeAmount);
        uint newAmount = delta > 0 ? largeAmount + uint(delta) : largeAmount - uint(-delta);
        uint balance = asset.balanceOf(address(escrowNFT));

        vm.expectEmit(address(escrowNFT));
        emit IEscrowSupplierNFT.OfferUpdated(offerId, supplier1, largeAmount, newAmount);
        escrowNFT.updateOfferAmount(offerId, newAmount);

        // next offer id not impacted
        assertEq(escrowNFT.nextOfferId(), offerId + 1);
        // offer
        EscrowSupplierNFT.Offer memory offer = escrowNFT.getOffer(offerId);
        assertEq(offer.supplier, supplier1);
        assertEq(offer.available, newAmount);
        assertEq(offer.duration, duration);
        assertEq(offer.interestAPR, interestAPR);
        assertEq(offer.maxGracePeriod, maxGracePeriod);
        assertEq(offer.lateFeeAPR, lateFeeAPR);
        // balance
        assertEq(asset.balanceOf(address(escrowNFT)), balance + newAmount - largeAmount);
    }

    function createAndCheckEscrow(address supplier, uint offerAmount, uint escrowAmount, uint fee)
        public
        returns (uint escrowId, EscrowSupplierNFT.Escrow memory escrow)
    {
        (uint offerId,) = createAndCheckOffer(supplier, offerAmount);
        return createAndCheckEscrowFromOffer(offerId, escrowAmount, fee);
    }

    function createAndCheckEscrowFromOffer(uint offerId, uint escrowAmount, uint fee)
        public
        returns (uint escrowId, EscrowSupplierNFT.Escrow memory escrow)
    {
        address supplier = escrowNFT.getOffer(offerId).supplier;
        uint offerAmount = escrowNFT.getOffer(offerId).available;

        uint balance = asset.balanceOf(address(escrowNFT));
        uint expectedId = escrowNFT.nextEscrowId();

        uint loanId = 1000; // arbitrary

        startHoax(loans);
        asset.approve(address(escrowNFT), escrowAmount + fee);

        vm.expectEmit(address(escrowNFT));
        emit IEscrowSupplierNFT.EscrowCreated(
            expectedId, escrowAmount, duration, fee, maxGracePeriod, offerId
        );
        vm.expectEmit(address(escrowNFT));
        emit IEscrowSupplierNFT.OfferUpdated(offerId, supplier, offerAmount, offerAmount - escrowAmount);
        vm.expectEmit(address(asset));
        // check the needed transfer events order and amounts
        emit IERC20.Transfer(loans, address(escrowNFT), escrowAmount + fee);
        vm.expectEmit(address(asset));
        emit IERC20.Transfer(address(escrowNFT), loans, escrowAmount);
        escrowId = escrowNFT.startEscrow(offerId, escrowAmount, fee, loanId);
        escrow = escrowNFT.getEscrow(escrowId);

        // Check escrow details
        assertEq(escrowId, expectedId);
        assertEq(escrow.offerId, offerId);
        assertEq(escrow.loans, loans);
        assertEq(escrow.loanId, loanId);
        assertEq(escrow.escrowed, escrowAmount);
        assertEq(escrow.maxGracePeriod, maxGracePeriod);
        assertEq(escrow.lateFeeAPR, lateFeeAPR);
        assertEq(escrow.duration, duration);
        assertEq(escrow.expiration, block.timestamp + duration);
        assertEq(escrow.interestHeld, fee);
        assertFalse(escrow.released);
        assertEq(escrow.withdrawable, 0);
        // check escrow view
        assertEq(abi.encode(escrowNFT.getEscrow(escrowId)), abi.encode(escrow));

        // Check updated offer
        EscrowSupplierNFT.Offer memory updatedOffer = escrowNFT.getOffer(offerId);
        assertEq(updatedOffer.available, offerAmount - escrowAmount);

        // Check NFT ownership
        assertEq(escrowNFT.ownerOf(escrowId), supplier);

        // balance change is only fee
        assertEq(asset.balanceOf(address(escrowNFT)), balance + fee);
    }

    function checkEndEscrow(uint escrowId, uint repaid, ExpectedRelease memory expected) internal {
        startHoax(loans);
        asset.approve(address(escrowNFT), repaid);

        EscrowSupplierNFT.Escrow memory escrow = escrowNFT.getEscrow(escrowId);

        uint balanceEscrow = asset.balanceOf(address(escrowNFT));
        uint balanceLoans = asset.balanceOf(loans);

        vm.expectEmit(address(escrowNFT));
        emit IEscrowSupplierNFT.EscrowReleased(escrowId, repaid, expected.withdrawable, expected.toLoans);
        // check the needed transfer events order and amounts
        emit IERC20.Transfer(loans, address(escrowNFT), repaid);
        vm.expectEmit(address(asset));
        emit IERC20.Transfer(address(escrowNFT), loans, expected.toLoans);
        uint toLoansReturned = escrowNFT.endEscrow(escrowId, repaid);

        assertEq(toLoansReturned, expected.toLoans);

        // Check escrow state
        escrow = escrowNFT.getEscrow(escrowId);
        assertTrue(escrow.released);
        assertEq(escrow.withdrawable, expected.withdrawable);

        // balance changes
        assertEq(asset.balanceOf(address(escrowNFT)), balanceEscrow + repaid - toLoansReturned);
        assertEq(asset.balanceOf(loans), balanceLoans + toLoansReturned - repaid);
    }

    function checkWithdrawReleased(uint escrowId, uint expectedWithdrawal) internal {
        startHoax(supplier1);
        uint balanceBefore = asset.balanceOf(supplier1);

        vm.expectEmit(address(escrowNFT));
        emit IEscrowSupplierNFT.WithdrawalFromReleased(escrowId, supplier1, expectedWithdrawal);
        escrowNFT.withdrawReleased(escrowId);

        // Check balance
        assertEq(asset.balanceOf(supplier1), balanceBefore + expectedWithdrawal);

        // Check state
        assertEq(escrowNFT.getEscrow(escrowId).withdrawable, 0);

        // Check NFT burned
        expectRevertERC721Nonexistent(escrowId);
        escrowNFT.ownerOf(escrowId);
    }

    function checkLastResortSeizeEscrow(uint delay) public {
        uint escrowAmount = largeAmount / 2;
        uint fee = 1 ether;
        (uint escrowId,) = createAndCheckEscrow(supplier1, largeAmount, escrowAmount, fee);

        // Skip past expiration and grace period
        skip(duration + maxGracePeriod + 1 + delay);

        startHoax(supplier1);
        uint balanceBefore = asset.balanceOf(supplier1);

        vm.expectEmit(address(escrowNFT));
        emit IEscrowSupplierNFT.EscrowSeizedLastResort(escrowId, supplier1, escrowAmount + fee);
        escrowNFT.lastResortSeizeEscrow(escrowId);

        // Check balance
        assertEq(asset.balanceOf(supplier1), balanceBefore + escrowAmount + fee);

        // Check escrow state
        EscrowSupplierNFT.Escrow memory escrow = escrowNFT.getEscrow(escrowId);
        assertTrue(escrow.released);
        assertEq(escrow.withdrawable, 0);

        // Check NFT burned
        expectRevertERC721Nonexistent(escrowId);
        escrowNFT.ownerOf(escrowId);
    }

    struct ExpectedRelease {
        uint withdrawable;
        uint toLoans;
        uint refund;
    }

    function check_preview_end_withdraw(
        uint escrowAmount,
        uint repaid,
        uint fee,
        uint toSkip,
        ExpectedRelease memory expected
    ) public {
        (uint escrowId,) = createAndCheckEscrow(supplier1, largeAmount, escrowAmount, fee);
        skip(toSkip);
        // check preview
        (uint withdrawable, uint toLoans, uint refund) = escrowNFT.previewRelease(escrowId, repaid);
        assertEq(withdrawable, expected.withdrawable);
        assertEq(toLoans, expected.toLoans);
        assertEq(refund, expected.refund);

        // check end escrow
        checkEndEscrow(escrowId, repaid, expected);
        // check withdraw
        checkWithdrawReleased(escrowId, expected.withdrawable);
    }

    function expectedLateFees(EscrowSupplierNFT.Escrow memory escrow) internal view returns (uint fee) {
        uint overdue = block.timestamp - escrow.expiration;
        fee = divUp(escrow.escrowed * lateFeeAPR * overdue, BIPS_100PCT * 365 days);
    }

    function divUp(uint x, uint y) internal pure returns (uint) {
        return (x == 0) ? 0 : ((x - 1) / y) + 1; // divUp(x,y) = (x-1 / y) + 1
    }
}

contract EscrowSupplierNFT_BasicEffectsTest is BaseEscrowSupplierNFTTest {
    function test_constructor() public {
        EscrowSupplierNFT newEscrowSupplierNFT =
            new EscrowSupplierNFT(owner, configHub, asset, "NewEscrowSupplierNFT", "NESNFT");

        assertEq(address(newEscrowSupplierNFT.owner()), owner);
        assertEq(address(newEscrowSupplierNFT.configHub()), address(configHub));
        assertEq(address(newEscrowSupplierNFT.asset()), address(asset));
        assertEq(newEscrowSupplierNFT.MAX_INTEREST_APR_BIPS(), BIPS_100PCT);
        assertEq(newEscrowSupplierNFT.MIN_GRACE_PERIOD(), 1 days);
        assertEq(newEscrowSupplierNFT.MAX_GRACE_PERIOD(), 30 days);
        assertEq(newEscrowSupplierNFT.MAX_LATE_FEE_APR_BIPS(), 12 * BIPS_100PCT);
        assertEq(newEscrowSupplierNFT.MAX_FEE_REFUND_BIPS(), 9500);
        assertEq(newEscrowSupplierNFT.VERSION(), "0.2.0");
        assertEq(newEscrowSupplierNFT.name(), "NewEscrowSupplierNFT");
        assertEq(newEscrowSupplierNFT.symbol(), "NESNFT");
    }

    function test_createOffer() public {
        createAndCheckOffer(supplier1, largeAmount);

        // another one (multiple offers)
        createAndCheckOffer(supplier1, largeAmount);

        // max values ok
        interestAPR = escrowNFT.MAX_INTEREST_APR_BIPS();
        maxGracePeriod = escrowNFT.MAX_GRACE_PERIOD();
        lateFeeAPR = escrowNFT.MAX_LATE_FEE_APR_BIPS();
        createAndCheckOffer(supplier1, largeAmount);
    }

    function test_updateOfferAmount() public {
        checkUpdateOfferAmount(int(largeAmount));

        checkUpdateOfferAmount(int(largeAmount) / 2);

        checkUpdateOfferAmount(-int(largeAmount));

        checkUpdateOfferAmount(-int(largeAmount) / 2);

        checkUpdateOfferAmount(0);
    }

    function test_startEscrow_simple() public {
        uint fee = 1 ether; // arbitrary
        createAndCheckEscrow(supplier1, largeAmount, largeAmount / 2, fee);
    }

    function test_tokenURI() public {
        (uint escrowId,) = createAndCheckEscrow(supplier1, largeAmount, largeAmount / 2, 1 ether);
        string memory expected = string.concat(
            "https://services.collarprotocol.xyz/metadata/",
            Strings.toString(block.chainid),
            "/",
            Strings.toHexString(address(escrowNFT)),
            "/",
            Strings.toString(escrowId)
        );
        console.log(expected);
        assertEq(escrowNFT.tokenURI(escrowId), expected);
    }

    function test_multipleEscrowsFromSameOffer() public {
        uint offerAmount = largeAmount;
        uint escrowAmount = largeAmount / 4;
        uint fee = 1 ether;

        (uint offerId,) = createAndCheckOffer(supplier1, offerAmount);

        for (uint i = 0; i < 3; i++) {
            createAndCheckEscrowFromOffer(offerId, escrowAmount, fee);
        }
        assertEq(escrowNFT.getOffer(offerId).available, offerAmount - 3 * escrowAmount);
    }

    function test_startEscrow_switchEscrow_minEscrow() public {
        (uint offerId,) = createAndCheckOffer(supplier1, largeAmount);
        // 0 amount works for startEscrow when minEscrow = 0
        (uint escrowId,) = createAndCheckEscrowFromOffer(offerId, 0, 0);
        // 0 amount works for switchEscrow when minEscrow = 0
        startHoax(loans);
        escrowNFT.switchEscrow(escrowId, offerId, 0, 0);

        uint fee = 1 ether;
        minEscrow = largeAmount / 10;
        // check non-zero minLocked effects (event)
        (offerId,) = createAndCheckOffer(supplier1, largeAmount);
        (escrowId,) = createAndCheckEscrowFromOffer(offerId, minEscrow, fee);
        startHoax(loans);
        asset.approve(address(escrowNFT), fee);
        escrowNFT.switchEscrow(escrowId, offerId, fee, 0);
    }

    function test_endEscrow_withdrawReleased_simple() public {
        uint escrowed = largeAmount / 2;
        uint fee = 1 ether;

        // after full duration
        check_preview_end_withdraw(
            escrowed, escrowed, fee, duration, ExpectedRelease(escrowed + fee, escrowed, 0)
        );

        // double time is the same
        check_preview_end_withdraw(
            escrowed, escrowed, fee, 2 * duration, ExpectedRelease(escrowed + fee, escrowed, 0)
        );
    }

    function test_endEscrow_withdrawReleased_underRepay() public {
        uint escrowed = largeAmount / 2;
        uint fee = 1 ether;

        // 0 repayment immediate release (cancellation)
        uint maxRefund = escrowNFT.MAX_FEE_REFUND_BIPS() * fee / BIPS_100PCT;
        check_preview_end_withdraw(
            escrowed, 0, fee, 0, ExpectedRelease(escrowed + fee - maxRefund, maxRefund, maxRefund)
        );

        // 0 repayment a bit after max refund time
        // 95% is max refund, so after 6% of duration, 94% should be refunded
        uint refund = fee * 94 / 100;
        check_preview_end_withdraw(
            escrowed, 0, fee, duration * 6 / 100, ExpectedRelease(escrowed + fee - refund, refund, refund)
        );

        // 0 repayment full duration
        check_preview_end_withdraw(escrowed, 0, fee, duration, ExpectedRelease(escrowed + fee, 0, 0));

        // 0 repayment with refund
        uint halfFee = fee / 2;
        check_preview_end_withdraw(
            escrowed, 0, fee, duration / 2, ExpectedRelease(escrowed + halfFee, halfFee, halfFee)
        );

        // partial repayment with refund
        check_preview_end_withdraw(
            escrowed,
            escrowed / 2,
            fee,
            duration / 2,
            ExpectedRelease(escrowed + halfFee, escrowed / 2 + halfFee, halfFee)
        );
    }

    function test_endEscrow_withdrawReleased_overPay() public {
        uint escrowed = largeAmount / 2;
        uint fee = 1 ether;
        uint halfFee = fee / 2;
        check_preview_end_withdraw(
            escrowed,
            escrowed * 2,
            fee,
            duration / 2,
            // does not take more than needed (escrow + fees - refund)
            ExpectedRelease(escrowed + halfFee, escrowed * 2 + halfFee, halfFee)
        );

        // overpayment no refund
        check_preview_end_withdraw(
            escrowed, escrowed * 2, fee, duration, ExpectedRelease(escrowed + fee, escrowed * 2, 0)
        );
    }

    struct Amounts {
        uint fee;
        uint newFee;
        uint escrowAmount;
        uint balanceLoans;
        uint balanceEscrow;
    }

    function test_switchEscrow_simple() public {
        Amounts memory amounts;
        amounts.escrowAmount = largeAmount / 2;
        amounts.fee = 1 ether;
        (uint oldEscrowId,) = createAndCheckEscrow(supplier1, largeAmount, amounts.escrowAmount, amounts.fee);

        amounts.newFee = amounts.fee * 2;
        (uint newOfferId,) = createAndCheckOffer(supplier2, largeAmount);

        uint newLoanId = 1000; // arbitrary

        startHoax(loans);
        asset.approve(address(escrowNFT), amounts.newFee);

        amounts.balanceLoans = asset.balanceOf(loans);
        amounts.balanceEscrow = asset.balanceOf(address(escrowNFT));

        // wait half a duration
        skip(duration / 2);
        (uint withdrawablePreview,, uint refundPreview) =
            escrowNFT.previewRelease(oldEscrowId, amounts.escrowAmount);

        uint expectedId = escrowNFT.nextEscrowId();

        vm.expectEmit(address(escrowNFT));
        emit IEscrowSupplierNFT.EscrowsSwitched(oldEscrowId, expectedId);
        (uint newEscrowId, uint feeRefund) =
            escrowNFT.switchEscrow(oldEscrowId, newOfferId, amounts.newFee, newLoanId);

        // check return values
        assertEq(newEscrowId, expectedId);
        assertEq(feeRefund, refundPreview);
        assertEq(feeRefund, amounts.fee / 2);

        // Check new escrow
        EscrowSupplierNFT.Escrow memory newEscrow = escrowNFT.getEscrow(newEscrowId);
        assertEq(newEscrow.offerId, newOfferId);
        assertEq(newEscrow.loans, loans);
        assertEq(newEscrow.loanId, newLoanId);
        assertEq(newEscrow.escrowed, amounts.escrowAmount);
        assertEq(newEscrow.interestHeld, amounts.newFee);
        assertFalse(newEscrow.released);
        assertEq(newEscrow.withdrawable, 0);

        // Check old escrow is released
        EscrowSupplierNFT.Escrow memory oldEscrow = escrowNFT.getEscrow(oldEscrowId);
        assertTrue(oldEscrow.released);
        assertEq(oldEscrow.withdrawable, withdrawablePreview);

        // Check NFT ownership
        assertEq(escrowNFT.ownerOf(newEscrowId), supplier2);
        assertEq(escrowNFT.ownerOf(oldEscrowId), supplier1); // unchanged

        // check balances
        assertEq(asset.balanceOf(loans), amounts.balanceLoans + feeRefund - amounts.newFee);
        assertEq(asset.balanceOf(address(escrowNFT)), amounts.balanceEscrow + amounts.newFee - feeRefund);

        // check withdrawal
        checkWithdrawReleased(oldEscrowId, withdrawablePreview);
    }

    function test_lastResortSeizeEscrow() public {
        checkLastResortSeizeEscrow(0);
        checkLastResortSeizeEscrow(1);
        checkLastResortSeizeEscrow(365 days);
    }

    // view effects

    function test_lateFees() public {
        uint escrowAmount = largeAmount / 2;
        uint fee = 1 ether;
        (uint escrowId, EscrowSupplierNFT.Escrow memory escrow) =
            createAndCheckEscrow(supplier1, largeAmount, escrowAmount, fee);

        // late fee are expected
        assertGt(escrowNFT.getEscrow(escrowId).lateFeeAPR, 0);

        // No late fee during min grace period
        skip(duration + escrowNFT.MIN_GRACE_PERIOD() - 1);
        (uint owed, uint lateFee) = escrowNFT.currentOwed(escrowId);
        assertEq(lateFee, 0);
        assertEq(owed, escrowAmount);

        // Late fee after grace period
        skip(1);
        (owed, lateFee) = escrowNFT.currentOwed(escrowId);
        uint expectedFee = expectedLateFees(escrow);
        assertTrue(expectedFee > 0);
        assertEq(lateFee, expectedFee);
        assertEq(owed, escrowAmount + expectedFee);

        skip(escrow.maxGracePeriod - escrowNFT.MIN_GRACE_PERIOD()); // we skipped min-grace already
        uint cappedLateFee;
        (owed, cappedLateFee) = escrowNFT.currentOwed(escrowId);
        expectedFee = expectedLateFees(escrow);
        assertTrue(cappedLateFee > 0);
        assertEq(cappedLateFee, expectedFee);
        assertEq(owed, escrowAmount + cappedLateFee);

        // Late fee capped at grace period
        skip(365 days);
        uint feeAfterGracePeriod;
        (owed, feeAfterGracePeriod) = escrowNFT.currentOwed(escrowId);
        assertEq(feeAfterGracePeriod, cappedLateFee);
        assertEq(owed, escrowAmount + feeAfterGracePeriod);

        // APR 0
        lateFeeAPR = 0;
        (escrowId, escrow) = createAndCheckEscrow(supplier1, largeAmount, escrowAmount, fee);
        skip(duration + 365 days);
        (, feeAfterGracePeriod) = escrowNFT.currentOwed(escrowId);
        assertEq(feeAfterGracePeriod, 0);
    }

    function test_gracePeriodFromFees() public {
        uint escrowAmount = largeAmount / 2;
        uint fee = 1 ether;
        (uint escrowId, EscrowSupplierNFT.Escrow memory escrow) =
            createAndCheckEscrow(supplier1, largeAmount, escrowAmount, fee);

        // Full grace period when fee amount covers it
        uint fullGracePeriod = escrowNFT.cappedGracePeriod(escrowId, escrowAmount);
        assertEq(fullGracePeriod, escrow.maxGracePeriod);

        // Partial grace period, 5 days at 100% is 1.3% (5/365 or 1/73)
        uint partialFeeAmount = escrowAmount / 73;

        uint expectedPeriod = partialFeeAmount * 365 days * BIPS_100PCT / escrowAmount / lateFeeAPR;
        uint partialGracePeriod = escrowNFT.cappedGracePeriod(escrowId, partialFeeAmount);
        assertTrue(partialGracePeriod < maxGracePeriod);
        assertEq(partialGracePeriod, expectedPeriod);

        // Minimum grace period when fee amount is very small
        assertEq(escrowNFT.cappedGracePeriod(escrowId, 0), escrowNFT.MIN_GRACE_PERIOD());
        assertEq(escrowNFT.cappedGracePeriod(escrowId, 1), escrowNFT.MIN_GRACE_PERIOD());

        // lateFeeAPR 0
        lateFeeAPR = 0;
        (uint newEscrowId,) = createAndCheckEscrow(supplier1, largeAmount, escrowAmount, fee);
        // full grace period even with no fee
        assertEq(escrowNFT.cappedGracePeriod(newEscrowId, 0), maxGracePeriod);
    }

    function test_interestFee_noFee() public {
        (uint offerId,) = createAndCheckOffer(supplier, largeAmount);

        // zero escrow amount
        assertEq(escrowNFT.interestFee(offerId, 0), 0);

        // zero APR
        interestAPR = 0;
        (offerId,) = createAndCheckOffer(supplier, largeAmount);
        assertEq(escrowNFT.interestFee(offerId, largeAmount), 0);
    }
}
