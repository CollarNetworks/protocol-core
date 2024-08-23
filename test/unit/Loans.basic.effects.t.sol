// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

import "forge-std/Test.sol";
import { IERC721Errors } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { TestERC20 } from "../utils/TestERC20.sol";
import { BaseAssetPairTestSetup } from "./BaseAssetPairTestSetup.sol";
import { MockSwapperRouter } from "../utils/MockSwapRouter.sol";

import { Loans, ILoans } from "../../src/Loans.sol";
import { CollarTakerNFT } from "../../src/CollarTakerNFT.sol";
import { ProviderPositionNFT } from "../../src/ProviderPositionNFT.sol";
import { SwapperUniV3, ISwapper } from "../../src/SwapperUniV3.sol";

contract LoansTestBase is BaseAssetPairTestSetup {
    MockSwapperRouter mockSwapperRouter;
    SwapperUniV3 swapperUniV3;
    Loans loans;

    address defaultSwapper;

    uint24 swapFeeTier = 500;

    // swap amount * ltv
    uint minLoanAmount = swapCashAmount * (ltv / BIPS_100PCT);

    function setUp() public override {
        super.setUp();

        // deploy
        mockSwapperRouter = new MockSwapperRouter();
        swapperUniV3 = new SwapperUniV3(address(mockSwapperRouter), swapFeeTier);
        loans = new Loans(owner, takerNFT);
        vm.label(address(mockSwapperRouter), "MockSwapRouter");
        vm.label(address(swapperUniV3), "SwapperUniV3");
        vm.label(address(loans), "Loans");

        // config
        vm.startPrank(owner);
        loans.setRollsContract(rolls);
        defaultSwapper = address(swapperUniV3);
        loans.setSwapperAllowed(defaultSwapper, true, true);
        vm.stopPrank();
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

    function defaultSwapParams(uint minOut) internal view returns (ILoans.SwapParams memory) {
        return ILoans.SwapParams({ minAmountOut: minOut, swapper: defaultSwapper, extraData: "" });
    }

    function createOfferAsProvider() internal returns (uint offerId) {
        startHoax(provider);
        cashAsset.approve(address(providerNFT), largeAmount);
        offerId = providerNFT.createOffer(callStrikeDeviation, largeAmount, ltv, duration);
    }

    function createAndCheckLoan() internal returns (uint takerId, uint providerId, uint loanAmount) {
        uint offerId = createOfferAsProvider();

        // TWAP price must be set for every block
        updatePrice();

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
        emit ILoans.LoanOpened(
            user1,
            address(providerNFT),
            offerId,
            collateralAmount,
            expectedLoanAmount,
            nextTakerId,
            nextProviderId
        );

        (takerId, providerId, loanAmount) = loans.openLoan(
            collateralAmount, minLoanAmount, defaultSwapParams(swapCashAmount), providerNFT, offerId
        );

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
        updatePrice();

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
        uint collateralOut = loans.closeLoan(takerId, defaultSwapParams(0));

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
        loans.closeLoan(takerId, defaultSwapParams(0));
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
        assertEq(address(loans.rollsContract()), address(0));
        //        assertEq(loans.swapFeeTier(), 500);
    }

    function test_openLoan() public {
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
        (uint takerId,, uint loanAmount) = createAndCheckLoan();
        skip(duration);

        CollarTakerNFT.TakerPosition memory takerPosition = takerNFT.getPosition(takerId);
        // withdrawal: no price change so only user locked (put locked)
        uint withdrawal = takerPosition.putLockedCash;
        // setup router output
        uint swapOut = prepareSwapToCollateralAtTWAPPrice();
        closeAndCheckLoan(takerId, user1, loanAmount, withdrawal, swapOut);
    }

    function test_closeLoan_byKeeper() public {
        (uint takerId,, uint loanAmount) = createAndCheckLoan();
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
