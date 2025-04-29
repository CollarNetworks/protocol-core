// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

import "forge-std/Test.sol";

import { BaseEscrowSupplierNFTTest } from "./EscrowSupplierNFT.effects.t.sol";

contract EscrowSupplierNFT_BasicRevertsTest is BaseEscrowSupplierNFTTest {
    function test_revert_createOffer_invalidParams() public {
        startHoax(supplier1);
        asset.approve(address(escrowNFT), largeUnderlying);

        uint val = escrowNFT.MAX_INTEREST_APR_BIPS();
        vm.expectRevert("escrow: interest APR too high");
        escrowNFT.createOffer(largeUnderlying, duration, val + 1, gracePeriod, lateFeeAPR, 0);

        val = escrowNFT.MIN_GRACE_PERIOD();
        vm.expectRevert("escrow: grace period too short");
        escrowNFT.createOffer(largeUnderlying, duration, interestAPR, val - 1, lateFeeAPR, 0);

        val = escrowNFT.MAX_GRACE_PERIOD();
        vm.expectRevert("escrow: grace period too long");
        escrowNFT.createOffer(largeUnderlying, duration, interestAPR, val + 1, lateFeeAPR, 0);

        val = escrowNFT.MAX_LATE_FEE_APR_BIPS();
        vm.expectRevert("escrow: late fee APR too high");
        escrowNFT.createOffer(largeUnderlying, duration, interestAPR, gracePeriod, val + 1, 0);
    }

    function test_revert_updateOfferAmount_notSupplier() public {
        (uint offerId,) = createAndCheckOffer(supplier1, largeUnderlying);

        startHoax(supplier2);
        vm.expectRevert("escrow: not offer supplier");
        escrowNFT.updateOfferAmount(offerId, largeUnderlying / 2);
    }

    function test_revert_startEscrow_minEscrow() public {
        minEscrow = 1;
        (uint offerId,) = createAndCheckOffer(supplier1, largeUnderlying);

        startHoax(loans);
        vm.expectRevert("escrow: amount too low");
        escrowNFT.startEscrow(offerId, 0, 0, 0);

        minEscrow = largeUnderlying / 2;
        uint fee = escrowFee;
        (offerId,) = createAndCheckOffer(supplier1, largeUnderlying);
        startHoax(loans);
        asset.approve(address(escrowNFT), largeUnderlying / 2);
        vm.expectRevert("escrow: amount too low");
        escrowNFT.startEscrow(offerId, minEscrow - 1, fee, 0);
    }

    function test_revert_startEscrow_invalidParams() public {
        (uint offerId,) = createAndCheckOffer(supplier1, largeUnderlying);

        startHoax(loans);
        asset.approve(address(escrowNFT), largeUnderlying);

        vm.expectRevert("escrow: amount too high");
        escrowNFT.startEscrow(offerId, largeUnderlying + 1, escrowFee, 1000);

        (uint minFee,,) = escrowNFT.upfrontFees(offerId, largeUnderlying);
        vm.expectRevert("escrow: insufficient upfront fees");
        escrowNFT.startEscrow(offerId, largeUnderlying, minFee - 1, 1000);

        vm.expectRevert("escrow: invalid offer");
        escrowNFT.startEscrow(offerId + 1, largeUnderlying, minFee, 1000);

        vm.startPrank(owner);
        configHub.setCollarDurationRange(duration + 1, duration + 2);
        vm.startPrank(loans);
        vm.expectRevert("escrow: unsupported duration");
        escrowNFT.startEscrow(offerId, largeUnderlying, escrowFee, 1000);
    }

    function test_revert_switchEscrow_minEscrow() public {
        (uint offer1,) = createAndCheckOffer(supplier1, largeUnderlying);
        minEscrow = 1;
        (uint offer2,) = createAndCheckOffer(supplier1, largeUnderlying);
        minEscrow = largeUnderlying / 2;
        (uint offer3,) = createAndCheckOffer(supplier1, largeUnderlying);

        startHoax(loans);
        // dust escrow
        (uint escrowId) = escrowNFT.startEscrow(offer1, 0, 0, 0);
        // switch to offer2, does not accept dust
        vm.expectRevert("escrow: amount too low");
        escrowNFT.switchEscrow(escrowId, offer2, 0, 0);

        uint fee = escrowFee;
        asset.approve(address(escrowNFT), largeUnderlying / 2 + fee - 1);
        (escrowId) = escrowNFT.startEscrow(offer1, largeUnderlying / 2 - 1, fee, 0);
        // switch to offer3, does not accept the amount
        vm.expectRevert("escrow: amount too low");
        escrowNFT.switchEscrow(escrowId, offer3, fee, 0);
    }

    function test_revert_switchEscrow_invalidParams() public {
        (uint escrowId,) = createAndCheckEscrow(supplier1, largeUnderlying, largeUnderlying, escrowFee);

        startHoax(loans);
        asset.approve(address(escrowNFT), largeUnderlying);

        (uint newOfferId,) = createAndCheckOffer(supplier2, largeUnderlying - 1);
        (uint minFee,,) = escrowNFT.upfrontFees(newOfferId, largeUnderlying - 1);

        // fee
        startHoax(loans);
        vm.expectRevert("escrow: insufficient upfront fees");
        escrowNFT.switchEscrow(escrowId, newOfferId, minFee - 1, 0);

        // new offer is insufficient
        vm.expectRevert("escrow: amount too high");
        escrowNFT.switchEscrow(escrowId, newOfferId, minFee, 0);
        (newOfferId,) = createAndCheckOffer(supplier2, largeUnderlying);

        startHoax(loans);
        vm.expectRevert("escrow: invalid offer");
        escrowNFT.switchEscrow(escrowId, newOfferId + 1, minFee, 0);

        vm.startPrank(owner);
        configHub.setCollarDurationRange(duration + 1, duration + 2);
        vm.startPrank(loans);
        vm.expectRevert("escrow: unsupported duration");
        escrowNFT.switchEscrow(escrowId, newOfferId, minFee, 0);

        // expired escrow
        vm.startPrank(loans);
        skip(duration + 1);
        vm.expectRevert("escrow: expired");
        escrowNFT.switchEscrow(escrowId, newOfferId, minFee, 0);
    }

    function test_revert_nonExistentID() public {
        vm.expectRevert("escrow: position does not exist");
        escrowNFT.getEscrow(1000);

        vm.expectRevert("escrow: position does not exist");
        escrowNFT.feesRefunds(1000);

        vm.expectRevert("escrow: position does not exist");
        escrowNFT.previewRelease(1000, 0);

        vm.startPrank(loans);
        vm.expectRevert("escrow: position does not exist");
        escrowNFT.endEscrow(1000, 0);

        vm.expectRevert("escrow: position does not exist");
        escrowNFT.switchEscrow(1000, 0, 0, 0);
    }

    function test_revert_startEscrow_unauthorizedLoans() public {
        (uint offerId,) = createAndCheckOffer(supplier1, largeUnderlying);

        setCanOpenSingle(address(escrowNFT), false);
        vm.startPrank(loans);
        vm.expectRevert("escrow: unsupported escrow");
        escrowNFT.startEscrow(offerId, largeUnderlying / 2, escrowFee, 1000);

        setCanOpenSingle(address(escrowNFT), true);

        // block loans access
        vm.startPrank(owner);
        configHub.setCanOpenPair(address(underlying), address(escrowNFT), address(loans), false);
        vm.startPrank(loans);
        vm.expectRevert("escrow: unauthorized loans contract");
        escrowNFT.startEscrow(offerId, largeUnderlying / 2, escrowFee, 1000);

        // some other address
        startHoax(makeAddr("otherLoans"));
        vm.expectRevert("escrow: unauthorized loans contract");
        escrowNFT.startEscrow(offerId, largeUnderlying / 2, escrowFee, 1000);
    }

    function test_revert_switchEscrow_unauthorizedLoans() public {
        (uint escrowId,) = createAndCheckEscrow(supplier1, largeUnderlying, largeUnderlying, escrowFee);
        (uint newOfferId,) = createAndCheckOffer(supplier2, largeUnderlying);

        setCanOpenSingle(address(escrowNFT), false);
        vm.startPrank(loans);
        vm.expectRevert("escrow: unsupported escrow");
        escrowNFT.switchEscrow(escrowId, newOfferId, 0, 0);

        setCanOpenSingle(address(escrowNFT), true);

        // block loans open
        vm.startPrank(owner);
        configHub.setCanOpenPair(address(underlying), address(escrowNFT), address(loans), false);
        vm.startPrank(loans);
        vm.expectRevert("escrow: unauthorized loans contract");
        escrowNFT.switchEscrow(escrowId, newOfferId, 0, 0);

        // some other address
        startHoax(makeAddr("otherLoans"));
        vm.expectRevert("escrow: loans address mismatch");
        escrowNFT.switchEscrow(escrowId, newOfferId, 0, 0);
    }

    function test_revert_loansCanOpen_only_switchEscrow() public {
        (uint escrowId,) = createAndCheckEscrow(supplier1, largeUnderlying, largeUnderlying / 2, escrowFee);

        // removing loans canOpen prevents switchEscrow
        vm.startPrank(owner);
        configHub.setCanOpenPair(address(underlying), address(escrowNFT), address(loans), false);
        vm.startPrank(loans);
        vm.expectRevert("escrow: unauthorized loans contract");
        escrowNFT.switchEscrow(escrowId, 0, 0, 0);
        // but not endEscrow
        escrowNFT.endEscrow(escrowId, 0);
    }

    function test_revert_endEscrow_switchEscrow() public {
        (uint escrowId,) = createAndCheckEscrow(supplier1, largeUnderlying, largeUnderlying / 2, escrowFee);

        // not same loans that started
        vm.startPrank(owner);
        configHub.setCanOpenPair(address(underlying), address(escrowNFT), address(supplier1), false);
        startHoax(supplier1);
        vm.expectRevert("escrow: loans address mismatch");
        escrowNFT.endEscrow(escrowId, 0);
        vm.expectRevert("escrow: loans address mismatch");
        escrowNFT.switchEscrow(escrowId, 0, 0, 0);

        // released already
        vm.startPrank(owner);
        configHub.setCanOpenPair(address(underlying), address(escrowNFT), address(loans), true);
        vm.startPrank(loans);
        asset.approve(address(escrowNFT), largeUnderlying);
        escrowNFT.endEscrow(escrowId, largeUnderlying / 2);
        vm.expectRevert("escrow: already released");
        escrowNFT.endEscrow(escrowId, 0);
        vm.expectRevert("escrow: already released");
        escrowNFT.switchEscrow(escrowId, 0, 0, 0);
    }

    function test_revert_withdrawReleased() public {
        (uint escrowId,) = createAndCheckEscrow(supplier1, largeUnderlying, largeUnderlying, escrowFee);

        startHoax(supplier2);
        vm.expectRevert("escrow: not escrow owner");
        escrowNFT.withdrawReleased(escrowId);

        startHoax(supplier1);
        vm.expectRevert("escrow: not released");
        escrowNFT.withdrawReleased(escrowId);

        startHoax(loans);
        asset.approve(address(escrowNFT), largeUnderlying);
        escrowNFT.endEscrow(escrowId, largeUnderlying);

        startHoax(supplier1);
        escrowNFT.transferFrom(supplier1, supplier2, escrowId);
        // works now
        startHoax(supplier2);
        escrowNFT.withdrawReleased(escrowId);

        // cannot withdraw twice
        expectRevertERC721Nonexistent(escrowId);
        escrowNFT.withdrawReleased(escrowId);
    }

    function test_revert_seizeEscrow() public {
        (uint escrowId,) = createAndCheckEscrow(supplier1, largeUnderlying, largeUnderlying / 2, escrowFee);

        startHoax(supplier2);
        vm.expectRevert("escrow: not escrow owner");
        escrowNFT.seizeEscrow(escrowId);

        skip(duration + gracePeriod);
        startHoax(supplier1);
        vm.expectRevert("escrow: grace period not elapsed");
        escrowNFT.seizeEscrow(escrowId);

        // release
        startHoax(loans);
        asset.approve(address(escrowNFT), largeUnderlying);
        escrowNFT.endEscrow(escrowId, largeUnderlying / 2);

        skip(1);
        startHoax(supplier1);
        vm.expectRevert("escrow: already released");
        escrowNFT.seizeEscrow(escrowId);
    }
}
