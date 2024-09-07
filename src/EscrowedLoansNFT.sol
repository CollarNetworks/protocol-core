// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity 0.8.22;

import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
// internal imports
import { CollarTakerNFT, ShortProviderNFT } from "./CollarTakerNFT.sol";
import { EscrowedSupplierNFT } from "./EscrowedSupplierNFT.sol";
import { BaseLoansNFT } from "./LoansNFT.sol";
import { IEscrowedLoansNFT } from "./interfaces/ILoansNFT.sol";
import { Rolls } from "./Rolls.sol";

contract EscrowedLoansNFT is IEscrowedLoansNFT, BaseLoansNFT {
    using SafeERC20 for IERC20;

    EscrowedSupplierNFT public immutable escrowNFT;

    mapping(uint loanId => uint escrowId) public loanIdToEscrowId;

    constructor(
        address initialOwner,
        CollarTakerNFT _takerNFT,
        EscrowedSupplierNFT _escrowNFT,
        string memory _name,
        string memory _symbol
    ) BaseLoansNFT(initialOwner, _takerNFT, _name, _symbol) {
        require(_escrowNFT.asset() == _takerNFT.collateralAsset(), "asset mismatch");
        escrowNFT = _escrowNFT;
    }

    // ----- VIEWS ----- //

    function canForeclose(uint loanId) public view returns (bool) {
        uint expiration = _expiration(loanId);

        // short-circuit to avoid calculating grace period with current price if not expired yet
        if (block.timestamp < expiration) {
            return false;
        }

        // calculate the grace period for settlement price (
        return block.timestamp > expiration + cappedGracePeriod(loanId);
    }

    function cappedGracePeriod(uint loanId) public view returns (uint) {
        uint expiration = _expiration(loanId);
        // if this is called before expiration (externally), estimate using current price
        uint settleTime = (block.timestamp < expiration) ? block.timestamp : expiration;
        // the price that will be used for settlement (past if available, or current if not)
        (uint oraclePrice,) = takerNFT.oracle().pastPriceWithFallback(uint32(settleTime));

        (uint cashAvailable,) =
            takerNFT.previewSettlement(takerNFT.getPosition(_takerId(loanId)), oraclePrice);

        // oracle price is for 1e18 tokens (regardless of decimals):
        // oracle-price = collateral-price * 1e18, so price = oracle-price / 1e18,
        // since collateral = cash / price, we get collateral = cash * 1e18 / oracle-price.
        // round down is ok since it's against the user (being foreclosed).
        // division by zero is not prevented because because a panic is ok with an invalid price
        uint collateralValue = cashAvailable * takerNFT.oracle().BASE_TOKEN_AMOUNT() / oraclePrice;

        // assume all available collateral can be used for fees (escrowNFT will cap between max and min)
        return escrowNFT.gracePeriodFromFees(loanIdToEscrowId[loanId], collateralValue);
    }

    // ----- MUTATIVE ----- //

    function openLoan(
        uint collateralAmount,
        uint minLoanAmount,
        SwapParams calldata swapParams,
        ShortProviderNFT providerNFT,
        uint shortOffer,
        uint escrowOffer,
        uint escrowFee
    ) external whenNotPaused returns (uint loanId, uint providerId, uint escrowId, uint loanAmount) {
        // pull escrow collateral + fee
        collateralAsset.safeTransferFrom(msg.sender, address(this), collateralAmount + escrowFee);

        uint expectedTakerId = takerNFT.nextPositionId();
        // get the supplier collateral for the swap
        collateralAsset.forceApprove(address(escrowNFT), collateralAmount + escrowFee);
        (escrowId,) = escrowNFT.startEscrow(escrowOffer, collateralAmount, escrowFee, expectedTakerId);
        // @dev no balance checks because contract holds no funds, mismatch will cause reverts

        // @dev Reentrancy assumption: no user state writes or reads BEFORE this call
        (loanId, providerId, loanAmount) =
            _openSwapAndMint(collateralAmount, providerNFT, shortOffer, swapParams);

        require(loanAmount >= minLoanAmount, "loan amount too low");
        // loanId is the takerId, but view was used before external calls so we need to ensure it matches still
        require(loanId == expectedTakerId, "unexpected loanId");
        // write the escrowId
        loanIdToEscrowId[loanId] = escrowId;

        // transfer the full loan amount on open
        cashAsset.safeTransfer(msg.sender, loanAmount);

        emit LoanOpened(
            msg.sender, address(providerNFT), shortOffer, collateralAmount, loanAmount, loanId, providerId
        );
    }

    function closeLoan(uint loanId, SwapParams calldata swapParams)
        external
        whenNotPaused
        onlyNFTOwnerOrKeeper(loanId)
        returns (uint collateralOut)
    {
        // @dev cache the user now, since _closeLoanNoTFOut will burn the NFT, so ownerOf will revert
        address user = ownerOf(loanId);

        collateralOut = _closeLoanNoTFOut(loanId, swapParams);

        _releaseEscrow(loanId, collateralOut, user);
    }

    function rollLoan(
        uint loanId,
        Rolls rolls,
        uint rollId,
        int minToUser, // cash
        uint newEscrowOffer,
        uint newEscrowFee // collateral
    )
        external
        whenNotPaused
        onlyNFTOwner(loanId)
        returns (uint newLoanId, uint newLoanAmount, int transferAmount)
    {
        // pull escrow fee
        collateralAsset.safeTransferFrom(msg.sender, address(this), newEscrowFee);

        // @dev _rollLoan is assumed to check that loan is not expired, so cannot be foreclosed
        (newLoanId, newLoanAmount, transferAmount) = _rollLoan(loanId, rolls, rollId, minToUser);

        // rotate escrows
        uint prevEscrowId = loanIdToEscrowId[loanId];
        collateralAsset.forceApprove(address(escrowNFT), newEscrowFee);
        (uint newEscrowId,, uint feeRefund) =
            escrowNFT.switchEscrow(prevEscrowId, newEscrowOffer, newEscrowFee, newLoanId);
        // @dev no balance checks because contract holds no funds, mismatch will cause reverts
        loanIdToEscrowId[newLoanId] = newEscrowId;

        // send potential interest fee refund
        collateralAsset.safeTransfer(msg.sender, feeRefund);
    }

    function unwrapAndCancelLoan(uint loanId) external whenNotPaused onlyNFTOwner(loanId) {
        bool escrowReleased = escrowNFT.getEscrow(loanIdToEscrowId[loanId]).released;

        if (escrowReleased) {
            // @dev unwrapping if escrow is released handles the case that escrow owner called
            // escrowNFT.lastResortSeizeEscrow() instead of loans.seizeEscrow() for any reason.
            // In this case, none of the other methods are callable because escrow is released
            // already, so the simplest thing that can be done to avoid locking user's funds is to cancel
            // the loan and send them their takerId to withdraw cash.
        } else {
            // do not allow to unwrap past expiry with unreleased escrow to prevent frontrunning
            // foreclosing. Past expiry either the user should call closeLoan(), or escrow owner should
            // call seizeEscrow()
            require(block.timestamp < _expiration(loanId), "loan expired");

            // release the escrowed user funds to the supplier since the user will not repay the loan
            uint toUser = escrowNFT.endEscrow(loanIdToEscrowId[loanId], 0);
            // @dev no balance checks because contract holds no funds, mismatch will cause reverts

            // send potential interest fee refund
            collateralAsset.safeTransfer(msg.sender, toUser);
        }

        // burning the token ensures this can only be called once
        _unwrapAndCancelLoan(loanId);
    }

    function seizeEscrow(uint loanId, SwapParams calldata swapParams) external whenNotPaused {
        // Funds beneficiary (escrow owner) should set the swapParams ideally.
        // A keeper can be needed because foreclosing can be time-sensitive (due to swap timing)
        // and because can be subject to griefing by opening many small loans.
        // @dev will also revert on non-existent (unminted / burned) escrow ID
        address escrowOwner = escrowNFT.ownerOf(loanIdToEscrowId[loanId]);
        require(_isSenderOrKeeperFor(escrowOwner), "not escrow NFT owner or allowed keeper");

        // @dev canForeclose's cappedGracePeriod uses twap-price, while actual foreclosing
        // later uses swap price. This has several implications:
        // 1. This protects foreclosing from price manipulation edge-cases.
        // 2. The final swap can be manipulated against the supplier, so either they or a trusted keeper
        //    should do it.
        // 3. This also means that swap amount may be different from the estimation in canForeclose
        //    if the period was capped by cash-time-value near the end a grace-period.
        //    In this case, if swap price is less than twap, the late fees may be slightly underpaid
        //    because of the swap-twap difference and slippage.
        // 4. Because the supplier (escrow owner) is controlling this call, they can manipulate the price
        //    to their benefit, but it still can't pay more than the lateFees calculated by time, and can only
        //    result in "leftovers" that will go to the borrower, so makes no sense for them to do (since
        //    manipulation costs money).
        require(canForeclose(loanId), "cannot foreclose yet");

        // @dev will revert if too early, although the canForeclose() check above will revert first
        uint cashAvailable = _settleAndWithdrawTaker(loanId);

        address user = ownerOf(loanId);
        // burn NFT from the user. Prevents any further actions for this loan.
        // Although they are not the caller, altering their assets is fine here because
        // foreClosing is a state with other negative consequence they should try to avoid anyway
        _burn(loanId);

        // @dev Reentrancy assumption: no user state writes or reads AFTER the swapper call in _swap.
        uint collateralOut = _swap(cashAsset, collateralAsset, cashAvailable, swapParams);

        // Release escrow, and send any leftovers to user. Their express trigger of balance update
        // (withdrawal) is neglected here due to being anyway in an undesirable state of being foreclosed
        // due to not repaying on time.
        _releaseEscrow(loanId, collateralOut, user);

        // TODO: event
    }

    // ----- INTERNAL MUTATIVE ----- //

    function _releaseEscrow(uint loanId, uint availableCollateral, address user) internal {
        uint escrowId = loanIdToEscrowId[loanId];
        // calculate late fee
        (uint lateFee, uint escrowed) = escrowNFT.lateFees(escrowId);

        uint owed = escrowed + lateFee;
        // if owing less than swapped, left over gains are for the user
        uint leftOver = availableCollateral > owed ? availableCollateral - owed : 0;
        // if owing more than swapped, use all, otherwise just what's owed
        uint toSupplier = availableCollateral <= owed ? availableCollateral : owed;
        // release from escrow, this can be smaller than available
        collateralAsset.forceApprove(address(escrowNFT), toSupplier);
        // releasedForUser is what escrow returns after deducting any shortfall
        // there should not be interest fee refund here because this method is called after expiry
        uint releasedToUser = escrowNFT.endEscrow(escrowId, toSupplier);
        // @dev no balance checks because contract holds no funds, mismatch will cause reverts

        // send to user the released and the leftovers. Zero-value-transfer is allowed
        collateralAsset.safeTransfer(user, releasedToUser + leftOver);

        // TODO: event?
    }

    // ----- INTERNAL VIEWS ----- //
}
