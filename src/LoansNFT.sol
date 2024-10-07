// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity 0.8.22;

import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { CollarTakerNFT, CollarProviderNFT, BaseNFT, ConfigHub } from "./CollarTakerNFT.sol";
import { Rolls } from "./Rolls.sol";
import { EscrowSupplierNFT, IEscrowSupplierNFT } from "./EscrowSupplierNFT.sol";
import { ISwapper } from "./interfaces/ISwapper.sol";
import { ILoansNFT } from "./interfaces/ILoansNFT.sol";

/**
 * @title LoansNFT
 * @dev This contract manages opening, closing, and rolling of collateralized loans via Collar positions,
 * with optional escrow support.
 *
 * Main Functionality:
 * 1. Allows users to open loans by providing collateral and borrowing against it, with or without escrow.
 * 2. Handles the swapping of collateral to the cash asset via allowed Swappers (that use dex routers).
 * 3. Wraps CollarTakerNFT (keeps it in the contract), and mints an NFT with loanId == takerId to the user.
 * 4. Manages loan closure, including repayment and swapping back to collateral.
 * 5. Provides keeper functionality for automated loan closure and foreclosure to mitigate price fluctuation risks.
 * 6. Allows rolling (extending) the loan via an owner and user approved Rolls contract.
 * 7. Supports escrow functionality, including opening escrow loans, switching escrows during rolls, and foreclosure.
 *
 * Key Assumptions and Prerequisites:
 * 1. Allowed Swappers and the underlying dex routers / aggregators are trusted and properly implemented.
 * 2. Depends on ConfigHub, CollarTakerNFT, CollarProviderNFT, EscrowSupplierNFT, Rolls, and their
 * dependencies (Oracle).
 * 3. Assets (ERC-20) used are standard compliant (non-rebasing, no transfer fees, no callbacks).
 *
 * Design Considerations:
 * 1. Mints and holds CollarTakerNFT NFTs, and mints LoanNFT IDs (equal to the wrapped CollarTakerNFT ID)
 *    to borrowers to represent loan positions, allowing for potential secondary market trading.
 * 2. Includes a keeper system for automated loan closure and foreclosure to allow users and escrow suppliers
 *    to delegate time-sensitive actions.
 */
