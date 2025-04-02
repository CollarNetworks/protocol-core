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
    uint gracePeriod = 7 days;
    uint lateFeeAPR = 5000; // 50%
    uint minEscrow = 0;
    uint escrowFee = 1000 ether; // roughly 1% (late fees 50% for one week, and interest for 5 minutes)

    function setUp() public override {
        super.setUp();
        asset = underlying;
        escrowNFT = new EscrowSupplierNFT(configHub, asset, "ES Test", "ES Test");

        setCanOpenSingle(address(escrowNFT), true);
        setCanOpen(loans, true);
        vm.startPrank(owner);
        configHub.setCanOpenPair(address(underlying), address(escrowNFT), address(loans), true);
        vm.stopPrank();

        asset.mint(loans, largeUnderlying * 10);
        asset.mint(supplier1, largeUnderlying * 10);
        asset.mint(supplier2, largeUnderlying * 10);
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
            supplier, interestAPR, duration, gracePeriod, lateFeeAPR, amount, expectedId, minEscrow
        );
        offerId = escrowNFT.createOffer(amount, duration, interestAPR, gracePeriod, lateFeeAPR, minEscrow);

        // offer ID
        assertEq(offerId, expectedId);
        assertEq(escrowNFT.nextOfferId(), expectedId + 1);
        // offer
        offer = escrowNFT.getOffer(offerId);
        assertEq(offer.supplier, supplier);
        assertEq(offer.available, amount);
        assertEq(offer.duration, duration);
        assertEq(offer.interestAPR, interestAPR);
        assertEq(offer.gracePeriod, gracePeriod);
        assertEq(offer.lateFeeAPR, lateFeeAPR);
        // balance
        assertEq(asset.balanceOf(supplier), balance - amount);
        // fees view
        uint expectedInterestFee = divUp(amount * interestAPR * duration, BIPS_100PCT * 365 days);
        uint expectedLateFee = divUp(amount * lateFeeAPR * gracePeriod, BIPS_100PCT * 365 days);
        (uint actualMinFee, uint interestHeld, uint lateFeeHeld) = escrowNFT.upfrontFees(offerId, amount);
        assertEq(interestHeld, expectedInterestFee);
        assertEq(lateFeeHeld, expectedLateFee);
        assertEq(actualMinFee, expectedInterestFee + expectedLateFee);
    }

    function checkUpdateOfferAmount(int delta) internal {
        (uint offerId,) = createAndCheckOffer(supplier1, largeUnderlying);

        asset.approve(address(escrowNFT), largeUnderlying);
        uint newAmount = delta > 0 ? largeUnderlying + uint(delta) : largeUnderlying - uint(-delta);
        uint balance = asset.balanceOf(address(escrowNFT));

        vm.expectEmit(address(escrowNFT));
        emit IEscrowSupplierNFT.OfferUpdated(offerId, supplier1, largeUnderlying, newAmount);
        escrowNFT.updateOfferAmount(offerId, newAmount);

        // next offer id not impacted
        assertEq(escrowNFT.nextOfferId(), offerId + 1);
        // offer
        EscrowSupplierNFT.Offer memory offer = escrowNFT.getOffer(offerId);
        assertEq(offer.supplier, supplier1);
        assertEq(offer.available, newAmount);
        assertEq(offer.duration, duration);
        assertEq(offer.interestAPR, interestAPR);
        assertEq(offer.gracePeriod, gracePeriod);
        assertEq(offer.lateFeeAPR, lateFeeAPR);
        // balance
        assertEq(asset.balanceOf(address(escrowNFT)), balance + newAmount - largeUnderlying);
    }

    function createAndCheckEscrow(address supplier, uint offerAmount, uint escrowAmount, uint fees)
        public
        returns (uint escrowId, EscrowSupplierNFT.Escrow memory escrow)
    {
        (uint offerId,) = createAndCheckOffer(supplier, offerAmount);
        return createAndCheckEscrowFromOffer(offerId, escrowAmount, fees);
    }

    function createAndCheckEscrowFromOffer(uint offerId, uint escrowAmount, uint fees)
        public
        returns (uint escrowId, EscrowSupplierNFT.Escrow memory escrow)
    {
        address supplier = escrowNFT.getOffer(offerId).supplier;
        uint offerAmount = escrowNFT.getOffer(offerId).available;

        uint balance = asset.balanceOf(address(escrowNFT));
        uint expectedId = escrowNFT.nextEscrowId();

        uint loanId = 1000; // arbitrary

        startHoax(loans);
        asset.approve(address(escrowNFT), escrowAmount + fees);

        vm.expectEmit(address(escrowNFT));
        emit IEscrowSupplierNFT.EscrowCreated(expectedId, escrowAmount, fees, offerId);
        vm.expectEmit(address(escrowNFT));
        emit IEscrowSupplierNFT.OfferUpdated(offerId, supplier, offerAmount, offerAmount - escrowAmount);
        vm.expectEmit(address(asset));
        // check the needed transfer events order and amounts
        emit IERC20.Transfer(loans, address(escrowNFT), escrowAmount + fees);
        vm.expectEmit(address(asset));
        emit IERC20.Transfer(address(escrowNFT), loans, escrowAmount);
        escrowId = escrowNFT.startEscrow(offerId, escrowAmount, fees, loanId);
        escrow = escrowNFT.getEscrow(escrowId);

        // Check escrow details
        assertEq(escrowId, expectedId);
        assertEq(escrow.offerId, offerId);
        assertEq(escrow.loans, loans);
        assertEq(escrow.loanId, loanId);
        assertEq(escrow.escrowed, escrowAmount);
        assertEq(escrow.gracePeriod, gracePeriod);
        assertEq(escrow.lateFeeAPR, lateFeeAPR);
        assertEq(escrow.duration, duration);
        assertEq(escrow.expiration, block.timestamp + duration);
        assertEq(escrow.feesHeld, fees);
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
        assertEq(asset.balanceOf(address(escrowNFT)), balance + fees);
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

    function checkSeizeEscrow(uint delay) public {
        uint escrowAmount = largeUnderlying / 2;
        (uint escrowId,) = createAndCheckEscrow(supplier1, largeUnderlying, escrowAmount, escrowFee);

        // Skip past expiration and grace period
        skip(duration + gracePeriod + 1 + delay);

        startHoax(supplier1);
        uint balanceBefore = asset.balanceOf(supplier1);

        vm.expectEmit(address(escrowNFT));
        emit IEscrowSupplierNFT.EscrowSeized(escrowId, supplier1, escrowAmount + escrowFee);
        escrowNFT.seizeEscrow(escrowId);

        // Check balance
        assertEq(asset.balanceOf(supplier1), balanceBefore + escrowAmount + escrowFee);

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
        (uint escrowId,) = createAndCheckEscrow(supplier1, largeUnderlying, escrowAmount, fee);
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
        uint feeHeld = divUp(escrow.escrowed * lateFeeAPR * gracePeriod, BIPS_100PCT * 365 days);
        uint refund = feeHeld * (gracePeriod - overdue) / gracePeriod;
        return feeHeld - refund;
    }

    function divUp(uint x, uint y) internal pure returns (uint) {
        return (x == 0) ? 0 : ((x - 1) / y) + 1; // divUp(x,y) = (x-1 / y) + 1
    }
}

