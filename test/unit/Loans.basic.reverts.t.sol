// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

import "forge-std/Test.sol";
import { IERC721Errors } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { LoansNFT, ILoansNFT } from "../../src/LoansNFT.sol";
import { CollarTakerNFT } from "../../src/CollarTakerNFT.sol";
import { CollarProviderNFT } from "../../src/CollarProviderNFT.sol";
import { Rolls } from "../../src/Rolls.sol";

import { LoansTestBase, EscrowSupplierNFT } from "./Loans.basic.effects.t.sol";

contract LoansBasicRevertsTest is LoansTestBase {
    function openLoan(uint _col, uint _minLoan, uint _minSwap, uint _providerOfferId) internal {
        if (openEscrowLoan) {
            // uses last set escrowOfferId
            loans.openEscrowLoan(
                _col,
                _minLoan,
                defaultSwapParams(_minSwap),
                providerOffer(_providerOfferId),
                escrowOffer(escrowOfferId),
                escrowFees
            );
        } else {
            loans.openLoan(_col, _minLoan, defaultSwapParams(_minSwap), providerOffer(_providerOfferId));
        }
    }

    function test_revert_openLoan_params() public {
        maybeCreateEscrowOffer();

        vm.startPrank(user1);
        underlying.approve(address(loans), underlyingAmount + escrowFees);
        prepareDefaultSwapToCash();

        // 0 underlying
        vm.expectRevert("loans: invalid underlying amount");
        openLoan(0, 0, 0, 0);

        // unsupported loans
        setCanOpen(address(loans), false);
        vm.startPrank(user1);
        vm.expectRevert("loans: unsupported loans");
        openLoan(0, 0, 0, 0);

        // unsupported taker
        setCanOpen(address(loans), true);
        setCanOpen(address(takerNFT), false);
        vm.startPrank(user1);
        vm.expectRevert("loans: unsupported taker");
        openLoan(0, 0, 0, 0);

        // unsupported provider
        setCanOpen(address(takerNFT), true);
        setCanOpen(address(providerNFT), false);
        vm.startPrank(user1);
        vm.expectRevert("loans: unsupported provider");
        openLoan(underlyingAmount, 0, 0, 0);

        // bad offer
        setCanOpen(address(providerNFT), true);
        vm.startPrank(user1);
        uint invalidOfferId = 999;
        vm.expectRevert("taker: invalid offer");
        openLoan(underlyingAmount, minLoanAmount, 0, invalidOfferId);

        uint offerId = createProviderOffer();
        // not enough approval for underlying
        vm.startPrank(user1);
        underlying.approve(address(loans), underlyingAmount);
        expectRevertERC20Allowance(address(loans), underlyingAmount, underlyingAmount + 1 + escrowFees);
        openLoan(underlyingAmount + 1, minLoanAmount, 0, offerId);
    }

    function test_revert_openLoan_swaps_router() public {
        uint offerId = createProviderOffer();
        maybeCreateEscrowOffer();
        prepareSwap(cashAsset, swapCashAmount);

        vm.startPrank(user1);
        underlying.approve(address(loans), underlyingAmount + escrowFees);

        // balance mismatch
        mockSwapperRouter.setupSwap(swapCashAmount - 1, swapCashAmount);
        vm.expectRevert("SwapperUniV3: balance update mismatch");
        openLoan(underlyingAmount, minLoanAmount, swapCashAmount, offerId);

        // slippage params
        mockSwapperRouter.setupSwap(swapCashAmount, swapCashAmount);
        vm.expectRevert("SwapperUniV3: slippage exceeded");
        openLoan(underlyingAmount, minLoanAmount, swapCashAmount + 1, offerId);

        // deviation vs. oracle
        prepareSwap(cashAsset, swapCashAmount / 2);
        vm.expectRevert("swap and oracle price too different");
        openLoan(underlyingAmount, minLoanAmount, 0, offerId);
    }

    function test_revert_openLoan_swapper_not_allowed() public {
        maybeCreateEscrowOffer();

        vm.startPrank(owner);
        // disable the default swapper
        loans.setSwapperAllowed(address(defaultSwapper), false, true);

        // not allowed
        startHoax(user1);
        underlying.approve(address(loans), underlyingAmount + escrowFees);
        vm.expectRevert("loans: swapper not allowed");
        openLoan(underlyingAmount, minLoanAmount, 0, 0);
    }

    function test_revert_openLoan_swaps_swapper() public {
        vm.startPrank(owner);
        // set the mock as the default swapper (instead of router)
        defaultSwapper = address(mockSwapperRouter);
        loans.setSwapperAllowed(defaultSwapper, true, true);
        // disable the default swapper to be sure
        loans.setSwapperAllowed(address(swapperUniV3), false, false);

        uint offerId = createProviderOffer();
        maybeCreateEscrowOffer();
        prepareSwap(cashAsset, swapCashAmount);

        vm.startPrank(user1);
        underlying.approve(address(loans), underlyingAmount + escrowFees);

        // balance mismatch
        mockSwapperRouter.setupSwap(swapCashAmount - 1, swapCashAmount);
        vm.expectRevert("loans: balance update mismatch");
        openLoan(underlyingAmount, minLoanAmount, swapCashAmount, offerId);

        // slippage params
        mockSwapperRouter.setupSwap(swapCashAmount, swapCashAmount);
        vm.expectRevert("loans: slippage exceeded");
        openLoan(underlyingAmount, minLoanAmount, swapCashAmount + 1, offerId);
    }

    function test_revert_openLoan_insufficientLoanAmount() public {
        uint offerId = createProviderOffer();
        maybeCreateEscrowOffer();
        uint swapOut = prepareDefaultSwapToCash();

        vm.startPrank(user1);
        underlying.approve(address(loans), underlyingAmount + escrowFees);

        uint highMinLoanAmount = (swapOut * ltv / BIPS_100PCT) + 1; // 1 wei more than ltv
        vm.expectRevert("loans: loan amount too low");
        openLoan(underlyingAmount, highMinLoanAmount, swapCashAmount, offerId);
    }

    function test_revert_openLoan_IdTaken() public {
        (uint loanId,, uint loanAmount) = createAndCheckLoan();
        uint offerId = providerNFT.nextOfferId() - 1;
        uint takerLocked = swapCashAmount - loanAmount;

        // prep again
        prepareDefaultSwapToCash();
        underlying.approve(address(loans), underlyingAmount + escrowFees);

        vm.mockCall(
            address(takerNFT),
            abi.encodeWithSelector(takerNFT.openPairedPosition.selector, takerLocked, providerNFT, offerId),
            abi.encode(loanId, 0, 0, 0) // returns old taker ID
        );
        vm.expectRevert("loans: loanId taken");
        openLoan(underlyingAmount, 0, swapCashAmount, offerId);
    }

    function test_revert_closeLoan_notNFTOwnerOrKeeper() public {
        (uint loanId,,) = createAndCheckLoan();
        vm.startPrank(address(0xdead));
        vm.expectRevert("loans: not NFT owner or allowed keeper");
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
        uint loanId = checkOpenCloseWithPriceChange(oraclePrice, BIPS_100PCT, 0);
        expectRevertERC721Nonexistent(loanId);
        loans.closeLoan(loanId, defaultSwapParams(0));
    }

    function test_revert_closeLoan_insufficientRepaymentAllowance() public {
        (uint loanId,, uint loanAmount) = createAndCheckLoan();
        skip(duration);
        vm.startPrank(user1);

        cashAsset.approve(address(loans), loanAmount - 1);
        expectRevertERC20Allowance(address(loans), loanAmount - 1, loanAmount);
        loans.closeLoan(loanId, defaultSwapParams(0));
    }

    function test_revert_closeLoan_beforeExpiration() public {
        (uint loanId,, uint loanAmount) = createAndCheckLoan();
        skip(duration - 1);

        vm.startPrank(user1);
        cashAsset.approve(address(loans), loanAmount);

        vm.expectRevert("taker: not expired");
        loans.closeLoan(loanId, defaultSwapParams(0));
    }

    function test_revert_closeLoan_swaps_router() public {
        (uint loanId,, uint loanAmount) = createAndCheckLoan();
        skip(duration);
        vm.startPrank(user1);
        cashAsset.approve(address(loans), loanAmount);
        prepareSwap(underlying, underlyingAmount);

        vm.expectRevert("SwapperUniV3: slippage exceeded");
        loans.closeLoan(loanId, defaultSwapParams(underlyingAmount + 1));

        mockSwapperRouter.setupSwap(underlyingAmount - 1, underlyingAmount);
        vm.expectRevert("SwapperUniV3: balance update mismatch");
        loans.closeLoan(loanId, defaultSwapParams(underlyingAmount));
    }

    function test_revert_closeLoan_swaps_swapper() public {
        // set the mock as the default swapper (instead of Uni swapper)
        vm.startPrank(owner);
        defaultSwapper = address(mockSwapperRouter);
        loans.setSwapperAllowed(defaultSwapper, true, true);
        // disable the uni swapper to be sure
        loans.setSwapperAllowed(address(swapperUniV3), false, false);

        (uint loanId,, uint loanAmount) = createAndCheckLoan();
        skip(duration);
        vm.startPrank(user1);
        cashAsset.approve(address(loans), loanAmount);
        prepareSwap(underlying, underlyingAmount);

        vm.expectRevert("loans: slippage exceeded");
        loans.closeLoan(loanId, defaultSwapParams(underlyingAmount + 1));

        mockSwapperRouter.setupSwap(underlyingAmount - 1, underlyingAmount);
        vm.expectRevert("loans: balance update mismatch");
        loans.closeLoan(loanId, defaultSwapParams(underlyingAmount));
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
        vm.expectRevert("loans: swapper not allowed");
        loans.closeLoan(loanId, defaultSwapParams(underlyingAmount));
    }

    function test_revert_closeLoan_keeperNotAllowed() public {
        (uint loanId,, uint loanAmount) = createAndCheckLoan();
        skip(duration);

        vm.startPrank(keeper);
        // keeper was not allowed by user
        vm.expectRevert("loans: not NFT owner or allowed keeper");
        loans.closeLoan(loanId, defaultSwapParams(0));

        vm.startPrank(user1);
        loans.setKeeperFor(0, keeper);
        // approved wrong loan
        vm.startPrank(keeper);
        vm.expectRevert("loans: not NFT owner or allowed keeper");
        loans.closeLoan(loanId, defaultSwapParams(0));

        // correct loan
        vm.startPrank(user1);
        loans.setKeeperFor(loanId, keeper);

        vm.startPrank(user1);
        // transfer invalidates approval
        loans.transferFrom(user1, provider, loanId);

        vm.startPrank(keeper);
        vm.expectRevert("loans: not NFT owner or allowed keeper");
        loans.closeLoan(loanId, defaultSwapParams(0));

        // transfer back
        vm.startPrank(provider);
        loans.transferFrom(provider, user1, loanId);
        // not keeper cannot call (provider is calling)
        vm.expectRevert("loans: not NFT owner or allowed keeper");
        loans.closeLoan(loanId, defaultSwapParams(0));

        // should work now
        vm.startPrank(user1);
        cashAsset.approve(address(loans), loanAmount);
        prepareSwap(underlying, underlyingAmount);
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
        vm.expectRevert("loans: not NFT owner");
        loans.unwrapAndCancelLoan(loanId);

        vm.startPrank(user1);
        // Close the loan normally
        skip(duration);
        uint swapOut = prepareDefaultSwapToUnderlying();
        closeAndCheckLoan(
            loanId, user1, loans.getLoan(loanId).loanAmount, takerNFT.getPosition(loanId).takerLocked, swapOut
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
