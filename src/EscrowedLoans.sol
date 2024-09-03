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
import { EscrowedSupplierNFT } from "./EscrowedSupplierNFT.sol";
import { Rolls } from "./Rolls.sol";
import { ISwapper } from "./interfaces/ISwapper.sol";

abstract contract BaseLoans is BaseEmergencyAdminNFT {
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
    /// @notice Stores loan information for each taker NFT ID
    struct Loan {
        uint collateralAmount;
        uint loanAmount;
        bool active;
    }

    mapping(uint loanId => Loan) internal loans;
    // optional keeper (set by contract owner) that's needed for swap back in time-sensitive methods
    address public closingKeeper;
    // callers (users or escrow owners that allow a keeper for swaps impacting their funds)
    mapping(address sender => bool enabled) public allowsClosingKeeper;
    // the currently configured & allowed rolls contract for this takerNFT and cash asset
    Rolls public rollsContract;
    // a convenience view to allow querying for a swapper onchain / FE without subgraph
    address public defaultSwapper;
    // contracts used for swaps, including the defaultSwapper
    mapping(address swapper => bool allowed) public allowedSwappers;

    struct SwapParams {
        uint minAmountOut; // can be cash or collateral, in correct token units
        address swapper;
        bytes extraData;
    }

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

    function setKeeperAllowed(bool enabled) external whenNotPaused {
        allowsClosingKeeper[msg.sender] = enabled;
        //        emit ClosingKeeperAllowed(msg.sender, enabled);
    }

    // admin methods

    /// @notice Sets the address of the closing keeper
    /// @dev only owner
    function setKeeper(address keeper) external onlyOwner {
        //        emit ClosingKeeperUpdated(closingKeeper, keeper);
        closingKeeper = keeper;
    }

    /// @notice Sets the Rolls contract to be used for rolling loans
    /// @dev only owner
    function setRollsContract(Rolls rolls) external onlyOwner {
        if (rolls != Rolls(address(0))) {
            require(rolls.takerNFT() == takerNFT, "rolls taker NFT mismatch");
        }
        //        emit RollsContractUpdated(rollsContract, rolls); // emit before for the prev value
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
        //        emit SwapperSet(swapper, allowed, setDefault);
    }

    // ----- INTERNAL MUTATIVE ----- //

    function _openAndMint(
        uint collateralAmount,
        uint cashFromSwap,
        ShortProviderNFT providerNFT,
        uint offerId
    ) internal returns (uint loanId, uint providerId, uint loanAmount) {
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
        loanId = _newLoanId(takerId);

        // store the loan opening data
        // takerId is assumed to be just minted, so storage must be empty
        loans[loanId] = Loan({ collateralAmount: collateralAmount, loanAmount: loanAmount, active: true });
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

    /// @dev this function assumes that swapper allowlist was checked before calling this
    /// @dev reentrancy assumption: _swap is called either before or after all internal user state
    /// writes or reads. Such that if there's a reentrancy (e.g., via a malicious token in a
    /// multi-hop route), it should NOT be able to take advantage of any inconsistent state.
    function _swap(IERC20 assetIn, IERC20 assetOut, uint amountIn, SwapParams calldata swapParams)
        internal
        returns (uint amountOut)
    {
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

    function _closeLoan(uint loanId, SwapParams calldata swapParams)
        internal
        returns (uint collateralOut, address user)
    {
        // swapper allowed
        require(allowedSwappers[swapParams.swapper], "swapper not allowed");

        Loan storage loan = loans[loanId];
        require(loan.active, "not active");
        loan.active = false; // set here to add reentrancy protection

        // total cash available
        // @dev will check settle, or try to settle - will revert if cannot settle yet (not expired)
        uint takerWithdrawal = _settleAndWithdrawTaker(loanId);

        // @dev user is the NFT owner, since msg.sender can be a keeper
        // If called by keeper, the user must trust it because:
        // - call pulls user funds (for repayment)
        // - call burns the NFT from user
        // - call sends the final funds to the user
        // - keeper sets the SwapParams and its slippage parameter
        user = ownerOf(loanId);

        // @dev assumes approval
        cashAsset.safeTransferFrom(user, address(this), loan.loanAmount);

        // burn token
        _burn(loanId);

        // @dev Reentrancy assumption: no user state writes or reads AFTER the swapper call in _swap.
        uint cashAmount = loan.loanAmount + takerWithdrawal;
        collateralOut = _swap(cashAsset, collateralAsset, cashAmount, swapParams);

        // TODO event
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
        // loan
        Loan storage loan = loans[loanId];
        require(loan.active, "not active");
        // close the previous loan, done here to add reentrancy protection
        loan.active = false;
        // burn token
        _burn(loanId);

        // pull and push NFT and cash, execute roll, emit event
        uint newTakerId;
        int rollFee;
        (newTakerId, transferAmount, rollFee) = _executeRoll(loanId, rollId, minToUser);
        newLoanAmount = _calculateNewLoan(transferAmount, rollFee, loan.loanAmount);
        newLoanId = _newLoanId(newTakerId);

        // store the new loan data
        // takerId is assumed to be just minted, so storage must be empty
        loans[newLoanId] =
            Loan({ collateralAmount: loan.collateralAmount, loanAmount: newLoanAmount, active: true });

        // mint the new laon NFT to the user, keep the taker NFT (with the same ID) in this contract
        _mint(msg.sender, newLoanId); // @dev does not use _safeMint to avoid reentrancy
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

        // TODO: event
    }

    /// @dev access control is expected to be checked by caller
    function _unwrapAndCancelLoan(uint loanId, address user) internal {
        require(_expiration(loanId) > block.timestamp, "loan expired");
        // cancel the loan
        require(loans[loanId].active, "loan not active");
        loans[loanId].active = false;

        // unwrap: send the taker NFT to user
        takerNFT.transferFrom(address(this), user, _takerId(loanId));

        // TODO: event
    }

    // ----- INTERNAL VIEWS ----- //

    function _isSenderOrKeeperFor(address authorizedSender) internal view returns (bool) {
        bool isSender = msg.sender == authorizedSender; // is the auth target
        bool isKeeper = msg.sender == closingKeeper;
        // our auth target allows the keeper
        bool keeperAllowed = allowsClosingKeeper[authorizedSender];
        return isSender || (keeperAllowed && isKeeper);
    }

    function _newLoanId(uint takerId) internal view returns (uint loanId) {
        // @dev loanIds correspond to takerIds they wrap for simplicity. this is ok because takerId are
        // unique (for the single taker contract wrapped by the loans) and are minted by this contract
        loanId = takerId;
        // @dev because we use the takerId for the loanId (instead of having separate IDs), we should
        // check that the ID is not yet taken. This should not be possible, since takerId should mint
        // correctly, to new IDs.
        require(loans[loanId].collateralAmount == 0, "loanId taken"); // this is ensured in openLoan
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

contract EscrowedLoans is BaseLoans {
    using SafeERC20 for IERC20;

    EscrowedSupplierNFT public immutable escrowNFT;

    mapping(uint loanId => uint escrowId) public loanIdToEscrowId;

    constructor(
        address initialOwner,
        CollarTakerNFT _takerNFT,
        EscrowedSupplierNFT _escrowNFT,
        string memory _name,
        string memory _symbol
    ) BaseLoans(initialOwner, _takerNFT, _name, _symbol) {
        escrowNFT = _escrowNFT;
        require(escrowNFT.asset() == collateralAsset, "asset mismatch");
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
        uint escrowOffer
    ) external whenNotPaused returns (uint loanId, uint providerId, uint escrowId, uint loanAmount) {
        // pull escrow collateral
        collateralAsset.safeTransferFrom(msg.sender, address(this), collateralAmount);

        uint expectedTakerId = takerNFT.nextPositionId();
        // get the supplier collateral for the swap
        collateralAsset.forceApprove(address(escrowNFT), collateralAmount);
        (escrowId,) = escrowNFT.escrowAndMint(escrowOffer, collateralAmount, expectedTakerId);
        // @dev no balance checks are needed, because this contract holds no funds (collateral or cash).
        // all collateral is either swapped or in escrow, so an incorrect balance will cause reverts on
        // transfers

        // 0 collateral is later checked to mean non-existing loan, also prevents div-zero
        require(collateralAmount != 0, "invalid collateral amount");
        // check swapper allowed
        require(allowedSwappers[swapParams.swapper], "swapper not allowed");

        // swap collateral
        // @dev Reentrancy assumption: no user state writes or reads BEFORE the swapper call in _swap.
        // The only state reads before are owner-set state: pause and swapper allowlist.
        uint cashFromSwap = _swapCollateralWithTwapCheck(collateralAmount, swapParams);

        (loanId, providerId, loanAmount) =
            _openAndMint(collateralAmount, cashFromSwap, providerNFT, shortOffer);

        require(loanAmount >= minLoanAmount, "loan amount too low");
        // loanId is the takerId, but view was used before external calls so we need to ensure it matches still
        require(loanId == expectedTakerId, "unexpected loanId");
        // write the escrowId
        loanIdToEscrowId[loanId] = escrowId;

        // transfer the full loan amount on open
        cashAsset.safeTransfer(msg.sender, loanAmount);

        // TODO event
    }

    function closeLoan(uint loanId, SwapParams calldata swapParams)
        external
        whenNotPaused
        onlyNFTOwnerOrKeeper(loanId)
        returns (uint collateralOut)
    {
        address user;
        (collateralOut, user) = _closeLoan(loanId, swapParams);

        _releaseEscrow(loanId, collateralOut, user);

        // TODO event
    }

    function rollLoan(uint loanId, Rolls rolls, uint rollId, int minToUser, uint newEscrowOffer)
        external
        whenNotPaused
        onlyNFTOwner(loanId)
        returns (uint newLoanId, uint newLoanAmount, int transferAmount)
    {
        // @dev _rollLoan is assumed to check that loan is not expired, so cannot be foreclosed
        (newLoanId, newLoanAmount, transferAmount) = _rollLoan(loanId, rolls, rollId, minToUser);

        // rotate escrows
        uint prevEscrowId = loanIdToEscrowId[loanId];
        (uint newEscrowId,) = escrowNFT.releaseAndMint(prevEscrowId, newEscrowOffer, newLoanId);
        loanIdToEscrowId[newLoanId] = newEscrowId;

        // TODO: event
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

        Loan storage loan = loans[loanId];
        require(loan.active, "not active");
        loan.active = false;

        // @dev will revert if too early, although the canForeclose() check above will revert first
        uint cashAvailable = _settleAndWithdrawTaker(loanId);

        address user = ownerOf(loanId);
        // burn NFT from the user. Although they are not the caller, altering their assets is fine here
        // because foreClosing is a state with other negative consequence they should try to avoid anyway
        _burn(loanId);

        // @dev Reentrancy assumption: no user state writes or reads AFTER the swapper call in _swap.
        uint collateralOut = _swap(cashAsset, collateralAsset, cashAvailable, swapParams);

        // Release escrow, and send any leftovers to user. Their express trigger of balance update
        // (withdrawal) is neglected here due to being anyway in an undesirable state of being foreclosed
        // due to not repaying on time.
        _releaseEscrow(loanId, collateralOut, user);

        // TODO: event
    }

    function unwrapAndCancelLoan(uint loanId) external whenNotPaused onlyNFTOwner(loanId) {
        _unwrapAndCancelLoan(loanId, msg.sender);

        // release the escrowed user funds to the supplier since the user will not repay the loan
        uint toUser = escrowNFT.releaseEscrow(loanIdToEscrowId[loanId], 0);
        require(toUser == 0, "unexpected releaseEscrow result");

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
        uint releasedToUser = escrowNFT.releaseEscrow(escrowId, toSupplier);
        // @dev no balance checks are needed, because this contract holds no funds (collateral or cash).
        // all collateral is either swapped or in escrow, so an incorrect balance will cause reverts on
        // transfer

        // send to user the released and the leftovers. Zero-value-transfer is allowed
        collateralAsset.safeTransfer(user, releasedToUser + leftOver);
    }

    // ----- INTERNAL VIEWS ----- //
}
