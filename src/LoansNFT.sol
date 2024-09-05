// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity 0.8.22;

import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
// internal imports
import { BaseEmergencyAdminNFT, ConfigHub } from "./base/BaseEmergencyAdminNFT.sol";
import { CollarTakerNFT, ShortProviderNFT } from "./CollarTakerNFT.sol";
import { Rolls } from "./Rolls.sol";
import { ISwapper } from "./interfaces/ISwapper.sol";
import { ILoansNFT, IBaseLoansNFT } from "./interfaces/ILoansNFT.sol";

abstract contract BaseLoansNFT is BaseEmergencyAdminNFT, IBaseLoansNFT {
    using SafeERC20 for IERC20;

    uint internal constant BIPS_BASE = 10_000;
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
        BaseEmergencyAdminNFT(initialOwner, _name, _symbol)
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

    // ----- STATE CHANGING FUNCTIONS ----- //

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

    // admin methods

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

    function _openSwapAndMint(
        uint collateralAmount,
        ShortProviderNFT providerNFT,
        uint offerId,
        SwapParams calldata swapParams
    ) internal returns (uint loanId, uint providerId, uint loanAmount) {
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

        uint takerId;
        // stores, mints, calls providerNFT and mints there, emits the event
        (takerId, providerId) = takerNFT.openPairedPosition(putLockedCash, providerNFT, offerId);

        loanId = _newLoanIdCheck(takerId);
        // store the loan opening data
        loans[loanId] = Loan({ collateralAmount: collateralAmount, loanAmount: loanAmount });
        // mint the laon NFT to the borrower, keep the taker NFT (with the same ID) in this contract
        _mint(msg.sender, loanId); // @dev does not use _safeMint to avoid reentrancy
    }

    function _swapCollateralWithTwapCheck(uint collateralAmount, SwapParams calldata swapParams)
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
    function _swap(IERC20 assetIn, IERC20 assetOut, uint amountIn, SwapParams calldata swapParams)
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

    /// @dev access control is expected to be checked by caller (loanId owner)
    function _rollLoan(uint loanId, Rolls rolls, uint rollId, int minToUser)
        internal
        returns (uint newLoanId, uint newLoanAmount, int transferAmount)
    {
        // rolls contract is valid
        require(rollsContract != Rolls(address(0)), "rolls contract unset");
        // Check user expected rolls contract is the currently configured rolls contract.
        // @dev user intent validation in case rolls contract config value was updated
        require(rolls == rollsContract, "rolls contract mismatch");
        require(rollsContract.getRollOffer(rollId).active, "invalid rollId"); // avoid using invalid data
        // @dev Rolls will check if taker position is still valid (unsettled)

        // @dev rolls contract is assumed to not allow rolling an expired or settled position,
        // but checking explicitly is safer and easier to review
        require(_expiration(loanId) > block.timestamp, "loan expired");
        // burn token. This prevents any further calls for this loan
        _burn(loanId);

        // pull and push NFT and cash, execute roll, emit event
        (uint newTakerId, int _transferAmount, int rollFee) = _executeRoll(loanId, rollId, minToUser);
        transferAmount = _transferAmount;

        // previous values. We burned the token, but loans storage is never modified
        uint prevLoanAmount = loans[loanId].loanAmount;
        uint collateralAmount = loans[loanId].collateralAmount;
        // calculate the updated loan amount (may have changed due to the roll)
        newLoanAmount = _calculateNewLoan(transferAmount, rollFee, prevLoanAmount);

        // set the new ID from new taker ID
        newLoanId = _newLoanIdCheck(newTakerId);
        // store the new loan data
        loans[newLoanId] = Loan({ collateralAmount: collateralAmount, loanAmount: newLoanAmount });

        // mint the new laon NFT to the user, keep the taker NFT (with the same ID) in this contract
        _mint(msg.sender, newLoanId); // @dev does not use _safeMint to avoid reentrancy

        emit LoanRolled(msg.sender, loanId, rollId, newLoanId, prevLoanAmount, newLoanAmount, transferAmount);
    }

    function _executeRoll(uint loanId, uint rollId, int minToUser)
        internal
        returns (uint newTakerId, int transferAmount, int rollFee)
    {
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

    /// @dev access control is expected to be checked by caller (loanId owner)
    function _unwrapAndCancelLoan(uint loanId) internal {
        // burn token. This prevents any further calls for this loan
        _burn(loanId);

        // unwrap: send the taker NFT to user
        takerNFT.transferFrom(address(this), msg.sender, _takerId(loanId));

        emit LoanCancelled(loanId, msg.sender);
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
    /// So, this check is just extra precaution and avoidance of manipulation edge-cases.
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
}

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
contract LoansNFT is ILoansNFT, BaseLoansNFT {
    using SafeERC20 for IERC20;

    constructor(address initialOwner, CollarTakerNFT _takerNFT, string memory _name, string memory _symbol)
        BaseLoansNFT(initialOwner, _takerNFT, _name, _symbol)
    { }

    // ----- STATE CHANGING FUNCTIONS ----- //

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
    ) external whenNotPaused returns (uint loanId, uint providerId, uint loanAmount) {
        // pull collateral
        collateralAsset.safeTransferFrom(msg.sender, address(this), collateralAmount);

        // @dev Reentrancy assumption: no user state writes or reads BEFORE this call
        (loanId, providerId, loanAmount) =
            _openSwapAndMint(collateralAmount, providerNFT, offerId, swapParams);
        require(loanAmount >= minLoanAmount, "loan amount too low");

        // transfer the full loan amount on open
        cashAsset.safeTransfer(msg.sender, loanAmount);

        emit LoanOpened(
            msg.sender, address(providerNFT), offerId, collateralAmount, loanAmount, loanId, providerId
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

        collateralOut = _closeLoanNoTFOut(loanId, swapParams);

        // send to user the released collateral
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
     * @param rolls The Rolls contract to be used for this operation (must match the configured one)
     * @param rollId The ID of the roll offer to be executed
     * @param minToUser The minimum acceptable transfer to user (negative if expecting to pay)
     * @return newLoanId The ID of the newly minted NFT representing the rolled loan
     * @return newLoanAmount The updated loan amount after rolling
     * @return transferAmount The actual transfer to user (or from user if negative) including roll-fee
     */
    function rollLoan(uint loanId, Rolls rolls, uint rollId, int minToUser)
        external
        whenNotPaused
        onlyNFTOwner(loanId)
        returns (uint newLoanId, uint newLoanAmount, int transferAmount)
    {
        return _rollLoan(loanId, rolls, rollId, minToUser);
    }

    /**
     * @notice Cancels an active loan, burns the loan NFT, and unwraps the taker NFT
     * @dev This function is used to unwrap a taker NFT, to allow disconnecting it from the loan
     * @param loanId The ID representing the loan to unwrap and cancel
     */
    function unwrapAndCancelLoan(uint loanId) external whenNotPaused onlyNFTOwner(loanId) {
        _unwrapAndCancelLoan(loanId);
    }
}
