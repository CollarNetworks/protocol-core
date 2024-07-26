// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

import "forge-std/Test.sol";
import { IERC721Errors } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { IERC20Errors } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { Loans, ILoans } from "../../src/Loans.sol";
import { CollarTakerNFT } from "../../src/CollarTakerNFT.sol";
import { ProviderPositionNFT } from "../../src/ProviderPositionNFT.sol";
import { Rolls } from "../../src/Rolls.sol";

import { LoansTestBase, TestERC20 } from "./Loans.basic.effects.t.sol";
import { BaseEmergencyAdminTestBase } from "./BaseEmergencyAdmin.t.sol";

contract LoansAdminTest is LoansTestBase {
    function test_onlyOwnerMethods() public {
        vm.startPrank(user1);
        bytes4 selector = Ownable.OwnableUnauthorizedAccount.selector;

        vm.expectRevert(abi.encodeWithSelector(selector, user1));
        loans.pause();

        vm.expectRevert(abi.encodeWithSelector(selector, user1));
        loans.unpause();

        vm.expectRevert(abi.encodeWithSelector(selector, user1));
        loans.setKeeper(keeper);

        vm.expectRevert(abi.encodeWithSelector(selector, user1));
        loans.setRollsContract(Rolls(address(0)));
    }

    function test_setKeeper() public {
        assertEq(loans.closingKeeper(), address(0));

        vm.startPrank(owner);
        vm.expectEmit(address(loans));
        emit ILoans.ClosingKeeperUpdated(address(0), keeper);
        loans.setKeeper(keeper);

        assertEq(loans.closingKeeper(), keeper);
    }

    function test_setRollsContract() public {
        // check setup
        assertEq(address(loans.rollsContract()), address(rolls));
        // check can upted
        Rolls newRolls = new Rolls(owner, takerNFT, cashAsset);
        vm.startPrank(owner);
        vm.expectEmit(address(loans));
        emit ILoans.RollsContractUpdated(rolls, newRolls);
        loans.setRollsContract(newRolls);
        // check effect
        assertEq(address(loans.rollsContract()), address(newRolls));

        // check can unset (set to zero address)
        Rolls unsetRolls = Rolls(address(0));
        vm.expectEmit(address(loans));
        emit ILoans.RollsContractUpdated(newRolls, unsetRolls);
        loans.setRollsContract(unsetRolls);
        // check effect
        assertEq(address(loans.rollsContract()), address(unsetRolls));
    }

    function test_pause() public {
        (uint takerId,,) = createAndCheckLoan();

        // pause
        vm.startPrank(owner);
        vm.expectEmit(address(loans));
        emit Pausable.Paused(owner);
        loans.pause();
        // paused view
        assertTrue(loans.paused());
        // methods are paused
        vm.startPrank(user1);

        vm.expectRevert(Pausable.EnforcedPause.selector);
        loans.createLoan(0, 0, 0, providerNFT, 0);

        vm.expectRevert(Pausable.EnforcedPause.selector);
        loans.setKeeperAllowedBy(takerId, true);

        vm.expectRevert(Pausable.EnforcedPause.selector);
        loans.closeLoan(takerId, 0);
    }

    function test_unpause() public {
        vm.startPrank(owner);
        loans.pause();
        vm.expectEmit(address(loans));
        emit Pausable.Unpaused(owner);
        loans.unpause();
        assertFalse(loans.paused());
        // check at least one method workds now
        createAndCheckLoan();
    }

    function test_revert_setRollsContract() public {
        vm.startPrank(owner);

        // Test revert when taker NFT doesn't match
        CollarTakerNFT invalidTakerNFT =
            new CollarTakerNFT(owner, configHub, cashAsset, collateralAsset, "InvalidTakerNFT", "INVTKR");
        Rolls invalidTakerRolls = new Rolls(owner, invalidTakerNFT, cashAsset);
        vm.expectRevert("rolls taker NFT mismatch");
        loans.setRollsContract(invalidTakerRolls);

        // Test revert when cash asset doesn't match
        Rolls invalidRolls = new Rolls(owner, takerNFT, collateralAsset); // collateralAsset instead of cashAsset
        vm.expectRevert("rolls cash asset mismatch");
        loans.setRollsContract(invalidRolls);

        // Test revert when called by non-owner (tested elsewhere as well)
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        loans.setRollsContract(Rolls(address(0)));
    }
}

contract LoansEmergencyAdminTest is BaseEmergencyAdminTestBase {
    function setupTestedContract() internal override {
        TestERC20 cashAsset = new TestERC20("TestCash", "TestCash");
        TestERC20 collateralAsset = new TestERC20("TestCollat", "TestCollat");

        vm.startPrank(owner);
        configHub.setCashAssetSupport(address(cashAsset), true);
        configHub.setCollateralAssetSupport(address(collateralAsset), true);
        vm.stopPrank();

        CollarTakerNFT takerNFT = new CollarTakerNFT(
            owner, configHub, cashAsset, collateralAsset, "CollarTakerNFT", "CollarTakerNFT"
        );

        testedContract = new Loans(owner, takerNFT);
    }
}
