// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

import "forge-std/Test.sol";

import { BaseEscrowSupplierNFTTest } from "./EscrowSupplierNFT.effects.t.sol";

contract EscrowSupplierNFT_BasicRevertsTest is BaseEscrowSupplierNFTTest {
    function test_revert_createOffer_invalidParams() public {
        startHoax(supplier1);
        asset.approve(address(escrowNFT), largeAmount);

        uint val = escrowNFT.MAX_INTEREST_APR_BIPS();
        vm.expectRevert("interest APR too high");
        escrowNFT.createOffer(largeAmount, duration, val + 1, maxGracePeriod, lateFeeAPR, 0);

        val = escrowNFT.MIN_GRACE_PERIOD();
        vm.expectRevert("grace period too short");
        escrowNFT.createOffer(largeAmount, duration, interestAPR, val - 1, lateFeeAPR, 0);

        val = escrowNFT.MAX_GRACE_PERIOD();
        vm.expectRevert("grace period too long");
        escrowNFT.createOffer(largeAmount, duration, interestAPR, val + 1, lateFeeAPR, 0);

        val = escrowNFT.MAX_LATE_FEE_APR_BIPS();
        vm.expectRevert("late fee APR too high");
        escrowNFT.createOffer(largeAmount, duration, interestAPR, maxGracePeriod, val + 1, 0);

        vm.expectRevert("unsupported duration");
        escrowNFT.createOffer(largeAmount, duration + 1, interestAPR, maxGracePeriod, lateFeeAPR, 0);

        // bad asset
        vm.startPrank(owner);
        configHub.setUnderlyingSupport(address(asset), false);
        vm.startPrank(supplier1);
        vm.expectRevert("unsupported asset");
        escrowNFT.createOffer(largeAmount, duration, interestAPR, maxGracePeriod, lateFeeAPR, 0);
    }

    function test_revert_updateOfferAmount_notSupplier() public {
        (uint offerId,) = createAndCheckOffer(supplier1, largeAmount);

        startHoax(supplier2);
        vm.expectRevert("not offer supplier");
        escrowNFT.updateOfferAmount(offerId, largeAmount / 2);
    }

    function test_revert_startEscrow_minEscrow() public {
        minEscrow = 1;
        (uint offerId,) = createAndCheckOffer(supplier1, largeAmount);

        startHoax(loans);
        vm.expectRevert("amount too low");
        escrowNFT.startEscrow(offerId, 0, 0, 0);

        minEscrow = largeAmount / 2;
        uint fee = 1 ether;
        (offerId,) = createAndCheckOffer(supplier1, largeAmount);
        startHoax(loans);
        asset.approve(address(escrowNFT), largeAmount / 2);
        vm.expectRevert("amount too low");
        escrowNFT.startEscrow(offerId, minEscrow - 1, fee, 0);
    }

    function test_revert_startEscrow_invalidParams() public {
        (uint offerId,) = createAndCheckOffer(supplier1, largeAmount);

        startHoax(loans);
        asset.approve(address(escrowNFT), largeAmount);

        vm.expectRevert("amount too high");
        escrowNFT.startEscrow(offerId, largeAmount + 1, 1 ether, 1000);

        uint minFee = escrowNFT.interestFee(offerId, largeAmount);
        vm.expectRevert("insufficient fee");
        escrowNFT.startEscrow(offerId, largeAmount, minFee - 1, 1000);

        vm.expectRevert("invalid offer");
        escrowNFT.startEscrow(offerId + 1, largeAmount, minFee, 1000);

        vm.startPrank(owner);
        configHub.setCollarDurationRange(duration + 1, duration + 2);
        vm.startPrank(loans);
        vm.expectRevert("unsupported duration");
        escrowNFT.startEscrow(offerId, largeAmount, 1 ether, 1000);

        // bad asset
        vm.startPrank(owner);
        configHub.setUnderlyingSupport(address(asset), false);
        vm.startPrank(loans);
        vm.expectRevert("unsupported asset");
        escrowNFT.startEscrow(offerId, largeAmount, 1 ether, 1000);
    }

    function test_revert_switchEscrow_minEscrow() public {
        (uint offer1,) = createAndCheckOffer(supplier1, largeAmount);
        minEscrow = 1;
        (uint offer2,) = createAndCheckOffer(supplier1, largeAmount);
        minEscrow = largeAmount / 2;
        (uint offer3,) = createAndCheckOffer(supplier1, largeAmount);

        startHoax(loans);
        // dust escrow
        (uint escrowId) = escrowNFT.startEscrow(offer1, 0, 0, 0);
        // switch to offer2, does not accept dust
        vm.expectRevert("amount too low");
        escrowNFT.switchEscrow(escrowId, offer2, 0, 0);

        uint fee = 1 ether;
        asset.approve(address(escrowNFT), largeAmount / 2 + fee - 1);
        (escrowId) = escrowNFT.startEscrow(offer1, largeAmount / 2 - 1, fee, 0);
        // switch to offer3, does not accept the amount
        vm.expectRevert("amount too low");
        escrowNFT.switchEscrow(escrowId, offer3, fee, 0);
    }

    function test_revert_switchEscrow_invalidParams() public {
        (uint escrowId,) = createAndCheckEscrow(supplier1, largeAmount, largeAmount, 1 ether);

        startHoax(loans);
        asset.approve(address(escrowNFT), largeAmount);

        (uint newOfferId,) = createAndCheckOffer(supplier2, largeAmount - 1);
        uint minFee = escrowNFT.interestFee(newOfferId, largeAmount - 1);

        // fee
        startHoax(loans);
        vm.expectRevert("insufficient fee");
        escrowNFT.switchEscrow(escrowId, newOfferId, minFee - 1, 0);

        // new offer is insufficient
        vm.expectRevert("amount too high");
        escrowNFT.switchEscrow(escrowId, newOfferId, minFee, 0);
        (newOfferId,) = createAndCheckOffer(supplier2, largeAmount);

        startHoax(loans);
        vm.expectRevert("invalid offer");
        escrowNFT.switchEscrow(escrowId, newOfferId + 1, minFee, 0);

        vm.startPrank(owner);
        configHub.setCollarDurationRange(duration + 1, duration + 2);
        vm.startPrank(loans);
        vm.expectRevert("unsupported duration");
        escrowNFT.switchEscrow(escrowId, newOfferId, minFee, 0);

        // bad asset
        vm.startPrank(owner);
        configHub.setUnderlyingSupport(address(asset), false);
        vm.startPrank(loans);
        vm.expectRevert("unsupported asset");
        escrowNFT.switchEscrow(escrowId, newOfferId, minFee, 0);

        // expired escrow
        vm.startPrank(owner);
        configHub.setUnderlyingSupport(address(asset), true);
        vm.startPrank(loans);
        skip(duration + 1);
        vm.expectRevert("expired escrow");
        escrowNFT.switchEscrow(escrowId, newOfferId, minFee, 0);
    }

    function test_revert_nonExistentID() public {
        vm.expectRevert("escrow position does not exist");
        escrowNFT.getEscrow(1000);

        vm.expectRevert("escrow position does not exist");
        escrowNFT.currentOwed(1000);

        vm.expectRevert("escrow position does not exist");
        escrowNFT.cappedGracePeriod(1000, 0);

        vm.expectRevert("escrow position does not exist");
        escrowNFT.previewRelease(1000, 0);

        vm.startPrank(loans);
        vm.expectRevert("escrow position does not exist");
        escrowNFT.endEscrow(1000, 0);

        vm.expectRevert("escrow position does not exist");
        escrowNFT.switchEscrow(1000, 0, 0, 0);
    }

    function test_revert_startEscrow_unauthorizedLoans() public {
        (uint offerId,) = createAndCheckOffer(supplier1, largeAmount);

        vm.startPrank(owner);
        configHub.setCanOpen(address(escrowNFT), false);
        vm.startPrank(loans);
        vm.expectRevert("unsupported supplier contract");
        escrowNFT.startEscrow(offerId, largeAmount / 2, 1 ether, 1000);

        vm.startPrank(owner);
        configHub.setCanOpen(loans, false);
        vm.startPrank(loans);
        vm.expectRevert("unsupported loans contract");
        escrowNFT.startEscrow(offerId, largeAmount / 2, 1 ether, 1000);

        // block loans access
        vm.startPrank(owner);
        escrowNFT.setLoansAllowed(loans, false);
        vm.startPrank(loans);
        vm.expectRevert("unauthorized loans contract");
        escrowNFT.startEscrow(offerId, largeAmount / 2, 1 ether, 1000);

        // some other address
        startHoax(makeAddr("otherLoans"));
        vm.expectRevert("unauthorized loans contract");
        escrowNFT.startEscrow(offerId, largeAmount / 2, 1 ether, 1000);
    }

    function test_revert_switchEscrow_unauthorizedLoans() public {
        (uint escrowId,) = createAndCheckEscrow(supplier1, largeAmount, largeAmount, 1 ether);
        (uint newOfferId,) = createAndCheckOffer(supplier2, largeAmount);

        vm.startPrank(owner);
        configHub.setCanOpen(address(escrowNFT), false);
        vm.startPrank(loans);
        vm.expectRevert("unsupported supplier contract");
        escrowNFT.switchEscrow(escrowId, newOfferId, 0, 0);

        vm.startPrank(owner);
        configHub.setCanOpen(loans, false);
        vm.startPrank(loans);
        vm.expectRevert("unsupported loans contract");
        escrowNFT.switchEscrow(escrowId, newOfferId, 0, 0);

        // block loans access
        vm.startPrank(owner);
        escrowNFT.setLoansAllowed(loans, false);
        vm.startPrank(loans);
        vm.expectRevert("unauthorized loans contract");
        escrowNFT.switchEscrow(escrowId, newOfferId, 0, 0);

        // some other address
        startHoax(makeAddr("otherLoans"));
        vm.expectRevert("unauthorized loans contract");
        escrowNFT.switchEscrow(escrowId, newOfferId, 0, 0);
    }

    function test_revert_endEscrow_switchEscrow() public {
        (uint escrowId,) = createAndCheckEscrow(supplier1, largeAmount, largeAmount / 2, 1 ether);

        // block loans access
        vm.startPrank(owner);
        escrowNFT.setLoansAllowed(loans, false);
        vm.startPrank(loans);
        vm.expectRevert("unauthorized loans contract");
        escrowNFT.endEscrow(escrowId, 0);
        vm.expectRevert("unauthorized loans contract");
        escrowNFT.switchEscrow(escrowId, 0, 0, 0);

        // not same loans that started
        vm.startPrank(owner);
        escrowNFT.setLoansAllowed(supplier1, true);
        startHoax(supplier1);
        vm.expectRevert("loans address mismatch");
        escrowNFT.endEscrow(escrowId, 0);
        vm.expectRevert("loans address mismatch");
        escrowNFT.switchEscrow(escrowId, 0, 0, 0);

        // released already
        vm.startPrank(owner);
        escrowNFT.setLoansAllowed(loans, true);
        vm.startPrank(loans);
        asset.approve(address(escrowNFT), largeAmount);
        escrowNFT.endEscrow(escrowId, largeAmount / 2);
        vm.expectRevert("already released");
        escrowNFT.endEscrow(escrowId, 0);
        vm.expectRevert("already released");
        escrowNFT.switchEscrow(escrowId, 0, 0, 0);
    }

    function test_revert_withdrawReleased() public {
        (uint escrowId,) = createAndCheckEscrow(supplier1, largeAmount, largeAmount, 1 ether);

        startHoax(supplier2);
        vm.expectRevert("not escrow owner");
        escrowNFT.withdrawReleased(escrowId);

        startHoax(supplier1);
        vm.expectRevert("not released");
        escrowNFT.withdrawReleased(escrowId);

        startHoax(loans);
        asset.approve(address(escrowNFT), largeAmount);
        escrowNFT.endEscrow(escrowId, largeAmount);

        startHoax(supplier1);
        escrowNFT.transferFrom(supplier1, supplier2, escrowId);
        // works now
        startHoax(supplier2);
        escrowNFT.withdrawReleased(escrowId);

        // cannot withdraw twice
        expectRevertERC721Nonexistent(escrowId);
        escrowNFT.withdrawReleased(escrowId);
    }

    function test_revert_lastResortSeizeEscrow() public {
        (uint escrowId,) = createAndCheckEscrow(supplier1, largeAmount, largeAmount / 2, 1 ether);

        startHoax(supplier2);
        vm.expectRevert("not escrow owner");
        escrowNFT.lastResortSeizeEscrow(escrowId);

        skip(duration + maxGracePeriod);
        startHoax(supplier1);
        vm.expectRevert("grace period not elapsed");
        escrowNFT.lastResortSeizeEscrow(escrowId);

        // release
        startHoax(loans);
        asset.approve(address(escrowNFT), largeAmount);
        escrowNFT.endEscrow(escrowId, largeAmount / 2);

        skip(1);
        startHoax(supplier1);
        vm.expectRevert("already released");
        escrowNFT.lastResortSeizeEscrow(escrowId);
    }
}
