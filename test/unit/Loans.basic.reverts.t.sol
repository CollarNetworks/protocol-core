// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

import "forge-std/Test.sol";
import { IERC721Errors } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { IERC20Errors } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { LoansNFT, IBaseLoansNFT } from "../../src/LoansNFT.sol";
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
        loans.openLoan(0, 0, defaultSwapParams(0), ShortProviderNFT(address(0)), 0);

        // bad provider
        ShortProviderNFT invalidProviderNFT = new ShortProviderNFT(
            owner, configHub, cashAsset, collateralAsset, address(takerNFT), "InvalidProviderNFT", "INVPRV"
        );
        vm.expectRevert("unsupported provider contract");
        loans.openLoan(collateralAmount, minLoanAmount, defaultSwapParams(0), invalidProviderNFT, 0);

        // bad offer
        uint invalidOfferId = 999;
        vm.expectRevert("invalid offer");
        loans.openLoan(collateralAmount, minLoanAmount, defaultSwapParams(0), providerNFT, invalidOfferId);

        uint offerId = createOfferAsProvider();
        // not enough approval for collatearal
        vm.startPrank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector,
                address(loans),
                collateralAmount,
                collateralAmount + 1
            )
        );
        loans.openLoan(collateralAmount + 1, minLoanAmount, defaultSwapParams(0), providerNFT, offerId);
    }

    function test_revert_openLoan_swaps_router() public {
        uint offerId = createOfferAsProvider();
        prepareSwap(cashAsset, swapCashAmount);

        vm.startPrank(user1);
        collateralAsset.approve(address(loans), collateralAmount);

        // balance mismatch
        mockSwapperRouter.setupSwap(swapCashAmount - 1, swapCashAmount);
        vm.expectRevert("balance update mismatch");
        loans.openLoan(
            collateralAmount, minLoanAmount, defaultSwapParams(swapCashAmount), providerNFT, offerId
        );

        // slippage params
        mockSwapperRouter.setupSwap(swapCashAmount, swapCashAmount);
        vm.expectRevert("slippage exceeded");
        loans.openLoan(
            collateralAmount, minLoanAmount, defaultSwapParams(swapCashAmount + 1), providerNFT, offerId
        );

        // deviation vs.TWAP
        prepareSwap(cashAsset, swapCashAmount / 2);
        vm.expectRevert("swap and twap price too different");
        loans.openLoan(collateralAmount, minLoanAmount, defaultSwapParams(0), providerNFT, offerId);
    }

    function test_revert_openLoan_swapper_not_allowed() public {
        vm.startPrank(owner);
        // disable the default swapper
        loans.setSwapperAllowed(address(swapperUniV3), false, true);

        // not allowed
        vm.expectRevert("swapper not allowed");
        loans.openLoan(collateralAmount, minLoanAmount, defaultSwapParams(0), providerNFT, 0);
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
        uint offerId = createOfferAsProvider();
        uint swapOut = prepareSwapToCashAtTWAPPrice();

        vm.startPrank(user1);
        collateralAsset.approve(address(loans), collateralAmount);

        uint highMinLoanAmount = (swapOut * ltv / BIPS_100PCT) + 1; // 1 wei more than ltv
        vm.expectRevert("loan amount too low");
        loans.openLoan(
            collateralAmount, highMinLoanAmount, defaultSwapParams(swapCashAmount), providerNFT, offerId
        );
    }

    function test_revert_closeLoan_notNFTOwnerOrKeeper() public {
        (uint loanId,,) = createAndCheckLoan();
        vm.startPrank(address(0xdead));
        vm.expectRevert("not NFT owner or allowed keeper");
        loans.closeLoan(loanId, defaultSwapParams(0));
    }

    function test_revert_closeLoan_nonExistentLoan() public {
        uint nonExistentLoanId = 999;
        vm.expectRevert(
            abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, nonExistentLoanId)
        );
        loans.closeLoan(nonExistentLoanId, defaultSwapParams(0));
    }

    function test_revert_closeLoan_noLoanForLoanID() public {
        uint offerId = createOfferAsProvider();
        vm.startPrank(user1);
        // create taker NFT not through loans
        (uint takerId,) = takerNFT.openPairedPosition(0, providerNFT, offerId);
        uint loanId = takerId;
        expectRevertERC721Nonexistent(loanId);
        loans.closeLoan(loanId, defaultSwapParams(0));
    }

    function test_revert_closeLoan_reentrnancy_alreadyClosed() public {
        (uint loanId,, uint loanAmount) = createAndCheckLoan();
        vm.startPrank(user1);
        cashAsset.approve(address(loans), loanAmount);

        // setup attack: reenter from closeLoan to closeLoan
        ReentrantCloser closer = new ReentrantCloser();
        closer.setParams(loans, takerNFT, loanId, user1);
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
        (uint loanId,,) = createAndCheckLoan();

        vm.startPrank(owner);
        // disable the default swapper
        loans.setSwapperAllowed(address(swapperUniV3), false, true);

        // not allowed
        vm.startPrank(user1);
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
        takerNFT.transferFrom(user1, provider, loanId);

        vm.startPrank(keeper);
        vm.expectRevert("not NFT owner or allowed keeper");
        loans.closeLoan(loanId, defaultSwapParams(0));

        // transfer back
        vm.startPrank(provider);
        takerNFT.transferFrom(provider, user1, loanId);

        // should work now
        vm.startPrank(user1);
        cashAsset.approve(address(loans), loanAmount);
        takerNFT.approve(address(loans), loanId);
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

        // expired
        (loanId,,) = createAndCheckLoan();
        skip(duration + 1);
        vm.expectRevert("loan expired");
        loans.unwrapAndCancelLoan(loanId);
    }
}

contract ReentrantCloser {
    address nftOwner;
    CollarTakerNFT nft;
    LoansNFT loans;
    uint id;

    function setParams(LoansNFT _loans, CollarTakerNFT _nft, uint _id, address _nftOwner) external {
        loans = _loans;
        nft = _nft;
        id = _id;
        nftOwner = _nftOwner;
    }

    fallback() external virtual {
        nft.transferFrom(nftOwner, address(this), id);
        loans.closeLoan(id, IBaseLoansNFT.SwapParams(0, address(loans.defaultSwapper()), ""));
    }
}
