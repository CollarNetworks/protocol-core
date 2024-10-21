// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

import "forge-std/Test.sol";
import { TestERC20 } from "../utils/TestERC20.sol";
import { BaseAssetPairTestSetup } from "./BaseAssetPairTestSetup.sol";
import { MockSwapperRouter } from "../utils/MockSwapRouter.sol";
import { SwapperArbitraryCall } from "../utils/SwapperArbitraryCall.sol";

import {
    LoansNFT, ILoansNFT, CollarProviderNFT, EscrowSupplierNFT, CollarTakerNFT
} from "../../src/LoansNFT.sol";
import { CollarTakerNFT } from "../../src/CollarTakerNFT.sol";
import { SwapperUniV3, ISwapper } from "../../src/SwapperUniV3.sol";

contract LoansTestBase is BaseAssetPairTestSetup {
    MockSwapperRouter mockSwapperRouter;
    SwapperUniV3 swapperUniV3;
    LoansNFT loans;
    EscrowSupplierNFT escrowNFT;

    EscrowSupplierNFT constant NO_ESCROW = EscrowSupplierNFT(address(0));

    // swapping
    address defaultSwapper;
    bytes extraData = "";
    uint24 swapFeeTier = 500;

    // swap amount * ltv
    uint minLoanAmount = swapCashAmount * (ltv / BIPS_100PCT);

    // escrow
    uint interestAPR = 500; // 5%
    uint maxGracePeriod = 7 days;
    uint lateFeeAPR = 10_000; // 100%

    // basic tests are without escrow
    bool openEscrowLoan = false;
    uint escrowOfferId;
    uint escrowFee;

    function setUp() public virtual override {
        super.setUp();

        // swapping deps
        mockSwapperRouter = new MockSwapperRouter();
        swapperUniV3 = new SwapperUniV3(address(mockSwapperRouter), swapFeeTier);
        vm.label(address(mockSwapperRouter), "MockSwapRouter");
        vm.label(address(swapperUniV3), "SwapperUniV3");
        // escrow
        escrowNFT = new EscrowSupplierNFT(owner, configHub, underlying, "Escrow", "Escrow");
        vm.label(address(escrowNFT), "Escrow");
        // loans
        loans = new LoansNFT(owner, takerNFT, "Loans", "Loans");
        vm.label(address(loans), "Loans");

        // config
        vm.startPrank(owner);
        // escrow
        configHub.setCanOpen(address(escrowNFT), true);
        escrowNFT.setLoansAllowed(address(loans), true);
        // loans
        configHub.setCanOpen(address(loans), true);
        loans.setContracts(rolls, providerNFT, escrowNFT);
        defaultSwapper = address(swapperUniV3);
        loans.setSwapperAllowed(defaultSwapper, true, true);
        vm.stopPrank();

        // mint dust (as in mintDustToContracts)
        cashAsset.mint(address(loans), 1);
        cashAsset.mint(address(mockSwapperRouter), 1);
        cashAsset.mint(defaultSwapper, 1);
        underlying.mint(address(loans), 1);
        underlying.mint(address(escrowNFT), 1);
        underlying.mint(address(mockSwapperRouter), 1);
        underlying.mint(defaultSwapper, 1);

        // dust NFTs
        dustPairedPositionNFTs(address(loans));
    }

    function prepareSwap(TestERC20 asset, uint amount) public {
        asset.mint(address(mockSwapperRouter), amount);
        mockSwapperRouter.setupSwap(amount, amount);
    }

    function prepareSwapToUnderlyingAtTWAPPrice() public returns (uint swapOut) {
        swapOut = underlyingAmount * 1e18 / twapPrice;
        prepareSwap(underlying, swapOut);
    }

    function prepareSwapToCashAtTWAPPrice() public returns (uint swapOut) {
        swapOut = underlyingAmount * twapPrice / 1e18;
        prepareSwap(cashAsset, swapOut);
    }

    function defaultSwapParams(uint minOut) internal view returns (ILoansNFT.SwapParams memory) {
        return ILoansNFT.SwapParams({ minAmountOut: minOut, swapper: defaultSwapper, extraData: extraData });
    }

    function createProviderOffer() internal returns (uint offerId) {
        startHoax(provider);
        cashAsset.approve(address(providerNFT), largeAmount);
        offerId = providerNFT.createOffer(callStrikePercent, largeAmount, ltv, duration, 0);
    }

    function maybeCreateEscrowOffer() internal {
        // calculates values for with or without escrow mode
        if (openEscrowLoan) {
            startHoax(supplier);
            underlying.approve(address(escrowNFT), largeAmount);
            escrowOfferId =
                escrowNFT.createOffer(largeAmount, duration, interestAPR, maxGracePeriod, lateFeeAPR, 0);
            escrowFee = escrowNFT.interestFee(escrowOfferId, underlyingAmount);
        } else {
            // reset to 0
            escrowOfferId = 0;
            escrowFee = 0;
        }
    }

    struct BalancesOpen {
        uint userUnderlying;
        uint userCash;
        uint feeRecipient;
        uint escrow;
    }

    struct Ids {
        uint loanId;
        uint providerId;
        uint nextEscrowId;
    }

    function createAndCheckLoan() internal returns (uint loanId, uint providerId, uint loanAmount) {
        uint providerOfferId = createProviderOffer();
        maybeCreateEscrowOffer();

        // TWAP price must be set for every block
        updatePrice();

        // convert at twap price
        uint swapOut = underlyingAmount * twapPrice / 1e18;
        prepareSwap(cashAsset, swapOut);

        startHoax(user1);
        underlying.approve(address(loans), underlyingAmount + escrowFee);

        BalancesOpen memory balances = BalancesOpen({
            userUnderlying: underlying.balanceOf(user1),
            userCash: cashAsset.balanceOf(user1),
            feeRecipient: cashAsset.balanceOf(protocolFeeRecipient),
            escrow: underlying.balanceOf(address(escrowNFT))
        });

        Ids memory ids = Ids({
            loanId: takerNFT.nextPositionId(),
            providerId: providerNFT.nextPositionId(),
            nextEscrowId: escrowNFT.nextEscrowId()
        });

        uint expectedLoanAmount = swapOut * ltv / BIPS_100PCT;
        uint expectedProviderLocked = swapOut * (callStrikePercent - BIPS_100PCT) / BIPS_100PCT;
        (uint expectedProtocolFee,) = providerNFT.protocolFee(expectedProviderLocked, duration);
        assertGt(expectedProtocolFee, 0); // ensure fee is expected

        ILoansNFT.SwapParams memory swapParams = defaultSwapParams(swapCashAmount);
        vm.expectEmit(address(loans));
        emit ILoansNFT.LoanOpened(ids.loanId, user1, providerOfferId, underlyingAmount, expectedLoanAmount);

        if (openEscrowLoan) {
            (loanId, providerId, loanAmount) = loans.openEscrowLoan(
                underlyingAmount, minLoanAmount, swapParams, providerOfferId, escrowOfferId
            );

            // sanity checks for test values
            assertGt(escrowOfferId, 0);
            assertGt(escrowFee, 0);
            // escrow effects
            _checkEscrowViews(ids.loanId, ids.nextEscrowId, escrowFee);
        } else {
            (loanId, providerId, loanAmount) =
                loans.openLoan(underlyingAmount, minLoanAmount, swapParams, providerOfferId);

            // sanity checks for test values
            assertEq(escrowOfferId, 0);
            assertEq(escrowFee, 0);
            // no escrow minted
            assertEq(escrowNFT.nextEscrowId(), ids.nextEscrowId);
        }

        // Check return values
        assertEq(loanId, ids.loanId);
        assertEq(providerId, ids.providerId);
        assertEq(loanAmount, expectedLoanAmount);

        // all struct views
        _checkStructViews(ids, underlyingAmount, swapOut, loanAmount);

        // Check balances
        assertEq(underlying.balanceOf(user1), balances.userUnderlying - underlyingAmount - escrowFee);
        assertEq(cashAsset.balanceOf(user1), balances.userCash + loanAmount);
        assertEq(cashAsset.balanceOf(protocolFeeRecipient), balances.feeRecipient + expectedProtocolFee);
        assertEq(underlying.balanceOf(address(escrowNFT)), balances.escrow + escrowFee);

        // Check NFT ownership
        assertEq(loans.ownerOf(loanId), user1);
        uint takerId = loanId;
        assertEq(takerNFT.ownerOf(takerId), address(loans));
        assertEq(providerNFT.ownerOf(providerId), provider);
    }

    function _checkStructViews(Ids memory ids, uint underlyingAmount, uint swapOut, uint loanAmount)
        internal
        view
    {
        // Check loan state
        ILoansNFT.Loan memory loan = loans.getLoan(ids.loanId);
        assertEq(loan.underlyingAmount, underlyingAmount);
        assertEq(loan.loanAmount, loanAmount);
        assertEq(loan.usesEscrow, openEscrowLoan);
        assertEq(address(loan.escrowNFT), address(openEscrowLoan ? escrowNFT : NO_ESCROW));
        assertEq(loan.escrowId, (openEscrowLoan ? ids.nextEscrowId : 0));

        // Check taker position
        uint expectedProviderLocked = swapOut * (callStrikePercent - BIPS_100PCT) / BIPS_100PCT;
        CollarTakerNFT.TakerPosition memory takerPosition = takerNFT.getPosition(ids.loanId);
        assertEq(address(takerPosition.providerNFT), address(providerNFT));
        assertEq(takerPosition.providerId, ids.providerId);
        assertEq(takerPosition.startPrice, twapPrice);
        assertEq(takerPosition.takerLocked, swapOut - loanAmount);
        assertEq(takerPosition.providerLocked, expectedProviderLocked);
        assertEq(takerPosition.duration, duration);
        assertEq(takerPosition.expiration, block.timestamp + duration);
        assertFalse(takerPosition.settled);
        assertEq(takerPosition.withdrawable, 0);

        // Check provider position
        CollarProviderNFT.ProviderPosition memory providerPosition = providerNFT.getPosition(ids.providerId);
        assertEq(providerPosition.duration, duration);
        assertEq(providerPosition.expiration, block.timestamp + duration);
        assertEq(providerPosition.providerLocked, expectedProviderLocked);
        assertEq(providerPosition.putStrikePercent, ltv);
        assertEq(providerPosition.callStrikePercent, callStrikePercent);
        assertFalse(providerPosition.settled);
        assertEq(providerPosition.withdrawable, 0);
    }

    function _checkEscrowViews(uint loanId, uint escrowId, uint expectedEscrowFee) internal view {
        assertEq(escrowNFT.ownerOf(escrowId), supplier);

        EscrowSupplierNFT.Escrow memory escrow = escrowNFT.getEscrow(escrowId);
        assertEq(escrow.offerId, escrowOfferId);
        assertEq(escrow.loans, address(loans));
        assertEq(escrow.loanId, loanId);
        assertEq(escrow.escrowed, underlyingAmount);
        assertEq(escrow.maxGracePeriod, maxGracePeriod);
        assertEq(escrow.lateFeeAPR, lateFeeAPR);
        assertEq(escrow.duration, duration);
        assertEq(escrow.expiration, block.timestamp + duration);
        assertEq(escrow.interestHeld, expectedEscrowFee);
        assertEq(escrow.released, false);
        assertEq(escrow.withdrawable, 0);
    }

    struct EscrowReleaseAmounts {
        uint toEscrow;
        uint fromEscrow;
        uint leftOver;
        uint lateFee;
    }

    function getEscrowReleaseValues(uint escrowId, uint swapOut)
        internal
        view
        returns (EscrowReleaseAmounts memory released)
    {
        uint owed;
        (owed, released.lateFee) = escrowNFT.currentOwed(escrowId);
        released.toEscrow = swapOut < owed ? swapOut : owed;
        released.leftOver = swapOut - released.toEscrow;
        (, released.fromEscrow,) = escrowNFT.previewRelease(escrowId, released.toEscrow);
    }

    struct BalancesClose {
        uint userUnderlying;
        uint userCash;
        uint escrow;
    }

    function closeAndCheckLoan(uint loanId, address caller, uint loanAmount, uint withdrawal, uint swapOut)
        internal
    {
        // TWAP price must be set for every block
        updatePrice();

        vm.startPrank(user1);
        // Approve loan contract to spend user's cash for repayment
        cashAsset.approve(address(loans), loanAmount);

        BalancesClose memory balances = BalancesClose({
            userUnderlying: underlying.balanceOf(user1),
            userCash: cashAsset.balanceOf(user1),
            escrow: underlying.balanceOf(address(escrowNFT))
        });
        ILoansNFT.Loan memory loan = loans.getLoan(loanId);
        EscrowReleaseAmounts memory released;
        if (loan.usesEscrow) {
            released = getEscrowReleaseValues(loan.escrowId, swapOut);
            assertGt(released.toEscrow, 0);
            assertGt(released.fromEscrow, 0);
        }

        // caller closes the loan
        vm.startPrank(caller);
        if (loan.usesEscrow) {
            // expect this only if escrow is used
            vm.expectEmit(address(loans));
            emit ILoansNFT.EscrowSettled(
                loan.escrowId, released.lateFee, released.toEscrow, released.fromEscrow, released.leftOver
            );
        }
        vm.expectEmit(address(loans));
        emit ILoansNFT.LoanClosed(loanId, caller, user1, loanAmount, loanAmount + withdrawal, swapOut);
        uint underlyingOut = loans.closeLoan(loanId, defaultSwapParams(0));

        // Check balances and return value
        assertEq(underlyingOut, swapOut + released.fromEscrow + released.leftOver - released.toEscrow);
        assertEq(underlying.balanceOf(user1), balances.userUnderlying + underlyingOut);
        assertEq(cashAsset.balanceOf(user1), balances.userCash - loanAmount);
        assertEq(
            underlying.balanceOf(address(escrowNFT)),
            balances.escrow + released.toEscrow - released.fromEscrow
        );

        // Check that the NFTs have been burned
        expectRevertERC721Nonexistent(loanId);
        loans.ownerOf(loanId);
        expectRevertERC721Nonexistent(loanId);
        uint takerId = loanId;
        takerNFT.ownerOf(takerId);

        // Try to close the loan again (should fail)
        expectRevertERC721Nonexistent(loanId);
        loans.closeLoan(loanId, defaultSwapParams(0));

        // check escrow released
        if (loan.usesEscrow) {
            assertTrue(escrowNFT.getEscrow(loans.getLoan(loanId).escrowId).released);
        }
    }

    function checkOpenCloseWithPriceChange(uint newPrice, uint putRatio, uint callRatio)
        public
        returns (uint)
    {
        (uint loanId,, uint loanAmount) = createAndCheckLoan();
        skip(duration);

        // update price
        twapPrice = newPrice;

        CollarTakerNFT.TakerPosition memory takerPosition = takerNFT.getPosition({ takerId: loanId });
        // calculate withdrawal amounts according to expected ratios
        uint withdrawal = takerPosition.takerLocked * putRatio / BIPS_100PCT
            + takerPosition.providerLocked * callRatio / BIPS_100PCT;
        // setup router output
        uint swapOut = prepareSwapToUnderlyingAtTWAPPrice();
        closeAndCheckLoan(loanId, user1, loanAmount, withdrawal, swapOut);
        return loanId;
    }

    function switchToArbitrarySwapper()
        internal
        returns (SwapperArbitraryCall arbCallSwapper, SwapperUniV3 newUniSwapper)
    {
        vm.startPrank(owner);
        // disable the old
        loans.setSwapperAllowed(address(swapperUniV3), false, false);
        // set the new
        arbCallSwapper = new SwapperArbitraryCall();
        defaultSwapper = address(arbCallSwapper);
        loans.setSwapperAllowed(address(arbCallSwapper), true, true);

        // swapper will call this other Uni swapper, because a swapper payload is easier to construct
        newUniSwapper = new SwapperUniV3(address(mockSwapperRouter), swapFeeTier);
    }

    function expectedLateFees(uint overdue) internal view returns (uint fee) {
        overdue = overdue > maxGracePeriod ? maxGracePeriod : overdue;
        fee = divUp(underlyingAmount * lateFeeAPR * overdue, BIPS_100PCT * 365 days);
    }

    function divUp(uint x, uint y) internal pure returns (uint) {
        return (x == 0) ? 0 : ((x - 1) / y) + 1; // divUp(x,y) = (x-1 / y) + 1
    }
}

