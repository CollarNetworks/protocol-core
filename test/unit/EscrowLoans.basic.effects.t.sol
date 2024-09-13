// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

import "forge-std/Test.sol";
import { TestERC20 } from "../utils/TestERC20.sol";
import { AllLoansTestSetup, IBaseLoansNFT } from "./Loans.basic.effects.t.sol";
import { MockSwapperRouter } from "../utils/MockSwapRouter.sol";
import { SwapperArbitraryCall } from "../utils/SwapperArbitraryCall.sol";

import { EscrowLoansNFT, IEscrowLoansNFT } from "../../src/EscrowLoansNFT.sol";
import { CollarTakerNFT } from "../../src/CollarTakerNFT.sol";
import { ShortProviderNFT } from "../../src/ShortProviderNFT.sol";
import { EscrowSupplierNFT } from "../../src/EscrowSupplierNFT.sol";
import { SwapperUniV3, ISwapper } from "../../src/SwapperUniV3.sol";

contract EscrowLoansTestBase is AllLoansTestSetup {
    EscrowSupplierNFT escrowNFT;
    EscrowLoansNFT eLoans;

    uint interestAPR = 500; // 5%
    uint gracePeriod = 7 days;
    uint lateFeeAPR = 10_000; // 100%
    uint escrowFee = 1 ether;

    function setUp() public override {
        super.setUp();

        escrowNFT = new EscrowSupplierNFT(owner, configHub, collateralAsset, "EscrowNFT", "EscrowNFT");
        eLoans = new EscrowLoansNFT(owner, takerNFT, escrowNFT, "EscrowLoans", "EscrowLoans");
        vm.label(address(escrowNFT), "EscrowNFT");
        vm.label(address(eLoans), "EscrowLoansNFT");

        // config
        defaultSwapper = address(swapperUniV3);
        vm.startPrank(owner);
        configHub.setCanOpen(address(eLoans), true);
        configHub.setCanOpen(address(escrowNFT), true);
        eLoans.setRollsContract(rolls);
        eLoans.setSwapperAllowed(defaultSwapper, true, true);
        escrowNFT.setLoansAllowed(address(eLoans), true);
        vm.stopPrank();
    }

    function createEscrowOffer() internal returns (uint offerId) {
        startHoax(supplier);
        collateralAsset.approve(address(escrowNFT), largeAmount);
        offerId = escrowNFT.createOffer(largeAmount, duration, interestAPR, gracePeriod, lateFeeAPR);
    }

    struct BalancesOpen {
        uint userCollateral;
        uint userCash;
        uint feeRecipient;
        uint escrow;
    }

    struct Ids {
        uint loanId;
        uint providerId;
        uint escrowId;
    }

    function createAndCheckLoan()
        internal
        returns (uint loanId, uint providerId, uint escrowId, uint loanAmount)
    {
        uint shortOfferId = createOfferAsProvider();
        uint escrowOfferId = createEscrowOffer();

        // TWAP price must be set for every block
        updatePrice();

        // convert at twap price
        uint swapOut = collateralAmount * twapPrice / 1e18;
        prepareSwap(cashAsset, swapOut);

        startHoax(user1);
        collateralAsset.approve(address(eLoans), collateralAmount + escrowFee);

        BalancesOpen memory balances = BalancesOpen({
            userCollateral: collateralAsset.balanceOf(user1),
            userCash: cashAsset.balanceOf(user1),
            feeRecipient: cashAsset.balanceOf(protocolFeeRecipient),
            escrow: collateralAsset.balanceOf(address(escrowNFT))
        });

        Ids memory ids = Ids({
            loanId: takerNFT.nextPositionId(),
            providerId: providerNFT.nextPositionId(),
            escrowId: escrowNFT.nextEscrowId()
        });

        uint expectedLoanAmount = swapOut * ltv / BIPS_100PCT;
        uint expectedProviderLocked = swapOut * (callStrikeDeviation - BIPS_100PCT) / BIPS_100PCT;
        (uint expectedProtocolFee,) = providerNFT.protocolFee(expectedProviderLocked, duration);
        assertGt(expectedProtocolFee, 0); // ensure fee is expected

        vm.expectEmit(address(eLoans));
        emit IBaseLoansNFT.LoanOpened(
            user1,
            address(providerNFT),
            shortOfferId,
            collateralAmount,
            expectedLoanAmount,
            ids.loanId,
            ids.providerId
        );

        (loanId, providerId, escrowId, loanAmount) = eLoans.openLoan(
            IEscrowLoansNFT.OpenLoanParams({
                collateralAmount: collateralAmount,
                minLoanAmount: minLoanAmount,
                swapParams: defaultSwapParams(swapCashAmount),
                providerNFT: providerNFT,
                shortOffer: shortOfferId,
                escrowOffer: escrowOfferId,
                escrowFee: escrowFee
            })
        );

        // Check return values
        assertEq(loanId, ids.loanId);
        assertEq(providerId, ids.providerId);
        assertEq(escrowId, ids.escrowId);
        assertEq(loanAmount, expectedLoanAmount);

        // escrowId view
        assertEq(eLoans.loanIdToEscrowId(loanId), escrowId);

        // Check balances
        assertEq(collateralAsset.balanceOf(user1), balances.userCollateral - collateralAmount - escrowFee);
        assertEq(cashAsset.balanceOf(user1), balances.userCash + loanAmount);
        assertEq(cashAsset.balanceOf(protocolFeeRecipient), balances.feeRecipient + expectedProtocolFee);
        assertEq(collateralAsset.balanceOf(address(escrowNFT)), balances.escrow + escrowFee);

        // Check NFT ownership
        assertEq(eLoans.ownerOf(loanId), user1);
        uint takerId = loanId;
        assertEq(takerNFT.ownerOf(takerId), address(eLoans));
        assertEq(providerNFT.ownerOf(providerId), provider);
        assertEq(escrowNFT.ownerOf(escrowId), supplier);

        _checkStructViews(loanId, collateralAmount, providerId, escrowId, swapOut, loanAmount);
    }

    function _checkStructViews(
        uint loanId,
        uint collateralAmount,
        uint providerId,
        uint escrowId,
        uint swapOut,
        uint loanAmount
    ) internal view {
        // Check loan state
        IBaseLoansNFT.Loan memory loan = eLoans.getLoan(loanId);
        assertEq(loan.collateralAmount, collateralAmount);
        assertEq(loan.loanAmount, loanAmount);

        // Check taker position
        uint expectedProviderLocked = swapOut * (callStrikeDeviation - BIPS_100PCT) / BIPS_100PCT;
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

        // Check escrow position
        EscrowSupplierNFT.Escrow memory escrow = escrowNFT.getEscrow(escrowId);
        assertEq(escrow.loans, address(eLoans));
        assertEq(escrow.loanId, loanId);
        assertEq(escrow.escrowed, collateralAmount);
        assertEq(escrow.gracePeriod, gracePeriod);
        assertEq(escrow.lateFeeAPR, lateFeeAPR);
        assertEq(escrow.duration, duration);
        assertEq(escrow.expiration, block.timestamp + duration);
        assertEq(escrow.interestHeld, escrowFee);
        assertEq(escrow.released, false);
        assertEq(escrow.withdrawable, 0);
    }

    struct EscrowReleaseAmounts {
        uint toEscrow;
        uint fromEscrow;
        uint leftOver;
    }

    function getEscrowReleaseValues(uint escrowId, uint collateral)
        internal
        view
        returns (EscrowReleaseAmounts memory released)
    {
        (uint lateFee, uint escrowed) = escrowNFT.lateFees(escrowId);
        uint owed = lateFee + escrowed;
        released.toEscrow = collateral < owed ? collateral : owed;
        released.leftOver = collateral - released.toEscrow;
        (, released.fromEscrow,) = escrowNFT.previewRelease(escrowId, released.toEscrow);
    }

    struct BalancesClose {
        uint userCollateral;
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
        cashAsset.approve(address(eLoans), loanAmount);

        BalancesClose memory balances = BalancesClose({
            userCollateral: collateralAsset.balanceOf(user1),
            userCash: cashAsset.balanceOf(user1),
            escrow: collateralAsset.balanceOf(address(escrowNFT))
        });
        uint escrowId = eLoans.loanIdToEscrowId(loanId);
        EscrowReleaseAmounts memory released = getEscrowReleaseValues(escrowId, swapOut);

        // caller closes the loan
        vm.startPrank(caller);
        vm.expectEmit(address(eLoans));
        emit IBaseLoansNFT.LoanClosed(loanId, caller, user1, loanAmount, loanAmount + withdrawal, swapOut);
        vm.expectEmit(address(eLoans));
        emit IEscrowLoansNFT.EscrowSettled(
            escrowId, released.toEscrow, released.fromEscrow, released.leftOver
        );
        uint collateralOut = eLoans.closeLoan(loanId, defaultSwapParams(0));

        // Check balances and return value
        assertEq(collateralOut, swapOut + released.fromEscrow + released.leftOver - released.toEscrow);
        assertEq(collateralAsset.balanceOf(user1), balances.userCollateral + collateralOut);
        assertEq(cashAsset.balanceOf(user1), balances.userCash - loanAmount);
        assertEq(
            collateralAsset.balanceOf(address(escrowNFT)),
            balances.escrow + released.toEscrow - released.fromEscrow
        );

        // Check that the NFTs have been burned
        expectRevertERC721Nonexistent(loanId);
        eLoans.ownerOf(loanId);
        expectRevertERC721Nonexistent(loanId);
        uint takerId = loanId;
        takerNFT.ownerOf(takerId);

        // Try to close the loan again (should fail)
        expectRevertERC721Nonexistent(loanId);
        eLoans.closeLoan(loanId, defaultSwapParams(0));
    }

    function checkOpenCloseWithPriceChange(uint newPrice, uint putRatio, uint callRatio)
        public
        returns (uint)
    {
        (uint loanId,,, uint loanAmount) = createAndCheckLoan();
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

contract EscrowLoansBasicEffectsTest is EscrowLoansTestBase {
    function switchToArbitrarySwapper()
        internal
        returns (SwapperArbitraryCall arbCallSwapper, SwapperUniV3 newUniSwapper)
    {
        vm.startPrank(owner);
        // disable the old
        eLoans.setSwapperAllowed(address(swapperUniV3), false, false);
        // set the new
        arbCallSwapper = new SwapperArbitraryCall();
        defaultSwapper = address(arbCallSwapper);
        eLoans.setSwapperAllowed(address(arbCallSwapper), true, true);

        // swapper will call this other Uni swapper, because a swapper payload is easier to construct
        newUniSwapper = new SwapperUniV3(address(mockSwapperRouter), swapFeeTier);
    }

    // tests

    function test_constructor() public {
        eLoans = new EscrowLoansNFT(owner, takerNFT, escrowNFT, "", "");
        assertEq(address(eLoans.configHub()), address(configHub));
        assertEq(address(eLoans.takerNFT()), address(takerNFT));
        assertEq(address(eLoans.escrowNFT()), address(escrowNFT));
        assertEq(address(eLoans.cashAsset()), address(cashAsset));
        assertEq(address(eLoans.collateralAsset()), address(collateralAsset));
        assertEq(eLoans.MAX_SWAP_TWAP_DEVIATION_BIPS(), 500);
        assertEq(eLoans.VERSION(), "0.2.0");
        assertEq(eLoans.owner(), owner);
        assertEq(eLoans.closingKeeper(), address(0));
        assertEq(address(eLoans.rollsContract()), address(0));
        assertEq(eLoans.name(), "");
        assertEq(eLoans.symbol(), "");
    }

    function test_openLoan() public {
        createAndCheckLoan();
    }

    function test_allowsClosingKeeper() public {
        startHoax(user1);
        assertFalse(eLoans.allowsClosingKeeper(user1));

        vm.expectEmit(address(eLoans));
        emit IBaseLoansNFT.ClosingKeeperAllowed(user1, true);
        eLoans.setKeeperAllowed(true);
        assertTrue(eLoans.allowsClosingKeeper(user1));

        vm.expectEmit(address(eLoans));
        emit IBaseLoansNFT.ClosingKeeperAllowed(user1, false);
        eLoans.setKeeperAllowed(false);
        assertFalse(eLoans.allowsClosingKeeper(user1));
    }

    function test_closeLoan_simple() public {
        (uint loanId,,, uint loanAmount) = createAndCheckLoan();
        skip(duration);

        CollarTakerNFT.TakerPosition memory takerPosition = takerNFT.getPosition({ takerId: loanId });
        // withdrawal: no price change so only user locked (put locked)
        uint withdrawal = takerPosition.putLockedCash;
        // setup router output
        uint swapOut = prepareSwapToCollateralAtTWAPPrice();
        closeAndCheckLoan(loanId, user1, loanAmount, withdrawal, swapOut);
    }

    function test_closeLoan_byKeeper() public {
        (uint loanId,,, uint loanAmount) = createAndCheckLoan();
        skip(duration);

        // Set the keeper
        vm.startPrank(owner);
        eLoans.setKeeper(keeper);

        // Allow the keeper to close the loan
        vm.startPrank(user1);
        eLoans.setKeeperAllowed(true);

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
        (SwapperArbitraryCall arbCallSwapper, SwapperUniV3 newUniSwapper) = switchToArbitrarySwapper();
        assertFalse(eLoans.allowedSwappers(address(swapperUniV3)));
        assertTrue(eLoans.allowedSwappers(address(arbCallSwapper)));

        // check that without extraData, open loan fails
        uint shortOfferId = createOfferAsProvider();
        uint escrowOfferId = createEscrowOffer();
        prepareSwap(cashAsset, swapCashAmount);
        vm.startPrank(user1);
        collateralAsset.approve(address(eLoans), collateralAmount + escrowFee);
        vm.expectRevert(new bytes(0)); // failure to decode extraData
        eLoans.openLoan(
            IEscrowLoansNFT.OpenLoanParams({
                collateralAmount: collateralAmount,
                minLoanAmount: 0,
                swapParams: defaultSwapParams(0),
                providerNFT: providerNFT,
                shortOffer: shortOfferId,
                escrowOffer: escrowOfferId,
                escrowFee: escrowFee
            })
        );

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
        (uint loanId,,, uint loanAmount) = createAndCheckLoan();
        skip(duration);
        uint swapOut = prepareSwapToCollateralAtTWAPPrice();

        // switch swappers
        (SwapperArbitraryCall arbCallSwapper, SwapperUniV3 newUniSwapper) = switchToArbitrarySwapper();
        assertFalse(eLoans.allowedSwappers(address(swapperUniV3)));
        assertTrue(eLoans.allowedSwappers(address(arbCallSwapper)));

        // try with incorrect data (extraData is empty)
        vm.startPrank(user1);
        cashAsset.approve(address(eLoans), loanAmount);
        vm.expectRevert(new bytes(0)); // failure to decode extraData
        eLoans.closeLoan(loanId, defaultSwapParams(0));

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

    //    function test_unwrapAndCancelLoan() public {
    //        (uint loanId,,,) = createAndCheckLoan();
    //        uint takerId = loanId;
    //        assertEq(takerNFT.ownerOf(takerId), address(eLoans));
    //
    //        // cancel
    //        vm.expectEmit(address(eLoans));
    //        emit IBaseLoansNFT.LoanCancelled(loanId, address(user1));
    //        eLoans.unwrapAndCancelLoan(loanId);
    //
    //        // NFT burned
    //        expectRevertERC721Nonexistent(loanId);
    //        eLoans.ownerOf(loanId);
    //
    //        // taker NFT unwrapped
    //        assertEq(takerNFT.ownerOf(takerId), user1);
    //
    //        // cannot cancel again
    //        expectRevertERC721Nonexistent(loanId);
    //        eLoans.unwrapAndCancelLoan(loanId);
    //    }
}
