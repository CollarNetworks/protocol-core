// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

import "forge-std/Test.sol";
import { IERC721Errors } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { IERC20Errors } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { Loans, ILoans } from "../../src/Loans.sol";
import { CollarTakerNFT } from "../../src/CollarTakerNFT.sol";
import { ShortProviderNFT } from "../../src/ShortProviderNFT.sol";
import { Rolls } from "../../src/Rolls.sol";

import { LoansTestBase, TestERC20, SwapperUniV3, ISwapper } from "./Loans.basic.effects.t.sol";

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

        vm.expectRevert(abi.encodeWithSelector(selector, user1));
        loans.setSwapperAllowed(address(0), true, true);
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
        // check can update
        Rolls newRolls = new Rolls(owner, takerNFT);
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

    function test_setSwapperAllowed() public {
        vm.startPrank(owner);

        SwapperUniV3 newSwapper = new SwapperUniV3(address(mockSwapperRouter), swapFeeTier);
        vm.expectEmit(address(loans));
        emit ILoans.SwapperSet(address(newSwapper), true, true);
        loans.setSwapperAllowed(address(newSwapper), true, true);
        assertTrue(loans.allowedSwappers(address(newSwapper)));
        assertEq(loans.defaultSwapper(), address(newSwapper));

        // disallow new
        vm.expectEmit(address(loans));
        emit ILoans.SwapperSet(address(newSwapper), false, false);
        loans.setSwapperAllowed(address(newSwapper), false, false);
        assertFalse(loans.allowedSwappers(address(newSwapper)));
        assertEq(loans.defaultSwapper(), address(newSwapper)); // default swapper should remain unchanged

        // unset default
        vm.expectEmit(address(loans));
        emit ILoans.SwapperSet(address(0), false, true);
        // does not revert
        loans.setSwapperAllowed(address(0), false, true);
        assertFalse(loans.allowedSwappers(address(0)));
        assertEq(loans.defaultSwapper(), address(0)); // default is unset
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
        loans.openLoan(0, 0, defaultSwapParams(0), providerNFT, 0);

        vm.expectRevert(Pausable.EnforcedPause.selector);
        loans.setKeeperAllowedBy(takerId, true);

        vm.expectRevert(Pausable.EnforcedPause.selector);
        loans.closeLoan(takerId, defaultSwapParams(0));

        vm.expectRevert(Pausable.EnforcedPause.selector);
        loans.cancelLoan(takerId);
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
        CollarTakerNFT invalidTakerNFT = new CollarTakerNFT(
            owner, configHub, cashAsset, collateralAsset, mockOracle, "InvalidTakerNFT", "INVTKR"
        );
        Rolls invalidTakerRolls = new Rolls(owner, invalidTakerNFT);
        vm.expectRevert("rolls taker NFT mismatch");
        loans.setRollsContract(invalidTakerRolls);

        // Test revert when called by non-owner (tested elsewhere as well)
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        loans.setRollsContract(Rolls(address(0)));
    }

    function test_setSwapperAllowed_InvalidSwapper() public {
        address invalidSwapper = address(0x456);

        vm.startPrank(owner);
        vm.expectRevert(new bytes(0));
        loans.setSwapperAllowed(invalidSwapper, true, true);

        vm.mockCall(invalidSwapper, abi.encodeCall(ISwapper.VERSION, ()), abi.encode(""));
        vm.expectRevert("invalid swapper");
        loans.setSwapperAllowed(invalidSwapper, true, true);
    }
}
