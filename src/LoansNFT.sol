// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { CollarTakerNFT, ICollarTakerNFT, ITakerOracle, BaseNFT, ConfigHub } from "./CollarTakerNFT.sol";
import { Rolls, CollarProviderNFT, IRolls } from "./Rolls.sol";
import { EscrowSupplierNFT, IEscrowSupplierNFT } from "./EscrowSupplierNFT.sol";
import { ISwapper } from "./interfaces/ISwapper.sol";
import { ISwapper } from "./interfaces/ISwapper.sol";
import { ILoansNFT } from "./interfaces/ILoansNFT.sol";

/**
 * @title LoansNFT
 * @dev This contract manages opening, closing, and rolling of loans via Collar positions,
 * with optional escrow support.
 *
 * Main Functionality:
 * 1. Allows users to open loans by providing underlying and borrowing against it, with or without escrow.
 * 2. Handles the swapping of underlying to the cash asset via allowed Swappers (that use dex routers).
 * 3. Wraps CollarTakerNFT (keeps it in the contract), and mints an NFT with loanId == takerId to the user.
 * 4. Manages loan closure, repayment of cash, swapping back to underlying, and releasing escrow if needed.
 * 5. Provides keeper functionality for automated loan closure and foreclosure to mitigate price fluctuation risks.
 * 6. Allows rolling (extending) the loan via an owner and user approved Rolls contract.
 * 7. Allows foreclosing escrow loans that were not repaid on time.
 *
 * Key Assumptions and Prerequisites:
 * 1. Allowed Swappers and the dex routers / aggregators they use are properly implemented.
 * 2. Depends on ConfigHub, CollarTakerNFT, CollarProviderNFT, EscrowSupplierNFT, Rolls, and their
 * dependencies (Oracle).
 * 3. Assets (ERC-20) used are simple: no hooks, balance updates only and exactly
 * according to transfer arguments (no rebasing, no FoT), 0 value approvals and transfers work.
 */
