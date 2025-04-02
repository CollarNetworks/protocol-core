// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

import "forge-std/Test.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { BaseEscrowSupplierNFTTest, IEscrowSupplierNFT } from "./EscrowSupplierNFT.effects.t.sol";

contract EscrowSupplierNFT_AdminTest is BaseEscrowSupplierNFTTest {
    function test_onlyConfigHubOwnerMethods() public {
        vm.startPrank(user1);

        vm.expectRevert("BaseManaged: not configHub owner");
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
}