contract LoansNFT is ILoansNFT, BaseNFT {
    using SafeERC20 for IERC20;

    uint internal constant BIPS_BASE = 10_000;
    address internal constant UNSET = address(0); // "magic" for disabled address

    /// should be set to not be overly restrictive since is mostly sanity-check
    uint public constant MAX_SWAP_TWAP_DEVIATION_BIPS = 500;

    string public constant VERSION = "0.2.0";

    // ----- IMMUTABLES ----- //
    CollarTakerNFT public immutable takerNFT;
    IERC20 public immutable cashAsset;
    IERC20 public immutable collateralAsset;

    // ----- STATE VARIABLES ----- //
    /// @notice Stores loan information for each NFT ID
    mapping(uint loanId => Loan) internal loans;
    // optional keeper (set by contract owner) that's needed for the time-sensitive
    // swap back during loan closing
    address public closingKeeper;
    // callers (users or escrow owners) that allow a keeper for loan closing
    mapping(address sender => bool enabled) public allowsClosingKeeper;
    // the currently configured & allowed rolls contract for this takerNFT and cash asset
    Rolls public currentRolls;
    // the currently configured provider contract for opening (may change)
    CollarProviderNFT public currentProviderNFT;
    // the currently configured escrow contract for opening (may change)
    EscrowSupplierNFT public currentEscrowNFT;
    // a convenience view to allow querying for a swapper onchain / FE without subgraph
    address public defaultSwapper;
    // contracts used for swaps, including the defaultSwapper
    mapping(address swapper => bool allowed) public allowedSwappers;

    constructor(address initialOwner, CollarTakerNFT _takerNFT, string memory _name, string memory _symbol)
        BaseNFT(initialOwner, _name, _symbol)
    {
        takerNFT = _takerNFT;
        cashAsset = _takerNFT.cashAsset();
        collateralAsset = _takerNFT.collateralAsset();
        _setConfigHub(_takerNFT.configHub());
    }

    modifier onlyNFTOwner(uint loanId) {
        /// @dev will also revert on non-existent (unminted / burned) taker ID
        require(msg.sender == ownerOf(loanId), "not NFT owner");
        _;
    }

    // ----- VIEW FUNCTIONS ----- //

    /// @notice Retrieves loan information for a given taker NFT ID
    /// @dev return memory struct (the default getter returns tuple)
    function getLoan(uint loanId) external view returns (Loan memory) {
        return loans[loanId];
    }

    /// @notice Calculates the end of the grace period using position cash value available for late fees.
    /// @dev Uses TWAP price for calculations, handles both pre and post-expiration scenarios
    /// @param loanId The ID of the loan to calculate for
    /// @return The timestamp when the grace period ends
    function escrowGracePeriodEnd(uint loanId) public view returns (uint) {
        uint expiration = _expiration(loanId);

        // if this is called before expiration (externally), estimate value using current price
        uint settleTime = Math.min(block.timestamp, expiration);
        // the price that will be used for settlement (past if available, or current if not)
        (uint oraclePrice,) = takerNFT.oracle().pastPriceWithFallback(uint32(settleTime));

        (uint cashAvailable,) = takerNFT.previewSettlement(_takerId(loanId), oraclePrice);

        // oracle price is for 1e18 tokens (regardless of decimals):
        // oracle-price = collateral-price * 1e18, so price = oracle-price / 1e18,
        // since collateral = cash / price, we get collateral = cash * 1e18 / oracle-price.
        // round down is ok since it's against the user (being foreclosed).
        // division by zero is not prevented because because a panic is ok with an invalid price
        uint collateral = cashAvailable * takerNFT.oracle().BASE_TOKEN_AMOUNT() / oraclePrice;

        Loan memory loan = loans[loanId];
        // assume all available collateral can be used for fees (escrowNFT will cap between max and min)
        uint gracePeriod = loan.escrowNFT.cappedGracePeriod(loan.escrowId, collateral);
        // always after expiration, also cappedGracePeriod() is at least min-grace-period
        return expiration + gracePeriod;
    }

    // ----- STATE CHANGING FUNCTIONS ----- //

    // ----- User / Keeper methods ----- //

    /**
     * @notice Opens a new loan by providing collateral and borrowing against it
     *      1. Transfers collateral from the user to this contract
     *      2. Swaps collateral for cash
     *      3. Opens a loan position using the CollarTakerNFT contract
     *      4. Transfers the borrowed amount to the user
     *      5. Transfers the minted NFT to the user
     * @param collateralAmount The amount of collateral asset to be provided
     * @param minLoanAmount The minimum acceptable loan amount (slippage protection)
     * @param swapParams SwapParams struct with:
     *     - The minimum acceptable amount of cash from the collateral swap (slippage protection)
     *     - an allowed Swapper
     *     - any extraData the swapper needs to use
     * @param providerOffer The ID of the liquidity offer to use from the provider
     * @return loanId The ID of the minted NFT representing the loan
     * @return providerId The ID of the minted CollarProviderNFT paired with this loan
     * @return loanAmount The actual amount of the loan opened in cash asset
     */
    function openLoan(
        uint collateralAmount,
        uint minLoanAmount,
        SwapParams calldata swapParams,
        uint providerOffer
    ) public whenNotPaused returns (uint loanId, uint providerId, uint loanAmount) {
        return _openLoan(collateralAmount, minLoanAmount, swapParams, providerOffer, false, 0);
    }

    /**
     * @notice Opens a new escrow-type loan by providing collateral and borrowing against it
     *      1. Transfers collateral from the user to this contract
     *      2. Uses the escrow contract to deposit user's callateral, and take supplier's collateral
     *      3. Swaps collateral for cash
     *      4. Opens a loan position using the CollarTakerNFT contract
     *      5. Transfers the borrowed amount to the user
     *      6. Transfers the minted NFT to the user
     * @param collateralAmount The amount of collateral asset to be provided
     * @param minLoanAmount The minimum acceptable loan amount (slippage protection)
     * @param swapParams SwapParams struct with:
     *     - The minimum acceptable amount of cash from the collateral swap (slippage protection)
     *     - an allowed Swapper
     *     - any extraData the swapper needs to use
     * @param providerOffer The ID of the liquidity offer to use from the provider
     * @param escrowOffer The ID of the escrow offer to use from the supplier
     * @return loanId The ID of the minted NFT representing the loan
     * @return providerId The ID of the minted CollarProviderNFT paired with this loan
     * @return loanAmount The actual amount of the loan opened in cash asset
     */
    function openEscrowLoan(
        uint collateralAmount,
        uint minLoanAmount,
        SwapParams calldata swapParams,
        uint providerOffer,
        uint escrowOffer
    ) external whenNotPaused returns (uint loanId, uint providerId, uint loanAmount) {
        return _openLoan(collateralAmount, minLoanAmount, swapParams, providerOffer, true, escrowOffer);
    }

    /**
     * @notice Closes an existing loan, repaying the borrowed amount and returning collateral.
     * If escrow was used, releases it by returning the swapped collateral in exchange for the user's collateral
     * handling any late fees.
     * The amount of collateral returned may be smaller or larger than originally deposited,
     * depending on the position's settlement result, fees, and the final swap.
     * This method can be called by either the loan's owner (the CollarTakerNFT owner) or by a keeper
     * if the keeper was allowed by the current owner (by calling setKeeperAllowed). Using a keeper
     * may be needed because the call's timing should be as close to settlement as possible, to
     * avoid additional price exposure since the swaps price's is always spot (not past).
     * To settle in cash (and avoid the repayment and swap) the user can instead call unwrapAndCancelLoan
     * to unwrap the CollarTakerNFT to settle it and withdraw it directly.
     * @dev the user must have approved this contract prior to calling for cash asset for repayment.
     * @dev This function handles the entire loan closure process:
     *      1. Transfers the repayment amount from the user to this contract
     *      2. Settles the CollarTakerNFT position
     *      3. Withdraws any available funds from the settled position
     *      4. Swaps the total cash amount back to collateral asset
     *      5. Releases the escrow if needed
     *      6. Transfers the collateral back to the user
     *      7. Burns the NFT
     * @param loanId The ID of the CollarTakerNFT representing the loan to close
     * @param swapParams SwapParams struct with:
     *     - The minimum acceptable amount of collateral to receive (slippage protection)
     *     - an allowed Swapper
     *     - any extraData the swapper needs to use
     * @return collateralOut The actual amount of collateral asset returned to the user
     */
    function closeLoan(uint loanId, SwapParams calldata swapParams)
        external
        whenNotPaused // also checked in _burn (mutations false positive)
        returns (uint collateralOut)
    {
        /// @dev will also revert on non-existent (unminted / burned) loan ID
        require(_isSenderOrKeeperFor(ownerOf(loanId)), "not NFT owner or allowed keeper");

        // @dev cache the user now, since _closeLoanNoTFOut will burn the NFT, so ownerOf will revert
        address user = ownerOf(loanId);

        uint fromSwap = _closeLoanNoTFOut(loanId, swapParams);

        collateralOut = _conditionalReleaseEscrow(loanId, fromSwap);

        collateralAsset.safeTransfer(user, collateralOut);
    }

    /**
     * @notice Rolls an existing loan to a new taker position with updated terms via a Rolls contract.
     * The loan amount is updated according to the funds transferred (excluding the roll-fee), and the
     * collateral is unchanged.
     * If the loan uses escrow, the previous escrow is switched for a new escrow, the new fee is pulled
     * from the user, and any refund for the previous escrow fee is sent to the user.
     * @dev The user must have approved this contract prior to calling:
     *      - Cash asset for potential repayment (if needed according for Roll execution)
     *      - Collateral asset for new escrow fee (if the original loan used escrow)
     * @param loanId The ID of the NFT representing the loan to be rolled
     * @param rollId The ID of the roll offer to be executed
     * @param minToUser The minimum acceptable transfer to user (negative if expecting to pay)
     * @param newEscrowOffer An escrowNFT offer for the new escrow to be opened if the loan is using
     * an escrow. The same escrowNFT contract will be used, but an offer must be supplied.
     * Argument ignored if escrow was not used.
     * @return newLoanId The ID of the newly minted NFT representing the rolled loan
     * @return newLoanAmount The updated loan amount after rolling
     * @return transferAmount The actual transfer to user (or from user if negative) including roll-fee
     */
    function rollLoan(uint loanId, uint rollId, int minToUser, uint newEscrowOffer)
        external
        whenNotPaused // also checked in _burn (mutations false positive)
        onlyNFTOwner(loanId)
        returns (uint newLoanId, uint newLoanAmount, int transferAmount)
    {
        // check opening loans is still allowed (not in exit-only mode)
        require(configHub.canOpen(address(this)), "unsupported loans contract");
        // @dev rolls contract is assumed to not allow rolling an expired or settled position,
        // but checking explicitly is safer and easier to review
        require(block.timestamp <= _expiration(loanId), "loan expired");
        // burn token. This prevents any further calls for this loan
        _burn(loanId);

        // pull and push NFT and cash, execute roll, emit event
        (uint newTakerId, int _transferAmount, int rollFee) = _executeRoll(loanId, rollId, minToUser);
        transferAmount = _transferAmount;

        Loan memory prevLoan = loans[loanId];
        // calculate the updated loan amount (may have changed due to the roll)
        newLoanAmount = _calculateNewLoan(transferAmount, rollFee, prevLoan.loanAmount);

        // switch escrows if escrow was used, @dev assumes interest fee approval
        uint newEscrowId = _conditionalSwitchEscrow(prevLoan, newEscrowOffer, newTakerId);

        // set the new ID from new taker ID
        newLoanId = _newLoanIdCheck(newTakerId);
        // store the new loan data
        loans[newLoanId] = Loan({
            collateralAmount: prevLoan.collateralAmount,
            loanAmount: newLoanAmount,
            usesEscrow: prevLoan.usesEscrow,
            escrowNFT: prevLoan.escrowNFT,
            escrowId: newEscrowId
        });
        // check escrow and loan have matching fields
        _conditionalEscrowValidations(newLoanId);

        // mint the new loan NFT to the user, keep the taker NFT (with the same ID) in this contract
        _mint(msg.sender, newLoanId); // @dev does not use _safeMint to avoid reentrancy

        emit LoanRolled(
            msg.sender, loanId, rollId, newLoanId, prevLoan.loanAmount, newLoanAmount, transferAmount
        );
    }

    /**
     * @notice Cancels an active loan, burns the loan NFT, and unwraps the taker NFT, to allow
     * disconnecting it from the loan. If escrow was used, checks if unwrapping is currently allowed,
     * and releases the escrow if it wasn't released.
     * @param loanId The ID representing the loan to unwrap and cancel
     */
    function unwrapAndCancelLoan(uint loanId) external whenNotPaused onlyNFTOwner(loanId) {
        // release escrow if needed with refunds (interest fee) to sender
        _conditionalCheckAndCancelEscrow(loanId, msg.sender);

        // burn token. This prevents any further calls for this loan
        _burn(loanId);

        // unwrap: send the taker NFT to user
        takerNFT.transferFrom(address(this), msg.sender, _takerId(loanId));

        emit LoanCancelled(loanId, msg.sender);
    }

    /**
     * @notice Forecloses an escrow loan that was not repaid on time, after grace period is finished.
     * The grace period and its late-fee APR is determined by the initial supplier's offer. The actual period
     * is dynamically limited by the position's cash, to minimize late-fee underpayment.
     * @dev Can be called only by the escrow owner or an allowed keeper (if authorized by escrow owner)
     * @param loanId The ID of the loan to foreclose
     * @param swapParams Swap parameters for cash to collateral conversion
     */
    function forecloseLoan(uint loanId, SwapParams calldata swapParams) external whenNotPaused {
        Loan memory loan = loans[loanId];
        require(loan.usesEscrow, "not an escrowed loan");

        (EscrowSupplierNFT escrowNFT, uint escrowId) = (loan.escrowNFT, loan.escrowId);
        // Funds beneficiary (escrow owner) should set the swapParams ideally.
        // A keeper can be needed because foreclosing can be time-sensitive (due to swap timing)
        // and because can be subject to griefing by opening many small loans.
        // @dev will also revert on non-existent (unminted / burned) escrow ID
        address escrowOwner = escrowNFT.ownerOf(escrowId);
        require(_isSenderOrKeeperFor(escrowOwner), "not escrow owner or allowed keeper");

        // get the user address here, both to ensure loan is active (will revert otherwise)
        // and because address won't be available after burning
        address user = ownerOf(loanId);

        // @dev escrowGracePeriodEnd uses twap-price, while actual foreclosing swap is using spot price.
        // This has several implications:
        // 1. This protects foreclosing from price manipulation edge-cases.
        // 2. The final swap can be manipulated against the supplier, so either they or a trusted keeper
        //    should do it.
        // 3. This also means that swap amount may be different from the estimation in escrowGracePeriodEnd
        //    if the period was capped by cash-time-value near the end a grace-period.
        //    In this case, if swap price is less than twap, the late fees may be slightly underpaid
        //    because of the swap-twap difference and slippage.
        // 4. Because the supplier (escrow owner) is controlling this call, they can manipulate the price
        //    to their benefit, but it still can't pay more than the lateFees calculated by time, and can only
        //    result in "leftovers" that will go to the borrower, so makes no sense for them to do (since
        //    manipulation costs money).
        require(block.timestamp > escrowGracePeriodEnd(loanId), "cannot foreclose yet");

        // burn NFT from the user. Prevents any further actions for this loan.
        // Although they are not the caller, altering their assets is fine here because
        // foreClosing is a state with other negative consequence they should try to avoid anyway
        _burn(loanId);

        // @dev will revert if too early, although the escrowGracePeriodEnd check above will revert first
        uint cashAvailable = _settleAndWithdrawTaker(loanId);

        // @dev Reentrancy assumption: no user state writes or reads AFTER the swapper call in _swap.
        uint fromSwap = _swap(cashAsset, collateralAsset, cashAvailable, swapParams);

        // Release escrow, and send any leftovers to user. Their express trigger of balance update
        // (withdrawal) is neglected here due to being anyway in an undesirable state of being foreclosed
        // due to not repaying on time.
        uint toUser = _releaseEscrow(escrowNFT, escrowId, fromSwap);
        collateralAsset.safeTransfer(user, toUser);

        emit LoanForeclosed(loanId, escrowId, fromSwap, toUser);
    }

    /**
     * @notice Allows or disallows a keeper for closing loans on behalf of a caller
     * @dev The allowance is tied to the the caller address, for any action that a keeper can
     *      do. So if they buy a new loan NFT, and they previously allowed a keeper - it is
     *      allowed for their new NFT as well.
     * @dev A user that sets this allowance has to also grant NFT and cash approvals to this contract
     * that should be valid when closeLoan is called by the keeper.
     * @param enabled True to allow the keeper, false to disallow
     */
    function setKeeperAllowed(bool enabled) external whenNotPaused {
        allowsClosingKeeper[msg.sender] = enabled;
        emit ClosingKeeperAllowed(msg.sender, enabled);
    }

    // ----- Admin methods ----- //

    /// @notice Sets the address of the closing keeper
    /// @dev only owner
    function setKeeper(address keeper) external onlyOwner {
        emit ClosingKeeperUpdated(closingKeeper, keeper);
        closingKeeper = keeper;
    }

    /// @notice Sets the dependency contracts to be used for rolling and opening loans
    /// @dev swapper is not set here because multiple swappers can be allowed at a time
    /// @dev only owner
    function setContracts(Rolls rolls, CollarProviderNFT providerNFT, EscrowSupplierNFT escrowNFT)
        external
        onlyOwner
    {
        require(address(rolls) == UNSET || rolls.takerNFT() == takerNFT, "rolls taker mismatch");
        require(
            address(providerNFT) == UNSET || providerNFT.taker() == address(takerNFT),
            "provider taker mismatch"
        );
        require(address(escrowNFT) == UNSET || escrowNFT.asset() == collateralAsset, "escrow asset mismatch");
        currentRolls = rolls;
        currentProviderNFT = providerNFT;
        currentEscrowNFT = escrowNFT;
        emit ContractsUpdated(rolls, providerNFT, escrowNFT);
    }

    /// @notice Enables or disables swappers and sets the defaultSwapper view.
    /// When no swapper is allowed, opening and closing loans will not be possible.
    /// The default swapper is a convenience view, and it's best to keep it up to date
    /// and to make sure the default one is allowed.
    /// @dev only owner
    function setSwapperAllowed(address swapper, bool allowed, bool setDefault) external onlyOwner {
        if (allowed) require(bytes(ISwapper(swapper).VERSION()).length > 0, "invalid swapper");
        // it is possible to disallow and set as default at the same time. E.g., to unset the default
        // to zero. Worst case is loan cannot be closed and is settled via takerNFT
        if (setDefault) defaultSwapper = swapper;
        allowedSwappers[swapper] = allowed;
        emit SwapperSet(swapper, allowed, setDefault);
    }

    // ----- INTERNAL MUTATIVE ----- //

    /// @dev handles both escrow and non-escrow loans
    function _openLoan(
        uint collateralAmount,
        uint minLoanAmount,
        SwapParams calldata swapParams,
        uint providerOffer,
        bool usesEscrow,
        uint escrowOffer
    ) internal returns (uint loanId, uint providerId, uint loanAmount) {
        require(configHub.canOpen(address(this)), "unsupported loans contract");
        // provider NFT is checked by taker
        // escrow NFT is checked in _conditionalOpenEscrow, taker is checked in _swapAndMintPaired

        // @dev in additional to this, escrow interest fee may also be pulled in _conditionalOpenEscrow
        // So approval needs to be for this + interest fee
        collateralAsset.safeTransferFrom(msg.sender, address(this), collateralAmount);

        // handle optional escrow, must be done first, to use "supplier's" collateral in swap
        (EscrowSupplierNFT escrowNFT, uint escrowId) =
            _conditionalOpenEscrow(usesEscrow, collateralAmount, escrowOffer);

        // @dev Reentrancy assumption: no user state writes or reads BEFORE this call
        uint takerId;
        (takerId, providerId, loanAmount) = _swapAndMintCollar(collateralAmount, providerOffer, swapParams);
        require(loanAmount >= minLoanAmount, "loan amount too low");

        loanId = _newLoanIdCheck(takerId);
        // store the loan opening data
        loans[loanId] = Loan({
            collateralAmount: collateralAmount,
            loanAmount: loanAmount,
            usesEscrow: usesEscrow,
            escrowNFT: escrowNFT, // save the escrow used
            escrowId: escrowId
        });
        // some validations that can only be done here, after everything is available
        _conditionalEscrowValidations(loanId);
        // mint the loan NFT to the borrower, keep the taker NFT (with the same ID) in this contract
        _mint(msg.sender, loanId); // @dev does not use _safeMint to avoid reentrancy

        // transfer the full loan amount on open
        cashAsset.safeTransfer(msg.sender, loanAmount);

        emit LoanOpened(loanId, msg.sender, providerOffer, collateralAmount, loanAmount);
    }

    /// @dev swaps collateral to cash and mints collar position
    function _swapAndMintCollar(uint collateralAmount, uint offerId, SwapParams calldata swapParams)
        internal
        returns (uint takerId, uint providerId, uint loanAmount)
    {
        require(configHub.canOpen(address(takerNFT)), "unsupported taker contract");
        // provider contract is valid
        require(address(currentProviderNFT) != UNSET, "provider contract unset");
        // 0 collateral is later checked to mean non-existing loan, also prevents div-zero
        require(collateralAmount != 0, "invalid collateral amount");

        // swap collateral
        // @dev Reentrancy assumption: no user state writes or reads BEFORE the swapper call in _swap.
        // The only state reads before are owner-set state: pause and swapper allowlist.
        uint cashFromSwap = _swapCollateralWithTwapCheck(collateralAmount, swapParams);

        uint putStrikePercent = currentProviderNFT.getOffer(offerId).putStrikePercent;

        // this assumes LTV === put strike price
        loanAmount = putStrikePercent * cashFromSwap / BIPS_BASE;
        // everything that remains is locked on the put side in the collar position
        uint takerLocked = cashFromSwap - loanAmount;

        // approve the taker contract
        cashAsset.forceApprove(address(takerNFT), takerLocked);

        // stores, mints, calls providerNFT and mints there, emits the event
        (takerId, providerId) = takerNFT.openPairedPosition(takerLocked, currentProviderNFT, offerId);
    }

    function _swapCollateralWithTwapCheck(uint collateralAmount, SwapParams calldata swapParams)
        internal
        returns (uint cashFromSwap)
    {
        cashFromSwap = _swap(collateralAsset, cashAsset, collateralAmount, swapParams);

        // @dev note that TWAP price is used for payout decision in CollarTakerNFT, and swap price
        // only affects the takerLocked passed into it - so does not affect the provider, only the user
        _checkSwapPrice(cashFromSwap, collateralAmount);
    }

    /// @dev swap logic with balance and slippage checks
    /// @dev reentrancy assumption: _swap is called either before or after all internal user state
    /// writes or reads. Such that if there's a reentrancy (e.g., via a malicious token in a
    /// multi-hop route), it should NOT be able to take advantage of any inconsistent state.
    function _swap(IERC20 assetIn, IERC20 assetOut, uint amountIn, SwapParams calldata swapParams)
        internal
        returns (uint amountOut)
    {
        // check swapper allowed
        require(allowedSwappers[swapParams.swapper], "swapper not allowed");

        uint balanceBefore = assetOut.balanceOf(address(this));
        // approve the swapper
        assetIn.forceApprove(swapParams.swapper, amountIn);

        /* @dev It may be tempting to simplify this by using an arbitrary call instead of a
        specific interface such as ISwapper. However:
        1. using a specific interface is safer because it makes stealing approvals impossible.
        This is safer than depending only on the allowlist.
        2. an arbitrary call payload for a swap is more difficult to construct and inspect
        so requires more user trust on the FE.
        3. swap's amountIn would need to be calculated off-chain, which in case of closing
        the loan is problematic, since it depends on withdrawal from the position.
        */
        uint amountOutSwapper = ISwapper(swapParams.swapper).swap(
            assetIn, assetOut, amountIn, swapParams.minAmountOut, swapParams.extraData
        );
        // Calculate the actual amount received
        amountOut = assetOut.balanceOf(address(this)) - balanceBefore;
        // check balance is updated as expected and as reported by swapper (no other balance changes)
        // asset cannot be fee-on-transfer or rebasing (e.g., internal shares accounting)
        require(amountOut == amountOutSwapper, "balance update mismatch");
        // check amount is as expected by user
        require(amountOut >= swapParams.minAmountOut, "slippage exceeded");
    }

    /// @dev loan closure logic without final transfer
    /// @dev access control (loanId owner ot their keeper) is expected to be checked by caller
    /// @dev this method DOES NOT transfer the swapped collateral to user
    function _closeLoanNoTFOut(uint loanId, SwapParams calldata swapParams)
        internal
        returns (uint collateralOut)
    {
        // @dev user is the NFT owner, since msg.sender can be a keeper
        // If called by keeper, the user must trust it because:
        // - call pulls user funds (for repayment)
        // - call burns the NFT from user
        // - call sends the final funds to the user
        // - keeper sets the SwapParams and its slippage parameter
        address user = ownerOf(loanId);
        uint loanAmount = loans[loanId].loanAmount;

        // burn token. This prevents any other (or reentrant) calls for this loan
        _burn(loanId);

        // total cash available
        // @dev will check settle, or try to settle - will revert if cannot settle yet (not expired)
        uint takerWithdrawal = _settleAndWithdrawTaker(loanId);

        // @dev assumes approval
        cashAsset.safeTransferFrom(user, address(this), loanAmount);

        // @dev Reentrancy assumption: no user state writes or reads AFTER the swapper call in _swap.
        uint cashAmount = loanAmount + takerWithdrawal;
        collateralOut = _swap(cashAsset, collateralAsset, cashAmount, swapParams);

        emit LoanClosed(loanId, msg.sender, user, loanAmount, cashAmount, collateralOut);
    }

    function _settleAndWithdrawTaker(uint loanId) internal returns (uint withdrawnAmount) {
        uint takerId = _takerId(loanId);

        // position could have been settled by user or provider already
        bool settled = takerNFT.getPosition(takerId).settled;
        if (!settled) {
            /// @dev this will revert on: too early, no position, calculation issues, ...
            takerNFT.settlePairedPosition(takerId);
        }

        /// @dev this should not be optional, since otherwise there is no point to the entire call
        /// (and the position NFT would be burned already, so would not belong to sender)
        withdrawnAmount = takerNFT.withdrawFromSettled(takerId, address(this));
    }

    function _executeRoll(uint loanId, uint rollId, int minToUser)
        internal
        returns (uint newTakerId, int transferAmount, int rollFee)
    {
        // rolls contract is valid, @dev canOpen is not checked because Rolls is no long living
        // user positions that should allow exit-only (for which canOpen is needed)
        require(address(currentRolls) != UNSET, "rolls contract unset");
        // avoid using invalid data
        require(currentRolls.getRollOffer(rollId).active, "invalid rollId");
        // @dev Rolls will check if taker position is still valid (unsettled)

        uint initialBalance = cashAsset.balanceOf(address(this));

        // get transfer amount and fee from rolls
        int transferPreview;
        (transferPreview,, rollFee) =
            currentRolls.calculateTransferAmounts(rollId, takerNFT.currentOraclePrice());

        // pull cash
        if (transferPreview < 0) {
            uint fromUser = uint(-transferPreview); // will revert for type(int).min
            // pull cash first, because rolls will try to pull it (if needed) from this contract
            // @dev assumes approval
            cashAsset.safeTransferFrom(msg.sender, address(this), fromUser);
            // allow rolls to pull this cash
            cashAsset.forceApprove(address(currentRolls), fromUser);
        }

        // approve the taker NFT for rolls to pull
        takerNFT.approve(address(currentRolls), _takerId(loanId));
        // execute roll
        (newTakerId,, transferAmount,) = currentRolls.executeRoll(rollId, minToUser);
        // check return value matches preview, which was used for updating the loan and pulling cash
        require(transferAmount == transferPreview, "unexpected transfer amount");
        // check slippage (would have been checked in Rolls as well)
        require(transferAmount >= minToUser, "roll transfer < minToUser");

        // transfer cash if should have received any
        if (transferAmount > 0) {
            // @dev this will revert if rolls contract didn't actually pay above
            cashAsset.safeTransfer(msg.sender, uint(transferAmount));
        }

        // there should be no balance change for the contract (which might happen e.g., if rolls contract
        // overestimated amount to pull from user, or under-reported return value)
        require(cashAsset.balanceOf(address(this)) == initialBalance, "contract balance changed");
    }

    // ----- Conditional escrow mutative methods ----- //

    function _conditionalOpenEscrow(bool usesEscrow, uint escrowed, uint escrowOffer)
        internal
        returns (EscrowSupplierNFT escrowNFT, uint escrowId)
    {
        if (usesEscrow) {
            escrowNFT = currentEscrowNFT;
            // escrow contract is valid
            require(address(escrowNFT) != UNSET, "escrow contract unset");
            // whitelisted only
            require(configHub.canOpen(address(escrowNFT)), "unsupported escrow contract");

            uint fee = _pullEscrowFee(escrowNFT, escrowOffer, escrowed);
            // @dev collateralAmount was pulled already before calling this method
            collateralAsset.forceApprove(address(escrowNFT), escrowed + fee);
            (escrowId,) = escrowNFT.startEscrow({
                offerId: escrowOffer,
                escrowed: escrowed,
                fee: fee,
                loanId: takerNFT.nextPositionId() // @dev should be checked later to correspond
             });
            // @dev no balance checks because contract holds no funds, mismatch will cause reverts
        } else {
            // returns default empty values
        }
    }

    /// @dev escrow switch during roll
    function _conditionalSwitchEscrow(Loan memory prevLoan, uint escrowOffer, uint expectedNewLoanId)
        internal
        returns (uint newEscrowId)
    {
        if (prevLoan.usesEscrow) {
            // check this escrow is still allowed
            require(configHub.canOpen(address(prevLoan.escrowNFT)), "unsupported escrow contract");

            uint newFee = _pullEscrowFee(prevLoan.escrowNFT, escrowOffer, prevLoan.collateralAmount);
            collateralAsset.forceApprove(address(prevLoan.escrowNFT), newFee);
            // rotate escrows
            uint feeRefund;
            (newEscrowId,, feeRefund) = prevLoan.escrowNFT.switchEscrow({
                releaseEscrowId: prevLoan.escrowId,
                offerId: escrowOffer,
                newLoanId: expectedNewLoanId, // @dev should be validated after this
                newFee: newFee
            });

            // send potential interest fee refund
            collateralAsset.safeTransfer(msg.sender, feeRefund);
        } else {
            // returns default empty value
        }
    }

    function _pullEscrowFee(EscrowSupplierNFT escrowNFT, uint escrowOffer, uint escrowed)
        internal
        returns (uint interestFee)
    {
        // calc and pull the interest fee to be paid upfront
        interestFee = escrowNFT.interestFee(escrowOffer, escrowed);
        // explicit approval check here to provide clearer error since fee amount is not provided by user
        uint allowance = collateralAsset.allowance(msg.sender, address(this));
        require(allowance >= interestFee, "insufficient allowance for escrow fee");
        collateralAsset.safeTransferFrom(msg.sender, address(this), interestFee);
    }

    function _conditionalReleaseEscrow(uint loanId, uint fromSwap) internal returns (uint collateralOut) {
        Loan memory loan = loans[loanId];
        // collateral is what's released by escrow, or return the full swap amount if escrow not used
        return loan.usesEscrow ? _releaseEscrow(loan.escrowNFT, loan.escrowId, fromSwap) : fromSwap;
    }

    function _releaseEscrow(EscrowSupplierNFT escrowNFT, uint escrowId, uint fromSwap)
        internal
        returns (uint collateralOut)
    {
        // get late fee owing
        (uint lateFee, uint escrowed) = escrowNFT.lateFees(escrowId);

        // if owing more than swapped, use all, otherwise just what's owed
        uint toEscrow = Math.min(fromSwap, escrowed + lateFee);
        // if owing less than swapped, left over gains are for the user
        uint leftOver = fromSwap - toEscrow;

        // release from escrow, this can be smaller than available
        collateralAsset.forceApprove(address(escrowNFT), toEscrow);
        // fromEscrow is what escrow returns after deducting any shortfall.
        // (although not problematic, there should not be any interest fee refund here,
        // because this method is called after expiry)
        uint fromEscrow = escrowNFT.endEscrow(escrowId, toEscrow);
        // @dev no balance checks because contract holds no funds, mismatch will cause reverts

        // the released and the leftovers to be sent to user. Zero-value-transfer is allowed
        collateralOut = fromEscrow + leftOver;

        emit EscrowSettled(escrowId, lateFee, toEscrow, fromEscrow, leftOver);
    }

    function _conditionalCheckAndCancelEscrow(uint loanId, address refundRecipient) internal {
        Loan memory loan = loans[loanId];
        // only check and release if escrow was used
        if (loan.usesEscrow) {
            (EscrowSupplierNFT escrowNFT, uint escrowId) = (loan.escrowNFT, loan.escrowId);
            bool escrowReleased = escrowNFT.getEscrow(escrowId).released;
            // 1. Do NOT allow to unwrap past expiry with unreleased escrow: to prevent frontrunning
            // foreclosing. Past expiry either the user should call closeLoan(), or escrow owner should
            // call forecloseLoan().
            // 2. Do allow if escrow is released: to handle the case of escrow owner
            // calling escrowNFT.lastResortSeizeEscrow() instead of loans.forecloseLoan() for any reason.
            // In this case, none of the other methods are callable because escrow is released
            // already, so the simplest thing that can be done to avoid locking user's funds is
            // to cancel the loan and send them their takerId to withdraw cash.
            require(escrowReleased || block.timestamp <= _expiration(loanId), "loan expired");
            // @dev this doesn't allow unwrapping during min-grace-period, despite late-fee being zero then.
            // This is because the grace period's purpose is to allow the user to control the swap,
            // in exchange for paying late fees, which are accumulating from expiry (with a cliff),
            // and allowing the user to unwrap then will grief the supplier.
            // This would be relevant in case the user position has some dust cash in it - not enough
            // to justify repaying (due to slippage on full amount). In such a case user should unwrap
            // before expiry.

            if (!escrowReleased) {
                // release the escrowed user funds to the supplier since the user will not repay the loan.
                // no late fees - loan is not expired, no repayment - there was no swap.
                uint toUser = escrowNFT.endEscrow(escrowId, 0);
                // @dev no balance checks because contract holds no funds, mismatch will cause reverts

                // send potential interest fee refund
                collateralAsset.safeTransfer(refundRecipient, toUser);
            }
        }
    }

    // ----- INTERNAL VIEWS ----- //

    function _isSenderOrKeeperFor(address authorizedSender) internal view returns (bool) {
        bool isSender = msg.sender == authorizedSender; // is the auth target
        bool isKeeper = msg.sender == closingKeeper;
        // our auth target allows the keeper
        bool keeperAllowed = allowsClosingKeeper[authorizedSender];
        return isSender || (keeperAllowed && isKeeper);
    }

    function _newLoanIdCheck(uint takerId) internal view returns (uint loanId) {
        // @dev loanIds correspond to takerIds they wrap for simplicity. this is ok because takerId is
        // unique (for the single taker contract wrapped here) and is minted by this contract
        loanId = takerId;
        // @dev because we use the takerId for the loanId (instead of having separate IDs), we should
        // check that the ID is not yet taken. This should not be possible, since takerId should mint
        // new IDs correctly, but can be checked for completeness.
        // @dev non-zero should be ensured when opening loan
        require(loans[loanId].collateralAmount == 0, "loanId taken");
    }

    function _takerId(uint loanId) internal pure returns (uint takerId) {
        // existence is not checked, because this is assumed to be used only for valid loanId
        takerId = loanId;
    }

    function _expiration(uint loanId) internal view returns (uint) {
        return takerNFT.getPosition(_takerId(loanId)).expiration;
    }

    /// @dev should be used for opening only. If used for close will prevent closing if slippage is too high.
    /// The swap price is only used for "pot sizing", but not for payouts division on expiry.
    /// Due to this, price manipulation *should* NOT leak value from provider / protocol.
    /// The caller (user) is protected via a slippage parameter, and SHOULD use it to avoid MEV (if present).
    /// So, this check is just extra precaution and avoidance of extreme edge-cases.
    function _checkSwapPrice(uint cashFromSwap, uint collateralAmount) internal view {
        uint twapPrice = takerNFT.currentOraclePrice();
        // collateral is checked on open to not be 0
        uint swapPrice = cashFromSwap * takerNFT.oracle().BASE_TOKEN_AMOUNT() / collateralAmount;
        uint diff = swapPrice > twapPrice ? swapPrice - twapPrice : twapPrice - swapPrice;
        uint deviation = diff * BIPS_BASE / twapPrice;
        require(deviation <= MAX_SWAP_TWAP_DEVIATION_BIPS, "swap and twap price too different");
    }

    function _calculateNewLoan(int rollTransferIn, int rollFee, uint initialLoanAmount)
        internal
        pure
        returns (uint newLoanAmount)
    {
        // The transfer subtracted the fee, so it needs to be added back. The fee is not part of
        // the loan so that if price hasn't changed, after rolling, the updated
        // loan amount would still be equivalent to the initial collateral.
        // Example: transfer = position-gain - fee = 100 - 1 = 99
        //      So: position-gain = transfer + fee = 99 + 1 = 100
        int loanChange = rollTransferIn + rollFee;
        if (loanChange < 0) {
            uint repayment = uint(-loanChange); // will revert for type(int).min
            require(repayment <= initialLoanAmount, "repayment larger than loan");
            newLoanAmount = initialLoanAmount - repayment;
        } else {
            newLoanAmount = initialLoanAmount + uint(loanChange);
        }
    }

    // ----- Internal escrow views ----- //

    function _conditionalEscrowValidations(uint loanId) internal view {
        Loan memory loan = loans[loanId];
        // @dev these checks are done in the end of openLoan because escrow position is created
        // first, so on creation cannot be validated with these two checks. On rolls these checks
        // are just reused
        if (loan.usesEscrow) {
            IEscrowSupplierNFT.Escrow memory escrow = loan.escrowNFT.getEscrow(loan.escrowId);
            // taker.nextPositionId() view was used to create escrow (in open), but it was used before
            // external calls, so we need to ensure it matches still (was not skipped by reentrancy).
            // For rolls this check is not really needed since no untrusted calls are made between
            // escrow creation and this code.
            require(escrow.loanId == loanId, "unexpected loanId");
            // check expirations are equal to ensure no duration mismatch between escrow and collar
            require(escrow.expiration == _expiration(loanId), "duration mismatch");
        }
    }
}
