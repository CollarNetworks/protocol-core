// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

import "forge-std/Test.sol";
import { TestERC20 } from "../utils/TestERC20.sol";
import { BaseAssetPairTestSetup } from "./BaseAssetPairTestSetup.sol";
import { MockSwapperRouter } from "../utils/MockSwapRouter.sol";
import { SwapperArbitraryCall } from "../utils/SwapperArbitraryCall.sol";

import { LoansNFT, IBaseLoansNFT, BaseLoansNFT } from "../../src/LoansNFT.sol";
import { CollarTakerNFT } from "../../src/CollarTakerNFT.sol";
import { ShortProviderNFT } from "../../src/ShortProviderNFT.sol";
import { SwapperUniV3, ISwapper } from "../../src/SwapperUniV3.sol";

contract AllLoansTestSetup is BaseAssetPairTestSetup {
    MockSwapperRouter mockSwapperRouter;
    SwapperUniV3 swapperUniV3;

    address defaultSwapper;
    bytes extraData = "";

    uint24 swapFeeTier = 500;

    // swap amount * ltv
    uint minLoanAmount = swapCashAmount * (ltv / BIPS_100PCT);

    function setUp() public virtual override {
        super.setUp();

        mockSwapperRouter = new MockSwapperRouter();
        swapperUniV3 = new SwapperUniV3(address(mockSwapperRouter), swapFeeTier);
        vm.label(address(mockSwapperRouter), "MockSwapRouter");
        vm.label(address(swapperUniV3), "SwapperUniV3");
    }

    function prepareSwap(TestERC20 asset, uint amount) public {
        asset.mint(address(mockSwapperRouter), amount);
        mockSwapperRouter.setupSwap(amount, amount);
    }

    function prepareSwapToCollateralAtTWAPPrice() public returns (uint swapOut) {
        swapOut = collateralAmount * 1e18 / twapPrice;
        prepareSwap(collateralAsset, swapOut);
    }

    function prepareSwapToCashAtTWAPPrice() public returns (uint swapOut) {
        swapOut = collateralAmount * twapPrice / 1e18;
        prepareSwap(cashAsset, swapOut);
    }

    function defaultSwapParams(uint minOut) internal view returns (IBaseLoansNFT.SwapParams memory) {
        return
            IBaseLoansNFT.SwapParams({ minAmountOut: minOut, swapper: defaultSwapper, extraData: extraData });
    }

    function createOfferAsProvider() internal returns (uint offerId) {
        startHoax(provider);
        cashAsset.approve(address(providerNFT), largeAmount);
        offerId = providerNFT.createOffer(callStrikeDeviation, largeAmount, ltv, duration);
    }

    function switchToArbitrarySwapper(BaseLoansNFT baseLoans)
        internal
        returns (SwapperArbitraryCall arbCallSwapper, SwapperUniV3 newUniSwapper)
    {
        vm.startPrank(owner);
        // disable the old
        baseLoans.setSwapperAllowed(address(swapperUniV3), false, false);
        // set the new
        arbCallSwapper = new SwapperArbitraryCall();
        defaultSwapper = address(arbCallSwapper);
        baseLoans.setSwapperAllowed(address(arbCallSwapper), true, true);

        // swapper will call this other Uni swapper, because a swapper payload is easier to construct
        newUniSwapper = new SwapperUniV3(address(mockSwapperRouter), swapFeeTier);
    }
}