contract LoansBasicEffectsTest is LoansTestBase {
    // tests

    function test_constructor() public {
        loans = new LoansNFT(owner, takerNFT, "", "");
        assertEq(address(loans.configHub()), address(configHub));
        assertEq(address(loans.takerNFT()), address(takerNFT));
        assertEq(address(loans.cashAsset()), address(cashAsset));
        assertEq(address(loans.underlying()), address(underlying));
        assertEq(loans.VERSION(), "0.2.0");
        assertEq(loans.owner(), owner);
        assertEq(loans.closingKeeper(), address(0));
        assertEq(address(loans.currentRolls()), address(0));
        assertEq(address(loans.currentProviderNFT()), address(0));
        assertEq(address(loans.currentEscrowNFT()), address(0));
        assertEq(address(loans.defaultSwapper()), address(0));
        assertEq(loans.name(), "");
        assertEq(loans.symbol(), "");
    }

    function test_openLoan() public {
        createAndCheckLoan();
    }

    function test_allowsClosingKeeper() public {
        startHoax(user1);
        assertFalse(loans.keeperApproved(user1));

        vm.expectEmit(address(loans));
        emit ILoansNFT.ClosingKeeperApproved(user1, true);
        loans.setKeeperApproved(true);
        assertTrue(loans.keeperApproved(user1));

        vm.expectEmit(address(loans));
        emit ILoansNFT.ClosingKeeperApproved(user1, false);
        loans.setKeeperApproved(false);
        assertFalse(loans.keeperApproved(user1));
    }

    function test_closeLoan_simple() public {
        (uint loanId,, uint loanAmount) = createAndCheckLoan();
        skip(duration);

        CollarTakerNFT.TakerPosition memory takerPosition = takerNFT.getPosition({ takerId: loanId });
        // withdrawal: no price change so only user locked (put locked)
        uint withdrawal = takerPosition.takerLocked;
        // setup router output
        uint swapOut = prepareSwapToUnderlyingAtTWAPPrice();
        closeAndCheckLoan(loanId, user1, loanAmount, withdrawal, swapOut);
    }

    function test_closeLoan_byKeeper() public {
        (uint loanId,, uint loanAmount) = createAndCheckLoan();
        skip(duration);

        // Set the keeper
        vm.startPrank(owner);
        loans.setKeeper(keeper);

        // Allow the keeper to close the loan
        vm.startPrank(user1);
        loans.setKeeperApproved(true);

        CollarTakerNFT.TakerPosition memory takerPosition = takerNFT.getPosition({ takerId: loanId });
        // withdrawal: no price change so only user locked (put locked)
        uint withdrawal = takerPosition.takerLocked;
        // setup router output
        uint swapOut = prepareSwapToUnderlyingAtTWAPPrice();
        closeAndCheckLoan(loanId, keeper, loanAmount, withdrawal, swapOut);
    }

    function test_closeLoan_priceUpToCall() public {
        uint newPrice = twapPrice * callStrikePercent / BIPS_100PCT;
        // price goes to call strike, withdrawal is 100% of pot (100% put + 100% call locked parts)
        checkOpenCloseWithPriceChange(newPrice, BIPS_100PCT, BIPS_100PCT);
    }

    function test_closeLoan_priceHalfUpToCall() public {
        uint delta = (callStrikePercent - BIPS_100PCT) / 2;
        uint newPrice = twapPrice * (BIPS_100PCT + delta) / BIPS_100PCT;
        // price goes to half way to call, withdrawal is 100% takerLocked + 50% of providerLocked
        checkOpenCloseWithPriceChange(newPrice, BIPS_100PCT, BIPS_100PCT / 2);
    }

    function test_closeLoan_priceOverCall() public {
        uint newPrice = twapPrice * (callStrikePercent + BIPS_100PCT) / BIPS_100PCT;
        // price goes over call, withdrawal is 100% takerLocked + 100% providerLocked
        checkOpenCloseWithPriceChange(newPrice, BIPS_100PCT, BIPS_100PCT);
    }

    function test_closeLoan_priceDownToPut() public {
        uint putStrikePercent = ltv;
        uint newPrice = twapPrice * putStrikePercent / BIPS_100PCT;
        // price goes to put strike, withdrawal is 0 (all gone to provider)
        checkOpenCloseWithPriceChange(newPrice, 0, 0);
    }

    function test_closeLoan_priceHalfDownToPut() public {
        uint putStrikePercent = ltv;
        uint delta = (BIPS_100PCT - putStrikePercent) / 2;
        uint newPrice = twapPrice * (BIPS_100PCT - delta) / BIPS_100PCT;
        // price goes half way to put strike, withdrawal is 50% of takerLocked and 0% of providerLocked
        checkOpenCloseWithPriceChange(newPrice, BIPS_100PCT / 2, 0);
    }

    function test_closeLoan_priceBelowPut() public {
        uint putStrikePercent = ltv;
        uint newPrice = twapPrice * (putStrikePercent - BIPS_100PCT / 10) / BIPS_100PCT;
        // price goes below put strike, withdrawal is 0% (all gone to provider)
        checkOpenCloseWithPriceChange(newPrice, 0, 0);
    }

    function test_openLoan_swapper_extraData() public {
        (SwapperArbitraryCall arbCallSwapper, SwapperUniV3 newUniSwapper) = switchToArbitrarySwapper();
        assertFalse(loans.allowedSwappers(address(swapperUniV3)));
        assertTrue(loans.allowedSwappers(address(arbCallSwapper)));

        // check that without extraData, open loan fails
        uint providerOfferId = createProviderOffer();
        maybeCreateEscrowOffer();
        prepareSwap(cashAsset, swapCashAmount);
        vm.startPrank(user1);
        underlying.approve(address(loans), underlyingAmount + escrowFee);
        vm.expectRevert(new bytes(0)); // failure to decode extraData
        if (openEscrowLoan) {
            // escrow loan
            loans.openEscrowLoan(underlyingAmount, 0, defaultSwapParams(0), providerOfferId, escrowOfferId);
        } else {
            // simple loan
            loans.openLoan(underlyingAmount, 0, defaultSwapParams(0), providerOfferId);
        }

        // call chain: loans -> arbitrary-swapper -> newUniSwapper -> mock-router.
        // by checking that this works we're ensuring that an arbitrary call swapper works, meaning that
        // extraData is passed correctly.
        // This is the extraData format that arbitrary swapper expects to unpack
        extraData = abi.encode(
            SwapperArbitraryCall.ArbitraryCall(
                address(newUniSwapper),
                abi.encodeCall(newUniSwapper.swap, (underlying, cashAsset, underlyingAmount, 0, ""))
            )
        );
        // open loan works now
        createAndCheckLoan();
    }

    function test_closeLoan_swapper_extraData() public {
        // create a closable loan
        (uint loanId,, uint loanAmount) = createAndCheckLoan();
        skip(duration);
        uint swapOut = prepareSwapToUnderlyingAtTWAPPrice();

        // switch swappers
        (SwapperArbitraryCall arbCallSwapper, SwapperUniV3 newUniSwapper) = switchToArbitrarySwapper();
        assertFalse(loans.allowedSwappers(address(swapperUniV3)));
        assertTrue(loans.allowedSwappers(address(arbCallSwapper)));

        // try with incorrect data (extraData is empty)
        vm.startPrank(user1);
        cashAsset.approve(address(loans), loanAmount);
        vm.expectRevert(new bytes(0)); // failure to decode extraData
        loans.closeLoan(loanId, defaultSwapParams(0));

        // price doesn't change so all takerLocked is withdrawn
        uint withdrawal = takerNFT.getPosition({ takerId: loanId }).takerLocked;
        // must know how much to swap
        uint expectedCashIn = loanAmount + withdrawal;
        // data for closing the loan (the swap back)
        // call chain: loans -> arbitrary-swapper -> newUniSwapper -> mock-router.
        extraData = abi.encode(
            SwapperArbitraryCall.ArbitraryCall(
                address(newUniSwapper),
                abi.encodeCall(newUniSwapper.swap, (cashAsset, underlying, expectedCashIn, 0, ""))
            )
        );
        // check close loan
        closeAndCheckLoan(loanId, user1, loanAmount, withdrawal, swapOut);
    }

    function test_unwrapAndCancelLoan_beforeExpiry() public {
        (uint loanId,,) = createAndCheckLoan();

        // taker owned by loans
        uint takerId = loanId;
        assertEq(takerNFT.ownerOf(takerId), address(loans));

        // user balance
        uint balanceBefore = underlying.balanceOf(user1);
        ILoansNFT.Loan memory loan = loans.getLoan(loanId);
        if (loan.usesEscrow) {
            // escrow unreleased
            assertEq(escrowNFT.ownerOf(loan.escrowId), supplier);
            assertEq(escrowNFT.getEscrow(loan.escrowId).released, false);
        }

        // release after half duration
        skip(duration / 2);

        // cancel
        vm.expectEmit(address(loans));
        emit ILoansNFT.LoanCancelled(loanId, address(user1));
        loans.unwrapAndCancelLoan(loanId);

        // NFT burned
        expectRevertERC721Nonexistent(loanId);
        loans.ownerOf(loanId);

        // taker NFT unwrapped
        assertEq(takerNFT.ownerOf(takerId), user1);

        // cannot cancel again
        expectRevertERC721Nonexistent(loanId);
        loans.unwrapAndCancelLoan(loanId);

        // escrow effects
        uint refund;
        if (loan.usesEscrow) {
            // escrow released
            assertEq(escrowNFT.getEscrow(loan.escrowId).released, true);
            // received refund for half a duration
            refund = escrowNFT.getEscrow(loan.escrowId).interestHeld / 2;
        }
        assertEq(underlying.balanceOf(user1), balanceBefore + refund);
    }

    function test_unwrapAndCancelLoan_afterExpiry() public {
        // cancel after expiry works for regular loans
        (uint loanId,,) = createAndCheckLoan();
        skip(duration + 1);

        if (!loans.getLoan(loanId).usesEscrow) {
            vm.expectEmit(address(loans));
            emit ILoansNFT.LoanCancelled(loanId, address(user1));
            loans.unwrapAndCancelLoan(loanId);
            // upwrapped
            assertEq(takerNFT.ownerOf({ tokenId: loanId }), user1);
            // cancelled
            expectRevertERC721Nonexistent(loanId);
            loans.ownerOf(loanId);
        } else {
            // also tested in reverts
            vm.expectRevert("loan expired");
            loans.unwrapAndCancelLoan(loanId);
        }
    }
}
