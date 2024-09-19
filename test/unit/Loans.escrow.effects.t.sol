// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

import { LoansBasicEffectsTest, ILoansNFT } from "./Loans.basic.effects.t.sol";

contract LoansEscrowEffectsTest is LoansBasicEffectsTest {
    function setUp() public virtual override {
        super.setUp();
        openEscrowLoan = true;
    }

    function expectedGracePeriodEnd(uint loanId, uint atPrice) internal returns (uint) {
        uint expiration = takerNFT.getPosition({ takerId: loanId }).expiration;
        (uint cashAvailable,) = takerNFT.previewSettlement({ takerId: loanId, endPrice: atPrice });
        uint collateral = cashAvailable * 1e18 / atPrice; // 1e18 is BASE_TOKEN_AMOUNT
        uint gracePeriod = escrowNFT.cappedGracePeriod(loans.getLoan(loanId).escrowId, collateral);
        return expiration + gracePeriod;
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

        // at expiry
        skip(duration);
        updatePrice();
        expected = expectedGracePeriodEnd(loanId, twapPrice);

        // this doesn't effect anything, since price needs to be updated manually, but
        twapPrice *= 2;

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
        updatePrice(highPrice);
        assertEq(loans.escrowGracePeriodEnd(loanId), expectedGracePeriodEnd(loanId, highPrice));

        // Price decrease
        uint lowPrice = twapPrice / 2;
        updatePrice(lowPrice);
        assertEq(loans.escrowGracePeriodEnd(loanId), expectedGracePeriodEnd(loanId, lowPrice));

        // min grace period (for very high price), very high price means cash is worth 0 collateral
        updatePrice(type(uint).max);
        assertEq(loans.escrowGracePeriodEnd(loanId), expiration + escrowNFT.MIN_GRACE_PERIOD());

        // min grace period (for very low price), because user has no cash (position is worth 0)
        uint minPrice = 1;
        updatePrice(minPrice);
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
}
