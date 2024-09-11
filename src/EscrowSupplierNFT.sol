// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity 0.8.22;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
// internal
import { ConfigHub } from "./ConfigHub.sol";
import { BaseEmergencyAdminNFT } from "./base/BaseEmergencyAdminNFT.sol";
import { IEscrowSupplierNFT } from "./interfaces/IEscrowSupplierNFT.sol";

contract EscrowSupplierNFT is IEscrowSupplierNFT, BaseEmergencyAdminNFT {
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
    uint public nextOfferId; // @dev this is NOT the NFT id, this is a  separate non transferrable ID

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
    ) BaseEmergencyAdminNFT(initialOwner, _name, _symbol) {
        asset = _asset;
        _setConfigHub(_configHub);
    }

    modifier onlyLoans() {
        require(allowedLoans[msg.sender], "unauthorized loans contract");
        _;
    }

    // ----- VIEWS ----- //

    function nextEscrowId() external view returns (uint) {
        return nextTokenId;
    }

    function getEscrow(uint escrowId) external view returns (Escrow memory) {
        return escrows[escrowId];
    }

    function getOffer(uint offerId) external view returns (Offer memory) {
        return offers[offerId];
    }

    function lateFees(uint escrowId) external view returns (uint fee, uint escrowed) {
        Escrow storage escrow = escrows[escrowId];
        escrowed = escrow.escrowed;
        if (block.timestamp < escrow.expiration + MIN_GRACE_PERIOD) {
            // grace period cliff
            fee = 0;
        } else {
            uint overdue = block.timestamp - escrow.expiration; // counts from expiration despite the cliff
            // cap at specified grace period
            overdue = _min(overdue, escrow.gracePeriod);
            // @dev rounds up to prevent avoiding fee using many small positions
            fee = _divUp(escrowed * escrow.lateFeeAPR * overdue, BIPS_BASE * 365 days);
        }
    }

    function gracePeriodFromFees(uint escrowId, uint feeAmount) external view returns (uint gracePeriod) {
        Escrow storage escrow = escrows[escrowId];
        // set to max
        gracePeriod = escrow.gracePeriod;
        if (escrow.escrowed != 0 && escrow.lateFeeAPR != 0) {
            // avoid div-zero
            // Calculate the grace period at which the fee will be higher than what's available.
            // Otherwise, late fees will be underpaid.
            // fee = escrowed * time * APR / year / 100bips;
            // time = fee * year * 100bips / escrowed / APR;
            uint valueToTime = feeAmount * 365 days * BIPS_BASE / escrow.escrowed / escrow.lateFeeAPR;
            // reduce from max to valueToTime (what can be paid for using that feeAmount)
            gracePeriod = _min(valueToTime, gracePeriod);
        }
        // increase to min if below it (for consistency with late fee being 0 during that period)
        // @dev this means that even if no funds are available, min grace period is available
        gracePeriod = _max(gracePeriod, MIN_GRACE_PERIOD);
    }

    function interestFee(uint escrowed, uint duration, uint feeAPR) public pure returns (uint fee) {
        return _divUp(escrowed * feeAPR * duration, BIPS_BASE * 365 days);
    }

    // @dev assumes release is done now
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

    function endEscrow(uint escrowId, uint repaid) external whenNotPaused onlyLoans returns (uint toLoans) {
        toLoans = _releaseEscrow(escrowId, repaid);

        // transfer in the repaid assets in: original supplier's assets, plus any late fee
        asset.safeTransferFrom(msg.sender, address(this), repaid);
        // release the escrow (with possible loss to the borrower): user's assets + refund - shortfall
        asset.safeTransfer(msg.sender, toLoans);
    }

    // @dev duration can be different (since doesn't is not problematic within this contract,
    // but Loans (the only caller), should check that new duration / expiration is as expected
    function switchEscrow(uint releaseEscrowId, uint offerId, uint newLoanId, uint newFee)
        external
        whenNotPaused
        onlyLoans
        returns (uint newEscrowId, Escrow memory newEscrow, uint feeRefund)
    {
        uint escrowAmount = escrows[releaseEscrowId].escrowed;

        /*
        1. initially user's escrow E secures O (old ID). O's own funds are away.
        2. E is then "transferred" to secure N (new ID). N's own funds are taken, to release O.
        3. O is released (with N's funds, which are now secured by E (user's escrow).

        Interest is accounted separately by transferring the full N's interest fee
        (held until release), and refunding O's interest held if O is released early (it likely is).
        */

        // N (new escrow): Mint a new escrow from the offer.
        // The escrow funds are the loan-escrow funds that have been escrowed in the ID being released.
        // The offer is reduced (which is used to repay the previous supplier)
        // A new escrow ID is minted.
        (newEscrowId, newEscrow) = _mintFromOffer(offerId, escrowAmount, newFee, newLoanId);

        // O (old escrow): Release funds to the supplier of previous ID.
        // The withdrawable for previous supplier comes from the N's offer, not from Loans repayment.
        // The escrowed loans-funds (E) move into the new escrow of the new supplier.
        // fromLoans must be 0, otherwise escrow will be sent to Loans instead of only the fee refund
        feeRefund = _releaseEscrow(releaseEscrowId, 0);

        // fee transfers
        asset.safeTransferFrom(msg.sender, address(this), newFee);
        asset.safeTransfer(msg.sender, feeRefund);

        emit EscrowsSwitched(releaseEscrowId, newEscrowId);
    }

    // ----- actions by escrow owner ----- //

    function withdrawReleased(uint escrowId) external whenNotPaused {
        require(msg.sender == ownerOf(escrowId), "not escrow owner");

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
     * @notice DO NOT use this is normal circumstances, use seizeEscrow on Loans. This method is only
     * for extreme scenarios to ensure suppliers can always withdraw even if Loans is broken / no Loans
     * contracts are allowed by admin.
     * This method can only be used after the full grace period is elapsed, and does not pay any late fees.
     * Ideally the owner of the NFT will call seizeEscrow() on Loans - which is either callable earlier
     * or pays late fees (or both). If they do, that method will call endEscrow and will set "released"
     * to true, making this method not callable.
     * In the opposite situation, if the NFT owner chooses to call this method by mistake instead,
     * the Loans method will not be callable, because released will be set to true (+NFT will be burned).
     */
    function lastResortSeizeEscrow(uint escrowId) external whenNotPaused {
        require(msg.sender == ownerOf(escrowId), "not escrow owner");

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

    function setLoansAllowed(address loans, bool allowed) external onlyOwner {
        // @dev no sanity check for Loans interface since it is not relied on and calls are made
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

        // check params are still supported
        _configHubValidations(offer.duration);

        // check amount
        // @dev fee is not taken from offer, because it is transferred in from escrow taker
        uint prevOfferAmount = offer.available;
        require(escrowed <= prevOfferAmount, "amount too high");

        uint minFee = interestFee(escrowed, offer.duration, offer.interestAPR);
        // we don't check equality to avoid revert due to minor precision inaccuracy to the upside,
        // even though exact value can be calculated from the view.
        // TODO: is this needed, or exact equality is better?
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
        // interest refund due to early release
        uint interestRefund = _refundInterestFee(escrow);

        // total released to supplier with refund deducted from the held interest.
        // max(): any gains are for the supplier (late fees), so supplier is guaranteed
        // note that either late fees are charged, or interest fee is refunded, but not both
        withdrawal = _max(fromLoans, escrow.escrowed) + escrow.interestHeld - interestRefund;

        // min(): any losses are for the borrower (e.g., slippage), taken out of their escrowed amount.
        // any refund still goes to loans regardless of repayment because was paid unfront for interest.
        toLoans = _min(fromLoans, escrow.escrowed) + interestRefund;

        /*
        @dev late fees are not enforced here, and instead Loans is trusted to use the views on this contract
        to correctly calculate the late fees and grace period to ensure they are not underpaid.
        This contract needs to trust Loans to do so for these reasons:
        1. Loans needs to swap from cash, and has the information needed to calculate the funds available
        for late fees (withdrawal amount, oracle rate, etc).
        2. Loans needs swap parameters, and has a keeper authorisation system for access control.

        So while a seizeEscrow() method in this contract *could* call to Loans, the keeper access control +
        the swap parameters + the reduced-grace-period time (by withdrawal), all make it more sensible to
        be done via Loans directly.
        */
    }

    function _refundInterestFee(Escrow storage escrow) internal view returns (uint refund) {
        uint duration = escrow.duration;
        // startTime = expiration - duration, elapsed = now - startTime
        uint elapsed = block.timestamp + duration - escrow.expiration;
        // cap to duration
        elapsed = _min(elapsed, duration);
        // refund is for time remaining, and is rounded down
        refund = escrow.interestHeld * (duration - elapsed) / duration;
        /* @dev there is no APR calculation here (APR calc used only on open), only time calculation because:
         1. simpler
         2. avoidance of mismatch due to rounding issues
         3. actual fee passed may be higher (it's checked to be above the minimal fee)
        */
    }

    function _configHubValidations(uint duration) internal view {
        // assets
        require(configHub.isSupportedCollateralAsset(address(asset)), "unsupported asset");
        // terms
        require(configHub.isValidCollarDuration(duration), "unsupported duration");
    }

    function _divUp(uint x, uint y) internal pure returns (uint) {
        return (x == 0) ? 0 : ((x - 1) / y) + 1; // divUp(x,y) = (x-1 / y) + 1
    }

    function _max(uint a, uint b) internal pure returns (uint) {
        return a > b ? a : b;
    }

    function _min(uint a, uint b) internal pure returns (uint) {
        return a < b ? a : b;
    }
}
