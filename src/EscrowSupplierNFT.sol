// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { BaseNFT, ConfigHub } from "./base/BaseNFT.sol";
import { IEscrowSupplierNFT } from "./interfaces/IEscrowSupplierNFT.sol";

/**
 * @title EscrowSupplierNFT
 * @notice Manages escrows and escrow offers for LoansNFT.
 *
 * Main Functionality:
 * 1. Allows suppliers to create and manage escrow offers for multiple loans contracts.
 * 2. Mints NFTs representing escrow positions when offers are taken.
 * 3. Handles starting, ending, and switching of escrow positions.
 * 4. Manages withdrawals of released escrows and last-resort emergency seizures.
 *
 * Difference vs. CollarProviderNFT:
 * - Asset: Escrow is "supplied" in underlying tokens (e.g., ETH), while "providers"
 * provide cash (e.g., USDC).
 * - Risk: "Suppliers" (as opposed to "providers") have no downside, and no exposure to price,
 * and have fixed / limited upside (interest and late fees).
 * - Optional: only used for escrow backed loans for specific tax reasons, not for regular loans.
 *
 * Key Assumptions and Prerequisites:
 * 1. Escrow suppliers must be able to receive ERC-721 to use this contract.
 * 2. The associated Loans contracts are trusted and properly implemented.
 * 3. ConfigHub contract correctly manages protocol parameters and authorization.
 * 4. Asset (ERC-20) contracts are simple (non rebasing), do not allow reentrancy. Balance
 *    changes corresponds to transfer arguments.
 */
