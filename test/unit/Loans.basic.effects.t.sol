// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

import "forge-std/Test.sol";
import { Strings } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

import { TestERC20 } from "../utils/TestERC20.sol";
import { BaseAssetPairTestSetup } from "./BaseAssetPairTestSetup.sol";
import { MockSwapperRouter } from "../utils/MockSwapRouter.sol";
import { SwapperArbitraryCall } from "../utils/SwapperArbitraryCall.sol";

import {
    LoansNFT,
    ILoansNFT,
    CollarProviderNFT,
    EscrowSupplierNFT,
    CollarTakerNFT,
    IEscrowSupplierNFT
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
    uint gracePeriod = 7 days;
    uint lateFeeAPR = 10_000; // 100%

    // basic tests are without escrow
    bool openEscrowLoan = false;
    uint escrowOfferId;
    uint escrowFees;

    function setUp() public virtual override {
        super.setUp();

        // swapping deps
        mockSwapperRouter = new MockSwapperRouter();
        swapperUniV3 = new SwapperUniV3(address(mockSwapperRouter), swapFeeTier);
        vm.label(address(mockSwapperRouter), "MockSwapRouter");
        vm.label(address(swapperUniV3), "SwapperUniV3");
        // escrow
        escrowNFT = new EscrowSupplierNFT(configHub, underlying, "Escrow", "Escrow");
        vm.label(address(escrowNFT), "Escrow");
        // loans
        loans = new LoansNFT(takerNFT, "Loans", "Loans");
        vm.label(address(loans), "Loans");

        // config
        // escrow
        setCanOpenSingle(address(escrowNFT), true);
        vm.startPrank(owner);
        configHub.setCanOpenPair(address(underlying), address(escrowNFT), address(loans), true);
        // loans
        setCanOpen(address(loans), true);
        setCanOpen(address(rolls), true);
        defaultSwapper = address(swapperUniV3);
        vm.startPrank(owner);
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

    function prepareDefaultSwapToUnderlying() public returns (uint swapOut) {
        swapOut = underlyingAmount * pow10(cashDecimals) / oraclePrice;
        prepareSwap(underlying, swapOut);
    }

    function prepareDefaultSwapToCash() public returns (uint swapOut) {
        swapOut = underlyingAmount * oraclePrice / 1e18;
        prepareSwap(cashAsset, swapOut);
    }

    function defaultSwapParams(uint minOut) internal view returns (ILoansNFT.SwapParams memory) {
        return ILoansNFT.SwapParams({ minAmountOut: minOut, swapper: defaultSwapper, extraData: extraData });
    }

    function providerOffer(uint offerId) internal view returns (ILoansNFT.ProviderOffer memory) {
        return ILoansNFT.ProviderOffer(providerNFT, offerId);
    }

    function escrowOffer(uint offerId) internal view returns (ILoansNFT.EscrowOffer memory) {
        return ILoansNFT.EscrowOffer(escrowNFT, offerId);
    }

    function rollOffer(uint rollId) internal view returns (ILoansNFT.RollOffer memory) {
        return ILoansNFT.RollOffer(rolls, rollId);
    }

    function createProviderOffer() internal returns (uint offerId) {
        startHoax(provider);
        cashAsset.approve(address(providerNFT), largeCash);
        offerId = providerNFT.createOffer(callStrikePercent, largeCash, ltv, duration, 0);
    }

    function maybeCreateEscrowOffer() internal {
        // calculates values for with or without escrow mode
        if (openEscrowLoan) {
            startHoax(supplier);
            underlying.approve(address(escrowNFT), largeUnderlying);
            escrowOfferId =
                escrowNFT.createOffer(largeUnderlying, duration, interestAPR, gracePeriod, lateFeeAPR, 0);
            (escrowFees,,) = escrowNFT.upfrontFees(escrowOfferId, underlyingAmount);
        } else {
            // reset to 0
            escrowOfferId = 0;
            escrowFees = 0;
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

        // price must be set for every block
        updatePrice();

        // convert at oracle price
        uint swapOut = underlyingAmount * oraclePrice / 1e18;
        prepareSwap(cashAsset, swapOut);

        startHoax(user1);
        underlying.approve(address(loans), underlyingAmount + escrowFees);

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
        (uint expectedProtocolFee,) =
            providerNFT.protocolFee(expectedProviderLocked, duration, callStrikePercent);
        if (expectedProviderLocked != 0) assertGt(expectedProtocolFee, 0); // ensure fee is expected

        ILoansNFT.SwapParams memory swapParams = defaultSwapParams(swapCashAmount);
        vm.expectEmit(address(loans));

        emit ILoansNFT.LoanOpened(
            ids.loanId,
            user1,
            underlyingAmount,
            expectedLoanAmount,
            openEscrowLoan,
            openEscrowLoan ? ids.nextEscrowId : 0,
            openEscrowLoan ? address(escrowNFT) : address(NO_ESCROW)
        );

        if (openEscrowLoan) {
            (loanId, providerId, loanAmount) = loans.openEscrowLoan(
                underlyingAmount,
                minLoanAmount,
                swapParams,
                providerOffer(providerOfferId),
                escrowOffer(escrowOfferId),
                escrowFees
            );

            // sanity checks for test values
            assertGt(escrowOfferId, 0);
            assertGt(escrowFees, 0);
            // escrow effects
            _checkEscrowViews(ids.loanId, ids.nextEscrowId, escrowFees);
        } else {
            (loanId, providerId, loanAmount) =
                loans.openLoan(underlyingAmount, minLoanAmount, swapParams, providerOffer(providerOfferId));

            // sanity checks for test values
            assertEq(escrowOfferId, 0);
            assertEq(escrowFees, 0);
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
        assertEq(underlying.balanceOf(user1), balances.userUnderlying - underlyingAmount - escrowFees);
        assertEq(cashAsset.balanceOf(user1), balances.userCash + loanAmount);
        assertEq(cashAsset.balanceOf(protocolFeeRecipient), balances.feeRecipient + expectedProtocolFee);
        assertEq(underlying.balanceOf(address(escrowNFT)), balances.escrow + escrowFees);

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
        assertEq(takerPosition.startPrice, oraclePrice);
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
        assertEq(escrow.gracePeriod, gracePeriod);
        assertEq(escrow.lateFeeAPR, lateFeeAPR);
        assertEq(escrow.duration, duration);
        assertEq(escrow.expiration, block.timestamp + duration);
        assertEq(escrow.feesHeld, expectedEscrowFee);
        assertEq(escrow.released, false);
        assertEq(escrow.withdrawable, 0);
    }

    struct EscrowReleaseAmounts {
        uint toEscrow;
        uint fromEscrow;
        uint leftOver;
        uint refunds;
    }

    function getEscrowReleaseValues(uint escrowId, uint swapOut)
        internal
        view
        returns (EscrowReleaseAmounts memory released)
    {
        uint owed = escrowNFT.getEscrow(escrowId).escrowed;
        released.toEscrow = swapOut < owed ? swapOut : owed;
        released.leftOver = swapOut - released.toEscrow;
        (, released.fromEscrow, released.refunds) = escrowNFT.previewRelease(escrowId, released.toEscrow);
    }

    struct BalancesClose {
        uint userUnderlying;
        uint userCash;
        uint escrow;
    }

    function closeAndCheckLoan(uint loanId, address caller, uint loanAmount, uint withdrawal, uint swapOut)
        internal
    {
        // price must be set for every block
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
                loan.escrowId, released.toEscrow, released.fromEscrow, released.leftOver
            );
        }
        vm.expectEmit(address(loans));
        emit ILoansNFT.LoanClosed(loanId, caller, user1, loanAmount, loanAmount + withdrawal, swapOut);
        uint underlyingOut = loans.closeLoan(loanId, defaultSwapParams(0));

        // Check balances and return value
        if (loan.usesEscrow) {
            assertEq(underlyingOut, released.leftOver + released.fromEscrow);
        }
        assertEq(underlyingOut, swapOut + released.fromEscrow - released.toEscrow);
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
        oraclePrice = newPrice;

        CollarTakerNFT.TakerPosition memory takerPosition = takerNFT.getPosition({ takerId: loanId });
        // calculate withdrawal amounts according to expected ratios
        uint withdrawal = takerPosition.takerLocked * putRatio / BIPS_100PCT
            + takerPosition.providerLocked * callRatio / BIPS_100PCT;
        // setup router output
        uint swapOut = prepareDefaultSwapToUnderlying();
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
        overdue = overdue > gracePeriod ? gracePeriod : overdue;
        fee = divUp(underlyingAmount * lateFeeAPR * overdue, BIPS_100PCT * 365 days);
    }

    function divUp(uint x, uint y) internal pure returns (uint) {
        return (x == 0) ? 0 : ((x - 1) / y) + 1; // divUp(x,y) = (x-1 / y) + 1
    }
}

contract LoansBasicEffectsTest is LoansTestBase {
    // tests

    function test_constructor() public {
        loans = new LoansNFT(takerNFT, "", "");
        assertEq(loans.MAX_SWAP_PRICE_DEVIATION_BIPS(), 1000);
        assertEq(address(loans.configHub()), address(configHub));
        assertEq(address(loans.takerNFT()), address(takerNFT));
        assertEq(address(loans.cashAsset()), address(cashAsset));
        assertEq(address(loans.underlying()), address(underlying));
        assertEq(loans.VERSION(), "0.3.0");
        assertEq(loans.configHubOwner(), owner);
        assertEq(address(loans.defaultSwapper()), address(0));
        assertEq(loans.name(), "");
        assertEq(loans.symbol(), "");
    }

    function test_openLoan() public {
        createAndCheckLoan();
    }

    function test_openLoan_slippage() public {
        uint providerOfferId = createProviderOffer();
        maybeCreateEscrowOffer();

        vm.startPrank(user1);
        underlying.approve(address(loans), underlyingAmount * 2);

        // 11% slippage down: nope
        prepareSwap(cashAsset, swapCashAmount * 89 / 100);
        vm.expectRevert("swap and oracle price too different");
        loans.openLoan(underlyingAmount, 0, defaultSwapParams(0), providerOffer(providerOfferId));

        // 11% slippage up: nope
        prepareSwap(cashAsset, swapCashAmount * 111 / 100);
        vm.expectRevert("swap and oracle price too different");
        loans.openLoan(underlyingAmount, 0, defaultSwapParams(0), providerOffer(providerOfferId));

        prepareSwap(cashAsset, swapCashAmount * 90 / 100);
        // 10% slippage down: fine
        loans.openLoan(underlyingAmount, 0, defaultSwapParams(0), providerOffer(providerOfferId));

        prepareSwap(cashAsset, swapCashAmount * 110 / 100);
        // 10% slippage up: fine
        loans.openLoan(underlyingAmount, 0, defaultSwapParams(0), providerOffer(providerOfferId));
    }

    function test_tokenURI() public {
        (uint loanId,,) = createAndCheckLoan();
        string memory expected = string.concat(
            "https://services.collarprotocol.xyz/metadata/",
            Strings.toString(block.chainid),
            "/",
            Strings.toHexString(address(loans)),
            "/",
            Strings.toString(loanId)
        );
        assertEq(loans.tokenURI(loanId), expected);
    }

    function test_setKeeperFor() public {
        uint loanId = 100;
        uint otherLoanId = 50;
        startHoax(user1);
        assertEq(loans.keeperApprovedFor(user1, loanId), address(0));
        assertEq(loans.keeperApprovedFor(user1, otherLoanId), address(0));

        vm.expectEmit(address(loans));
        emit ILoansNFT.ClosingKeeperApproved(user1, loanId, keeper);
        loans.setKeeperFor(loanId, keeper);
        assertEq(loans.keeperApprovedFor(user1, loanId), keeper);
        assertEq(loans.keeperApprovedFor(user1, otherLoanId), address(0));

        vm.expectEmit(address(loans));
        emit ILoansNFT.ClosingKeeperApproved(user1, loanId, address(0));
        loans.setKeeperFor(loanId, address(0));
        assertEq(loans.keeperApprovedFor(user1, loanId), address(0));
        assertEq(loans.keeperApprovedFor(user1, otherLoanId), address(0));
    }

    function test_closeLoan_simple() public {
        (uint loanId,, uint loanAmount) = createAndCheckLoan();
        skip(duration);

        // withdrawal: no price change so only user locked (put locked)
        uint withdrawal = takerNFT.getPosition({ takerId: loanId }).takerLocked;
        // setup router output
        uint swapOut = prepareDefaultSwapToUnderlying();
        closeAndCheckLoan(loanId, user1, loanAmount, withdrawal, swapOut);
    }

    function test_closeLoan_largeLeftOver() public {
        (uint loanId,, uint loanAmount) = createAndCheckLoan();
        skip(duration);

        // withdrawal: no price change so only user locked (put locked)
        uint withdrawal = takerNFT.getPosition({ takerId: loanId }).takerLocked;
        // setup router output too large
        prepareSwap(underlying, underlyingAmount * 2);
        closeAndCheckLoan(loanId, user1, loanAmount, withdrawal, underlyingAmount * 2);
    }

    function test_closeLoan_zero_amount_swap() public {
        uint providerOfferId = createProviderOffer();

        // set up a 0 loanAmount loan
        updatePrice(cashUnits(1e12)); // 1 wei underlying (18) is worth 1 wei cash (6)
        prepareSwap(cashAsset, 1);
        startHoax(user1);
        // 1 wei underlying
        underlying.approve(address(loans), 1);
        (uint loanId,, uint loanAmount) =
            loans.openLoan(1, 0, defaultSwapParams(0), providerOffer(providerOfferId));

        assertEq(loanAmount, 0);
        skip(duration);

        // should revert for next swap
        mockSwapperRouter.setReverts(true);

        // empty swap amount doesn't hit swapper
        closeAndCheckLoan(loanId, user1, 0, 0, 0);
    }

    function test_closeLoan_settled() public {
        (uint loanId,, uint loanAmount) = createAndCheckLoan();
        skip(duration);

        // settle so that close should skip settling
        takerNFT.settlePairedPosition(loanId);

        // withdrawal: no price change so only user locked (put locked)
        uint withdrawal = takerNFT.getPosition({ takerId: loanId }).takerLocked;
        // setup router output
        uint swapOut = prepareDefaultSwapToUnderlying();
        closeAndCheckLoan(loanId, user1, loanAmount, withdrawal, swapOut);
    }

    function test_closeLoan_settledAsCancelled() public {
        (uint loanId,, uint loanAmount) = createAndCheckLoan();
        skip(duration + takerNFT.SETTLE_AS_CANCELLED_DELAY());

        // oracle reverts now
        vm.mockCallRevert(address(takerNFT.oracle()), abi.encodeCall(takerNFT.oracle().currentPrice, ()), "");
        // check that settlement reverts
        vm.expectRevert(new bytes(0));
        takerNFT.settlePairedPosition(loanId);

        // settle as cancelled works
        takerNFT.settleAsCancelled(loanId);

        // withdrawal: no price settlement change since settled as cancelled
        uint withdrawal = takerNFT.getPosition({ takerId: loanId }).takerLocked;
        // setup router output
        uint swapOut = prepareDefaultSwapToUnderlying();
        // closing works
        closeAndCheckLoan(loanId, user1, loanAmount, withdrawal, swapOut);
    }

    function test_closeLoan_byKeeper() public {
        (uint loanId,, uint loanAmount) = createAndCheckLoan();
        skip(duration);

        // Allow the keeper to close the loan
        vm.startPrank(user1);
        loans.setKeeperFor(loanId, keeper);

        CollarTakerNFT.TakerPosition memory takerPosition = takerNFT.getPosition({ takerId: loanId });
        // withdrawal: no price change so only user locked (put locked)
        uint withdrawal = takerPosition.takerLocked;
        // setup router output
        uint swapOut = prepareDefaultSwapToUnderlying();
        closeAndCheckLoan(loanId, keeper, loanAmount, withdrawal, swapOut);
    }

    function test_closeLoan_priceUpToCall() public {
        uint newPrice = oraclePrice * callStrikePercent / BIPS_100PCT;
        // price goes to call strike, withdrawal is 100% of pot (100% put + 100% call locked parts)
        checkOpenCloseWithPriceChange(newPrice, BIPS_100PCT, BIPS_100PCT);
    }

    function test_closeLoan_priceHalfUpToCall() public {
        uint delta = (callStrikePercent - BIPS_100PCT) / 2;
        uint newPrice = oraclePrice * (BIPS_100PCT + delta) / BIPS_100PCT;
        // price goes to half way to call, withdrawal is 100% takerLocked + 50% of providerLocked
        checkOpenCloseWithPriceChange(newPrice, BIPS_100PCT, BIPS_100PCT / 2);
    }

    function test_closeLoan_priceOverCall() public {
        uint newPrice = oraclePrice * (callStrikePercent + BIPS_100PCT) / BIPS_100PCT;
        // price goes over call, withdrawal is 100% takerLocked + 100% providerLocked
        checkOpenCloseWithPriceChange(newPrice, BIPS_100PCT, BIPS_100PCT);
    }

    function test_closeLoan_priceDownToPut() public {
        uint putStrikePercent = ltv;
        uint newPrice = oraclePrice * putStrikePercent / BIPS_100PCT;
        // price goes to put strike, withdrawal is 0 (all gone to provider)
        checkOpenCloseWithPriceChange(newPrice, 0, 0);
    }

    function test_closeLoan_priceHalfDownToPut() public {
        uint putStrikePercent = ltv;
        uint delta = (BIPS_100PCT - putStrikePercent) / 2;
        uint newPrice = oraclePrice * (BIPS_100PCT - delta) / BIPS_100PCT;
        // price goes half way to put strike, withdrawal is 50% of takerLocked and 0% of providerLocked
        checkOpenCloseWithPriceChange(newPrice, BIPS_100PCT / 2, 0);
    }

    function test_closeLoan_priceBelowPut() public {
        uint putStrikePercent = ltv;
        uint newPrice = oraclePrice * (putStrikePercent - BIPS_100PCT / 10) / BIPS_100PCT;
        // price goes below put strike, withdrawal is 0% (all gone to provider)
        checkOpenCloseWithPriceChange(newPrice, 0, 0);
    }

    function test_openLoan_swapper_extraData() public {
        (SwapperArbitraryCall arbCallSwapper, SwapperUniV3 newUniSwapper) = switchToArbitrarySwapper();
        assertFalse(loans.isAllowedSwapper(address(swapperUniV3)));
        assertTrue(loans.isAllowedSwapper(address(arbCallSwapper)));

        // check that without extraData, open loan fails
        uint providerOfferId = createProviderOffer();
        maybeCreateEscrowOffer();
        prepareSwap(cashAsset, swapCashAmount);
        vm.startPrank(user1);
        underlying.approve(address(loans), underlyingAmount + escrowFees);
        vm.expectRevert(new bytes(0)); // failure to decode extraData
        if (openEscrowLoan) {
            // escrow loan
            loans.openEscrowLoan(
                underlyingAmount,
                0,
                defaultSwapParams(0),
                providerOffer(providerOfferId),
                escrowOffer(escrowOfferId),
                escrowFees
            );
        } else {
            // simple loan
            loans.openLoan(underlyingAmount, 0, defaultSwapParams(0), providerOffer(providerOfferId));
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
        uint swapOut = prepareDefaultSwapToUnderlying();

        // switch swappers
        (SwapperArbitraryCall arbCallSwapper, SwapperUniV3 newUniSwapper) = switchToArbitrarySwapper();
        assertFalse(loans.isAllowedSwapper(address(swapperUniV3)));
        assertTrue(loans.isAllowedSwapper(address(arbCallSwapper)));

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
        uint refund;
        if (loan.usesEscrow) {
            IEscrowSupplierNFT.Escrow memory escrow = escrowNFT.getEscrow(loan.escrowId);
            (, uint interestHeld, uint lateFeeHeld) = escrowNFT.upfrontFees(escrow.offerId, escrow.escrowed);
            // received refund for half a duration
            refund = interestHeld / 2 + lateFeeHeld;

            // expect this only if escrow is used
            vm.expectEmit(address(loans));
            emit ILoansNFT.EscrowSettled(loan.escrowId, 0, refund, 0);
        }
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
        if (loan.usesEscrow) {
            // escrow released
            assertEq(escrowNFT.getEscrow(loan.escrowId).released, true);
        }
        assertEq(underlying.balanceOf(user1), balanceBefore + refund);
    }

    function test_unwrapAndCancelLoan_afterExpiry() public {
        // cancel after expiry works for regular loans
        (uint loanId,,) = createAndCheckLoan();
        skip(duration + 1);

        vm.expectEmit(address(loans));
        emit ILoansNFT.LoanCancelled(loanId, address(user1));
        loans.unwrapAndCancelLoan(loanId);
        // upwrapped
        assertEq(takerNFT.ownerOf({ tokenId: loanId }), user1);
        // cancelled
        expectRevertERC721Nonexistent(loanId);
        loans.ownerOf(loanId);
    }

    function test_exitIfBrokenOracle() public {
        // exit cases when the oracle is broken or if it reverts due to sequencer checks
        (uint loanId,,) = createAndCheckLoan();

        // disable oracle
        vm.startPrank(owner);
        mockCLFeed.setReverts(true);
        vm.expectRevert("oracle reverts");
        takerNFT.currentOraclePrice();

        // can still unwrap
        vm.startPrank(user1);
        loans.unwrapAndCancelLoan(loanId);

        // taker NFT unwrapped
        uint takerId = loanId;
        assertEq(takerNFT.ownerOf(takerId), user1);
        takerNFT.transferFrom(user1, provider, takerId);

        // cancel position also works
        vm.startPrank(provider);
        providerNFT.approve(address(takerNFT), takerNFT.getPosition(takerId).providerId);
        takerNFT.cancelPairedPosition(takerId);
    }
}
