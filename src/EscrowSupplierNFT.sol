// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity 0.8.22;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
// internal
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
 * Role in the Protocol:
 * This contract acts as the interface for escrow suppliers to LoansNFT in the Collar Protocol.
 * It works in tandem with corresponding LoansNFT contracts, which are trusted by this contract
 * to manage the borrower side of escrow positions and enforce late fees.
 *
 * Key Assumptions and Prerequisites:
 * 1. Escrow suppliers must be able to receive ERC-721 tokens to withdraw offers or earnings.
 * 2. The associated Loans contracts are trusted and properly implemented.
 * 3. The ConfigHub contract correctly manages protocol parameters and authorization.
 * 4. Asset (ERC-20) contracts are simple (non rebasing) and do not allow reentrancy.
 *
 * Design Considerations:
 * 1. Uses NFTs to represent escrow positions, allowing for secondary market usage.
 * 2. Implements pausability and asset recovery for emergency situations via BaseEmergencyAdminNFT.
 * 3. Provides a last resort seizure mechanism for extreme scenarios.
 */
contract EscrowSupplierNFT is IEscrowSupplierNFT, BaseNFT {
    using SafeERC20 for IERC20;

    uint internal constant BIPS_BASE = 10_000;
    uint public constant MAX_INTEREST_APR_BIPS = BIPS_BASE; // 100% APR
    uint public constant MIN_GRACE_PERIOD = 1 days;
    uint public constant MAX_GRACE_PERIOD = 30 days;
    uint public constant MAX_LATE_FEE_APR_BIPS = BIPS_BASE * 12; // 1200% APR (100% for a max period of 30 days)

    string public constant VERSION = "0.2.0";

    // ----- IMMUTABLES ----- //
    IERC20 public immutable asset;

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

    /// @notice Retrieves the details of a specific escrow (corresponds to the NFT token ID)
    /// @dev This is used instead of the default getter because the default getter returns a tuple
    function getEscrow(uint escrowId) external view returns (Escrow memory) {
        return escrows[escrowId];
    }

    /// @notice Retrieves the details of a specific non-transferrable offer.
    /// @dev This is used instead of the default getter because the default getter returns a tuple
    function getOffer(uint offerId) external view returns (Offer memory) {
        return offers[offerId];
    }

    /**
     * @notice Calculates the late fees for an escrow with a min-grace-period "cliff": Overdue
     * time is counted from expiry, but during the min-grace-period late fees are
     * returned as 0 (even though are "accumulating").
     * @param escrowId The ID of the escrow to calculate late fees for
     * @return fee The calculated late fee
     * @return escrowed The original escrowed amount
     */
    function lateFees(uint escrowId) external view returns (uint fee, uint escrowed) {
        Escrow storage escrow = escrows[escrowId];
        return (_lateFee(escrow), escrow.escrowed);
    }

    /**
     * @notice Calculates the grace period based on available late fee amount. This is the grace period
     * a lateFee "can afford" before causing an shortfall of late fees. This view should be used to
     * enforce a reduced gracePeriod in case funds are insufficient for the full grace period.
     * Grace period returned is between min-grace-period and the offer's terms.
     * @param escrowId The ID of the escrow to calculate for
     * @param lateFee The available fee amount
     * @return gracePeriod The calculated grace period in seconds
     */
    function cappedGracePeriod(uint escrowId, uint lateFee) external view returns (uint gracePeriod) {
        Escrow storage escrow = escrows[escrowId];
        // set to max
        gracePeriod = escrow.gracePeriod;
        if (escrow.escrowed != 0 && escrow.lateFeeAPR != 0) {
            // avoid div-zero
            // Calculate the grace period at which the fee will be higher than what's available.
            // Otherwise, late fees will be underpaid.
            // fee = escrowed * time * APR / year / 100bips;
            // time = fee * year * 100bips / escrowed / APR;
            // rounding down, against the user
            uint valueToTime = lateFee * 365 days * BIPS_BASE / escrow.escrowed / escrow.lateFeeAPR;
            // reduce from max to valueToTime (what can be paid for using that feeAmount)
            gracePeriod = Math.min(valueToTime, gracePeriod);
        }
        // increase to min if below it (for consistency with late fee being 0 during that period)
        // @dev this means that even if no funds are available, min grace period is available
        gracePeriod = Math.max(gracePeriod, MIN_GRACE_PERIOD);
    }

    /**
     * @notice Calculates the interest fee for given parameters. Rounds up.
     * @param offerId The offer Id to use for calculations
     * @param escrowed The escrowed amount
     * @return fee The calculated interest fee
     */
    function interestFee(uint offerId, uint escrowed) public view returns (uint fee) {
        Offer storage offer = offers[offerId];
        return Math.ceilDiv(escrowed * offer.interestAPR * offer.duration, BIPS_BASE * 365 days);
    }

    /**
     * @notice Previews the result of releasing an escrow if it is done in this block (time affects
     * interest refund calculations).
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
        refund = _refundInterestFee(escrows[escrowId]);
        (withdrawal, toLoans) = _releaseCalculations(escrows[escrowId], fromLoans);
    }

    // ----- MUTATIVE ----- //

    // ----- Offer actions ----- //

    /**
     * @notice Creates a new escrow offer
     * @param amount The offered amount
     * @param duration The offer duration in seconds
     * @param interestAPR The annual interest rate in basis points
     * @param gracePeriod The grace period duration in seconds
     * @param lateFeeAPR The annual late fee rate in basis points
     * @return offerId The ID of the created offer
     */
    function createOffer(uint amount, uint duration, uint interestAPR, uint gracePeriod, uint lateFeeAPR)
        external
        whenNotPaused
        returns (uint offerId)
    {
        // sanity checks
        require(interestAPR <= MAX_INTEREST_APR_BIPS, "interest APR too high");
        require(gracePeriod >= MIN_GRACE_PERIOD, "grace period too short");
        require(gracePeriod <= MAX_GRACE_PERIOD, "grace period too long");
        require(lateFeeAPR <= MAX_LATE_FEE_APR_BIPS, "late fee APR too high");
        // config hub allows values
        _configHubValidations(duration);

        offerId = nextOfferId++;
        offers[offerId] = Offer({
            supplier: msg.sender,
            available: amount,
            duration: duration,
            interestAPR: interestAPR,
            gracePeriod: gracePeriod,
            lateFeeAPR: lateFeeAPR
        });
        asset.safeTransferFrom(msg.sender, address(this), amount);
        emit OfferCreated(msg.sender, interestAPR, duration, gracePeriod, lateFeeAPR, amount, offerId);
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
     * @dev Can only be called by allowed Loans contracts
     * @param offerId The ID of the offer to use
     * @param escrowed The amount to escrow
     * @param fee The upfront interest fee amount. May be refunded pro-rata if
     * released before expiration.
     * @param loanId The associated loan ID
     * @return escrowId The ID of the created escrow
     * @return escrow The Escrow struct of the created escrow
     */
    function startEscrow(uint offerId, uint escrowed, uint fee, uint loanId)
        external
        whenNotPaused
        onlyLoans
        returns (uint escrowId, Escrow memory escrow)
    {
        (escrowId, escrow) = _mintFromOffer(offerId, escrowed, fee, loanId);

        // @dev despite the fact that they partially cancel out, so can be done as just fee transfer,
        // these transfers are the whole point of this contract from product point of view.
        // The transfer events for the full amounts are needed.
        asset.safeTransferFrom(msg.sender, address(this), escrowed + fee);
        // transfer the supplier's funds, equal to the escrowed amount, to loans.
        // @dev this is less than amount because of the interest fee held
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
        toLoans = _releaseEscrow(escrowId, repaid);

        // transfer in the repaid assets in: original supplier's assets, plus any late fee
        asset.safeTransferFrom(msg.sender, address(this), repaid);
        // release the escrow (with possible loss to the borrower): user's assets + refund - shortfall
        asset.safeTransfer(msg.sender, toLoans);
    }

    /**
     * @notice Switches an escrow to a new escrow.
     * @dev While it is basically startEscrow + endEscrow, calling these methods externally
     * is not possible because startEscrow pulls the escrow amount in and transfers it out,
     * which is not possible when switching escrows (the loans contract has no collateral for
     * such a transfer at that point). So instead this method is needed to "move" funds internally.
     * @dev Can only be called by the Loans contract that started the original escrow
     * @dev durations can be different (is not problematic within this contract),
     * but Loans - the only caller of this - should check the new offer duration / new escrow
     * expiration is as is needed for its use.
     * @param releaseEscrowId The ID of the escrow to release
     * @param offerId The ID of the new offer
     * @param newLoanId The new loan ID
     * @param newFee The new interest fee amount
     * @return newEscrowId The ID of the new escrow
     * @return newEscrow The Escrow data struct of the new escrow
     * @return feeRefund The refunded fee amount from the old escrow's upfront interest
     */
    function switchEscrow(uint releaseEscrowId, uint offerId, uint newLoanId, uint newFee)
        external
        whenNotPaused
        onlyLoans
        returns (uint newEscrowId, Escrow memory newEscrow, uint feeRefund)
    {
        /*
        1. initially user's escrow E secures O (old ID). O's own funds are away.
        2. E is then "transferred" to secure N (new ID). N's own funds are taken, to release O.
        3. O is released (with N's funds, which are now secured by E (user's escrow).

        Interest is accounted separately by transferring the full N's interest fee
        (held until release), and refunding O's interest held if O is released early (it likely is).
        */

        // O (old escrow): Release funds to the supplier of previous ID.
        // The withdrawable for previous supplier comes from the N's offer, not from Loans repayment.
        // The escrowed loans-funds (E) move into the new escrow of the new supplier.
        // fromLoans must be 0, otherwise escrow will be sent to Loans instead of only the fee refund
        uint newEscrowAmount = escrows[releaseEscrowId].escrowed;
        feeRefund = _releaseEscrow(releaseEscrowId, 0);

        // N (new escrow): Mint a new escrow from the offer.
        // The escrow funds are the loan-escrow funds that have been escrowed in the ID being released.
        // The offer is reduced (which is used to repay the previous supplier)
        // A new escrow ID is minted.
        (newEscrowId, newEscrow) = _mintFromOffer(offerId, newEscrowAmount, newFee, newLoanId);

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
     * This method can only be used after the full grace period is elapsed, and does not pay any late fees.
     * @dev Ideally the owner of the NFT will call LoansNFT.forecloseLoan() which is callable earlier
     * or pays late fees (or both). If they do that, "released" will be set to true, disabling this method.
     * In the opposite situation, if the NFT owner chooses to call this method by mistake,
     * the LoansNFT method will not be callable, because "released" will true (+NFT will be burned).
     * @dev Only for use when Loans contracts are unavailable to handle release / seizure
     * @param escrowId The ID of the escrow to seize
     */
    function lastResortSeizeEscrow(uint escrowId) external whenNotPaused {
        require(msg.sender == ownerOf(escrowId), "not escrow owner"); // will revert for burned

        Escrow storage escrow = escrows[escrowId];
        require(!escrow.released, "already released");
        require(block.timestamp > escrow.expiration + escrow.gracePeriod, "grace period not elapsed");
        escrow.released = true;
        // @dev escrow.withdrawable is not set here (_releaseEscrow not called): withdrawal is immediate
        uint withdawal = escrow.escrowed + escrow.interestHeld; // escrowed and full interest

        // burn token
        // @dev we burn the NFT because this is a withdrawal and a direct last action by NFT owner
        _burn(escrowId);
        asset.safeTransfer(msg.sender, withdawal);
        emit EscrowSeizedLastResort(escrowId, msg.sender, withdawal);
    }

    // ----- admin ----- //

    /// @notice Sets whether a Loans contract is allowed to interact with this contract
    function setLoansAllowed(address loans, bool allowed) external onlyOwner {
        // @dev no sanity check for Loans interface since it is not relied on: calls are made
        // from Loans to this contract
        allowedLoans[loans] = allowed;
        emit LoansAllowedSet(loans, allowed);
    }

    // ----- INTERNAL MUTATIVE ----- //

    function _mintFromOffer(uint offerId, uint escrowed, uint fee, uint loanId)
        internal
        returns (uint escrowId, Escrow memory escrow)
    {
        require(configHub.canOpen(msg.sender), "unsupported loans contract");
        require(configHub.canOpen(address(this)), "unsupported supplier contract");

        Offer storage offer = offers[offerId];
        require(offer.supplier != address(0), "invalid offer"); // revert here for clarity

        // check params are still supported
        _configHubValidations(offer.duration);

        // check amount
        // @dev fee is not taken from offer, because it is transferred in from escrow taker
        uint prevOfferAmount = offer.available;
        require(escrowed <= prevOfferAmount, "amount too high");

        uint minFee = interestFee(offerId, escrowed);
        // we don't check equality to avoid revert due to minor precision inaccuracy to the upside,
        // even though exact value can be calculated from the view.
        require(fee >= minFee, "insufficient fee");

        // storage updates
        offer.available = prevOfferAmount - escrowed;
        escrowId = nextTokenId++;
        escrow = Escrow({
            loans: msg.sender,
            loanId: loanId,
            escrowed: escrowed,
            gracePeriod: offer.gracePeriod,
            lateFeeAPR: offer.lateFeeAPR,
            duration: offer.duration,
            expiration: block.timestamp + offer.duration,
            interestHeld: fee,
            released: false,
            withdrawable: 0
        });
        escrows[escrowId] = escrow;

        // emit before token transfer event in mint for easier indexing
        emit EscrowCreated(escrowId, escrowed, offer.duration, fee, offer.gracePeriod, offerId);
        // mint the NFT to the supplier
        // @dev does not use _safeMint to avoid reentrancy
        _mint(offer.supplier, escrowId);

        emit OfferUpdated(offerId, offer.supplier, prevOfferAmount, offer.available);
    }

    function _releaseEscrow(uint escrowId, uint fromLoans) internal returns (uint toLoans) {
        Escrow storage escrow = escrows[escrowId];
        require(!escrow.released, "already released");
        // only allow the same loans contract to release
        require(msg.sender == escrow.loans, "loans address mismatch");
        // update storage
        escrow.released = true;

        // calculate and store withdrawal and refund
        (escrow.withdrawable, toLoans) = _releaseCalculations(escrow, fromLoans);

        emit EscrowReleased(escrowId, fromLoans, escrow.withdrawable, toLoans);
    }

    // ----- INTERNAL VIEWS ----- //

    function _releaseCalculations(Escrow storage escrow, uint fromLoans)
        internal
        view
        returns (uint withdrawal, uint toLoans)
    {
        // handle under-payment (slippage, default) or over-payment (excessive late fees):
        // any shortfall are for the borrower (e.g., slippage) - taken out of the funds held

        // lateFee is non-zero after min-grace-period is over (late close loan / seized escrow)
        uint lateFee = _lateFee(escrow);
        // refund due to early release. If late fee is not 0, this is likely 0 (because is after expiry).
        uint interestRefund = _refundInterestFee(escrow);

        // everything owed: original escrow + (interest held - interest refund) + late fee
        uint targetWithdrawal = escrow.escrowed + escrow.interestHeld + lateFee - interestRefund;
        // what we have is what we held (escrow + full interest) and whatever loans just sent us
        // @dev note that withdrawal of at least escrow is guaranteed (due to being held in this contract)
        uint available = escrow.escrowed + escrow.interestHeld + fromLoans;

        // use as much as possible from available up to target
        withdrawal = Math.min(available, targetWithdrawal);
        // refund the rest if anything is left
        toLoans = available - withdrawal;

        // @dev note 1: that interest refund "theoretically" covers some of the late fee shortfall, but
        // "in practice" this will never happen because either late fees are 0 or interest refund is 0.
        // @dev note 2: if fromLoans is 0, and lateFee is 0 (roll case), toLoans is just the interest refund

        /* @dev late fees are calculated, but cannot be "enforced" here, and instead Loans is trusted to use
        the views on this contract to correctly calculate the late fees and grace period to ensure they are
        not underpaid. This contract needs to trust Loans to do so for these reasons:
        1. Loans needs to swap from cash, and has the information needed to calculate the funds available
        for late fees (withdrawal amount, oracle rate, etc).
        2. Loans needs swap parameters, and has a keeper authorisation system for access control.

        So while a seizeEscrow() method in this contract *could* call to Loans, the keeper access control +
        the swap parameters + the reduced-grace-period time (by withdrawal), all make it more sensible to
        be done via Loans directly.
        */
    }

    function _lateFee(Escrow storage escrow) internal view returns (uint) {
        if (block.timestamp < escrow.expiration + MIN_GRACE_PERIOD) {
            // grace period cliff
            return 0;
        }
        uint overdue = block.timestamp - escrow.expiration; // counts from expiration despite the cliff
        // cap at specified grace period
        overdue = Math.min(overdue, escrow.gracePeriod);
        // @dev rounds up to prevent avoiding fee using many small positions
        return Math.ceilDiv(escrow.escrowed * escrow.lateFeeAPR * overdue, BIPS_BASE * 365 days);
    }

    function _refundInterestFee(Escrow storage escrow) internal view returns (uint refund) {
        uint duration = escrow.duration;
        // startTime = expiration - duration, elapsed = now - startTime
        uint elapsed = block.timestamp + duration - escrow.expiration;
        // cap to duration
        elapsed = Math.min(elapsed, duration);
        // refund is for time remaining, and is rounded down
        refund = escrow.interestHeld * (duration - elapsed) / duration; // no div-zero due to min-duration

        /* @dev there is no APR calculation here (APR calc used only on open), only time calculation because:
         1. simpler
         2. avoidance of mismatch due to rounding issues
         3. actual fee passed may be higher (it's checked to be above the minimal fee)
        */
    }

    function _configHubValidations(uint duration) internal view {
        require(configHub.isSupportedCollateralAsset(address(asset)), "unsupported asset");
        require(configHub.isValidCollarDuration(duration), "unsupported duration");
    }
}