contract EscrowSupplierNFT_BasicEffectsTest is BaseEscrowSupplierNFTTest {
    function test_constructor() public {
        EscrowSupplierNFT newEscrowSupplierNFT =
            new EscrowSupplierNFT(configHub, asset, "NewEscrowSupplierNFT", "NESNFT");

        assertEq(address(newEscrowSupplierNFT.configHubOwner()), owner);
        assertEq(address(newEscrowSupplierNFT.configHub()), address(configHub));
        assertEq(address(newEscrowSupplierNFT.asset()), address(asset));
        assertEq(newEscrowSupplierNFT.MAX_INTEREST_APR_BIPS(), BIPS_100PCT);
        assertEq(newEscrowSupplierNFT.MIN_GRACE_PERIOD(), 1 days);
        assertEq(newEscrowSupplierNFT.MAX_GRACE_PERIOD(), 30 days);
        assertEq(newEscrowSupplierNFT.MAX_LATE_FEE_APR_BIPS(), 12 * BIPS_100PCT);
        assertEq(newEscrowSupplierNFT.MAX_FEE_REFUND_BIPS(), 9500);
        assertEq(newEscrowSupplierNFT.VERSION(), "0.3.0");
        assertEq(newEscrowSupplierNFT.name(), "NewEscrowSupplierNFT");
        assertEq(newEscrowSupplierNFT.symbol(), "NESNFT");
    }

    function test_createOffer() public {
        createAndCheckOffer(supplier1, largeUnderlying);

        // another one (multiple offers)
        createAndCheckOffer(supplier1, largeUnderlying);

        // max values ok
        interestAPR = escrowNFT.MAX_INTEREST_APR_BIPS();
        gracePeriod = escrowNFT.MAX_GRACE_PERIOD();
        lateFeeAPR = escrowNFT.MAX_LATE_FEE_APR_BIPS();
        createAndCheckOffer(supplier1, largeUnderlying);
    }

    function test_updateOfferAmount() public {
        checkUpdateOfferAmount(int(largeUnderlying));

        checkUpdateOfferAmount(int(largeUnderlying) / 2);

        checkUpdateOfferAmount(-int(largeUnderlying));

        checkUpdateOfferAmount(-int(largeUnderlying) / 2);

        checkUpdateOfferAmount(0);
    }

    function test_startEscrow_simple() public {
        createAndCheckEscrow(supplier1, largeUnderlying, largeUnderlying / 2, escrowFee);
    }

    function test_tokenURI() public {
        (uint escrowId,) = createAndCheckEscrow(supplier1, largeUnderlying, largeUnderlying / 2, escrowFee);
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
        uint offerAmount = largeUnderlying;
        uint escrowAmount = largeUnderlying / 4;

        (uint offerId,) = createAndCheckOffer(supplier1, offerAmount);

        for (uint i = 0; i < 3; i++) {
            createAndCheckEscrowFromOffer(offerId, escrowAmount, escrowFee);
        }
        assertEq(escrowNFT.getOffer(offerId).available, offerAmount - 3 * escrowAmount);
    }

    function test_startEscrow_switchEscrow_minEscrow() public {
        (uint offerId,) = createAndCheckOffer(supplier1, largeUnderlying);
        // 0 amount works for startEscrow when minEscrow = 0
        (uint escrowId,) = createAndCheckEscrowFromOffer(offerId, 0, 0);
        // 0 amount works for switchEscrow when minEscrow = 0
        startHoax(loans);
        escrowNFT.switchEscrow(escrowId, offerId, 0, 0);

        minEscrow = largeUnderlying / 10;
        // check non-zero minLocked effects (event)
        (offerId,) = createAndCheckOffer(supplier1, largeUnderlying);
        (escrowId,) = createAndCheckEscrowFromOffer(offerId, minEscrow, escrowFee);
        startHoax(loans);
        asset.approve(address(escrowNFT), escrowFee);
        escrowNFT.switchEscrow(escrowId, offerId, escrowFee, 0);
    }

    function test_endEscrow_withdrawReleased_simple() public {
        uint escrowed = largeUnderlying / 2;

        (uint offerId,) = createAndCheckOffer(supplier, largeUnderlying);
        (, uint interestHeld,) = escrowNFT.upfrontFees(offerId, escrowed);
        uint refund = escrowFee - interestHeld;

        // after full duration
        check_preview_end_withdraw(
            escrowed,
            escrowed,
            escrowFee,
            duration,
            ExpectedRelease(escrowed + escrowFee - refund, escrowed + refund, refund)
        );

        // double time is the same
        check_preview_end_withdraw(
            escrowed,
            escrowed,
            escrowFee,
            2 * duration,
            ExpectedRelease(escrowed + escrowFee - refund, escrowed + refund, refund)
        );
    }

    function test_endEscrow_withdrawReleased_underRepay() public {
        uint escrowed = largeUnderlying / 2;

        (uint offerId,) = createAndCheckOffer(supplier, largeUnderlying);
        (, uint interestHeld,) = escrowNFT.upfrontFees(offerId, escrowed);

        // 0 repayment immediate release (cancellation)
        uint interestRefund = escrowNFT.MAX_FEE_REFUND_BIPS() * interestHeld / BIPS_100PCT;
        uint refund = escrowFee - (interestHeld - interestRefund);
        check_preview_end_withdraw(
            escrowed, 0, escrowFee, 0, ExpectedRelease(escrowed + escrowFee - refund, refund, refund)
        );

        // 0 repayment a bit after max refund time
        // 95% is max refund, so after 6% of duration, 94% should be refunded
        refund = escrowFee - (interestHeld - interestHeld * 94 / 100);
        check_preview_end_withdraw(
            escrowed,
            0,
            escrowFee,
            duration * 6 / 100,
            ExpectedRelease(escrowed + escrowFee - refund, refund, refund)
        );

        // 0 repayment full duration
        refund = escrowFee - interestHeld;
        check_preview_end_withdraw(
            escrowed, 0, escrowFee, duration, ExpectedRelease(escrowed + escrowFee - refund, refund, refund)
        );

        // 0 repayment with refund
        refund = escrowFee - interestHeld / 2;
        check_preview_end_withdraw(
            escrowed,
            0,
            escrowFee,
            duration / 2,
            ExpectedRelease(escrowed + escrowFee - refund, refund, refund)
        );

        // partial repayment with refund
        check_preview_end_withdraw(
            escrowed,
            escrowed / 2,
            escrowFee,
            duration / 2,
            ExpectedRelease(escrowed + escrowFee - refund, escrowed / 2 + refund, refund)
        );
    }

    function test_endEscrow_withdrawReleased_overPay() public {
        uint escrowed = largeUnderlying / 2;

        (uint offerId,) = createAndCheckOffer(supplier, largeUnderlying);
        (, uint interestHeld,) = escrowNFT.upfrontFees(offerId, escrowed);
        uint refund = escrowFee - interestHeld / 2;

        check_preview_end_withdraw(
            escrowed,
            escrowed * 2,
            escrowFee,
            duration / 2,
            // does not take more than needed (escrow + fees - refund)
            ExpectedRelease(escrowed + escrowFee - refund, escrowed * 2 + refund, refund)
        );

        // overpayment no interest refund
        refund = escrowFee - interestHeld;
        check_preview_end_withdraw(
            escrowed,
            escrowed * 2,
            escrowFee,
            duration,
            ExpectedRelease(escrowed + escrowFee - refund, escrowed * 2 + refund, refund)
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
        amounts.escrowAmount = largeUnderlying / 2;
        amounts.fee = escrowFee;
        (uint oldEscrowId, EscrowSupplierNFT.Escrow memory oldEscrow) =
            createAndCheckEscrow(supplier1, largeUnderlying, amounts.escrowAmount, amounts.fee);

        amounts.newFee = amounts.fee * 2;
        (uint newOfferId,) = createAndCheckOffer(supplier2, largeUnderlying);

        uint newLoanId = 1000; // arbitrary

        startHoax(loans);
        asset.approve(address(escrowNFT), amounts.newFee);

        amounts.balanceLoans = asset.balanceOf(loans);
        amounts.balanceEscrow = asset.balanceOf(address(escrowNFT));

        // wait half a duration
        skip(duration / 2);
        (, uint interestHeld,) = escrowNFT.upfrontFees(oldEscrow.offerId, oldEscrow.escrowed);
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
        assertEq(feeRefund, amounts.fee - interestHeld / 2);

        // Check new escrow
        EscrowSupplierNFT.Escrow memory newEscrow = escrowNFT.getEscrow(newEscrowId);
        assertEq(newEscrow.offerId, newOfferId);
        assertEq(newEscrow.loans, loans);
        assertEq(newEscrow.loanId, newLoanId);
        assertEq(newEscrow.escrowed, amounts.escrowAmount);
        assertEq(newEscrow.feesHeld, amounts.newFee);
        assertFalse(newEscrow.released);
        assertEq(newEscrow.withdrawable, 0);

        // Check old escrow is released
        oldEscrow = escrowNFT.getEscrow(oldEscrowId);
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

    function test_seizeEscrow() public {
        checkSeizeEscrow(0);
        checkSeizeEscrow(1);
        checkSeizeEscrow(365 days);
    }

    // view effects

    function checkLateFeeAndOverpaymentRefunds(uint escrowId, uint feesPaid)
        public
        view
        returns (uint lateFee)
    {
        EscrowSupplierNFT.Escrow memory escrow = escrowNFT.getEscrow(escrowId);
        (, uint interestFeeHeld, uint lateFeeHeld) = escrowNFT.upfrontFees(escrow.offerId, escrow.escrowed);
        (, uint interestFeeRefund, uint lateFeeRefund, uint overpayRefund) = escrowNFT.feesRefunds(escrowId);
        (,, uint refunds) = escrowNFT.previewRelease(escrowId, 0);
        // no interest refund after expiry
        assertEq(interestFeeRefund, 0);
        // overpayment is refunded
        assertEq(overpayRefund, feesPaid - interestFeeHeld - lateFeeHeld);
        // total refund are as expected
        assertEq(refunds, lateFeeRefund + overpayRefund);
        return lateFeeHeld - lateFeeRefund;
    }

    function test_lateFeeRefund() public {
        uint escrowAmount = largeUnderlying / 2;
        uint fees = escrowFee;
        (uint escrowId, EscrowSupplierNFT.Escrow memory escrow) =
            createAndCheckEscrow(supplier1, largeUnderlying, escrowAmount, fees);

        // late fee are expected
        assertGt(escrow.lateFeeAPR, 0);

        // No late fee during min grace period
        skip(duration + escrowNFT.MIN_GRACE_PERIOD());
        uint lateFee = checkLateFeeAndOverpaymentRefunds(escrowId, fees);
        assertEq(lateFee, 0);

        // Late fee after grace period
        skip(1);
        lateFee = checkLateFeeAndOverpaymentRefunds(escrowId, fees);
        uint expectedFee = expectedLateFees(escrow);
        assertEq(lateFee, expectedFee);

        // skip to last second of max-grace
        skip(escrow.gracePeriod - escrowNFT.MIN_GRACE_PERIOD() - 1); // we skipped min-grace already
        expectedFee = expectedLateFees(escrow);
        uint cappedLateFee = checkLateFeeAndOverpaymentRefunds(escrowId, fees);
        assertTrue(cappedLateFee > 0);
        assertEq(cappedLateFee, expectedFee);

        // Late fee capped at grace period
        skip(365 days);
        uint feeAfterGracePeriod = checkLateFeeAndOverpaymentRefunds(escrowId, fees);
        assertEq(feeAfterGracePeriod, cappedLateFee);

        // APR 0
        lateFeeAPR = 0;
        (escrowId, escrow) = createAndCheckEscrow(supplier1, largeUnderlying, escrowAmount, fees);
        skip(duration + 365 days);
        feeAfterGracePeriod = checkLateFeeAndOverpaymentRefunds(escrowId, fees);
        assertEq(feeAfterGracePeriod, 0);
    }

    function test_interestFee_noFee() public {
        (uint offerId,) = createAndCheckOffer(supplier, largeUnderlying);

        // zero escrow amount
        (uint fees,,) = escrowNFT.upfrontFees(offerId, 0);
        assertEq(fees, 0);

        // zero APR
        interestAPR = 0;
        (offerId,) = createAndCheckOffer(supplier, largeUnderlying);
        (, uint interestHeld,) = escrowNFT.upfrontFees(offerId, largeUnderlying);
        assertEq(interestHeld, 0);
    }
}