contract LoansNFT is ILoansNFT, BaseNFT {
    using SafeERC20 for IERC20;

    uint internal constant BIPS_BASE = 10_000;
    address internal constant UNSET = address(0);

    string public constant VERSION = "0.2.0";

    // ----- IMMUTABLES ----- //
    CollarTakerNFT public immutable takerNFT;
    IERC20 public immutable cashAsset;
    IERC20 public immutable underlying;

    // ----- STATE VARIABLES ----- //

    // ----- User state ----- //
    /// @notice Stores loan information for each NFT ID
    mapping(uint loanId => Loan) internal loans;
    // callers (users or escrow owners) that allow a keeper for loan closing
    mapping(address sender => bool enabled) public keeperApproved;

    // ----- Admin state ----- //
    // optional keeper (set by contract owner) that's useful for the time-sensitive
    // swap back during loan closing and foreclosing
    address public closingKeeper;
    // the currently configured & allowed rolls contract for this takerNFT and cash asset. Can be unset.
    Rolls public currentRolls;
    // the currently configured provider contract for opening. Can be unset.
    CollarProviderNFT public currentProviderNFT;
    // the currently configured escrow contract for opening. Can be unset.
    EscrowSupplierNFT public currentEscrowNFT;
    // a convenience view to allow querying for a swapper onchain / FE without subgraph
    address public defaultSwapper;
    // contracts allowed for swaps, including the defaultSwapper
    mapping(address swapper => bool allowed) public allowedSwappers;

    constructor(address initialOwner, CollarTakerNFT _takerNFT, string memory _name, string memory _symbol)
        BaseNFT(initialOwner, _name, _symbol)
    {
        takerNFT = _takerNFT;
        cashAsset = _takerNFT.cashAsset();
        underlying = IERC20(_takerNFT.underlying());
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

    /// @notice The available grace period using position cash value available for late fees.
    /// @dev Uses TWAP price for calculations, reverts if position not settled (and therefore before expiry).
    /// No validation of loan existing or being active, so can return nonsense values for invalid loans.
    /// @param loanId The ID of the loan to calculate for
    /// @return The length of the grace period
    function escrowGracePeriod(uint loanId) public view returns (uint) {
        ICollarTakerNFT.TakerPosition memory takerPosition = takerNFT.getPosition(_takerId(loanId));
        // @dev avoid settlement estimation complexity: if position is not settled, estimating
        // withdrawable funds is unnecessarily complex.
        // Instead, since positions can and should be settled soon after expiry - require that it is.
        require(takerPosition.settled, "taker position not settled");
        uint cashAvailable = takerPosition.withdrawable;

        // use current price for estimation of swap output.
        // round down is ok since it's against the user (being foreclosed).
        ITakerOracle oracle = takerNFT.oracle();
        uint underlyingAmount = oracle.convertToBaseAmount(cashAvailable, oracle.currentPrice());

        Loan memory loan = loans[loanId];
        // assume all available underlying can be used for fees (escrowNFT will cap between max and min)
        return loan.escrowNFT.cappedGracePeriod(loan.escrowId, underlyingAmount);
    }

    // ----- STATE CHANGING FUNCTIONS ----- //

    // ----- User / Keeper methods ----- //

    /**
     * @notice Opens a new loan by providing underlying and borrowing against it (without using escrow)
     *      1. Transfers underlying from the user to this contract
     *      2. Swaps underlying for cash
     *      3. Opens a loan position using the CollarTakerNFT contract
     *      4. Transfers the borrowed amount to the user
     *      5. Transfers the minted NFT to the user
     * @param underlyingAmount The amount of underlying asset to be provided
     * @param minLoanAmount The minimum acceptable loan amount (slippage protection)
     * @param swapParams SwapParams struct with:
     *     - The minimum acceptable amount of cash from the underlying swap (slippage protection)
     *     - an allowed Swapper
     *     - any extraData the swapper needs to use
     * @param providerOffer The ID of the liquidity offer to use from the provider
     * @return loanId The ID of the minted NFT representing the loan
     * @return providerId The ID of the minted CollarProviderNFT paired with this loan
     * @return loanAmount The actual amount of the loan opened in cash asset
     */
    function openLoan(
        uint underlyingAmount,
        uint minLoanAmount,
        SwapParams calldata swapParams,
        uint providerOffer
    ) public whenNotPaused returns (uint loanId, uint providerId, uint loanAmount) {
        return _openLoan(underlyingAmount, minLoanAmount, swapParams, providerOffer, false, 0);
    }

    /**
     * @notice Opens a new escrow-type loan by providing underlying and borrowing against it
     *      1. Transfers underlying from the user to this contract
     *      2. Uses the escrow contract to deposit user's underlying, and take supplier's underlying
     *      3. Swaps underlying for cash
     *      4. Opens a loan position using the CollarTakerNFT contract
     *      5. Transfers the borrowed amount to the user
     *      6. Transfers the minted NFT to the user
     * @param underlyingAmount The amount of underlying asset to be provided
     * @param minLoanAmount The minimum acceptable loan amount (slippage protection)
     * @param swapParams SwapParams struct with:
     *     - The minimum acceptable amount of cash from the underlying swap (slippage protection)
     *     - an allowed Swapper
     *     - any extraData the swapper needs to use
     * @param providerOffer The ID of the liquidity offer to use from the provider
     * @param escrowOffer The ID of the escrow offer to use from the supplier
     * @return loanId The ID of the minted NFT representing the loan
     * @return providerId The ID of the minted CollarProviderNFT paired with this loan
     * @return loanAmount The actual amount of the loan opened in cash asset
     */
    function openEscrowLoan(
        uint underlyingAmount,
        uint minLoanAmount,
        SwapParams calldata swapParams,
        uint providerOffer,
        uint escrowOffer
    ) external whenNotPaused returns (uint loanId, uint providerId, uint loanAmount) {
        return _openLoan(underlyingAmount, minLoanAmount, swapParams, providerOffer, true, escrowOffer);
    }

    /**
     * @notice Closes an existing loan, repaying the borrowed amount and returning underlying.
     * If escrow was used, releases it by returning the swapped underlying in exchange for the
     * user's underlying, handling any late fees.
     * The amount of underlying returned may be smaller or larger than originally deposited,
     * depending on the position's settlement result, escrow late fees, and the final swap.
     * This method can be called by either the loanId's NFT owner or by a keeper
     * if the keeper was allowed by the current owner (by calling setKeeperAllowed).
     * Using a keeper may be desired because the call's timing should be as close to settlement
     * as possible, to avoid additional price exposure since the swaps uses the spot price.
     * However, allowing a keeper also trusts them to set the swap parameters, trusting them
     * with the entire swap amount (to not self-sandwich, or lose it to MEV).
     * To instead settle in cash (and avoid both repayment and swap) the user can call unwrapAndCancelLoan
     * to unwrap the CollarTakerNFT to settle it and withdraw it directly.
     * @dev the user must have approved this contract for cash asset for repayment prior to calling.
     * @dev This function:
     *      1. Transfers the repayment amount from the user to this contract
     *      2. Settles the CollarTakerNFT position if needed
     *      3. Withdraws any available funds from the settled position
     *      4. Swaps the total cash amount back to underlying asset
     *      5. Releases the escrow if needed
     *      6. Transfers the underlying back to the user
     *      7. Burns the NFT
     * @param loanId The ID of the CollarTakerNFT representing the loan to close
     * @param swapParams SwapParams struct with:
     *     - The minimum acceptable amount of underlying to receive (slippage protection)
     *     - an allowed Swapper
     *     - any extraData the swapper needs to use
     * @return underlyingOut The actual amount of underlying asset returned to the user
     */
    function closeLoan(uint loanId, SwapParams calldata swapParams)
        external
        whenNotPaused // also checked in _burn (mutations false positive)
        returns (uint underlyingOut)
    {
        /// @dev ownerOf will revert on non-existent (unminted / burned) loan ID
        require(_isSenderOrKeeperFor(ownerOf(loanId)), "not NFT owner or allowed keeper");

        // @dev cache the borrower now, since _closeLoan will burn the NFT, so ownerOf will revert
        // Borrower is the NFT owner, since msg.sender can be a keeper.
        // If called by keeper, the borrower must trust it because:
        // - call pulls borrower funds (for repayment)
        // - call burns the NFT from borrower
        // - call sends the final funds to the borrower
        // - keeper sets the SwapParams and its slippage parameter
        address borrower = ownerOf(loanId);

        uint underlyingFromSwap = _closeLoan(loanId, borrower, swapParams);

        // release escrow if it was used, paying any late fees if needed
        // @dev no slippage param / check on escrow release result since it depends only on time
        // so cannot be manipulated and so can be checked off-chain / known in advance reliably
        underlyingOut = _conditionalReleaseEscrow(loanId, underlyingFromSwap);

        underlying.safeTransfer(borrower, underlyingOut);
    }

    /**
     * @notice Rolls an existing loan to a new taker position with updated terms via a Rolls contract.
     * The loan amount is updated according to the funds transferred (excluding the roll-fee), and the
     * underlying is unchanged.
     * If the loan uses escrow, the previous escrow is switched for a new escrow, the new fee is pulled
     * from the user, and any refund for the previous escrow fee is sent to the user.
     * @dev The user must have approved this contract prior to calling:
     *      - Cash asset for potential repayment (if needed for Roll execution)
     *      - Underlying asset for new escrow fee (if the original loan used escrow)
     * @param loanId The ID of the NFT representing the loan to be rolled
     * @param rollId The ID of the roll offer to be executed
     * @param minToUser The minimum acceptable transfer to user (negative if expecting to pay)
     * @param newEscrowOffer An escrowNFT offer for the new escrow to be opened if the loan is using
     * an escrow. The same escrowNFT contract will be used, but an offer must be supplied.
     * Argument ignored if escrow was not used.
     * @return newLoanId The ID of the newly minted NFT representing the rolled loan
     * @return newLoanAmount The updated loan amount after rolling
     * @return toUser The actual transfer to user (or from user if negative) including roll-fee
     */
    function rollLoan(uint loanId, uint rollId, int minToUser, uint newEscrowOffer)
        external
        whenNotPaused // also checked in _burn (mutations false positive)
        onlyNFTOwner(loanId)
        returns (uint newLoanId, uint newLoanAmount, int toUser)
    {
        // check opening loans is still allowed (not in exit-only mode)
        require(configHub.canOpen(address(this)), "unsupported loans contract");
        // rolls contracts do not need canOpen checks since there's no lock-up (for close-only mode),
        // and auth is handled directly by setting currentRolls
        require(address(currentRolls) != UNSET, "rolls contract unset");
        // @dev rolls contract is assumed to not allow rolling an expired or settled position,
        // but checking explicitly is safer and easier to review
        require(block.timestamp <= _expiration(loanId), "loan expired");
        // avoid using invalid data
        require(currentRolls.getRollOffer(rollId).active, "invalid rollId");

        // burn token. This prevents any further calls for this loan
        _burn(loanId);

        // pull and push NFT and cash, execute roll, emit event
        (uint newTakerId, int _toUser, int rollFee) = _executeRoll(loanId, rollId, minToUser);
        toUser = _toUser; // convenience to allow declaring all outputs above

        Loan memory prevLoan = loans[loanId];
        // calculate the updated loan amount (changed due to the roll)
        newLoanAmount = _loanAmountAfterRoll(toUser, rollFee, prevLoan.loanAmount);

        // set the new ID from new taker ID
        newLoanId = _newLoanIdCheck(newTakerId);

        // switch escrows if escrow was used because collar expiration has changed
        // @dev assumes interest fee approval
        uint newEscrowId = _conditionalSwitchEscrow(prevLoan, newEscrowOffer, newLoanId);

        // store the new loan data
        loans[newLoanId] = Loan({
            underlyingAmount: prevLoan.underlyingAmount,
            loanAmount: newLoanAmount,
            usesEscrow: prevLoan.usesEscrow,
            escrowNFT: prevLoan.escrowNFT,
            escrowId: newEscrowId
        });

        // mint the new loan NFT to the user, keep the taker NFT (with the same ID) in this contract
        _mint(msg.sender, newLoanId); // @dev does not use _safeMint to avoid reentrancy

        emit LoanRolled(msg.sender, loanId, rollId, newLoanId, prevLoan.loanAmount, newLoanAmount, toUser);
    }

    /**
     * @notice Cancels an active loan, burns the loan NFT, and unwraps the taker NFT to user,
     * disconnecting it from the loan.
     * If escrow was used, checks if unwrapping is currently allowed, and releases the escrow
     * if it wasn't released.
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
     * @notice Forecloses an escrow loan, that was not repaid on time, after grace period is finished.
     * The max grace period and its late-fee APR is determined by the initial supplier's offer.
     * The actual period is dynamically limited by the position's value, to reduce late-fee underpayment.
     * @dev Can be called only by the escrow owner or an allowed keeper (if authorized by escrow owner)
     * @param loanId The ID of the loan to foreclose
     * @param swapParams Swap parameters for cash to underlying conversion
     */
    function forecloseLoan(uint loanId, SwapParams calldata swapParams) external whenNotPaused {
        // get the borrower address here, both to ensure loan is active (will revert otherwise)
        // and because owner address won't be available after burning the NFT
        address borrower = ownerOf(loanId);

        Loan memory loan = loans[loanId];
        require(loan.usesEscrow, "not an escrowed loan");

        (EscrowSupplierNFT escrowNFT, uint escrowId) = (loan.escrowNFT, loan.escrowId);
        // Funds beneficiary (escrow owner) should ideally set the swapParams.
        // A keeper can be useful because foreclosing can be time-sensitive, due to swap timing
        // impacting the amount of funds available for late-fee repayment.
        // @dev will also revert on non-existent (unminted / burned) escrow ID
        address escrowOwner = escrowNFT.ownerOf(escrowId);
        require(_isSenderOrKeeperFor(escrowOwner), "not escrow owner or allowed keeper");

        // @dev escrowGracePeriod uses twap-price, while actual foreclosing swap is using spot price.
        // This has several implications:
        // 1. This protects foreclosing from price manipulation edge-cases.
        // 2. The final swap can be manipulated against the supplier, so either they or a trusted keeper
        //    should do it.
        // 3. This also means that swap amount may be different from the estimation in escrowGracePeriod
        //    if near the end of a grace-period that was capped.
        //    In this case, if swap price is less than twap, the late fees may be slightly underpaid
        //    because of the swap-twap difference and slippage.
        // 4. Because the supplier (escrow owner) is controlling this call, they can manipulate the price
        //    to their benefit, but it still can't pay more than the lateFees calculated by time, and can only
        //    result in "leftovers" that will go to the borrower, so makes no sense for them to do (since
        //    manipulation costs money).
        uint gracePeriodEnd = _expiration(loanId) + escrowGracePeriod(loanId);
        require(block.timestamp > gracePeriodEnd, "cannot foreclose yet");

        // burn NFT from the user. Prevents any further actions for this loan.
        // Although they are not the caller, altering their assets is fine here because
        // foreclosing is a state with other negative consequence they should try to avoid anyway
        _burn(loanId);

        // position was checked to settled already, so we only need to withdraw.
        // @dev because taker NFT is held by this contract, this could not have been called already
        uint cashAvailable = takerNFT.withdrawFromSettled(_takerId(loanId));

        // @dev Reentrancy assumption: no user state writes or reads AFTER the swapper call in _swap.
        // A call to escrowNFT.endEscrow is made after this, but escrow belongs to the caller, and is
        // protected via "released" flag in escrow.
        uint fromSwap = _swap(cashAsset, underlying, cashAvailable, swapParams);

        // Release escrow, and send any leftovers to user. Their express trigger of balance update
        // (withdrawal) is neglected here due to being anyway in an undesirable state of being foreclosed
        // due to not repaying on time. It's the responsibility of the NFT owner to avoid foreclosure
        // so if the NFT is in some contract that won't attribute these funds, it's the owner's fault.
        uint toBorrower = _releaseEscrow(escrowNFT, escrowId, fromSwap);
        underlying.safeTransfer(borrower, toBorrower);

        emit LoanForeclosed(loanId, escrowId, fromSwap, toBorrower);
    }

    /**
     * @notice Allows or disallows a keeper for closing loans on behalf of a caller
     * A user that sets this allowance with the intention for the keeper to closeLoan
     * has to also cash approval to this contract that should be valid when
     * closeLoan is called by the keeper.
     * @dev The allowance is tied to the the caller address, for any action that a keeper can
     *      do. So if they buy a new loan NFT, and they previously allowed a keeper - it is
     *      allowed for their new NFT as well. If they are also an escrow supplier, from the
     *      same address, the keeper would be able to call foreCloseLoan on their behalf.
     * @param enabled True to allow the keeper, false to disallow
     */
    function setKeeperApproved(bool enabled) external whenNotPaused {
        keeperApproved[msg.sender] = enabled;
        emit ClosingKeeperApproved(msg.sender, enabled);
    }

    // ----- Admin methods ----- //

    /// @notice Sets the address of the single allowed closing keeper. Alternative decentralized keeper
    /// arrangements can be added via composability, e.g., a contract that would hold the NFTs (thus
    /// will be able to perform actions) and allow incentivised keepers to call it.
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
        require(address(escrowNFT) == UNSET || escrowNFT.asset() == underlying, "escrow asset mismatch");
        currentRolls = rolls;
        currentProviderNFT = providerNFT;
        currentEscrowNFT = escrowNFT;
        emit ContractsUpdated(rolls, providerNFT, escrowNFT);
    }

    /// @notice Enables or disables swappers and sets the defaultSwapper view.
    /// When no swapper is allowed, opening and closing loans will not be possible, only cancelling.
    /// The default swapper is a convenience view, and it's best to keep it up to date
    /// and to make sure the default one is allowed.
    /// @dev only owner
    function setSwapperAllowed(address swapper, bool allowed, bool setDefault) external onlyOwner {
        if (allowed) require(bytes(ISwapper(swapper).VERSION()).length > 0, "invalid swapper");
        allowedSwappers[swapper] = allowed;

        // it is possible to disallow and set as default at the same time. E.g., to unset the default
        // to zero. Worst case, if no swappers are allowed, loans can be cancelled and unwrapped.
        if (setDefault) defaultSwapper = swapper;

        emit SwapperSet(swapper, allowed, setDefault);
    }

    // ----- INTERNAL MUTATIVE ----- //

    /// @dev handles both escrow and non-escrow loans
    function _openLoan(
        uint underlyingAmount,
        uint minLoanAmount,
        SwapParams calldata swapParams,
        uint providerOffer,
        bool usesEscrow,
        uint escrowOffer
    ) internal returns (uint loanId, uint providerId, uint loanAmount) {
        require(configHub.canOpen(address(this)), "unsupported loans contract");
        // provider NFT canOpen is checked by taker contract
        // taker NFT canOpen is checked in _swapAndMintPaired
        // escrow NFT canOpen is checked in _conditionalOpenEscrow

        // @dev in additional to this, escrow interest fee may also be pulled in _conditionalOpenEscrow
        // So approval needs to be for this + interest fee
        underlying.safeTransferFrom(msg.sender, address(this), underlyingAmount);

        // handle optional escrow, must be done first, to use "supplier's" underlying in swap
        (EscrowSupplierNFT escrowNFT, uint escrowId) =
            _conditionalOpenEscrow(usesEscrow, underlyingAmount, escrowOffer);

        // @dev Reentrancy assumption: no user manipulable state writes or reads BEFORE this call due to
        // potential untrusted calls during swapping, The only exception is taker.nextPositionId(), which
        // is why escrow's loanId is later validated in _escrowValidations.
        uint takerId;
        (takerId, providerId, loanAmount) = _swapAndMintCollar(underlyingAmount, providerOffer, swapParams);
        require(loanAmount >= minLoanAmount, "loan amount too low");

        // validate loanId
        loanId = _newLoanIdCheck(takerId);

        // @dev these checks can only be done in the end of _openLoan, after both escrow and taker
        // positions exist
        if (usesEscrow) _escrowValidations(loanId, escrowNFT, escrowId);

        // store the loan opening data
        loans[loanId] = Loan({
            underlyingAmount: underlyingAmount,
            loanAmount: loanAmount,
            usesEscrow: usesEscrow,
            escrowNFT: escrowNFT,
            escrowId: escrowId
        });

        // mint the loan NFT to the borrower, keep the taker NFT (with the same ID) in this contract
        _mint(msg.sender, loanId); // @dev does not use _safeMint to avoid reentrancy

        // transfer the full loan amount on open
        cashAsset.safeTransfer(msg.sender, loanAmount);

        emit LoanOpened(loanId, msg.sender, providerOffer, underlyingAmount, loanAmount);
    }

    /// @dev swaps underlying to cash and mints collar position
    function _swapAndMintCollar(uint underlyingAmount, uint offerId, SwapParams calldata swapParams)
        internal
        returns (uint takerId, uint providerId, uint loanAmount)
    {
        require(configHub.canOpen(address(takerNFT)), "unsupported taker contract");
        // provider contract is set
        require(address(currentProviderNFT) != UNSET, "provider contract unset");
        // 0 underlying is later checked to mean non-existing loan, also prevents div-zero
        require(underlyingAmount != 0, "invalid underlying amount");

        // swap underlying
        // @dev Reentrancy assumption: no user state writes or reads BEFORE the swapper call in _swap.
        // The only state reads before are owner-set state (e.g., pause and swapper allowlist).
        uint cashFromSwap = _swap(underlying, cashAsset, underlyingAmount, swapParams);
        /* @dev note on swap price manipulation:
        The swap price is only used for "pot sizing", but not for payouts division on expiry.
        Due to this, price manipulation *should* NOT leak value from provider / escrow / protocol,
        only from sender. But sender (borrower) is protected via a slippage parameter, and should
        use it to avoid MEV (if present).
        */

        // split the cash to loanAmount and takerLocked
        // this uses LTV === put strike price, so the loan is the pre-exercised put (sent to user)
        // in the "Variable Prepaid Forward" (trad-fi) structure. The Collar paired position NFTs
        // implement the rest of the payout.
        uint ltvPercent = currentProviderNFT.getOffer(offerId).putStrikePercent;
        loanAmount = ltvPercent * cashFromSwap / BIPS_BASE;
        // everything that remains is locked on the taker side in the collar position
        uint takerLocked = cashFromSwap - loanAmount;

        // open the paired taker and provider positions
        cashAsset.forceApprove(address(takerNFT), takerLocked);
        (takerId, providerId) = takerNFT.openPairedPosition(takerLocked, currentProviderNFT, offerId);
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
        1. Using a specific interface is safer because it makes stealing approvals impossible.
        This is safer than depending only on the allowlist.
        2. An arbitrary call payload for a swap is more difficult to construct and inspect
        so requires more user trust on the FE.
        3. Swap's amountIn would need to be calculated off-chain exactly, which in case of closing
        the loan is problematic if position was not settled already (and so exact withdrawal amount
        is not known), so would require first settling, and then closing.

        The interface still allows arbitrary complexity via the extraData field if needed.
        */
        uint amountOutSwapper = ISwapper(swapParams.swapper).swap(
            assetIn, assetOut, amountIn, swapParams.minAmountOut, swapParams.extraData
        );
        // Calculate the actual amount received
        amountOut = assetOut.balanceOf(address(this)) - balanceBefore;
        // check balance is updated as expected and as reported by swapper (no other balance changes)
        require(amountOut == amountOutSwapper, "balance update mismatch");
        // check amount is as expected by user
        require(amountOut >= swapParams.minAmountOut, "slippage exceeded");
    }

    /// @dev loan closure logic without final transfer of underlying
    function _closeLoan(uint loanId, address borrower, SwapParams calldata swapParams)
        internal
        returns (uint underlyingFromSwap)
    {
        // burn token. This prevents any other (or reentrant) calls for this loan
        _burn(loanId);

        // total cash available
        // @dev will check settle, or try to settle - will revert if cannot settle yet (not expired)
        uint takerWithdrawal = _settleAndWithdrawTaker(loanId);

        uint repayment = loans[loanId].loanAmount;
        // @dev assumes approval
        cashAsset.safeTransferFrom(borrower, address(this), repayment);

        uint cashAmount = repayment + takerWithdrawal;
        // @dev Reentrancy assumption: no user state writes or reads AFTER the swapper call in _swap.
        underlyingFromSwap = _swap(cashAsset, underlying, cashAmount, swapParams);

        emit LoanClosed(loanId, msg.sender, borrower, repayment, cashAmount, underlyingFromSwap);
    }

    function _settleAndWithdrawTaker(uint loanId) internal returns (uint withdrawnAmount) {
        uint takerId = _takerId(loanId);

        // position could have been settled by anyone already
        (, bool settled) = takerNFT.expirationAndSettled(takerId);
        if (!settled) {
            /// @dev this will revert on: too early, no position, calculation issues, ...
            takerNFT.settlePairedPosition(takerId);
        }

        /// @dev because taker NFT is held by this contract, this could not have been called already
        withdrawnAmount = takerNFT.withdrawFromSettled(takerId);
    }

    function _executeRoll(uint loanId, uint rollId, int minToUser)
        internal
        returns (uint newTakerId, int toTaker, int rollFee)
    {
        uint initialBalance = cashAsset.balanceOf(address(this));

        // get transfer amount and fee from rolls
        IRolls.PreviewResults memory preview = currentRolls.previewRoll(rollId, takerNFT.currentOraclePrice());
        rollFee = preview.rollFee;

        // pull cash
        if (preview.toTaker < 0) {
            uint fromUser = uint(-preview.toTaker); // will revert for type(int).min
            // pull cash first, because rolls will try to pull it (if needed) from this contract
            // @dev assumes approval
            cashAsset.safeTransferFrom(msg.sender, address(this), fromUser);
            // allow rolls to pull this cash
            cashAsset.forceApprove(address(currentRolls), fromUser);
        }

        // approve the taker NFT (held in this contract) for rolls to pull
        takerNFT.approve(address(currentRolls), _takerId(loanId));
        // execute roll
        (newTakerId,, toTaker,) = currentRolls.executeRoll(rollId, minToUser);
        // check return value matches preview, which is used for updating the loan and pulling cash
        require(toTaker == preview.toTaker, "unexpected transfer amount");
        // check slippage (would have been checked in Rolls as well)
        require(toTaker >= minToUser, "roll transfer < minToUser");

        // transfer cash if should have received any
        if (toTaker > 0) {
            // @dev this will revert if rolls contract didn't actually pay above
            cashAsset.safeTransfer(msg.sender, uint(toTaker));
        }

        // there should be no balance change for the contract (which might happen e.g., if rolls contract
        // overestimated amount to pull from user and under-reported return value)
        require(cashAsset.balanceOf(address(this)) == initialBalance, "contract balance changed");
    }

    // ----- Conditional escrow mutative methods ----- //

    function _conditionalOpenEscrow(bool usesEscrow, uint escrowed, uint escrowOffer)
        internal
        returns (EscrowSupplierNFT escrowNFT, uint escrowId)
    {
        if (usesEscrow) {
            escrowNFT = currentEscrowNFT;
            // escrow contract is set
            require(address(escrowNFT) != UNSET, "escrow contract unset");
            // whitelisted only
            require(configHub.canOpen(address(escrowNFT)), "unsupported escrow contract");

            uint fee = _pullEscrowFee(escrowNFT, escrowOffer, escrowed);
            // @dev underlyingAmount was pulled already before calling this method
            underlying.forceApprove(address(escrowNFT), escrowed + fee);
            escrowId = escrowNFT.startEscrow({
                offerId: escrowOffer,
                escrowed: escrowed,
                fee: fee,
                loanId: takerNFT.nextPositionId() // @dev checked later in _escrowValidations
             });
            // @dev no balance checks because contract holds no funds, mismatch will cause reverts
        } else {
            // returns default empty values
        }
    }

    /// @dev escrow switch during roll
    function _conditionalSwitchEscrow(Loan memory prevLoan, uint escrowOffer, uint newLoanId)
        internal
        returns (uint newEscrowId)
    {
        if (prevLoan.usesEscrow) {
            // check this escrow is still allowed
            require(configHub.canOpen(address(prevLoan.escrowNFT)), "unsupported escrow contract");

            uint newFee = _pullEscrowFee(prevLoan.escrowNFT, escrowOffer, prevLoan.underlyingAmount);
            underlying.forceApprove(address(prevLoan.escrowNFT), newFee);
            uint feeRefund;
            (newEscrowId, feeRefund) = prevLoan.escrowNFT.switchEscrow({
                releaseEscrowId: prevLoan.escrowId,
                offerId: escrowOffer,
                newLoanId: newLoanId,
                newFee: newFee
            });

            // check escrow and loan have matching fields
            _escrowValidations(newLoanId, prevLoan.escrowNFT, newEscrowId);

            // send potential interest fee refund
            underlying.safeTransfer(msg.sender, feeRefund);
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
        // explicit allowance check here to provide clearer error since fee amount is not a user argument
        uint allowance = underlying.allowance(msg.sender, address(this));
        // underlyingAmount was already pulled, so its allowance has been consumed
        require(allowance >= interestFee, "insufficient allowance for escrow fee");
        underlying.safeTransferFrom(msg.sender, address(this), interestFee);
    }

    function _conditionalReleaseEscrow(uint loanId, uint fromSwap) internal returns (uint underlyingOut) {
        Loan memory loan = loans[loanId];
        // if escrow not used: return the full swap amount, otherwise the underlying after releasing escrow
        return loan.usesEscrow ? _releaseEscrow(loan.escrowNFT, loan.escrowId, fromSwap) : fromSwap;
    }

    function _releaseEscrow(EscrowSupplierNFT escrowNFT, uint escrowId, uint fromSwap)
        internal
        returns (uint underlyingOut)
    {
        // get owing and late fee (included in totalOwed)
        (uint totalOwed, uint lateFee) = escrowNFT.currentOwed(escrowId);

        // if owing more than swapped, use all, otherwise just what's owed
        uint toEscrow = Math.min(fromSwap, totalOwed);
        // if owing less than swapped, left over gains are for the borrower
        uint leftOver = fromSwap - toEscrow;

        underlying.forceApprove(address(escrowNFT), toEscrow);
        // fromEscrow is what escrow returns after deducting any shortfall.
        // (although not problematic, there should not be any interest fee refund here,
        // because this method is called after expiry)
        uint fromEscrow = escrowNFT.endEscrow(escrowId, toEscrow);
        // @dev no balance checks because contract holds no funds, mismatch will cause reverts

        // the released and the leftovers to be sent to borrower. Zero-value-transfer is allowed
        underlyingOut = fromEscrow + leftOver;

        emit EscrowSettled(escrowId, lateFee, toEscrow, fromEscrow, leftOver);
    }

    function _conditionalCheckAndCancelEscrow(uint loanId, address refundRecipient) internal {
        Loan memory loan = loans[loanId];
        // only check and release if escrow was used
        if (loan.usesEscrow) {
            (EscrowSupplierNFT escrowNFT, uint escrowId) = (loan.escrowNFT, loan.escrowId);
            bool escrowReleased = escrowNFT.getEscrow(escrowId).released;
            /* Allow two cases:

            1. Escrow was released: to handle the case of escrow owner
              calling escrowNFT.lastResortSeizeEscrow() instead of loans.forecloseLoan() for any reason.
              In that case, none of the other methods are callable because escrow is released
              already, and user is very late to close, the simplest thing that can be done to
              avoid locking user's funds is to cancel the loan and send them the takerId to withdraw cash.

            2. Loan NOT after expiry. This to prevent frontrunning foreclosing if after expiry (and min grace).
              After expiry either the user should call closeLoan(), or escrow owner should
              call forecloseLoan().

            Note that 2 doesn't allow unwrapping during min-grace-period, despite late-fee being zero then.
            This is because the grace period's purpose is to allow the user to control the swap,
            not to prolong their expiry. This is in exchange for accumulating late fees, accumulated
            from expiry (with a cliff). Allowing the user to unwrap then will grief the supplier.
            This would be relevant in case the user position has some dust cash in it - not enough
            to justify repaying (due to slippage on full amount). In such a case user should unwrap
            before expiry, or allow the dust to go to the escrow supplier.
            */
            require(escrowReleased || block.timestamp <= _expiration(loanId), "loan expired");

            if (!escrowReleased) {
                // if not released, release the user funds to the supplier since the user will not repay
                // the loan. There's no late fees - loan hsa not expired, but also no repayment - there was
                // no swap. There may be an interest fee refund for the borrower.
                // @dev For an open + immediate cancel all fees are refunded, however, this is unlikely to
                // be used to grief supplier offers, since it would both costs swap fees and lock
                // funds in the taker position.
                uint feeRefund = escrowNFT.endEscrow(escrowId, 0);
                // @dev no balance checks because contract holds no funds, mismatch will cause reverts

                // send potential interest fee refund
                underlying.safeTransfer(refundRecipient, feeRefund);
            }
        }
    }

    // ----- INTERNAL VIEWS ----- //

    function _isSenderOrKeeperFor(address authorizedSender) internal view returns (bool) {
        bool isSender = msg.sender == authorizedSender; // is the auth target
        bool isKeeper = msg.sender == closingKeeper;
        // our auth target allows the keeper
        bool _keeperApproved = keeperApproved[authorizedSender];
        return isSender || (_keeperApproved && isKeeper);
    }

    function _newLoanIdCheck(uint takerId) internal view returns (uint loanId) {
        // @dev loanIds correspond to takerIds they wrap for simplicity. this is ok because takerId is
        // unique (for the single taker contract wrapped here) and the ID is minted by this contract
        loanId = takerId;
        // @dev because we use the takerId for the loanId (instead of having separate IDs), we should
        // check that the ID is not yet taken. This should not be possible, since takerId should mint
        // new IDs correctly, but can be checked for completeness.
        // @dev non-zero should be ensured when opening loan
        require(loans[loanId].underlyingAmount == 0, "loanId taken");
    }

    function _takerId(uint loanId) internal pure returns (uint takerId) {
        // existence is not checked, because this is assumed to be used only for valid loanId
        takerId = loanId;
    }

    function _expiration(uint loanId) internal view returns (uint expiration) {
        (expiration,) = takerNFT.expirationAndSettled(_takerId(loanId));
    }

    function _loanAmountAfterRoll(int fromRollsToUser, int rollFee, uint prevLoanAmount)
        internal
        pure
        returns (uint newLoanAmount)
    {
        // The transfer subtracted the fee (see Rolls _previewTransferAmounts), so it needs
        // to be added back. The fee is not part of the position, so that if price hasn't changed,
        // after rolling, the updated position (loan amount + takerLocked) would still be equivalent
        // to the initial underlying.
        // Example: toTaker       = position-gain - fee = 100 - 1 = 99
        //      So: position-gain = toTaker       + fee = 99  + 1 = 100
        int loanChange = fromRollsToUser + rollFee;
        if (loanChange < 0) {
            uint repayment = uint(-loanChange); // will revert for type(int).min
            require(repayment <= prevLoanAmount, "repayment larger than loan");
            // if the borrower manipulated (sandwiched) their open swap price to be very low, they
            // may not be able to roll now. Rolling is optional, so this is not a problem.
            newLoanAmount = prevLoanAmount - repayment;
        } else {
            newLoanAmount = prevLoanAmount + uint(loanChange);
        }
    }

    // ----- Internal escrow views ----- //

    // @dev this can be called when both escrow and taker positions exist
    function _escrowValidations(uint loanId, EscrowSupplierNFT escrowNFT, uint escrowId) internal view {
        IEscrowSupplierNFT.Escrow memory escrow = escrowNFT.getEscrow(escrowId);
        // taker.nextPositionId() view was used to create escrow (in open), but it was used before
        // external calls, so we need to ensure it matches still (was not skipped by reentrancy).
        // For rolls this check is not really needed since no untrusted calls are made between
        // switching escrow and this code.
        require(escrow.loanId == loanId, "unexpected loanId");
        // check expirations are equal to ensure no duration mismatch between escrow and collar
        require(escrow.expiration == _expiration(loanId), "duration mismatch");
    }
}
