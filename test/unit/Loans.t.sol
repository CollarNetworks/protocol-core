// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

import "forge-std/Test.sol";
import { IERC721Errors } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { IERC20Errors } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { TestERC20 } from "../utils/TestERC20.sol";
import { MockEngine } from "../../test/utils/MockEngine.sol";
import { MockUniRouter } from "../../test/utils/MockUniRouter.sol";

import { Loans, ILoans } from "../../src/Loans.sol";
import { CollarTakerNFT } from "../../src/CollarTakerNFT.sol";
import { ProviderPositionNFT } from "../../src/ProviderPositionNFT.sol";

contract LoansTest is Test {
    TestERC20 cashAsset;
    TestERC20 collateralAsset;
    MockEngine engine;
    MockUniRouter uniRouter;
    CollarTakerNFT takerNFT;
    ProviderPositionNFT providerNFT;
    Loans loans;

    address owner = makeAddr("owner");
    address user1 = makeAddr("user1");
    address provider = makeAddr("provider");
    address keeper = makeAddr("keeper");

    uint constant BIPS_100PCT = 10_000;
    uint ltv = 9000;
    uint duration = 300;
    uint callStrikeDeviation = 12_000;

    uint twapPrice = 10 ether;
    uint collateralAmount = 10 ether;
    // swap amount
    uint minSwapCash = (collateralAmount * twapPrice / 1e18);
    // swap amount * ltv
    uint minLoanAmount = minSwapCash * (ltv / BIPS_100PCT);
    uint amountToProvide = 100_000 ether;

    function setUp() public {
        cashAsset = new TestERC20("TestCash", "TestCash");
        collateralAsset = new TestERC20("TestCollat", "TestCollat");
        uniRouter = new MockUniRouter();
        engine = new MockEngine(address(uniRouter));
        setupEngine();

        takerNFT = new CollarTakerNFT(owner, engine, cashAsset, collateralAsset, "CollarTakerNFT", "TKRNFT");
        providerNFT = new ProviderPositionNFT(
            owner, engine, cashAsset, collateralAsset, address(takerNFT), "ProviderNFT", "PRVNFT"
        );
        loans = new Loans(owner, takerNFT);

        engine.setCollarTakerContractAuth(address(takerNFT), true);
        engine.setProviderContractAuth(address(providerNFT), true);

        collateralAsset.mint(user1, collateralAmount * 10);
        cashAsset.mint(user1, minSwapCash * 10);
        cashAsset.mint(provider, amountToProvide * 10);

        engine.setHistoricalAssetPrice(address(collateralAsset), block.timestamp, twapPrice);

        vm.label(address(cashAsset), "TestCash");
        vm.label(address(collateralAsset), "TestCollat");
        vm.label(address(engine), "CollarEngine");
        vm.label(address(uniRouter), "UniRouter");
        vm.label(address(takerNFT), "CollarTakerNFT");
        vm.label(address(providerNFT), "ProviderPositionNFT");
        vm.label(address(loans), "Loans");
    }

    function setupEngine() public {
        engine.addLTV(ltv);
        engine.addCollarDuration(duration);
        engine.addSupportedCashAsset(address(cashAsset));
        engine.addSupportedCollateralAsset(address(collateralAsset));
    }

    function prepareSwap(TestERC20 asset, uint amount) public {
        asset.mint(address(uniRouter), amount);
        uniRouter.setAmountToReturn(amount);
        uniRouter.setTransferAmount(amount);
    }

    function prepareSwapToCollateralAtTWAPPrice() public returns (uint swapOut) {
        swapOut = collateralAmount * 1e18 / twapPrice;
        prepareSwap(collateralAsset, swapOut);
    }

    function prepareSwapToCashAtTWAPPrice() public returns (uint swapOut) {
        swapOut = collateralAmount * twapPrice / 1e18;
        prepareSwap(cashAsset, swapOut);
    }

    function createOfferAsProvider() internal returns (uint offerId) {
        startHoax(provider);
        cashAsset.approve(address(providerNFT), amountToProvide);
        offerId = providerNFT.createOffer(callStrikeDeviation, amountToProvide, ltv, duration);
    }

    function createAndCheckLoan() internal returns (uint takerId, uint providerId, uint loanAmount) {
        uint offerId = createOfferAsProvider();

        // TWAP price must be set for every block
        engine.setHistoricalAssetPrice(address(collateralAsset), block.timestamp, twapPrice);

        // convert at twap price
        uint swapOut = collateralAmount * twapPrice / 1e18;
        prepareSwap(cashAsset, swapOut);

        startHoax(user1);
        collateralAsset.approve(address(loans), collateralAmount);

        uint initialCollateralBalance = collateralAsset.balanceOf(user1);
        uint initialCashBalance = cashAsset.balanceOf(user1);
        uint nextTakerId = takerNFT.nextPositionId();
        uint nextProviderId = providerNFT.nextPositionId();
        uint expectedLoanAmount = swapOut * ltv / 10_000;

        vm.expectEmit(address(loans));
        emit ILoans.LoanCreated(
            user1,
            address(providerNFT),
            offerId,
            collateralAmount,
            expectedLoanAmount,
            nextTakerId,
            nextProviderId
        );

        (takerId, providerId, loanAmount) =
            loans.createLoan(collateralAmount, minLoanAmount, minSwapCash, providerNFT, offerId);

        // Check return values
        assertEq(takerId, nextTakerId);
        assertEq(providerId, nextProviderId);
        assertEq(loanAmount, expectedLoanAmount);

        // Check balances
        assertEq(collateralAsset.balanceOf(user1), initialCollateralBalance - collateralAmount);
        assertEq(cashAsset.balanceOf(user1), initialCashBalance + loanAmount);

        // Check NFT ownership
        assertEq(takerNFT.ownerOf(takerId), user1);
        assertEq(providerNFT.ownerOf(providerId), provider);

        // Check loan state
        Loans.Loan memory loan = loans.getLoan(takerId);
        assertEq(loan.collateralAmount, collateralAmount);
        assertEq(loan.loanAmount, loanAmount);
        assertEq(loan.keeperAllowedBy, address(0));
        assertTrue(loan.active);

        // Check taker position
        CollarTakerNFT.TakerPosition memory takerPosition = takerNFT.getPosition(takerId);
        assertEq(address(takerPosition.providerNFT), address(providerNFT));
        assertEq(takerPosition.providerPositionId, providerId);
        assertEq(takerPosition.initialPrice, twapPrice);
        assertEq(takerPosition.putLockedCash, swapOut - loanAmount);
        assertEq(takerPosition.duration, duration);
        assertEq(takerPosition.expiration, block.timestamp + duration);
        assertFalse(takerPosition.settled);
        assertEq(takerPosition.withdrawable, 0);

        // Check provider position
        ProviderPositionNFT.ProviderPosition memory providerPosition = providerNFT.getPosition(providerId);
        assertEq(providerPosition.expiration, block.timestamp + duration);
        assertEq(providerPosition.principal, takerPosition.callLockedCash);
        assertEq(providerPosition.putStrikeDeviation, ltv);
        assertEq(providerPosition.callStrikeDeviation, callStrikeDeviation);
        assertFalse(providerPosition.settled);
        assertEq(providerPosition.withdrawable, 0);
    }

    function closeAndCheckLoan(
        uint takerId,
        address caller,
        uint loanAmount,
        uint withdrawal,
        uint expectedCollateralOut
    ) internal {
        // TWAP price must be set for every block
        engine.setHistoricalAssetPrice(address(collateralAsset), block.timestamp, twapPrice);

        vm.startPrank(user1);
        // Approve loan contract to spend user's cash for repayment
        cashAsset.approve(address(loans), loanAmount);
        // Approve loan contract to transfer user's NFT for settlement
        takerNFT.approve(address(loans), takerId);

        uint initialCollateralBalance = collateralAsset.balanceOf(user1);
        uint initialCashBalance = cashAsset.balanceOf(user1);

        // caller closes the loan
        vm.startPrank(caller);
        vm.expectEmit(address(loans));
        emit ILoans.LoanClosed(
            takerId, caller, user1, loanAmount, loanAmount + withdrawal, expectedCollateralOut
        );
        uint collateralOut = loans.closeLoan(takerId, 0);

        // Check balances and return value
        assertEq(collateralOut, expectedCollateralOut);
        assertEq(collateralAsset.balanceOf(user1), initialCollateralBalance + collateralOut);
        assertEq(cashAsset.balanceOf(user1), initialCashBalance - loanAmount);

        // Check loan state
        assertFalse(loans.getLoan(takerId).active);

        // Check that the NFT has been burned
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, takerId));
        takerNFT.ownerOf(takerId);

        // Try to close the loan again (should fail)
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, takerId));
        loans.closeLoan(takerId, 0);
    }

    function checkOpenCloseWithPriceChange(uint newPrice, uint putRatio, uint callRaio)
        public
        returns (uint)
    {
        (uint takerId, uint providerId, uint loanAmount) = createAndCheckLoan();
        skip(duration);

        // update price
        twapPrice = newPrice;

        CollarTakerNFT.TakerPosition memory takerPosition = takerNFT.getPosition(takerId);
        // calculate withdrawal amounts according to expected ratios
        uint withdrawal = takerPosition.putLockedCash * putRatio / BIPS_100PCT
            + takerPosition.callLockedCash * callRaio / BIPS_100PCT;
        // setup router output
        uint swapOut = prepareSwapToCollateralAtTWAPPrice();
        closeAndCheckLoan(takerId, user1, loanAmount, withdrawal, swapOut);
        return takerId;
    }

    // happy paths

    function test_constructor() public {
        loans = new Loans(owner, takerNFT);
        assertEq(address(loans.engine()), address(engine));
        assertEq(address(loans.takerNFT()), address(takerNFT));
        assertEq(address(loans.cashAsset()), address(cashAsset));
        assertEq(address(loans.collateralAsset()), address(collateralAsset));
        assertEq(loans.MAX_SWAP_TWAP_DEVIATION_BIPS(), 500);
        assertEq(loans.VERSION(), "0.2.0");
        assertEq(loans.owner(), owner);
        assertEq(loans.closingKeeper(), address(0));
    }

    function test_createLoan() public {
        createAndCheckLoan();
    }

    function test_setKeeperAllowedBy() public {
        (uint takerId,,) = createAndCheckLoan();

        vm.expectEmit(address(loans));
        emit ILoans.ClosingKeeperAllowed(user1, takerId, true);
        loans.setKeeperAllowedBy(takerId, true);

        Loans.Loan memory loan = loans.getLoan(takerId);
        assertEq(loan.keeperAllowedBy, user1);

        vm.expectEmit(address(loans));
        emit ILoans.ClosingKeeperAllowed(user1, takerId, false);
        loans.setKeeperAllowedBy(takerId, false);

        loan = loans.getLoan(takerId);
        assertEq(loan.keeperAllowedBy, address(0));
    }

    function test_closeLoan_simple() public {
        (uint takerId, uint providerId, uint loanAmount) = createAndCheckLoan();
        skip(duration);

        CollarTakerNFT.TakerPosition memory takerPosition = takerNFT.getPosition(takerId);
        // withdrawal: no price change so only user locked (put locked)
        uint withdrawal = takerPosition.putLockedCash;
        // setup router output
        uint swapOut = prepareSwapToCollateralAtTWAPPrice();
        closeAndCheckLoan(takerId, user1, loanAmount, withdrawal, swapOut);
    }

    function test_closeLoan_byKeeper() public {
        (uint takerId, uint providerId, uint loanAmount) = createAndCheckLoan();
        skip(duration);

        // Set the keeper
        vm.startPrank(owner);
        loans.setKeeper(keeper);

        // Allow the keeper to close the loan
        vm.startPrank(user1);
        loans.setKeeperAllowedBy(takerId, true);

        CollarTakerNFT.TakerPosition memory takerPosition = takerNFT.getPosition(takerId);
        // withdrawal: no price change so only user locked (put locked)
        uint withdrawal = takerPosition.putLockedCash;
        // setup router output
        uint swapOut = prepareSwapToCollateralAtTWAPPrice();
        closeAndCheckLoan(takerId, keeper, loanAmount, withdrawal, swapOut);
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

    function test_setKeeper() public {
        assertEq(loans.closingKeeper(), address(0));

        vm.prank(owner);
        vm.expectEmit(address(loans));
        emit ILoans.ClosingKeeperUpdated(address(0), keeper);
        loans.setKeeper(keeper);

        assertEq(loans.closingKeeper(), keeper);
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
        loans.createLoan(0, 0, 0, providerNFT, 0);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        loans.setKeeperAllowedBy(takerId, true);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        loans.closeLoan(takerId, 0);
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

    // reverts

    function test_onlyOwnerMethods() public {
        vm.startPrank(user1);
        bytes4 selector = Ownable.OwnableUnauthorizedAccount.selector;
        vm.expectRevert(abi.encodeWithSelector(selector, user1));
        loans.pause();
        vm.expectRevert(abi.encodeWithSelector(selector, user1));
        loans.unpause();
        vm.expectRevert(abi.encodeWithSelector(selector, user1));
        loans.setKeeper(keeper);
    }

    function test_revert_createLoan_params() public {
        vm.startPrank(user1);
        collateralAsset.approve(address(loans), collateralAmount);
        prepareSwapToCashAtTWAPPrice();

        // 0 collateral
        vm.expectRevert("invalid collateral amount");
        loans.createLoan(0, 0, 0, ProviderPositionNFT(address(0)), 0);

        // bad provider
        ProviderPositionNFT invalidProviderNFT = new ProviderPositionNFT(
            owner, engine, cashAsset, collateralAsset, address(takerNFT), "InvalidProviderNFT", "INVPRV"
        );
        vm.expectRevert("unsupported provider contract");
        loans.createLoan(collateralAmount, minLoanAmount, minSwapCash, invalidProviderNFT, 0);

        // bad offer
        uint invalidOfferId = 999;
        vm.expectRevert("invalid offer");
        loans.createLoan(collateralAmount, minLoanAmount, minSwapCash, providerNFT, invalidOfferId);

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
        loans.createLoan(collateralAmount + 1, minLoanAmount, minSwapCash, providerNFT, offerId);
    }

    function test_revert_createLoan_swaps() public {
        uint offerId = createOfferAsProvider();
        prepareSwap(cashAsset, minSwapCash);

        vm.startPrank(user1);
        collateralAsset.approve(address(loans), collateralAmount);

        // balance mismatch
        uniRouter.setAmountToReturn(minSwapCash - 1);
        vm.expectRevert("balance update mismatch");
        loans.createLoan(collateralAmount, minLoanAmount, minSwapCash, providerNFT, offerId);

        // slippage params
        uniRouter.setAmountToReturn(minSwapCash);
        vm.expectRevert("slippage exceeded");
        loans.createLoan(collateralAmount, minLoanAmount, minSwapCash + 1, providerNFT, offerId);

        // deviation vs.TWAP
        prepareSwap(cashAsset, minSwapCash / 2);
        vm.expectRevert("swap and twap price too different");
        loans.createLoan(collateralAmount, minLoanAmount, 0, providerNFT, offerId);
    }

    function test_revert_createLoan_insufficientLoanAmount() public {
        uint offerId = createOfferAsProvider();
        uint swapOut = prepareSwapToCashAtTWAPPrice();

        vm.startPrank(user1);
        collateralAsset.approve(address(loans), collateralAmount);

        uint highMinLoanAmount = (swapOut * ltv / BIPS_100PCT) + 1; // 1 wei more than ltv
        vm.expectRevert("loan amount too low");
        loans.createLoan(collateralAmount, highMinLoanAmount, minSwapCash, providerNFT, offerId);
    }

    function test_revert_closeLoan_notNFTOwnerOrKeeper() public {
        (uint takerId,,) = createAndCheckLoan();
        vm.startPrank(address(0xdead));
        vm.expectRevert("not taker NFT owner or allowed keeper");
        loans.closeLoan(takerId, 0);
    }

    function test_revert_closeLoan_nonExistentLoan() public {
        uint nonExistentTakerId = 999;
        vm.expectRevert(
            abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, nonExistentTakerId)
        );
        loans.closeLoan(nonExistentTakerId, 0);
    }

    function test_revert_closeLoan_noLoanForTakerID() public {
        uint offerId = createOfferAsProvider();
        vm.startPrank(user1);
        // create taker NFT not through loans
        (uint takerId,) = takerNFT.openPairedPosition(0, providerNFT, offerId);
        vm.expectRevert("not active");
        loans.closeLoan(takerId, 0);
    }

    function test_revert_closeLoan_reentrnancy_alreadyClosed() public {
        (uint takerId,, uint loanAmount) = createAndCheckLoan();
        vm.startPrank(user1);
        cashAsset.approve(address(loans), loanAmount);

        // setup attack: reenter from closeLoan to closeLoan
        ReentrantCloser closer = new ReentrantCloser();
        closer.setParams(loans, takerNFT, takerId, user1);
        cashAsset.setAttacker(address(closer));
        takerNFT.approve(address(closer), takerId); // allow attacker to pull nft
        vm.expectRevert("not active");
        loans.closeLoan(takerId, 0);

        // setup attack: reenter from closeLoan to setKeeperAllowedBy
        ReentrantKeeperSetter keeperSetter = new ReentrantKeeperSetter();
        keeperSetter.setParams(loans, takerNFT, takerId, user1);
        cashAsset.setAttacker(address(keeperSetter));
        takerNFT.approve(address(keeperSetter), takerId); // allow attacker to pull nft
        vm.expectRevert("not active");
        loans.closeLoan(takerId, 0);
    }

    function test_revert_closeLoan_alreadyClosed() public {
        uint takerId = checkOpenCloseWithPriceChange(twapPrice, BIPS_100PCT, 0);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, takerId));
        loans.closeLoan(takerId, 0);
    }

    function test_revert_closeLoan_insufficientRepaymentAllowance() public {
        (uint takerId,, uint loanAmount) = createAndCheckLoan();
        skip(duration);
        vm.startPrank(user1);

        cashAsset.approve(address(loans), loanAmount - 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, address(loans), loanAmount - 1, loanAmount
            )
        );
        loans.closeLoan(takerId, 0);
    }

    function test_revert_closeLoan_notApprovedNFT() public {
        (uint takerId,, uint loanAmount) = createAndCheckLoan();
        skip(duration);
        vm.startPrank(user1);
        cashAsset.approve(address(loans), loanAmount);

        vm.expectRevert(
            abi.encodeWithSelector(IERC721Errors.ERC721InsufficientApproval.selector, address(loans), takerId)
        );
        loans.closeLoan(takerId, 0);
    }

    function test_revert_closeLoan_beforeExpiration() public {
        (uint takerId,, uint loanAmount) = createAndCheckLoan();
        skip(duration - 1);

        vm.startPrank(user1);
        cashAsset.approve(address(loans), loanAmount);
        takerNFT.approve(address(loans), takerId);

        vm.expectRevert("not expired");
        loans.closeLoan(takerId, 0);
    }

    function test_revert_closeLoan_slippageExceeded() public {
        (uint takerId,, uint loanAmount) = createAndCheckLoan();
        skip(duration);
        vm.startPrank(user1);
        cashAsset.approve(address(loans), loanAmount);
        takerNFT.approve(address(loans), takerId);
        prepareSwap(collateralAsset, collateralAmount);

        vm.expectRevert("slippage exceeded");
        loans.closeLoan(takerId, collateralAmount + 1);
    }

    function test_revert_closeLoan_keeperNotAllowed() public {
        (uint takerId,, uint loanAmount) = createAndCheckLoan();
        skip(duration);

        vm.startPrank(owner);
        loans.setKeeper(keeper);

        vm.startPrank(keeper);
        // keeper was not allowed by user
        vm.expectRevert("not taker NFT owner or allowed keeper");
        loans.closeLoan(takerId, 0);

        vm.startPrank(user1);
        loans.setKeeperAllowedBy(takerId, true);

        vm.startPrank(user1);
        // transfer invalidates approval
        takerNFT.transferFrom(user1, provider, takerId);

        vm.startPrank(keeper);
        vm.expectRevert("not taker NFT owner or allowed keeper");
        loans.closeLoan(takerId, 0);

        // transfer back
        vm.startPrank(provider);
        takerNFT.transferFrom(provider, user1, takerId);

        // should work now
        vm.startPrank(user1);
        cashAsset.approve(address(loans), loanAmount);
        takerNFT.approve(address(loans), takerId);
        prepareSwap(collateralAsset, collateralAmount);
        // close from keeper
        vm.startPrank(keeper);
        loans.closeLoan(takerId, 0);
        assertFalse(loans.getLoan(takerId).active);
    }

    function test_revert_setKeeperAllowedBy_notNFTOwner() public {
        (uint takerId,,) = createAndCheckLoan();
        vm.startPrank(address(0xdead));
        vm.expectRevert("not taker NFT owner");
        loans.setKeeperAllowedBy(takerId, true);
    }

    function test_revert_setKeeperAllowedBy_nonExistentLoan() public {
        uint nonExistentTakerId = 999;
        vm.startPrank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, nonExistentTakerId)
        );
        loans.setKeeperAllowedBy(nonExistentTakerId, true);
    }

    function test_revert_setKeeperAllowedBy_alreadyClosed() public {
        uint takerId = checkOpenCloseWithPriceChange(twapPrice, BIPS_100PCT, 0);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, takerId));
        loans.setKeeperAllowedBy(takerId, true);
    }

    function test_revert_setKeeperAllowedBy_noLoanForTakerID() public {
        uint offerId = createOfferAsProvider();
        vm.startPrank(user1);
        // create taker NFT not through loans
        (uint takerId,) = takerNFT.openPairedPosition(0, providerNFT, offerId);
        vm.expectRevert("not active");
        loans.setKeeperAllowedBy(takerId, true);
    }

    function test_revert_setKeeperAllowedBy_afterTransfer() public {
        (uint takerId,,) = createAndCheckLoan();
        address newOwner = address(0xbeef);

        vm.startPrank(user1);
        takerNFT.transferFrom(user1, newOwner, takerId);

        vm.startPrank(user1);
        vm.expectRevert("not taker NFT owner");
        loans.setKeeperAllowedBy(takerId, true);
    }
}

contract ReentrantCloser {
    address nftOwner;
    CollarTakerNFT nft;
    Loans loans;
    uint id;

    function setParams(Loans _loans, CollarTakerNFT _nft, uint _id, address _nftOwner) external {
        loans = _loans;
        nft = _nft;
        id = _id;
        nftOwner = _nftOwner;
    }

    fallback() external virtual {
        nft.transferFrom(nftOwner, address(this), id);
        loans.closeLoan(id, 0);
    }
}

contract ReentrantKeeperSetter is ReentrantCloser {
    fallback() external override {
        nft.transferFrom(nftOwner, address(this), id);
        loans.setKeeperAllowedBy(id, true);
    }
}
