// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

import "forge-std/Test.sol";
import { IERC721Errors } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { TestERC20 } from "../utils/TestERC20.sol";
import { MockConfigHub } from "../../test/utils/MockConfigHub.sol";
import { MockUniRouter } from "../../test/utils/MockUniRouter.sol";

import { Loans, ILoans } from "../../src/Loans.sol";
import { CollarTakerNFT } from "../../src/CollarTakerNFT.sol";
import { ProviderPositionNFT } from "../../src/ProviderPositionNFT.sol";
import { Rolls } from "../../src/Rolls.sol";

contract LoansTestBase is Test {
    TestERC20 cashAsset;
    TestERC20 collateralAsset;
    MockConfigHub configHub;
    MockUniRouter uniRouter;
    CollarTakerNFT takerNFT;
    ProviderPositionNFT providerNFT;
    Loans loans;
    Rolls rolls;

    address owner = makeAddr("owner");
    address user1 = makeAddr("user1");
    address provider = makeAddr("provider");
    address keeper = makeAddr("keeper");

    uint constant BIPS_100PCT = 10_000;
    uint ltv = 9000;
    uint duration = 300;
    uint callStrikeDeviation = 12_000;

    uint twapPrice = 1000 ether;
    uint collateralAmount = 1 ether;
    // swap amount
    uint minSwapCash = (collateralAmount * twapPrice / 1e18);
    // swap amount * ltv
    uint minLoanAmount = minSwapCash * (ltv / BIPS_100PCT);
    uint amountToProvide = 100_000 ether;

    // rolls
    int rollFee = 1 ether;

    function setUp() public {
        cashAsset = new TestERC20("TestCash", "TestCash");
        collateralAsset = new TestERC20("TestCollat", "TestCollat");
        uniRouter = new MockUniRouter();
        configHub = new MockConfigHub(address(uniRouter));
        setupConfigHub();

        takerNFT =
            new CollarTakerNFT(owner, configHub, cashAsset, collateralAsset, "CollarTakerNFT", "TKRNFT");
        providerNFT = new ProviderPositionNFT(
            owner, configHub, cashAsset, collateralAsset, address(takerNFT), "ProviderNFT", "PRVNFT"
        );
        rolls = new Rolls(owner, takerNFT, cashAsset);
        loans = new Loans(owner, takerNFT);

        configHub.setCollarTakerContractAuth(address(takerNFT), true);
        configHub.setProviderContractAuth(address(providerNFT), true);

        vm.prank(owner);
        loans.setRollsContract(rolls);

        collateralAsset.mint(user1, collateralAmount * 10);
        cashAsset.mint(user1, minSwapCash * 10);
        cashAsset.mint(provider, amountToProvide * 10);

        configHub.setHistoricalAssetPrice(address(collateralAsset), block.timestamp, twapPrice);

        vm.label(address(cashAsset), "TestCash");
        vm.label(address(collateralAsset), "TestCollat");
        vm.label(address(configHub), "ConfigHub");
        vm.label(address(uniRouter), "UniRouter");
        vm.label(address(takerNFT), "CollarTakerNFT");
        vm.label(address(providerNFT), "ProviderPositionNFT");
        vm.label(address(loans), "Loans");
    }

    function setupConfigHub() public {
        configHub.setCashAssetSupport(address(cashAsset), true);
        configHub.setCollateralAssetSupport(address(collateralAsset), true);
        configHub.setLTVRange(ltv, ltv);
        configHub.setCollarDurationRange(duration, duration);
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
        configHub.setHistoricalAssetPrice(address(collateralAsset), block.timestamp, twapPrice);

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
        configHub.setHistoricalAssetPrice(address(collateralAsset), block.timestamp, twapPrice);

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

    function checkOpenCloseWithPriceChange(uint newPrice, uint putRatio, uint callRatio)
        public
        returns (uint)
    {
        (uint takerId,, uint loanAmount) = createAndCheckLoan();
        skip(duration);

        // update price
        twapPrice = newPrice;

        CollarTakerNFT.TakerPosition memory takerPosition = takerNFT.getPosition(takerId);
        // calculate withdrawal amounts according to expected ratios
        uint withdrawal = takerPosition.putLockedCash * putRatio / BIPS_100PCT
            + takerPosition.callLockedCash * callRatio / BIPS_100PCT;
        // setup router output
        uint swapOut = prepareSwapToCollateralAtTWAPPrice();
        closeAndCheckLoan(takerId, user1, loanAmount, withdrawal, swapOut);
        return takerId;
    }
}

contract LoansBasicHappyPathsTest is LoansTestBase {
    function test_constructor() public {
        loans = new Loans(owner, takerNFT);
        assertEq(address(loans.configHub()), address(configHub));
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
}
