// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity 0.8.22;

import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
// internal imports
import { CollarTakerNFT, ShortProviderNFT, BaseNFT, ConfigHub } from "./CollarTakerNFT.sol";
import { Rolls } from "./Rolls.sol";
import { EscrowSupplierNFT, IEscrowSupplierNFT } from "./EscrowSupplierNFT.sol";
import { ISwapper } from "./interfaces/ISwapper.sol";
import { ILoansNFT } from "./interfaces/ILoansNFT.sol";

/**
 * @title LoansNFT
 * @dev This contract manages opening and closing of collateralized loans via Collar positions.
 *
 * Main Functionality:
 * 1. Allows users to open loans by providing collateral and borrowing against it.
 * 2. Handles the swapping of collateral to the cash asset via allowed Swappers (that use dex routers).
 * 3. Wraps CollarTakerNFT (keeps it in the contract), and mints an NFT with loanId == takerId to the user.
 * 4. Manages loan closure, including repayment and swapping back to collateral.
 * 5. Provides keeper functionality for automated loan closure to allow avoiding price
 * fluctuations negatively impacting swapping back to collateral.
 * 6. Allows rolling (extending) the loan via an owner and user approved Rolls contract.
 *
 * Role in the Protocol:
 * This contract acts as the main entry point for borrowers in the Collar Protocol.
 *
 * Key Assumptions and Prerequisites:
 * 1. Allowed Swappers and the underlying dex routers / aggregators are trusted and properly implemented.
 * 2. The CollarTakerNFT and ShortProviderNFT contracts are correctly implemented and authorized.
 * 3. The ConfigHub contract correctly manages protocol parameters and reports prices.
 * 4. Assets (ERC-20) used are standard compliant (non-rebasing, no transfer fees, no callbacks).
 * 5. The Rolls contract is trusted by user (and allowed by owner) and correctly rolls the taker position.
 *
 * Design Considerations:
 * 1. Wraps CollarTakerNFT NFTs, and mints LoanNFT IDs (equal to the wrapped CollarTakerNFT ID)
 *    to represent loan positions, allowing for potential secondary market trading.
 * 2. Implements pausability for emergency situations.
 * 3. Includes a keeper system for automated loan closure to allow users to delegate the time-sensitive
 * loan closure action.
 * 4. Uses TWAP prices from Uniswap V3 for price manipulation protection when swapping during borrowing
 * (but not during closing).
 */