contract LoansTestBase is AllLoansTestSetup {
    LoansNFT loans;

    function setUp() public override {
        super.setUp();

        loans = new LoansNFT(owner, takerNFT, "Loans", "Loans");
        vm.label(address(loans), "Loans");

        // config
        vm.startPrank(owner);
        loans.setRollsContract(rolls);
        defaultSwapper = address(swapperUniV3);
        loans.setSwapperAllowed(defaultSwapper, true, true);
        vm.stopPrank();
    }

    function _baseLoans() internal returns (BaseLoansNFT baseLoans) {
        return BaseLoansNFT(address(loans));
    }

    struct Balances {
        uint userCollateral;
        uint userCash;
        uint feeRecipient;
    }

    function createAndCheckLoan() internal returns (uint loanId, uint providerId, uint loanAmount) {
        uint offerId = createOfferAsProvider();

        // TWAP price must be set for every block
        updatePrice();

        // convert at twap price
        uint swapOut = collateralAmount * twapPrice / 1e18;
        prepareSwap(cashAsset, swapOut);

        startHoax(user1);
        collateralAsset.approve(address(loans), collateralAmount);

        Balances memory balances = Balances({
            userCollateral: collateralAsset.balanceOf(user1),
            userCash: cashAsset.balanceOf(user1),
            feeRecipient: cashAsset.balanceOf(protocolFeeRecipient)
        });
        uint expectedLoanId = takerNFT.nextPositionId();
        uint nextProviderId = providerNFT.nextPositionId();
        uint expectedLoanAmount = swapOut * ltv / BIPS_100PCT;
        uint expectedProviderLocked = swapOut * (callStrikeDeviation - BIPS_100PCT) / BIPS_100PCT;
        (uint expectedFee,) = providerNFT.protocolFee(expectedProviderLocked, duration);
        assertGt(expectedFee, 0); // ensure fee is expected

        vm.expectEmit(address(loans));
        emit IBaseLoansNFT.LoanOpened(
            user1,
            address(providerNFT),
            offerId,
            collateralAmount,
            expectedLoanAmount,
            expectedLoanId,
            nextProviderId
        );

        (loanId, providerId, loanAmount) = loans.openLoan(
            collateralAmount, minLoanAmount, defaultSwapParams(swapCashAmount), providerNFT, offerId
        );

        // Check return values
        assertEq(loanId, expectedLoanId);
        assertEq(providerId, nextProviderId);
        assertEq(loanAmount, expectedLoanAmount);

        // Check balances
        assertEq(collateralAsset.balanceOf(user1), balances.userCollateral - collateralAmount);
        assertEq(cashAsset.balanceOf(user1), balances.userCash + loanAmount);
        assertEq(cashAsset.balanceOf(protocolFeeRecipient), balances.feeRecipient + expectedFee);

        // Check NFT ownership
        assertEq(loans.ownerOf(loanId), user1);
        uint takerId = loanId;
        assertEq(takerNFT.ownerOf(takerId), address(loans));
        assertEq(providerNFT.ownerOf(providerId), provider);

        // Check loan state
        LoansNFT.Loan memory loan = loans.getLoan(loanId);
        assertEq(loan.collateralAmount, collateralAmount);
        assertEq(loan.loanAmount, loanAmount);

        // Check taker position
        CollarTakerNFT.TakerPosition memory takerPosition = takerNFT.getPosition(loanId);
        assertEq(address(takerPosition.providerNFT), address(providerNFT));
        assertEq(takerPosition.providerPositionId, providerId);
        assertEq(takerPosition.initialPrice, twapPrice);
        assertEq(takerPosition.putLockedCash, swapOut - loanAmount);
        assertEq(takerPosition.callLockedCash, expectedProviderLocked);
        assertEq(takerPosition.duration, duration);
        assertEq(takerPosition.expiration, block.timestamp + duration);
        assertFalse(takerPosition.settled);
        assertEq(takerPosition.withdrawable, 0);

        // Check provider position
        ShortProviderNFT.ProviderPosition memory providerPosition = providerNFT.getPosition(providerId);
        assertEq(providerPosition.expiration, block.timestamp + duration);
        assertEq(providerPosition.principal, expectedProviderLocked);
        assertEq(providerPosition.putStrikeDeviation, ltv);
        assertEq(providerPosition.callStrikeDeviation, callStrikeDeviation);
        assertFalse(providerPosition.settled);
        assertEq(providerPosition.withdrawable, 0);
    }

    function closeAndCheckLoan(uint loanId, address caller, uint loanAmount, uint withdrawal, uint fromSwap)
        internal
    {
        // TWAP price must be set for every block
        updatePrice();

        vm.startPrank(user1);
        // Approve loan contract to spend user's cash for repayment
        cashAsset.approve(address(loans), loanAmount);

        uint initialCollateralBalance = collateralAsset.balanceOf(user1);
        uint initialCashBalance = cashAsset.balanceOf(user1);

        // caller closes the loan
        vm.startPrank(caller);
        vm.expectEmit(address(loans));
        emit IBaseLoansNFT.LoanClosed(loanId, caller, user1, loanAmount, loanAmount + withdrawal, fromSwap);
        uint collateralOut = loans.closeLoan(loanId, defaultSwapParams(0));

        // Check balances and return value
        assertEq(collateralOut, fromSwap);
        assertEq(collateralAsset.balanceOf(user1), initialCollateralBalance + collateralOut);
        assertEq(cashAsset.balanceOf(user1), initialCashBalance - loanAmount);

        // Check that the NFTs have been burned
        expectRevertERC721Nonexistent(loanId);
        loans.ownerOf(loanId);
        expectRevertERC721Nonexistent(loanId);
        uint takerId = loanId;
        takerNFT.ownerOf(takerId);

        // Try to close the loan again (should fail)
        expectRevertERC721Nonexistent(loanId);
        loans.closeLoan(loanId, defaultSwapParams(0));
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
        uint withdrawal = takerPosition.putLockedCash * putRatio / BIPS_100PCT
            + takerPosition.callLockedCash * callRatio / BIPS_100PCT;
        // setup router output
        uint swapOut = prepareSwapToCollateralAtTWAPPrice();
        closeAndCheckLoan(loanId, user1, loanAmount, withdrawal, swapOut);
        return loanId;
    }
}

