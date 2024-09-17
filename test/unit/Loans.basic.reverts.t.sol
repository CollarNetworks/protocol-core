// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

import "forge-std/Test.sol";
import { IERC721Errors } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { IERC20Errors } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { LoansNFT, ILoansNFT } from "../../src/LoansNFT.sol";
import { CollarTakerNFT } from "../../src/CollarTakerNFT.sol";
import { ShortProviderNFT } from "../../src/ShortProviderNFT.sol";
import { Rolls } from "../../src/Rolls.sol";

import { LoansTestBase } from "./Loans.basic.effects.t.sol";

contract LoansBasicRevertsTest is LoansTestBase {
    function test_revert_openLoan_params() public {
        vm.startPrank(user1);
        collateralAsset.approve(address(loans), collateralAmount);
        prepareSwapToCashAtTWAPPrice();

        // 0 collateral
        vm.expectRevert("invalid collateral amount");
        loans.openLoan(0, 0, defaultSwapParams(0), 0, 0);

        // unsupported loans
        vm.startPrank(owner);
        configHub.setCanOpen(address(loans), false);
        vm.startPrank(user1);
        vm.expectRevert("unsupported loans contract");
        loans.openLoan(0, 0, defaultSwapParams(0), 0, 0);

        // unsupported taker
        vm.startPrank(owner);
        configHub.setCanOpen(address(loans), true);
        configHub.setCanOpen(address(takerNFT), false);
        vm.startPrank(user1);
        vm.expectRevert("unsupported taker contract");
        loans.openLoan(0, 0, defaultSwapParams(0), 0, 0);

        // unset provider
        vm.startPrank(owner);
        configHub.setCanOpen(address(takerNFT), true);
        loans.setContracts(rolls, ShortProviderNFT(address(0)), escrowNFT);
        vm.startPrank(user1);
        vm.expectRevert("provider contract unset");
        loans.openLoan(0, 0, defaultSwapParams(0), 0, 0);

        // unsupported provider
        vm.startPrank(owner);
        loans.setContracts(rolls, providerNFT, escrowNFT);
        configHub.setCanOpen(address(providerNFT), false);
        vm.startPrank(user1);
        vm.expectRevert("unsupported provider contract");
        loans.openLoan(collateralAmount, 0, defaultSwapParams(0), 0, 0);

        // bad offer
        vm.startPrank(owner);
        configHub.setCanOpen(address(providerNFT), true);
        vm.startPrank(user1);
        uint invalidOfferId = 999;
        vm.expectRevert("invalid offer");
        loans.openLoan(collateralAmount, minLoanAmount, defaultSwapParams(0), invalidOfferId, 0);

        uint offerId = createProviderOffer();
        // not enough approval for collateral
        vm.startPrank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector,
                address(loans),
                collateralAmount,
                collateralAmount + 1
            )
        );
        loans.openLoan(collateralAmount + 1, minLoanAmount, defaultSwapParams(0), offerId, 0);
    }

    function test_revert_openLoan_swaps_router() public {
        uint offerId = createProviderOffer();
        prepareSwap(cashAsset, swapCashAmount);

        vm.startPrank(user1);
        collateralAsset.approve(address(loans), collateralAmount);

        // balance mismatch
        mockSwapperRouter.setupSwap(swapCashAmount - 1, swapCashAmount);
        vm.expectRevert("balance update mismatch");
        loans.openLoan(collateralAmount, minLoanAmount, defaultSwapParams(swapCashAmount), offerId, 0);

        // slippage params
        mockSwapperRouter.setupSwap(swapCashAmount, swapCashAmount);
        vm.expectRevert("slippage exceeded");
        loans.openLoan(collateralAmount, minLoanAmount, defaultSwapParams(swapCashAmount + 1), offerId, 0);

        // deviation vs.TWAP
        prepareSwap(cashAsset, swapCashAmount / 2);
        vm.expectRevert("swap and twap price too different");
        loans.openLoan(collateralAmount, minLoanAmount, defaultSwapParams(0), offerId, 0);
    }

    function test_revert_openLoan_swapper_not_allowed() public {
        vm.startPrank(owner);
        // disable the default swapper
        loans.setSwapperAllowed(address(defaultSwapper), false, true);

        // not allowed
        startHoax(user1);
        collateralAsset.approve(address(loans), collateralAmount);
        vm.expectRevert("swapper not allowed");
        loans.openLoan(collateralAmount, minLoanAmount, defaultSwapParams(0), 0, 0);
    }

    function test_revert_openLoan_swaps_swapper() public {
        vm.startPrank(owner);
        // set the mock as the default swapper (instead of router) to reuse the router revert tests
        defaultSwapper = address(mockSwapperRouter);
        loans.setSwapperAllowed(defaultSwapper, true, true);
        // disable the default swapper to be sure
        loans.setSwapperAllowed(address(swapperUniV3), false, false);

        // now run the slippage and balance tests, but the reverts are now in the loans contract
        test_revert_openLoan_swaps_router();
    }

    function test_revert_openLoan_insufficientLoanAmount() public {
        uint offerId = createProviderOffer();
        uint swapOut = prepareSwapToCashAtTWAPPrice();

        vm.startPrank(user1);
        collateralAsset.approve(address(loans), collateralAmount);

        uint highMinLoanAmount = (swapOut * ltv / BIPS_100PCT) + 1; // 1 wei more than ltv
        vm.expectRevert("loan amount too low");
        loans.openLoan(collateralAmount, highMinLoanAmount, defaultSwapParams(swapCashAmount), offerId, 0);
    }

    function test_revert_openLoan_IdTaken() public {
        (uint loanId,, uint loanAmount) = createAndCheckLoan();
        uint offerId = providerNFT.nextOfferId() - 1;
        uint putLocked = swapCashAmount - loanAmount;

        // prep again
        prepareSwapToCashAtTWAPPrice();
        collateralAsset.approve(address(loans), collateralAmount);

        vm.mockCall(
            address(takerNFT),
            abi.encodeWithSelector(takerNFT.openPairedPosition.selector, putLocked, providerNFT, offerId),
            abi.encode(loanId, 0, 0, 0) // returns old taker ID
        );
        vm.expectRevert("loanId taken");
        loans.openLoan(collateralAmount, 0, defaultSwapParams(swapCashAmount), offerId, 0);
    }

    function test_revert_closeLoan_notNFTOwnerOrKeeper() public {
        (uint loanId,,) = createAndCheckLoan();
        vm.startPrank(address(0xdead));
        vm.expectRevert("not NFT owner or allowed keeper");
        loans.closeLoan(loanId, defaultSwapParams(0));
    }

    function test_revert_closeLoan_nonExistentLoan() public {
        uint nonExistentLoanId = 999;
        expectRevertERC721Nonexistent(nonExistentLoanId);
        loans.closeLoan(nonExistentLoanId, defaultSwapParams(0));
    }

    function test_revert_closeLoan_noLoanForLoanID() public {
        uint offerId = createProviderOffer();
        vm.startPrank(user1);
        // create taker NFT not through loans
        (uint takerId,) = takerNFT.openPairedPosition(0, providerNFT, offerId);
        uint loanId = takerId;
        expectRevertERC721Nonexistent(loanId);
        loans.closeLoan(loanId, defaultSwapParams(0));
    }

    function test_revert_closeLoan_reentrnancy_alreadyClosed() public {
        (uint loanId,, uint loanAmount) = createAndCheckLoan();
        skip(duration);
        vm.startPrank(user1);
        cashAsset.approve(address(loans), loanAmount);

        // setup attack: reenter from closeLoan to closeLoan
        ReentrantCloser closer = new ReentrantCloser();
        closer.setParams(loans, loanId, user1);
        cashAsset.setAttacker(address(closer));
        loans.approve(address(closer), loanId); // allow attacker to pull nft
        expectRevertERC721Nonexistent(loanId);
        loans.closeLoan(loanId, defaultSwapParams(0));
    }

    function test_revert_closeLoan_alreadyClosed() public {
        uint loanId = checkOpenCloseWithPriceChange(twapPrice, BIPS_100PCT, 0);
        expectRevertERC721Nonexistent(loanId);
        loans.closeLoan(loanId, defaultSwapParams(0));
    }

    function test_revert_closeLoan_insufficientRepaymentAllowance() public {
        (uint loanId,, uint loanAmount) = createAndCheckLoan();
        skip(duration);
        vm.startPrank(user1);

        cashAsset.approve(address(loans), loanAmount - 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, address(loans), loanAmount - 1, loanAmount
            )
        );
        loans.closeLoan(loanId, defaultSwapParams(0));
    }

    function test_revert_closeLoan_beforeExpiration() public {
        (uint loanId,, uint loanAmount) = createAndCheckLoan();
        skip(duration - 1);

        vm.startPrank(user1);
        cashAsset.approve(address(loans), loanAmount);

        vm.expectRevert("not expired");
        loans.closeLoan(loanId, defaultSwapParams(0));
    }

    function test_revert_closeLoan_swaps_router() public {
        (uint loanId,, uint loanAmount) = createAndCheckLoan();
        skip(duration);
        vm.startPrank(user1);
        cashAsset.approve(address(loans), loanAmount);
        prepareSwap(collateralAsset, collateralAmount);

        vm.expectRevert("slippage exceeded");
        loans.closeLoan(loanId, defaultSwapParams(collateralAmount + 1));

        mockSwapperRouter.setupSwap(collateralAmount - 1, collateralAmount);
        vm.expectRevert("balance update mismatch");
        loans.closeLoan(loanId, defaultSwapParams(collateralAmount));
    }

    function test_revert_closeLoan_swaps_swapper() public {
        // set the mock as the default swapper (instead of Uni swapper) to reuse the router revert tests
        vm.startPrank(owner);
        defaultSwapper = address(mockSwapperRouter);
        loans.setSwapperAllowed(defaultSwapper, true, true);
        // disable the uni swapper to be sure
        loans.setSwapperAllowed(address(swapperUniV3), false, false);

        // now run the slippage and balance tests, but the reverts are now in the loans contract
        test_revert_closeLoan_swaps_router();
    }

    function test_revert_closeLoan_swapper_not_allowed() public {
        (uint loanId,, uint loanAmount) = createAndCheckLoan();
        skip(duration);

        vm.startPrank(owner);
        // disable the default swapper
        loans.setSwapperAllowed(address(swapperUniV3), false, true);

        // not allowed
        vm.startPrank(user1);
        cashAsset.approve(address(loans), loanAmount);
        vm.expectRevert("swapper not allowed");
        loans.closeLoan(loanId, defaultSwapParams(collateralAmount));
    }

    function test_revert_closeLoan_keeperNotAllowed() public {
        (uint loanId,, uint loanAmount) = createAndCheckLoan();
        skip(duration);

        vm.startPrank(owner);
        loans.setKeeper(keeper);

        vm.startPrank(keeper);
        // keeper was not allowed by user
        vm.expectRevert("not NFT owner or allowed keeper");
        loans.closeLoan(loanId, defaultSwapParams(0));

        vm.startPrank(user1);
        loans.setKeeperAllowed(true);

        vm.startPrank(user1);
        // transfer invalidates approval
        loans.transferFrom(user1, provider, loanId);

        vm.startPrank(keeper);
        vm.expectRevert("not NFT owner or allowed keeper");
        loans.closeLoan(loanId, defaultSwapParams(0));

        // transfer back
        vm.startPrank(provider);
        loans.transferFrom(provider, user1, loanId);

        // should work now
        vm.startPrank(user1);
        cashAsset.approve(address(loans), loanAmount);
        prepareSwap(collateralAsset, collateralAmount);
        // close from keeper
        vm.startPrank(keeper);
        loans.closeLoan(loanId, defaultSwapParams(0));
        expectRevertERC721Nonexistent(loanId);
        loans.ownerOf(loanId);
    }

    function test_revert_cancelLoan_reverts() public {
        (uint loanId,,) = createAndCheckLoan();

        // only NFT owner
        vm.stopPrank();
        vm.expectRevert("not NFT owner");
        loans.unwrapAndCancelLoan(loanId);

        vm.startPrank(user1);
        // Close the loan normally
        skip(duration);
        uint swapOut = prepareSwapToCollateralAtTWAPPrice();
        closeAndCheckLoan(
            loanId,
            user1,
            loans.getLoan(loanId).loanAmount,
            takerNFT.getPosition(loanId).putLockedCash,
            swapOut
        );

        // Try to cancel the already closed loan
        expectRevertERC721Nonexistent(loanId);
        loans.unwrapAndCancelLoan(loanId);
    }
}

contract ReentrantCloser {
    address nftOwner;
    LoansNFT loans;
    uint id;

    function setParams(LoansNFT _loans, uint _id, address _nftOwner) external {
        loans = _loans;
        id = _id;
        nftOwner = _nftOwner;
    }

    fallback() external virtual {
        loans.transferFrom(nftOwner, address(this), id);
        loans.closeLoan(id, ILoansNFT.SwapParams(0, address(loans.defaultSwapper()), ""));
    }
}