contract EscrowSupplierNFT is IEscrowSupplierNFT, BaseNFT {
    using SafeERC20 for IERC20;

    uint internal constant BIPS_BASE = 10_000;
    uint internal constant YEAR = 365 days;

    uint public constant MAX_INTEREST_APR_BIPS = BIPS_BASE; // 100% APR
    uint public constant MAX_LATE_FEE_APR_BIPS = BIPS_BASE * 12; // 1200% APR (100% for a max period of 30 days)
    uint public constant MIN_GRACE_PERIOD = 1 days;
    uint public constant MAX_GRACE_PERIOD = 30 days;

    string public constant VERSION = "0.2.0";

    // ----- IMMUTABLES ----- //
    IERC20 public immutable asset; // corresponds to Loans' underlying

    // ----- STATE ----- //
    // @dev this is NOT the NFT id, this is a  separate non transferrable ID
    uint public nextOfferId = 1; // starts from 1 so that 0 ID is not used

    // allowed loans contracts
    mapping(address loans => bool allowed) public allowedLoans;

    mapping(uint offerId => Offer) internal offers;

    mapping(uint escrowId => Escrow) internal escrows;

    constructor(
        address initialOwner,
        ConfigHub _configHub,
        IERC20 _asset,
        string memory _name,
        string memory _symbol
    ) BaseNFT(initialOwner, _name, _symbol) {
        asset = _asset;
        _setConfigHub(_configHub);
    }

    modifier onlyLoans() {
        require(allowedLoans[msg.sender], "unauthorized loans contract");
        _;
    }

    // ----- VIEWS ----- //

    /// @notice Returns the NFT ID of the next escrow to be minted
    function nextEscrowId() external view returns (uint) {
        return nextTokenId;
    }

    /// @notice Retrieves the details of a specific non-transferrable offer.
    /// @dev This is used instead of the default getter because the default getter returns a tuple
    function getOffer(uint offerId) external view returns (Offer memory) {
        return offers[offerId];
    }

    /// @notice Retrieves the details of a specific escrow (corresponds to the NFT token ID)
    /// @dev This is used instead of the default getter because the default getter returns a tuple
    function getEscrow(uint escrowId) external view returns (Escrow memory) {
        return escrows[escrowId];
    }

    /**
     * @notice Returns the total owed including late fees for an escrow.
     * Uses a MIN_GRACE_PERIOD "cliff": Overdue time is counted from expiry, but during
     * the MIN_GRACE_PERIOD late fees are returned as 0 (even though are "accumulating" for it).
     * @param escrowId The ID of the escrow to calculate late fees for
     * @return totalOwed Total owed: escrowed amount + late fee
     * @return lateFee The calculated late fee
     */
    function owedTo(uint escrowId) external view returns (uint totalOwed, uint lateFee) {
        Escrow memory escrow = escrows[escrowId];
        lateFee = _lateFee(escrow);
        return (escrow.escrowed + lateFee, lateFee);
    }

    /**
     * @notice Calculates the grace period based on available late fee amount. This is the grace period
     * the maxLateFee "can afford" before causing an shortfall of late fees. This view should be used to
     * enforce a reduced gracePeriod in available case funds are insufficient for the full grace period.
     * Grace period returned is between MIN_GRACE_PERIOD and the offer's `gracePeriod`.
     * @param escrowId The ID of the escrow to calculate for
     * @param maxLateFee The available fee amount
     * @return The calculated grace period in seconds
     */
    function cappedGracePeriod(uint escrowId, uint maxLateFee) external view returns (uint) {
        Escrow memory escrow = escrows[escrowId];
        // initialize with max according to terms
        uint period = escrow.maxGracePeriod;
        // avoid div-zero
        if (escrow.escrowed != 0 && escrow.lateFeeAPR != 0) {
            // Calculate the grace period that can be "afforded" by maxLateFee according to few APR.
            //  fee = escrowed * time * APR / year / 100bips, so
            //  time = fee * year * 100bips / escrowed / APR;
            // rounding down, against the user
            uint timeAfforded = maxLateFee * YEAR * BIPS_BASE / escrow.escrowed / escrow.lateFeeAPR;
            // cap to timeAfforded
            period = Math.min(timeAfforded, period);
        }
        // ensure MIN_GRACE_PERIOD, which means that even if no funds are available, min grace period
        // is available.
        return Math.max(period, MIN_GRACE_PERIOD);
    }

    /**
     * @notice Calculates the interest fee (to be deposited upfront) for an offer and escrow amount.
     * @param offerId The offer Id to use for calculations
     * @param escrowed The escrowed amount
     * @return fee The calculated interest fee
     */
    function interestFee(uint offerId, uint escrowed) public view returns (uint) {
        Offer memory offer = offers[offerId];
        // rounds up against the user
        return Math.ceilDiv(escrowed * offer.interestAPR * offer.duration, BIPS_BASE * YEAR);
    }

    /**
     * @notice Previews the result of releasing an escrow if it is done now.
     * @param escrowId The ID of the escrow to preview
     * @param fromLoans The amount repaid from loans
     * @return withdrawal The amount to be withdrawn by the supplier
     * @return toLoans The amount to be returned to loans (includes refund)
     * @return refund The refunded interest amount
     */
    function previewRelease(uint escrowId, uint fromLoans)
        external
        view
        returns (uint withdrawal, uint toLoans, uint refund)
    {
        (withdrawal, toLoans, refund) = _releaseCalculations(escrows[escrowId], fromLoans);
    }

    // ----- MUTATIVE ----- //

    // ----- Offer actions ----- //

    /**
     * @notice Creates a new escrow offer
     * @param amount The offered amount
     * @param duration The offer duration in seconds
     * @param interestAPR The annual interest rate in basis points
     * @param maxGracePeriod The maximum grace period duration in seconds
     * @param lateFeeAPR The annual late fee rate in basis points
     * @return offerId The ID of the created offer
     */
    function createOffer(uint amount, uint duration, uint interestAPR, uint maxGracePeriod, uint lateFeeAPR)
        external
        whenNotPaused
        returns (uint offerId)
    {
        // sanity checks
        require(interestAPR <= MAX_INTEREST_APR_BIPS, "interest APR too high");
        require(lateFeeAPR <= MAX_LATE_FEE_APR_BIPS, "late fee APR too high");
        require(maxGracePeriod >= MIN_GRACE_PERIOD, "grace period too short");
        require(maxGracePeriod <= MAX_GRACE_PERIOD, "grace period too long");
        // config hub allows values
        _configHubValidations(duration);

        offerId = nextOfferId++;
        offers[offerId] = Offer({
            supplier: msg.sender,
            available: amount,
            duration: duration,
            interestAPR: interestAPR,
            maxGracePeriod: maxGracePeriod,
            lateFeeAPR: lateFeeAPR
        });
        asset.safeTransferFrom(msg.sender, address(this), amount);
        emit OfferCreated(msg.sender, interestAPR, duration, maxGracePeriod, lateFeeAPR, amount, offerId);
    }

    /**
     * @notice Updates the total available amount of an existing offer. Update to 0 to fully withdraw.
     * @dev Can increase or decrease the offer amount. Must be from original offer supplier
     * @param offerId The ID of the offer to update
     * @param newAmount The new offer amount
     */
    function updateOfferAmount(uint offerId, uint newAmount) external whenNotPaused {
        require(msg.sender == offers[offerId].supplier, "not offer supplier");

        uint previousAmount = offers[offerId].available;
        if (newAmount > previousAmount) {
            // deposit more
            uint toAdd = newAmount - previousAmount;
            offers[offerId].available += toAdd;
            asset.safeTransferFrom(msg.sender, address(this), toAdd);
        } else if (newAmount < previousAmount) {
            // withdraw
            uint toRemove = previousAmount - newAmount;
            offers[offerId].available -= toRemove;
            asset.safeTransfer(msg.sender, toRemove);
        } else { } // no change
        emit OfferUpdated(offerId, msg.sender, previousAmount, newAmount);
    }

    // ----- Escrow actions ----- //

    // ----- actions through loans contract ----- //

    /**
     * @notice Starts a new escrow from an existing offer. Transfer the full amount in, escrow + fee,
     * and then transfers out the escrow amount back.
     * @dev Can only be called by allowed Loans contracts. Use `interestFee` view to calculate the
     * required fee. Fee is specified explicitly for interface clarity, because is on top of the
     * escrowed amount, so the amount to approve is escrowed + fee.
     * @param offerId The ID of the offer to use
     * @param escrowed The amount to escrow
     * @param fee The upfront interest fee amount. Checked to be sufficient.
     *   Will be partially refunded if escrow is released before expiration.
     * @param loanId The associated loan ID
     * @return escrowId The ID of the created escrow
     */
    function startEscrow(uint offerId, uint escrowed, uint fee, uint loanId)
        external
        whenNotPaused
        onlyLoans
        returns (uint escrowId)
    {
        escrowId = _startEscrow(offerId, escrowed, fee, loanId);

        // @dev despite the fact that they partially cancel out, so can be done as just fee transfer,
        // these transfers are the whole point of this contract from product point of view.
        // The transfer events for the full amounts are needed such that the tokens used for the swap
        // in Loans should be "supplier's", and not "borrower's" from CGT tax lows perspective.
        // transfer "borrower's" funds in
        asset.safeTransferFrom(msg.sender, address(this), escrowed + fee);
        // transfer "supplier's" funds out
        asset.safeTransfer(msg.sender, escrowed);
    }

    /**
     * @notice Ends an escrow
     * @dev Can only be called by the Loans contract that started the escrow
     * @param escrowId The ID of the escrow to end
     * @param repaid The amount repaid, can be more or less than original escrow amount, depending on
     * late fees (enforced by the loans contract), or position / slippage / default shortfall. The
     * supplier is guaranteed to withdraw at least the escrow amount regardless.
     * @return toLoans Amount to be returned to loans including potential refund and deducing shortfalls
     */
    function endEscrow(uint escrowId, uint repaid) external whenNotPaused onlyLoans returns (uint toLoans) {
        toLoans = _endEscrow(escrowId, repaid);

        // transfer in the repaid assets in: original supplier's assets, plus any late fee
        asset.safeTransferFrom(msg.sender, address(this), repaid);
        // release the escrow (with possible loss to the borrower): user's assets + refund - shortfall
        asset.safeTransfer(msg.sender, toLoans);
    }

    /**
     * @notice Switches an escrow to a new escrow.
     * @dev While it is basically startEscrow + endEscrow, calling these methods externally
     * is not possible: startEscrow pulls the escrow amount in and transfers it out,
     * which is not possible when switching escrows because the caller (loans) has no underlying for
     * such a transfer at that point. So instead this method is needed to "move" funds internally.
     * @dev Can only be called by the Loans contract that started the original escrow
     * @dev durations can theoretically be different (is not problematic within this contract),
     * but Loans - the only caller of this - should check the new offer duration / new escrow
     * expiration is as is needed for its use.
     * @param releaseEscrowId The ID of the escrow to release
     * @param offerId The ID of the new offer
     * @param newLoanId The new loan ID
     * @param newFee The new interest fee amount
     * @return newEscrowId The ID of the new escrow
     * @return feeRefund The refunded fee amount from the old escrow's upfront interest
     */
    function switchEscrow(uint releaseEscrowId, uint offerId, uint newLoanId, uint newFee)
        external
        whenNotPaused
        onlyLoans
        returns (uint newEscrowId, uint feeRefund)
    {
        Escrow memory previousEscrow = escrows[releaseEscrowId];
        // do not allow expired escrow to be switched since 0 fromLoans is used for _endEscrow
        require(block.timestamp <= previousEscrow.expiration, "expired escrow");

        /*
        1. initially user's escrow "E" secures old ID, "O". O's supplier's funds are away.
        2. E is then "transferred" to secure new ID, "N". N's supplier's funds are taken, to release O.
        3. O is released (with N's funds). N's funds are now secured by E (user's escrow).

        Interest is accounted separately by transferring the full N's interest fee
        (held until release), and refunding O's interest held.
        */

        // "O" (old escrow): Release funds to the supplier.
        // The withdrawable for O's supplier comes from the N's offer, not from Loans repayment.
        // The escrowed loans-funds (E) move into the new escrow of the new supplier.
        // fromLoans must be 0, otherwise escrow will be sent to Loans instead of only the fee refund.
        feeRefund = _endEscrow(releaseEscrowId, 0);

        // N (new escrow): Mint a new escrow from the offer (can be old or new offer).
        // The escrow funds are funds that have been escrowed in the ID being released ("O").
        // The offer is reduced (which is used to repay the previous supplier)
        // A new escrow ID is minted.
        newEscrowId = _startEscrow(offerId, previousEscrow.escrowed, newFee, newLoanId);

        // fee transfers
        asset.safeTransferFrom(msg.sender, address(this), newFee);
        asset.safeTransfer(msg.sender, feeRefund);

        emit EscrowsSwitched(releaseEscrowId, newEscrowId);
    }

    // ----- actions by escrow owner ----- //

    /// @notice Withdraws funds from a released escrow. Burns the NFT.
    /// @param escrowId The ID of the escrow to withdraw from
    function withdrawReleased(uint escrowId) external whenNotPaused {
        require(msg.sender == ownerOf(escrowId), "not escrow owner"); // will revert for burned

        Escrow storage escrow = escrows[escrowId];
        require(escrow.released, "not released");

        uint withdrawable = escrow.withdrawable;
        // zero out withdrawable
        escrow.withdrawable = 0;
        // burn token
        _burn(escrowId);
        // transfer tokens
        asset.safeTransfer(msg.sender, withdrawable);

        emit WithdrawalFromReleased(escrowId, msg.sender, withdrawable);
    }

    /**
     * @notice Emergency function to seize escrow funds after max grace period. Burns the NFT.
     * WARNING: DO NOT use this is normal circumstances, instead use LoansNFT.forecloseLoan().
     * This method is only for extreme scenarios to ensure suppliers can always withdraw even if
     * original LoansNFT is broken / disabled / disallowed by admin.
     * This method can only be used after the max grace period is elapsed, and does not pay any late fees.
     * @dev Ideally the owner of the NFT will call LoansNFT.forecloseLoan() which is callable earlier
     * or pays late fees (or both). If they do that, "released" will be set to true, disabling this method.
     * In the opposite situation, if the NFT owner chooses to call this method by mistake,
     * the LoansNFT method will not be callable, because "released" will true (+NFT will be burned).
     * @param escrowId The ID of the escrow to seize
     */
    function lastResortSeizeEscrow(uint escrowId) external whenNotPaused {
        require(msg.sender == ownerOf(escrowId), "not escrow owner"); // will revert for burned

        Escrow memory escrow = escrows[escrowId];
        require(!escrow.released, "already released");
        require(block.timestamp > escrow.expiration + escrow.maxGracePeriod, "grace period not elapsed");

        // update storage
        escrows[escrowId].released = true;

        // burn token because this is a withdrawal and a direct last action by NFT owner
        _burn(escrowId);

        // @dev withdrawal is immediate, so escrow.withdrawable is not set here (no _releaseEscrow call).
        // release escrowed and full interest
        uint withdawal = escrow.escrowed + escrow.interestHeld;
        asset.safeTransfer(msg.sender, withdawal);

        emit EscrowSeizedLastResort(escrowId, msg.sender, withdawal);
    }

    // ----- admin ----- //

    /// @notice Sets whether a Loans contract is allowed to interact with this contract
    function setLoansAllowed(address loans, bool allowed) external onlyOwner {
        // @dev no checks for Loans interface since calls are only from Loans to this contract
        allowedLoans[loans] = allowed;
        emit LoansAllowedSet(loans, allowed);
    }

    // ----- INTERNAL MUTATIVE ----- //

    function _startEscrow(uint offerId, uint escrowed, uint fee, uint loanId)
        internal
        returns (uint escrowId)
    {
        require(configHub.canOpen(msg.sender), "unsupported loans contract");
        require(configHub.canOpen(address(this)), "unsupported supplier contract");

        Offer memory offer = offers[offerId];
        require(offer.supplier != address(0), "invalid offer"); // revert here for clarity

        // check params are still supported
        _configHubValidations(offer.duration);

        // we don't check equality to avoid revert due to minor inaccuracies to the upside,
        // even though exact value should be used from the view.
        require(fee >= interestFee(offerId, escrowed), "insufficient fee");

        // @dev fee is not taken from offer, because it is transferred in from loans
        uint prevOfferAmount = offer.available;
        require(escrowed <= prevOfferAmount, "amount too high");

        // storage updates
        offers[offerId].available -= escrowed;
        escrowId = nextTokenId++;
        escrows[escrowId] = Escrow({
            loans: msg.sender,
            loanId: loanId,
            escrowed: escrowed,
            maxGracePeriod: offer.maxGracePeriod,
            lateFeeAPR: offer.lateFeeAPR,
            duration: offer.duration,
            expiration: block.timestamp + offer.duration,
            interestHeld: fee,
            released: false,
            withdrawable: 0
        });

        // emit before token transfer event in mint for easier indexing
        emit EscrowCreated(escrowId, escrowed, offer.duration, fee, offer.maxGracePeriod, offerId);
        // mint the NFT to the supplier
        // @dev does not use _safeMint to avoid reentrancy
        _mint(offer.supplier, escrowId);

        emit OfferUpdated(offerId, offer.supplier, prevOfferAmount, prevOfferAmount - escrowed);
    }

    function _endEscrow(uint escrowId, uint fromLoans) internal returns (uint toLoans) {
        Escrow storage escrow = escrows[escrowId];
        require(!escrow.released, "already released");
        // only allow the same loans contract to release
        require(msg.sender == escrow.loans, "loans address mismatch");

        // storage updates
        escrow.released = true;
        (escrow.withdrawable, toLoans,) = _releaseCalculations(escrow, fromLoans);

        emit EscrowReleased(escrowId, fromLoans, escrow.withdrawable, toLoans);
    }

    // ----- INTERNAL VIEWS ----- //

    function _releaseCalculations(Escrow memory escrow, uint fromLoans)
        internal
        view
        returns (uint withdrawal, uint toLoans, uint interestRefund)
    {
        // handle under-payment (slippage, default) or over-payment (excessive late fees):
        // any shortfall is for the borrower (e.g., slippage) - taken out of the escrow funds held

        // lateFee is non-zero after MIN_GRACE_PERIOD is over (late close loan / seized escrow)
        uint lateFee = _lateFee(escrow);
        // refund due to early release. If late fee is not 0, this is likely 0 (because is after expiry).
        interestRefund = _interestFeeRefund(escrow);

        // everything owed: original escrow + (interest held - interest refund) + late fee
        uint targetWithdrawal = escrow.escrowed + escrow.interestHeld + lateFee - interestRefund;
        // what we have is what we held (escrow + full interest) and whatever loans just sent us
        // @dev note that withdrawal of at least escrow + interest fee is always guaranteed
        uint available = escrow.escrowed + escrow.interestHeld + fromLoans;

        // use as much as possible from available up to target
        withdrawal = Math.min(available, targetWithdrawal);
        // refund the rest if anything is left, this accounts both for interestRefund and any overpayment
        toLoans = available - withdrawal;

        // @dev note 1: interest refund "theoretically" covers some of the late fee shortfall, but
        // "in practice" this will never happen because either late fees are 0 or interest refund is 0.

        // @dev note 2: for (swtichEscrow, fromLoans is 0, and lateFee is 0, so toLoans is just
        // the interest refund

        /* @dev note 3: late fees are calculated, but cannot be "enforced" here, and instead Loans is
        trusted to use the views on this contract to correctly calculate the late fees and grace period
        to ensure they are not underpaid. This contract needs to trust Loans to do so for these reasons:
        1. Loans needs to swap from cash, and has the information needed to calculate the funds available
        for late fees (withdrawal amount, oracle rate, etc).
        2. Loans needs swap parameters, and has a keeper authorisation system for access control.

        So while a seizeEscrow() method in this contract *could* call to Loans, the keeper access control +
        the swap parameters + the reduced-grace-period time (by withdrawal), all make it more sensible to
        be done via Loans directly. The result is that "principal" is always guaranteed by this contract due
        to always remaining in it, but correct late fees payment depends on Loans implementation.
        */
    }

    function _lateFee(Escrow memory escrow) internal view returns (uint) {
        if (block.timestamp < escrow.expiration + MIN_GRACE_PERIOD) {
            // grace period cliff
            return 0;
        }
        uint overdue = block.timestamp - escrow.expiration; // counts from expiration despite the cliff
        // cap at specified grace period
        overdue = Math.min(overdue, escrow.maxGracePeriod);
        // @dev rounds up to prevent avoiding fee using many small positions
        return Math.ceilDiv(escrow.escrowed * escrow.lateFeeAPR * overdue, BIPS_BASE * YEAR);
    }

    function _interestFeeRefund(Escrow memory escrow) internal view returns (uint refund) {
        uint duration = escrow.duration;
        // elapsed = now - startTime; startTime = expiration - duration
        uint elapsed = block.timestamp + duration - escrow.expiration;
        // cap to duration
        elapsed = Math.min(elapsed, duration);
        // refund is for time remaining. round down against user.
        // no div-zero due to range checks in ConfigHub
        refund = escrow.interestHeld * (duration - elapsed) / duration;

        /* @dev there is no APR calculation here (APR calc used only on open) because:
         1. simpler
         2. avoidance of mismatch due to rounding issues
         3. actual fee held may be higher (it's checked to be >= APR calculated fee)
        */
    }

    function _configHubValidations(uint duration) internal view {
        require(configHub.isSupportedUnderlying(address(asset)), "unsupported asset");
        require(configHub.isValidCollarDuration(duration), "unsupported duration");
    }
}
