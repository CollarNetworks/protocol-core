// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

import { LoansBasicEffectsTest, ILoansNFT } from "./Loans.basic.effects.t.sol";
import { IEscrowSupplierNFT } from "../../src/LoansNFT.sol";

contract LoansEscrowEffectsTest is LoansBasicEffectsTest {
    function setUp() public virtual override {
        super.setUp();
        openEscrowLoan = true;
    }

    function expectedGracePeriodEnd(uint loanId, uint atPrice) internal view returns (uint) {
        uint expiration = takerNFT.getPosition({ takerId: loanId }).expiration;
        (uint cashAvailable,) = takerNFT.previewSettlement({ takerId: loanId, endPrice: atPrice });
        uint collateral = cashAvailable * 1e18 / atPrice; // 1e18 is BASE_TOKEN_AMOUNT
        uint gracePeriod = escrowNFT.cappedGracePeriod(loans.getLoan(loanId).escrowId, collateral);
        return expiration + gracePeriod;
    }

    function checkForecloseLoan(uint newPrice, uint skipAfterGrace, address caller) internal {
        (uint loanId,,) = createAndCheckLoan();

        // set settlement price and prepare swap
        mockOracle.setHistoricalAssetPrice(block.timestamp + duration, newPrice);

        // estimate the end of grace period
        uint endGracetime = loans.escrowGracePeriodEnd(loanId);
        // skip past grace period
        skip(endGracetime + skipAfterGrace - block.timestamp);

        twapPrice = newPrice;
        uint swapOut = prepareSwapToCollateralAtTWAPPrice();

        // calculate expected escrow release values
        uint escrowId = loans.getLoan(loanId).escrowId;
        EscrowReleaseAmounts memory released = getEscrowReleaseValues(escrowId, swapOut);
        uint expectedToUser = released.fromEscrow + released.leftOver;
        uint userBalance = collateralAsset.balanceOf(user1);
        uint escrowBalance = collateralAsset.balanceOf(address(escrowNFT));

        // foreclose
        vm.startPrank(caller);
        vm.expectEmit(address(loans));
        emit ILoansNFT.EscrowSettled(
            escrowId, released.toEscrow, released.lateFee, released.fromEscrow, released.leftOver
        );
        vm.expectEmit(address(loans));
        emit ILoansNFT.LoanForeclosed(loanId, escrowId, swapOut, expectedToUser);
        loans.forecloseLoan(loanId, defaultSwapParams(0));

        // balances
        assertEq(collateralAsset.balanceOf(user1), userBalance + expectedToUser);
        assertEq(
            collateralAsset.balanceOf(address(escrowNFT)),
            escrowBalance + released.toEscrow - released.fromEscrow
        );

        // struct
        IEscrowSupplierNFT.Escrow memory escrow = escrowNFT.getEscrow(escrowId);
        assertTrue(escrow.released);
        assertEq(escrow.withdrawable, escrow.escrowed + escrow.interestHeld + swapOut - expectedToUser);

        // loan and taker NFTs burned
        expectRevertERC721Nonexistent(loanId);
        loans.ownerOf(loanId);
        expectRevertERC721Nonexistent(loanId);
        takerNFT.ownerOf({ tokenId: loanId });
    }

    // tests

    // repeat all effects tests (open, close, unwrap) from super, but with escrow

    function test_unwrapAndCancelLoan_releasedEscrow() public {
        (uint loanId,,) = createAndCheckLoan();

        // check that escrow unreleased
        uint escrowId = loans.getLoan(loanId).escrowId;
        assertFalse(escrowNFT.getEscrow(escrowId).released);

        // after expiry
        skip(duration + 1);

        // cannot release
        vm.expectRevert("loan expired");
        loans.unwrapAndCancelLoan(loanId);

        // user balance
        uint userBalance = collateralAsset.balanceOf(user1);
        uint loansBalance = collateralAsset.balanceOf(address(loans));

        // release escrow via some other way without closing the loan
        // can be lastResortSeizeEscrow if after full grace period
        vm.startPrank(address(loans));
        escrowNFT.endEscrow(escrowId, 0);
        assertTrue(escrowNFT.getEscrow(escrowId).released);

        // now can unwrap
        vm.startPrank(user1);
        loans.unwrapAndCancelLoan(loanId);

        // no funds moved
        assertEq(collateralAsset.balanceOf(user1), userBalance);
        assertEq(collateralAsset.balanceOf(address(loans)), loansBalance);

        // NFT burned
        expectRevertERC721Nonexistent(loanId);
        loans.ownerOf(loanId);
        // taker NFT unwrapped
        assertEq(takerNFT.ownerOf({ tokenId: loanId }), user1);
        // cannot cancel again
        expectRevertERC721Nonexistent(loanId);
        loans.unwrapAndCancelLoan(loanId);
    }

    function test_escrowGracePeriodEnd_beforeAndAfterExpiry() public {
        (uint loanId,,) = createAndCheckLoan();

        // before expiry, uses current price
        uint expected = expectedGracePeriodEnd(loanId, twapPrice);
        assertEq(loans.escrowGracePeriodEnd(loanId), expected);

        mockOracle.setHistoricalAssetPrice(block.timestamp + duration, twapPrice);
        expected = expectedGracePeriodEnd(loanId, twapPrice);

        // at expiry
        skip(duration);
        assertEq(loans.escrowGracePeriodEnd(loanId), expected);

        // after expiry, keeps using previous price
        skip(1);
        assertEq(loans.escrowGracePeriodEnd(loanId), expected);

        // After min grace period
        skip(escrowNFT.MIN_GRACE_PERIOD() - 1);
        assertEq(loans.escrowGracePeriodEnd(loanId), expected);

        // After max grace period
        skip(escrowNFT.MAX_GRACE_PERIOD());
        assertEq(loans.escrowGracePeriodEnd(loanId), expected);
    }

    function test_escrowGracePeriodEnd_priceChanges() public {
        (uint loanId,,) = createAndCheckLoan();
        uint expiration = block.timestamp + duration;

        skip(duration); // at expiry

        // Price increase
        uint highPrice = twapPrice * 2;
        mockOracle.setHistoricalAssetPrice(expiration, highPrice);
        assertEq(loans.escrowGracePeriodEnd(loanId), expectedGracePeriodEnd(loanId, highPrice));

        // Price decrease
        uint lowPrice = twapPrice / 2;
        mockOracle.setHistoricalAssetPrice(expiration, lowPrice);
        assertEq(loans.escrowGracePeriodEnd(loanId), expectedGracePeriodEnd(loanId, lowPrice));

        // min grace period (for very high price), very high price means cash is worth 0 collateral
        mockOracle.setHistoricalAssetPrice(expiration, type(uint).max);
        assertEq(loans.escrowGracePeriodEnd(loanId), expiration + escrowNFT.MIN_GRACE_PERIOD());

        // min grace period (for very low price), because user has no cash (position is worth 0)
        uint minPrice = 1;
        mockOracle.setHistoricalAssetPrice(expiration, minPrice);
        assertEq(loans.escrowGracePeriodEnd(loanId), expiration + escrowNFT.MIN_GRACE_PERIOD());

        // make preview settlement return a lot of cash, which at low price (1) will buy a lot
        // of collateral. Grace period should be capped at max grace period.
        vm.mockCall(
            address(takerNFT),
            abi.encodeCall(takerNFT.previewSettlement, (loanId, minPrice)),
            abi.encode(100 * largeAmount, 0)
        );
        assertEq(loans.escrowGracePeriodEnd(loanId), expiration + gracePeriod);
    }

    function test_forecloseLoan() public {
        // just after grace period end
        checkForecloseLoan(twapPrice, 1, supplier);

        // long after max gracePeriod
        checkForecloseLoan(twapPrice, gracePeriod, supplier);

        // price increase
        checkForecloseLoan(largeAmount, gracePeriod, supplier);

        // price decrease
        checkForecloseLoan(1 ether, gracePeriod, supplier);
    }

    function test_forecloseLoan_byKeeper() public {
        // Set the keeper
        vm.startPrank(owner);
        loans.setKeeper(keeper);

        // Supplier allows the keeper to foreclose
        vm.startPrank(supplier);
        loans.setKeeperAllowed(true);

        // by keeper
        checkForecloseLoan(twapPrice, 1, keeper);
    }

    function test_forecloseLoan_settled() public {
        (uint loanId,,) = createAndCheckLoan();

        // skip past grace period
        skip(duration + gracePeriod + 1);
        mockOracle.setCheckPrice(true);
        updatePrice();
        prepareSwapToCollateralAtTWAPPrice();

        // settle taker position
        takerNFT.settlePairedPosition({takerId: loanId});

        // foreclose
        vm.startPrank(supplier);
        loans.forecloseLoan(loanId, defaultSwapParams(0));

        // loan and taker NFTs burned
        expectRevertERC721Nonexistent(loanId);
        loans.ownerOf(loanId);
        expectRevertERC721Nonexistent(loanId);
        takerNFT.ownerOf({ tokenId: loanId });
    }
}
