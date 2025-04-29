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
    function test_onlyConfigHubOwnerMethods() public {
        vm.startPrank(user1);

        vm.expectRevert("BaseManaged: not configHub owner");
        loans.setSwapperAllowed(address(0), true, true);
    }

    function test_setSwapperAllowed() public {
        vm.startPrank(owner);

        address[] memory oneSwapper = new address[](1);
        oneSwapper[0] = defaultSwapper;
        assertEq(loans.allAllowedSwappers(), oneSwapper);

        // not default
        SwapperUniV3 newSwapper = new SwapperUniV3(address(mockSwapperRouter), swapFeeTier);
        vm.expectEmit(address(loans));
        emit ILoansNFT.SwapperSet(address(newSwapper), true, false);
        loans.setSwapperAllowed(address(newSwapper), true, false);
        assertTrue(loans.isAllowedSwapper(address(newSwapper)));
        assertEq(loans.defaultSwapper(), address(defaultSwapper));
        address[] memory twoSwappers = new address[](2);
        twoSwappers[0] = defaultSwapper;
        twoSwappers[1] = address(newSwapper);
        assertEq(loans.allAllowedSwappers(), twoSwappers);

        vm.expectEmit(address(loans));
        emit ILoansNFT.SwapperSet(address(newSwapper), true, true);
        loans.setSwapperAllowed(address(newSwapper), true, true);
        assertTrue(loans.isAllowedSwapper(address(newSwapper)));
        assertEq(loans.defaultSwapper(), address(newSwapper));
        assertEq(loans.allAllowedSwappers(), twoSwappers);

        // disallow new
        vm.expectEmit(address(loans));
        emit ILoansNFT.SwapperSet(address(newSwapper), false, false);
        loans.setSwapperAllowed(address(newSwapper), false, false);
        assertFalse(loans.isAllowedSwapper(address(newSwapper)));
        assertEq(loans.defaultSwapper(), address(newSwapper)); // default swapper should remain unchanged
        oneSwapper[0] = defaultSwapper;
        assertEq(loans.allAllowedSwappers(), oneSwapper);

        // unset default
        vm.expectEmit(address(loans));
        emit ILoansNFT.SwapperSet(address(0), false, true);
        // does not revert
        loans.setSwapperAllowed(address(0), false, true);
        assertFalse(loans.isAllowedSwapper(address(0)));
        assertEq(loans.defaultSwapper(), address(0)); // default is unset
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
