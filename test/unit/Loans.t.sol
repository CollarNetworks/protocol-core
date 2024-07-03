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
        loans = new Loans(owner, engine, takerNFT, cashAsset, collateralAsset);

        engine.setCollarTakerContractAuth(address(takerNFT), true);
        engine.setProviderContractAuth(address(providerNFT), true);

        collateralAsset.mint(user1, collateralAmount * 10);
        cashAsset.mint(user1, collateralAmount * 10 * twapPrice / 1e18);
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

    function setupSwap(TestERC20 asset, uint amount) public {
        asset.mint(address(uniRouter), amount);
        uniRouter.setAmountToReturn(amount);
        uniRouter.setTransferAmount(amount);
    }

    function createOfferAsProvider() internal returns (uint offerId) {
        startHoax(provider);
        cashAsset.approve(address(providerNFT), amountToProvide);
        offerId = providerNFT.createOffer(callStrikeDeviation, amountToProvide, ltv, duration);
    }

    function createAndCheckLoan() internal returns (uint takerId, uint providerId, uint loanAmount) {
        uint offerId = createOfferAsProvider();

        engine.setHistoricalAssetPrice(address(collateralAsset), block.timestamp, twapPrice);

        uint swapOut = collateralAmount * twapPrice / 1e18;
        setupSwap(cashAsset, swapOut);

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
        assertFalse(loan.closed);

        // Check taker position
        CollarTakerNFT.TakerPosition memory takerPosition = takerNFT.getPosition(takerId);
        assertEq(address(takerPosition.providerNFT), address(providerNFT));
        assertEq(takerPosition.providerPositionId, providerId);
        assertEq(takerPosition.initialPrice, twapPrice);
        assertEq(takerPosition.putLockedCash, swapOut - loanAmount);
        assertEq(takerPosition.openedAt, block.timestamp);
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
    )
        internal
    {
        // TWAP price must be set for every block
        engine.setHistoricalAssetPrice(address(collateralAsset), block.timestamp, twapPrice);

        // Approve loan contract to spend user's cash for repayment
        vm.startPrank(user1);
        cashAsset.approve(address(loans), loanAmount);
        // Approve loan contract to transfer user's NFT for settlement
        takerNFT.approve(address(loans), takerId);

        uint initialCollateralBalance = collateralAsset.balanceOf(user1);
        uint initialCashBalance = cashAsset.balanceOf(user1);

        // Keeper closes the loan
        vm.startPrank(caller);
        vm.expectEmit(address(loans));
        emit ILoans.LoanClosed(
            takerId, caller, user1, loanAmount, loanAmount + withdrawal, expectedCollateralOut
        );
        uint collateralOut = loans.closeLoan(takerId, 0);

        // Check balances after loan closure
        assertEq(collateralOut, expectedCollateralOut);
        assertEq(collateralAsset.balanceOf(user1), initialCollateralBalance + collateralOut);
        assertEq(cashAsset.balanceOf(user1), initialCashBalance - loanAmount);

        // Check loan state
        assertTrue(loans.getLoan(takerId).closed);

        // Check that the NFT has been burned
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, takerId));
        takerNFT.ownerOf(takerId);

        // Try to close the loan again (should fail)
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, takerId));
        loans.closeLoan(takerId, 0);
    }

    function checkOpenCloseLoanPriceChange(uint newPrice, uint putPortion, uint callPortion) public {
        (uint takerId, uint providerId, uint loanAmount) = createAndCheckLoan();
        skip(duration);

        // update price
        twapPrice = newPrice;

        CollarTakerNFT.TakerPosition memory takerPosition = takerNFT.getPosition(takerId);
        // calculate withdrawal amounts
        uint withdrawal = takerPosition.putLockedCash * putPortion / BIPS_100PCT
            + takerPosition.callLockedCash * callPortion / BIPS_100PCT;
        // setup router output
        uint swapOut = collateralAmount * 1e18 / twapPrice;
        setupSwap(collateralAsset, swapOut);

        closeAndCheckLoan(takerId, user1, loanAmount, withdrawal, swapOut);
    }

    function allowKeeper(uint takerId) internal {
        // Set the keeper
        vm.startPrank(owner);
        loans.setKeeper(keeper);

        // Allow the keeper to close the loan
        vm.startPrank(user1);
        loans.setKeeperAllowedBy(takerId, true);
    }

    // happy paths

    function test_constructor() public {
        assertEq(address(loans.engine()), address(engine));
        assertEq(address(loans.takerNFT()), address(takerNFT));
        assertEq(address(loans.cashAsset()), address(cashAsset));
        assertEq(address(loans.collateralAsset()), address(collateralAsset));
        assertEq(loans.TWAP_LENGTH(), 15 minutes);
        assertEq(loans.MAX_SWAP_TWAP_DEVIATION_BIPS(), 100);
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
        uint swapOut = collateralAmount * 1e18 / twapPrice;
        setupSwap(collateralAsset, swapOut);

        closeAndCheckLoan(takerId, user1, loanAmount, withdrawal, swapOut);
    }

    function test_closeLoan_byKeeper() public {
        (uint takerId, uint providerId, uint loanAmount) = createAndCheckLoan();
        skip(duration);
        // allow keeper
        allowKeeper(takerId);

        CollarTakerNFT.TakerPosition memory takerPosition = takerNFT.getPosition(takerId);
        // withdrawal: no price change so only user locked (put locked)
        uint withdrawal = takerPosition.putLockedCash;
        // setup router output
        uint swapOut = collateralAmount * 1e18 / twapPrice;
        setupSwap(collateralAsset, swapOut);

        closeAndCheckLoan(takerId, keeper, loanAmount, withdrawal, swapOut);
    }

    function test_closeLoan_priceUpToCall() public {
        uint newPrice = twapPrice * callStrikeDeviation / BIPS_100PCT;
        // price goes to call strike, withdrawal is 100% of pot (put + call locked parts)
        checkOpenCloseLoanPriceChange(newPrice, BIPS_100PCT, BIPS_100PCT);
    }

    function test_closeLoan_priceHalfUpToCall() public {
        uint delta = (callStrikeDeviation - BIPS_100PCT) / 2;
        uint newPrice = twapPrice * (BIPS_100PCT + delta) / BIPS_100PCT;
        // price goes to half way to call, withdrawal is putLocked + half of callLocked
        checkOpenCloseLoanPriceChange(newPrice, BIPS_100PCT, BIPS_100PCT / 2);
    }

    function test_closeLoan_priceOverCall() public {
        uint newPrice = twapPrice * (callStrikeDeviation + BIPS_100PCT) / BIPS_100PCT;
        // price goes over call, withdrawal is putLocked + callLocked
        checkOpenCloseLoanPriceChange(newPrice, BIPS_100PCT, BIPS_100PCT);
    }

    function test_closeLoan_priceDownToPut() public {
        uint putStrikeDeviation = ltv;
        uint newPrice = twapPrice * putStrikeDeviation / BIPS_100PCT;
        // price goes to put strike, withdrawal is 0 (all gone to provider)
        checkOpenCloseLoanPriceChange(newPrice, 0, 0);
    }

    function test_closeLoan_priceHalfDownToPut() public {
        uint putStrikeDeviation = ltv;
        uint delta = (BIPS_100PCT - putStrikeDeviation) / 2;
        uint newPrice = twapPrice * (BIPS_100PCT - delta) / BIPS_100PCT;
        // price goes half way to put strike, withdrawal is half of putLocked and 0 of callLocked
        checkOpenCloseLoanPriceChange(newPrice, BIPS_100PCT / 2, 0);
    }

    function test_closeLoan_priceBelowPut() public {
        uint putStrikeDeviation = ltv;
        uint newPrice = twapPrice * (putStrikeDeviation - BIPS_100PCT / 10) / BIPS_100PCT;
        // price goes below put strike, withdrawal is 0 (all gone to provider)
        checkOpenCloseLoanPriceChange(newPrice, 0, 0);
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
        setupSwap(cashAsset, twapPrice * collateralAmount / 1e18);

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

        // too much collateral for offer
        uint offerId = createOfferAsProvider();
        // not enough approval for collatearal
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(loans), collateralAmount, collateralAmount + 1));
        loans.createLoan(collateralAmount + 1, minLoanAmount, minSwapCash, providerNFT, offerId);
    }

    function test_revert_createLoan_swaps() public {
        // too much slippage
        uint offerId = createOfferAsProvider();
        setupSwap(cashAsset, minSwapCash);

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
        setupSwap(cashAsset, minSwapCash / 2);
        vm.expectRevert("swap and twap price too different");
        loans.createLoan(collateralAmount, minLoanAmount, 0, providerNFT, offerId);
    }

    function test_revert_createLoan_insufficientLoanAmount() public {
        uint offerId = createOfferAsProvider();
        uint swapOut = collateralAmount * twapPrice / 1e18;
        setupSwap(cashAsset, swapOut);

        vm.startPrank(user1);
        collateralAsset.approve(address(loans), collateralAmount);

        uint highMinLoanAmount = (swapOut * ltv / BIPS_100PCT) + 1; // 1 wei more than ltv
        vm.expectRevert("loan amount too low");
        loans.createLoan(collateralAmount, highMinLoanAmount, minSwapCash, providerNFT, offerId);
    }

}