contract LoansBasicEffectsTest is LoansTestBase {
    // tests

    function test_constructor() public {
        loans = new LoansNFT(owner, takerNFT, "", "");
        assertEq(address(loans.configHub()), address(configHub));
        assertEq(address(loans.takerNFT()), address(takerNFT));
        assertEq(address(loans.cashAsset()), address(cashAsset));
        assertEq(address(loans.collateralAsset()), address(collateralAsset));
        assertEq(loans.MAX_SWAP_TWAP_DEVIATION_BIPS(), 500);
        assertEq(loans.VERSION(), "0.2.0");
        assertEq(loans.owner(), owner);
        assertEq(loans.closingKeeper(), address(0));
        assertEq(address(loans.rollsContract()), address(0));
        assertEq(loans.name(), "");
        assertEq(loans.symbol(), "");
    }

    function test_openLoan() public {
        createAndCheckLoan();
    }

    function test_allowsClosingKeeper() public {
        startHoax(user1);
        assertFalse(loans.allowsClosingKeeper(user1));

        vm.expectEmit(address(loans));
        emit IBaseLoansNFT.ClosingKeeperAllowed(user1, true);
        loans.setKeeperAllowed(true);
        assertTrue(loans.allowsClosingKeeper(user1));

        vm.expectEmit(address(loans));
        emit IBaseLoansNFT.ClosingKeeperAllowed(user1, false);
        loans.setKeeperAllowed(false);
        assertFalse(loans.allowsClosingKeeper(user1));
    }

    function test_closeLoan_simple() public {
        (uint loanId,, uint loanAmount) = createAndCheckLoan();
        skip(duration);

        CollarTakerNFT.TakerPosition memory takerPosition = takerNFT.getPosition({ takerId: loanId });
        // withdrawal: no price change so only user locked (put locked)
        uint withdrawal = takerPosition.putLockedCash;
        // setup router output
        uint swapOut = prepareSwapToCollateralAtTWAPPrice();
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
        loans.setKeeperAllowed(true);

        CollarTakerNFT.TakerPosition memory takerPosition = takerNFT.getPosition({ takerId: loanId });
        // withdrawal: no price change so only user locked (put locked)
        uint withdrawal = takerPosition.putLockedCash;
        // setup router output
        uint swapOut = prepareSwapToCollateralAtTWAPPrice();
        closeAndCheckLoan(loanId, keeper, loanAmount, withdrawal, swapOut);
    }

    function test_closeLoan_priceUpToCall() public {
        uint newPrice = twapPrice * callStrikeDeviation / BIPS_100PCT;
        // price goes to call strike, withdrawal is 100% of pot (100% put + 100% call locked parts)
        checkOpenCloseWithPriceChange(newPrice, BIPS_100PCT, BIPS_100PCT);
    }

    function test_closeLoan_priceHalfUpToCall() public {
        uint delta = (callStrikeDeviation - BIPS_100PCT) / 2;
        uint newPrice = twapPrice * (BIPS_100PCT + delta) / BIPS_100PCT;
        // price goes to half way to call, withdrawal is 100% putLocked + 50% of callLocked
        checkOpenCloseWithPriceChange(newPrice, BIPS_100PCT, BIPS_100PCT / 2);
    }

    function test_closeLoan_priceOverCall() public {
        uint newPrice = twapPrice * (callStrikeDeviation + BIPS_100PCT) / BIPS_100PCT;
        // price goes over call, withdrawal is 100% putLocked + 100% callLocked
        checkOpenCloseWithPriceChange(newPrice, BIPS_100PCT, BIPS_100PCT);
    }

    function test_closeLoan_priceDownToPut() public {
        uint putStrikeDeviation = ltv;
        uint newPrice = twapPrice * putStrikeDeviation / BIPS_100PCT;
        // price goes to put strike, withdrawal is 0 (all gone to provider)
        checkOpenCloseWithPriceChange(newPrice, 0, 0);
    }

    function test_closeLoan_priceHalfDownToPut() public {
        uint putStrikeDeviation = ltv;
        uint delta = (BIPS_100PCT - putStrikeDeviation) / 2;
        uint newPrice = twapPrice * (BIPS_100PCT - delta) / BIPS_100PCT;
        // price goes half way to put strike, withdrawal is 50% of putLocked and 0% of callLocked
        checkOpenCloseWithPriceChange(newPrice, BIPS_100PCT / 2, 0);
    }

    function test_closeLoan_priceBelowPut() public {
        uint putStrikeDeviation = ltv;
        uint newPrice = twapPrice * (putStrikeDeviation - BIPS_100PCT / 10) / BIPS_100PCT;
        // price goes below put strike, withdrawal is 0% (all gone to provider)
        checkOpenCloseWithPriceChange(newPrice, 0, 0);
    }

    function test_openLoan_swapper_extraData() public {
        (SwapperArbitraryCall arbCallSwapper, SwapperUniV3 newUniSwapper) =
            switchToArbitrarySwapper(_baseLoans());
        assertFalse(loans.allowedSwappers(address(swapperUniV3)));
        assertTrue(loans.allowedSwappers(address(arbCallSwapper)));

        // check that without extraData, open loan fails
        uint offerId = createOfferAsProvider();
        prepareSwap(cashAsset, swapCashAmount);
        vm.startPrank(user1);
        collateralAsset.approve(address(loans), collateralAmount);
        vm.expectRevert(new bytes(0)); // failure to decode extraData
        loans.openLoan(collateralAmount, 0, defaultSwapParams(0), providerNFT, offerId);

        // call chain: loans -> arbitrary-swapper -> newUniSwapper -> mock-router.
        // by checking that this works we're ensuring that an arbitrary call swapper works, meaning that
        // extraData is passed correctly.
        // This is the extraData format that arbitrary swapper expects to unpack
        extraData = abi.encode(
            SwapperArbitraryCall.ArbitraryCall(
                address(newUniSwapper),
                abi.encodeCall(newUniSwapper.swap, (collateralAsset, cashAsset, collateralAmount, 0, ""))
            )
        );
        // open loan works now
        createAndCheckLoan();
    }

    function test_closeLoan_swapper_extraData() public {
        // create a closable loan
        (uint loanId,, uint loanAmount) = createAndCheckLoan();
        skip(duration);
        uint swapOut = prepareSwapToCollateralAtTWAPPrice();

        // switch swappers
        (SwapperArbitraryCall arbCallSwapper, SwapperUniV3 newUniSwapper) =
            switchToArbitrarySwapper(_baseLoans());
        assertFalse(loans.allowedSwappers(address(swapperUniV3)));
        assertTrue(loans.allowedSwappers(address(arbCallSwapper)));

        // try with incorrect data (extraData is empty)
        vm.startPrank(user1);
        cashAsset.approve(address(loans), loanAmount);
        vm.expectRevert(new bytes(0)); // failure to decode extraData
        loans.closeLoan(loanId, defaultSwapParams(0));

        // price doesn't change so all putLocked is withdrawn
        uint withdrawal = takerNFT.getPosition({ takerId: loanId }).putLockedCash;
        // must know how much to swap
        uint expectedCashIn = loanAmount + withdrawal;
        // data for closing the loan (the swap back)
        // call chain: loans -> arbitrary-swapper -> newUniSwapper -> mock-router.
        extraData = abi.encode(
            SwapperArbitraryCall.ArbitraryCall(
                address(newUniSwapper),
                abi.encodeCall(newUniSwapper.swap, (cashAsset, collateralAsset, expectedCashIn, 0, ""))
            )
        );
        // check close loan
        closeAndCheckLoan(loanId, user1, loanAmount, withdrawal, swapOut);
    }

    function test_unwrapAndCancelLoan() public {
        (uint loanId,,) = createAndCheckLoan();
        uint takerId = loanId;
        assertEq(takerNFT.ownerOf(takerId), address(loans));

        // cancel
        vm.expectEmit(address(loans));
        emit IBaseLoansNFT.LoanCancelled(loanId, address(user1));
        loans.unwrapAndCancelLoan(loanId);

        // NFT burned
        expectRevertERC721Nonexistent(loanId);
        loans.ownerOf(loanId);

        // taker NFT unwrapped
        assertEq(takerNFT.ownerOf(takerId), user1);

        // cannot cancel again
        expectRevertERC721Nonexistent(loanId);
        loans.unwrapAndCancelLoan(loanId);
    }
}
