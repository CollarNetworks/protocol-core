// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

import "forge-std/Test.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { BaseEscrowSupplierNFTTest, IEscrowSupplierNFT } from "./EscrowSupplierNFT.effects.t.sol";

contract EscrowSupplierNFT_AdminTest is BaseEscrowSupplierNFTTest {
    function test_onlyOwnerMethods() public {
        vm.startPrank(user1);
        bytes4 selector = Ownable.OwnableUnauthorizedAccount.selector;

        vm.expectRevert(abi.encodeWithSelector(selector, user1));
        escrowNFT.pause();

        vm.expectRevert(abi.encodeWithSelector(selector, user1));
        escrowNFT.unpause();

        vm.expectRevert(abi.encodeWithSelector(selector, user1));
        escrowNFT.setLoansCanOpen(loans, true);
    }

    function test_setLoansCanOpen() public {
        assertEq(escrowNFT.loansCanOpen(loans), true);

        address newLoansContract = makeAddr("newLoans");

        startHoax(owner);
        vm.expectEmit(address(escrowNFT));
        emit IEscrowSupplierNFT.LoansCanOpenSet(newLoansContract, true);
        escrowNFT.setLoansCanOpen(newLoansContract, true);

        assertTrue(escrowNFT.loansCanOpen(newLoansContract));

        vm.expectEmit(address(escrowNFT));
        emit IEscrowSupplierNFT.LoansCanOpenSet(newLoansContract, false);
        escrowNFT.setLoansCanOpen(newLoansContract, false);

        assertFalse(escrowNFT.loansCanOpen(newLoansContract));
    }

    function test_paused_methods() public {
        (uint escrowId,) = createAndCheckEscrow(supplier1, largeAmount, largeAmount, 1 ether);

        // pause
        vm.startPrank(owner);
        vm.expectEmit(address(escrowNFT));
        emit Pausable.Paused(owner);
        escrowNFT.pause();
        // paused view
        assertTrue(escrowNFT.paused());
        // methods are paused
        vm.startPrank(user1);

        vm.expectRevert(Pausable.EnforcedPause.selector);
        escrowNFT.createOffer(0, 0, 0, 0, 0, 0);

        vm.expectRevert(Pausable.EnforcedPause.selector);
        escrowNFT.updateOfferAmount(0, 0);

        vm.expectRevert(Pausable.EnforcedPause.selector);
        escrowNFT.startEscrow(0, 0, 0, 0);

        vm.expectRevert(Pausable.EnforcedPause.selector);
        escrowNFT.endEscrow(0, 0);

        vm.expectRevert(Pausable.EnforcedPause.selector);
        escrowNFT.switchEscrow(0, 0, 0, 0);

        vm.expectRevert(Pausable.EnforcedPause.selector);
        escrowNFT.withdrawReleased(0);

        vm.expectRevert(Pausable.EnforcedPause.selector);
        escrowNFT.lastResortSeizeEscrow(0);

        // transfers are paused
        vm.expectRevert(Pausable.EnforcedPause.selector);
        escrowNFT.transferFrom(supplier1, supplier2, escrowId);
    }

    function test_unpause() public {
        vm.startPrank(owner);
        escrowNFT.pause();
        vm.expectEmit(address(escrowNFT));
        emit Pausable.Unpaused(owner);
        escrowNFT.unpause();
        assertFalse(escrowNFT.paused());
        // check at least one method workds now
        createAndCheckOffer(supplier1, largeAmount);
    }
}