contract LoansNFT is BaseNFT, ILoansNFT {
    using SafeERC20 for IERC20;

    uint internal constant BIPS_BASE = 10_000;
    EscrowSupplierNFT internal constant NO_ESCROW = EscrowSupplierNFT(address(0));

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
    Rolls public rollsContract;
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

    modifier onlyNFTOwnerOrKeeper(uint loanId) {
        /// @dev will also revert on non-existent (unminted / burned) taker ID
        require(_isSenderOrKeeperFor(ownerOf(loanId)), "not NFT owner or allowed keeper");
        _;
    }

    // ----- VIEW FUNCTIONS ----- //

    /// @notice Retrieves loan information for a given taker NFT ID
    /// @dev return memory struct (the default getter returns tuple)
    function getLoan(uint loanId) external view returns (Loan memory) {
        return loans[loanId];
    }

    // TODO: docs
    function escrowGracePeriodEnd(uint loanId) public view returns (uint) {
        uint expiration = _expiration(loanId);

        // if this is called before expiration (externally), estimate value using current price
        uint settleTime = _min(block.timestamp, expiration);
        // the price that will be used for settlement (past if available, or current if not)
        (uint oraclePrice,) = takerNFT.oracle().pastPriceWithFallback(uint32(settleTime));

        (uint cashAvailable,) = takerNFT.previewSettlement(_takerId(loanId), oraclePrice);

        // oracle price is for 1e18 tokens (regardless of decimals):
        // oracle-price = collateral-price * 1e18, so price = oracle-price / 1e18,
        // since collateral = cash / price, we get collateral = cash * 1e18 / oracle-price.
        // round down is ok since it's against the user (being foreclosed).
        // division by zero is not prevented because because a panic is ok with an invalid price
        uint collateral = cashAvailable * takerNFT.oracle().BASE_TOKEN_AMOUNT() / oraclePrice;

        Loan storage loan = loans[loanId];
        // assume all available collateral can be used for fees (escrowNFT will cap between max and min)
        uint cappedGracePeriod = loan.escrowNFT.cappedGracePeriod(loan.escrowId, collateral);
        // always after expiration, also cappedGracePeriod() is at least min-grace-period
        return expiration + cappedGracePeriod;
    }

    // ----- STATE CHANGING FUNCTIONS ----- //

    // ----- User / Keeper methods ----- //

    function openLoan(
        OpenLoanParams memory params // TODO: calldata instead of memory
    ) public whenNotPaused returns (uint loanId, uint providerId, uint loanAmount) {
        require(configHub.canOpen(address(this)), "unsupported loans");
        // provider NFT is checked by taker
        // escrow NFT is checked in _optionalOpenEscrow, taker is checked in _swapAndMintPaired

        uint pulled = params.collateralAmount + params.escrowFee;
        collateralAsset.safeTransferFrom(msg.sender, address(this), pulled);

        // handle optional escrow, must be done first, to use "supplier's" collateral in swap
        uint escrowId = _optionalOpenEscrow(params);

        // @dev Reentrancy assumption: no user state writes or reads BEFORE this call
        uint takerId;
        (takerId, providerId, loanAmount) = _swapAndMintCollar(
            params.collateralAmount, params.providerNFT, params.shortOffer, params.swapParams
        );
        require(loanAmount >= params.minLoanAmount, "loan amount too low");

        loanId = _newLoanIdCheck(takerId);
        // store the loan opening data
        loans[loanId] = Loan({
            collateralAmount: params.collateralAmount,
            loanAmount: loanAmount,
            escrowNFT: params.escrowNFT,
            escrowId: escrowId
        });
        // mint the loan NFT to the borrower, keep the taker NFT (with the same ID) in this contract
        _mint(msg.sender, loanId); // @dev does not use _safeMint to avoid reentrancy

        // some validations that can only be done here, after everything is available
        _optionalEscrowValidation(loanId, params.escrowNFT, escrowId);

        // transfer the full loan amount on open
        cashAsset.safeTransfer(msg.sender, loanAmount);

        emit LoanOpened(
            msg.sender,
            address(params.providerNFT),
            params.shortOffer,
            params.collateralAmount,
            loanAmount,
            loanId,
            providerId
        );
    }

    // TODO: remove this temp method
    /**
     * @notice Opens a new loan by providing collateral and borrowing against it
     * @dev This function handles the entire loan creation process:
     *      1. Transfers collateral from the user to this contract
     *      2. Swaps collateral for cash assets using Uniswap V3
     *      3. Opens a loan position using the CollarTakerNFT contract
     *      4. Transfers the borrowed amount to the user
     *      5. Transfers the minted NFT to the user
     * @param collateralAmount The amount of collateral asset to be provided
     * @param minLoanAmount The minimum acceptable loan amount (slippage protection)
     * @param swapParams SwapParams struct with:
     *     - The minimum acceptable amount of cash from the collateral swap (slippage protection)
     *     - an allowed Swapper
     *     - any extraData the swapper needs to use
     * @param providerNFT The address of the ShortProviderNFT contract to use
     * @param offerId The ID of the liquidity offer to use from the provider
     * @return loanId The ID of the minted NFT representing the loan
     * @return providerId The ID of the minted ShortProviderNFT paired with this loan
     * @return loanAmount The actual amount of the loan opened in cash asset
     */
    function openLoan(
        uint collateralAmount,
        uint minLoanAmount,
        SwapParams calldata swapParams,
        ShortProviderNFT providerNFT, // @dev will be validated by takerNFT, which is immutable
        uint offerId // @dev implies specific provider, put & call deviations, duration
    ) external returns (uint loanId, uint providerId, uint loanAmount) {
        return openLoan(
            OpenLoanParams(collateralAmount, minLoanAmount, swapParams, providerNFT, offerId, NO_ESCROW, 0, 0)
        );
    }

    /**
     * @notice Closes an existing loan, repaying the borrowed amount and returning collateral.
     * The amount of collateral returned may be smaller or larger than originally deposited,
     * depending on the position's settlement result, and the final swap.
     * This method can be called by either the loan's owner (the CollarTakerNFT owner) or by a keeper
     * if the keeper was allowed by the current owner (by calling setKeeperAllowed). Using a keeper
     * may be needed because the call's timing should be as close to settlement as possible, to
     * avoid additional price exposure since the swaps price's is always spot (not past).
     * To settle in cash (and avoid the repayment and swap) the user can instead call unwrapAndCancelLoan
     * to unwrap the CollarTakerNFT to settle it and withdraw it directly.
     * @dev the user must have approved this contract prior to calling: cash asset for repayment, and
     * the NFT id for settlement.
     * @dev This function handles the entire loan closure process:
     *      1. Transfers the repayment amount from the user to this contract
     *      2. Settles the CollarTakerNFT position
     *      3. Withdraws any available funds from the settled position
     *      4. Swaps the total cash amount back to collateral asset
     *      5. Transfers the collateral back to the user
     *      6. Burns the NFT
     * @param loanId The ID of the CollarTakerNFT representing the loan to close
     * @param swapParams SwapParams struct with:
     *     - The minimum acceptable amount of collateral to receive (slippage protection)
     *     - an allowed Swapper
     *     - any extraData the swapper needs to use
     * @return collateralOut The actual amount of collateral asset returned to the user
     */
    function closeLoan(uint loanId, SwapParams calldata swapParams)
        external
        whenNotPaused
        onlyNFTOwnerOrKeeper(loanId)
        returns (uint collateralOut)
    {
        // @dev cache the user now, since _closeLoanNoTFOut will burn the NFT, so ownerOf will revert
        address user = ownerOf(loanId);

        uint fromSwap = _closeLoanNoTFOut(loanId, swapParams);

        collateralOut = _optionalReleaseEscrow(loanId, fromSwap);

        collateralAsset.safeTransfer(user, collateralOut);
    }

    /**
     * @notice Rolls an existing loan to a new taker position with updated terms via a Rolls contract.
     * The loan amount is updated according to the funds transferred (excluding the roll-fee), and the
     * collateral is unchanged.
     * @dev The user must have approved this contract prior to calling:
     *      - Cash asset for potential repayment (if needed according for Roll execution)
     *      - The loan NFT for burning
     * @param loanId The ID of the NFT representing the loan to be rolled
     * @param rollId The ID of the roll offer to be executed
     * @param minToUser The minimum acceptable transfer to user (negative if expecting to pay)
     * @param newEscrowOffer An escrowNFT offer for the new escrow to be opened if the loans is using
     * and escrow. The same escrowNFT contract will be used, but an offer must be specified.
     * @param newEscrowFee The fee to pay for the new escrow. Any interest refund from previous escrow
     * will be sent to msg.sender.
     * @return newLoanId The ID of the newly minted NFT representing the rolled loan
     * @return newLoanAmount The updated loan amount after rolling
     * @return transferAmount The actual transfer to user (or from user if negative) including roll-fee
     */
    // TODO update docs
    function rollLoan(
        uint loanId,
        uint rollId,
        int minToUser, // cash
        uint newEscrowOffer, // if escrow was used for original loan
        uint newEscrowFee // collateral
    )
        public
        whenNotPaused
        onlyNFTOwner(loanId)
        returns (uint newLoanId, uint newLoanAmount, int transferAmount)
    {
        // @dev rolls contract is assumed to not allow rolling an expired or settled position,
        // but checking explicitly is safer and easier to review
        require(_expiration(loanId) > block.timestamp, "loan expired");
        // burn token. This prevents any further calls for this loan
        _burn(loanId);

        // pull and push NFT and cash, execute roll, emit event
        (uint newTakerId, int _transferAmount, int rollFee) = _executeRoll(loanId, rollId, minToUser);
        transferAmount = _transferAmount;

        Loan storage prevLoan = loans[loanId];
        // calculate the updated loan amount (may have changed due to the roll)
        newLoanAmount = _calculateNewLoan(transferAmount, rollFee, prevLoan.loanAmount);

        // switch escrows if escrow was used
        uint newEscrowId = _optionalSwitchEscrow(loanId, newEscrowOffer, newEscrowFee, newTakerId);

        // set the new ID from new taker ID
        newLoanId = _newLoanIdCheck(newTakerId);
        // store the new loan data
        loans[newLoanId] = Loan({
            collateralAmount: prevLoan.collateralAmount,
            loanAmount: newLoanAmount,
            escrowNFT: prevLoan.escrowNFT,
            escrowId: newEscrowId
        });

        // check escrow and loan have matching fields
        _optionalEscrowValidation(newLoanId, prevLoan.escrowNFT, newEscrowId);

        // mint the new loan NFT to the user, keep the taker NFT (with the same ID) in this contract
        _mint(msg.sender, newLoanId); // @dev does not use _safeMint to avoid reentrancy

        emit LoanRolled(
            msg.sender, loanId, rollId, newLoanId, prevLoan.loanAmount, newLoanAmount, transferAmount
        );
    }

    /**
     * @notice Cancels an active loan, burns the loan NFT, and unwraps the taker NFT
     * @dev This function is used to unwrap a taker NFT, to allow disconnecting it from the loan
     * @param loanId The ID representing the loan to unwrap and cancel
     */
    // TODO update docs
    function unwrapAndCancelLoan(uint loanId) external whenNotPaused onlyNFTOwner(loanId) {
        // release escrow if needed with refunds (interest fee) to sender
        _optionalCheckAndCancelEscrow(loanId, msg.sender);

        // burn token. This prevents any further calls for this loan
        _burn(loanId);

        // unwrap: send the taker NFT to user
        takerNFT.transferFrom(address(this), msg.sender, _takerId(loanId));

        emit LoanCancelled(loanId, msg.sender);
    }

    function seizeEscrow(uint loanId, SwapParams calldata swapParams) external whenNotPaused {
        EscrowSupplierNFT escrowNFT = loans[loanId].escrowNFT;
        require(escrowNFT != NO_ESCROW, "not an escrowed loan");

        // Funds beneficiary (escrow owner) should set the swapParams ideally.
        // A keeper can be needed because foreclosing can be time-sensitive (due to swap timing)
        // and because can be subject to griefing by opening many small loans.
        // @dev will also revert on non-existent (unminted / burned) escrow ID
        uint escrowId = loans[loanId].escrowId;
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
        require(block.timestamp > escrowGracePeriodEnd(loanId), "cannot seize escrow yet");

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
        uint collateralOut = _releaseEscrow(escrowNFT, escrowId, fromSwap);
        collateralAsset.safeTransfer(user, collateralOut);

        // TODO: event
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

    /// @notice Sets the Rolls contract to be used for rolling loans
    /// @dev only owner
    function setRollsContract(Rolls rolls) external onlyOwner {
        if (rolls != Rolls(address(0))) {
            require(rolls.takerNFT() == takerNFT, "rolls taker NFT mismatch");
        }
        emit RollsContractUpdated(rollsContract, rolls); // emit before for the prev value
        rollsContract = rolls;
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

    function _swapAndMintCollar(
        uint collateralAmount,
        ShortProviderNFT providerNFT,
        uint offerId,
        SwapParams memory swapParams // TODO: calldata instead of memory
    ) internal returns (uint takerId, uint providerId, uint loanAmount) {
        require(configHub.canOpen(address(takerNFT)), "unsupported taker");
        // 0 collateral is later checked to mean non-existing loan, also prevents div-zero
        require(collateralAmount != 0, "invalid collateral amount");

        // swap collateral
        // @dev Reentrancy assumption: no user state writes or reads BEFORE the swapper call in _swap.
        // The only state reads before are owner-set state: pause and swapper allowlist.
        uint cashFromSwap = _swapCollateralWithTwapCheck(collateralAmount, swapParams);

        uint putStrikeDeviation = providerNFT.getOffer(offerId).putStrikeDeviation;

        // this assumes LTV === put strike price
        loanAmount = putStrikeDeviation * cashFromSwap / BIPS_BASE;
        // everything that remains is locked on the put side in the collar position
        uint putLockedCash = cashFromSwap - loanAmount;

        // approve the taker contract
        cashAsset.forceApprove(address(takerNFT), putLockedCash);

        // stores, mints, calls providerNFT and mints there, emits the event
        (takerId, providerId) = takerNFT.openPairedPosition(putLockedCash, providerNFT, offerId);
    }

    // TODO: calldata instead of memory
    function _swapCollateralWithTwapCheck(uint collateralAmount, SwapParams memory swapParams)
        internal
        returns (uint cashFromSwap)
    {
        cashFromSwap = _swap(collateralAsset, cashAsset, collateralAmount, swapParams);

        // @dev note that TWAP price is used for payout decision in CollarTakerNFT, and swap price
        // only affects the putLockedCash passed into it - so does not affect the provider, only the user
        _checkSwapPrice(cashFromSwap, collateralAmount);
    }

    /// @dev reentrancy assumption: _swap is called either before or after all internal user state
    /// writes or reads. Such that if there's a reentrancy (e.g., via a malicious token in a
    /// multi-hop route), it should NOT be able to take advantage of any inconsistent state.
    // TODO: calldata instead of memory
    function _swap(IERC20 assetIn, IERC20 assetOut, uint amountIn, SwapParams memory swapParams)
        internal
        returns (uint amountOut)
    {
        // check swapper allowed
        require(allowedSwappers[swapParams.swapper], "swapper not allowed");

        uint balanceBefore = assetOut.balanceOf(address(this));
        // approve the dex router
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

    /// @dev access control (loanId owner ot their keeper) is expected to be checked by caller
    /// @dev this method DOES NOT transfer the swapped collateral to user
    // TODO: calldata instead of memory
    function _closeLoanNoTFOut(uint loanId, SwapParams memory swapParams)
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
        // rolls contract is valid
        require(rollsContract != Rolls(address(0)), "rolls contract unset");
        // avoid using invalid data
        require(rollsContract.getRollOffer(rollId).active, "invalid rollId");
        // @dev Rolls will check if taker position is still valid (unsettled)

        uint initialBalance = cashAsset.balanceOf(address(this));

        // get transfer amount and fee from rolls
        int transferPreview;
        (transferPreview,, rollFee) =
            rollsContract.calculateTransferAmounts(rollId, takerNFT.currentOraclePrice());

        // pull cash
        if (transferPreview < 0) {
            uint fromUser = uint(-transferPreview); // will revert for type(int).min
            // pull cash first, because rolls will try to pull it (if needed) from this contract
            // @dev assumes approval
            cashAsset.safeTransferFrom(msg.sender, address(this), fromUser);
            // allow rolls to pull this cash
            cashAsset.forceApprove(address(rollsContract), fromUser);
        }

        // approve the taker NFT for rolls to pull
        takerNFT.approve(address(rollsContract), _takerId(loanId));
        // execute roll
        (newTakerId,, transferAmount,) = rollsContract.executeRoll(rollId, minToUser);
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

    // ----- Optional escrow mutative methods ----- //

    // TODO: calldata instead of memory
    function _optionalOpenEscrow(OpenLoanParams memory params) internal returns (uint escrowId) {
        EscrowSupplierNFT escrowNFT = params.escrowNFT;
        if (escrowNFT == NO_ESCROW) {
            require(params.escrowFee == 0, "invalid escrowFee"); // user / FE mistake
                // no-up, returns default value
        } else {
            // whitelisted only
            require(configHub.canOpen(address(escrowNFT)), "unsupported escrow");
            // fail gracefully for assets mismatch (instead of allowance / balance failures)
            require(escrowNFT.asset() == takerNFT.collateralAsset(), "asset mismatch");
            // get the supplier collateral for the swap
            collateralAsset.forceApprove(address(escrowNFT), params.collateralAmount + params.escrowFee);
            (escrowId,) = escrowNFT.startEscrow({
                offerId: params.escrowOffer,
                escrowed: params.collateralAmount,
                fee: params.escrowFee,
                loanId: takerNFT.nextPositionId() // @dev will be checked later to correspond
             });
            // @dev no balance checks because contract holds no funds, mismatch will cause reverts
        }
    }

    function _optionalReleaseEscrow(uint loanId, uint fromSwap) internal returns (uint collateralOut) {
        EscrowSupplierNFT escrowNFT = loans[loanId].escrowNFT;
        if (escrowNFT == NO_ESCROW) {
            collateralOut = fromSwap; // no-op
        } else {
            collateralOut = _releaseEscrow(escrowNFT, loans[loanId].escrowId, fromSwap);
        }
    }

    function _releaseEscrow(EscrowSupplierNFT escrowNFT, uint escrowId, uint fromSwap)
        internal
        returns (uint collateralOut)
    {
        // get late fee owing
        (uint lateFee, uint escrowed) = escrowNFT.lateFees(escrowId);

        // if owing more than swapped, use all, otherwise just what's owed
        uint toEscrow = _min(fromSwap, escrowed + lateFee);
        // if owing less than swapped, left over gains are for the user
        uint leftOver = fromSwap - toEscrow;

        // release from escrow, this can be smaller than available
        collateralAsset.forceApprove(address(escrowNFT), toEscrow);
        // fromEscrow is what escrow returns after deducting any shortfall.
        // (although not problematic, there should not be any interest fee refund here,
        // because this method is called after expiry)
        uint fromEscrow = escrowNFT.endEscrow(escrowId, toEscrow);
        // @dev no balance checks because contract holds no funds, mismatch will cause reverts

        // send to user the released and the leftovers. Zero-value-transfer is allowed
        collateralOut = fromEscrow + leftOver;

        emit EscrowSettled(escrowId, toEscrow, fromEscrow, leftOver);
    }

    function _optionalCheckAndCancelEscrow(uint loanId, address refundRecipient) internal {
        EscrowSupplierNFT escrowNFT = loans[loanId].escrowNFT;
        if (escrowNFT == NO_ESCROW) {
            return; // no-op and no checks
        }

        uint escrowId = loans[loanId].escrowId;
        bool escrowReleased = escrowNFT.getEscrow(escrowId).released;
        if (!escrowReleased) {
            // do not allow to unwrap past expiry with unreleased escrow to prevent frontrunning
            // foreclosing. Past expiry either the user should call closeLoan(), or escrow owner should
            // call seizeEscrow()
            require(block.timestamp < _expiration(loanId), "loan expired");

            // release the escrowed user funds to the supplier since the user will not repay the loan
            // no late fees here, since loan is not expired
            uint toUser = escrowNFT.endEscrow(escrowId, 0);
            // @dev no balance checks because contract holds no funds, mismatch will cause reverts

            // send potential interest fee refund
            collateralAsset.safeTransfer(refundRecipient, toUser);
        } else {
            // @dev unwrapping if escrow was released handles the case that escrow owner called
            // escrowNFT.lastResortSeizeEscrow() instead of loans.seizeEscrow() for any reason.
            // In this case, none of the other methods are callable because escrow is released
            // already, so the simplest thing that can be done to avoid locking user's funds is
            // to cancel the loan and send them their takerId to withdraw cash.
        }
    }

    function _optionalSwitchEscrow(
        uint prevLoanId,
        uint newEscrowOffer,
        uint newEscrowFee,
        uint expectedNewLoanId
    ) internal returns (uint newEscrowId) {
        EscrowSupplierNFT escrowNFT = loans[prevLoanId].escrowNFT;
        if (escrowNFT == NO_ESCROW) {
            return 0; // no-op, returns 0 since escrow is not used
        }
        // pull and push escrow fee
        collateralAsset.safeTransferFrom(msg.sender, address(this), newEscrowFee);
        collateralAsset.forceApprove(address(escrowNFT), newEscrowFee);
        // rotate escrows
        uint feeRefund;
        (newEscrowId,, feeRefund) = escrowNFT.switchEscrow({
            releaseEscrowId: loans[prevLoanId].escrowId,
            offerId: newEscrowOffer,
            newLoanId: expectedNewLoanId, // @dev should be validated after this
            newFee: newEscrowFee
        });

        // send potential interest fee refund
        collateralAsset.safeTransfer(msg.sender, feeRefund);
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

    function _optionalEscrowValidation(uint loanId, EscrowSupplierNFT escrowNFT, uint escrowId)
        internal
        view
    {
        // @dev these checks are done in the end of openLoan because escrow position is created
        // first, so on creation cannot be validated with these two checks. On rolls these checks
        // are just reused
        if (escrowNFT != NO_ESCROW) {
            IEscrowSupplierNFT.Escrow memory escrow = escrowNFT.getEscrow(escrowId);
            // taker.nextPositionId() view was used to create escrow, but it was used before external
            // calls, so we need to ensure it matches still (was not skipped by reentrancy)
            require(escrow.loanId == loanId, "unexpected loanId");
            // check expirations are equal to ensure no duration mismatch between escrow and collar
            require(escrow.expiration == _expiration(loanId), "duration mismatch");
        }
    }
}
