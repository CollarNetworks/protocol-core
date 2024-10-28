// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

import "forge-std/Test.sol";
import { IERC721Errors } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { LoansNFT, ILoansNFT } from "../../src/LoansNFT.sol";
import { CollarTakerNFT } from "../../src/CollarTakerNFT.sol";
import { CollarProviderNFT } from "../../src/CollarProviderNFT.sol";
import { Rolls } from "../../src/Rolls.sol";

import {
    LoansTestBase, TestERC20, SwapperUniV3, ISwapper, EscrowSupplierNFT
} from "./Loans.basic.effects.t.sol";

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
        loans.setSwapperAllowed(address(0), true, true);
    }

    function test_setKeeper() public {
        assertEq(loans.closingKeeper(), address(0));

        vm.startPrank(owner);
        vm.expectEmit(address(loans));
        emit ILoansNFT.ClosingKeeperUpdated(address(0), keeper);
        loans.setKeeper(keeper);

        assertEq(loans.closingKeeper(), keeper);
    }

    function test_setSwapperAllowed() public {
        vm.startPrank(owner);

        // not default
        SwapperUniV3 newSwapper = new SwapperUniV3(address(mockSwapperRouter), swapFeeTier);
        vm.expectEmit(address(loans));
        emit ILoansNFT.SwapperSet(address(newSwapper), true, false);
        loans.setSwapperAllowed(address(newSwapper), true, false);
        assertTrue(loans.allowedSwappers(address(newSwapper)));
        assertEq(loans.defaultSwapper(), address(defaultSwapper));

        vm.expectEmit(address(loans));
        emit ILoansNFT.SwapperSet(address(newSwapper), true, true);
        loans.setSwapperAllowed(address(newSwapper), true, true);
        assertTrue(loans.allowedSwappers(address(newSwapper)));
        assertEq(loans.defaultSwapper(), address(newSwapper));

        // disallow new
        vm.expectEmit(address(loans));
        emit ILoansNFT.SwapperSet(address(newSwapper), false, false);
        loans.setSwapperAllowed(address(newSwapper), false, false);
        assertFalse(loans.allowedSwappers(address(newSwapper)));
        assertEq(loans.defaultSwapper(), address(newSwapper)); // default swapper should remain unchanged

        // unset default
        vm.expectEmit(address(loans));
        emit ILoansNFT.SwapperSet(address(0), false, true);
        // does not revert
        loans.setSwapperAllowed(address(0), false, true);
        assertFalse(loans.allowedSwappers(address(0)));
        assertEq(loans.defaultSwapper(), address(0)); // default is unset
    }

    function test_pause() public {
        (uint loanId,,) = createAndCheckLoan();

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
        loans.openLoan(0, 0, defaultSwapParams(0), providerOffer(0));

        vm.expectRevert(Pausable.EnforcedPause.selector);
        loans.openEscrowLoan(0, 0, defaultSwapParams(0), providerOffer(0), escrowOffer(0), 0);

        vm.expectRevert(Pausable.EnforcedPause.selector);
        loans.setKeeperApproved(true);

        vm.expectRevert(Pausable.EnforcedPause.selector);
        loans.closeLoan(loanId, defaultSwapParams(0));

        vm.expectRevert(Pausable.EnforcedPause.selector);
        loans.forecloseLoan(loanId, defaultSwapParams(0));

        vm.expectRevert(Pausable.EnforcedPause.selector);
        loans.rollLoan(loanId, rollOffer(0), 0, 0, 0);

        vm.expectRevert(Pausable.EnforcedPause.selector);
        loans.unwrapAndCancelLoan(loanId);

        // transfers are paused
        vm.expectRevert(Pausable.EnforcedPause.selector);
        loans.transferFrom(user1, provider, loanId);
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

    function test_setSwapperAllowed_InvalidSwapper() public {
        address invalidSwapper = address(0x456);

        vm.startPrank(owner);
        vm.expectRevert(new bytes(0));
        loans.setSwapperAllowed(invalidSwapper, true, true);

        vm.mockCall(invalidSwapper, abi.encodeCall(ISwapper.VERSION, ()), abi.encode(""));
        vm.expectRevert("loans: invalid swapper");
        loans.setSwapperAllowed(invalidSwapper, true, true);
    }
}
