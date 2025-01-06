// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { BaseNFT, ConfigHub } from "./base/BaseNFT.sol";
import { IEscrowSupplierNFT } from "./interfaces/IEscrowSupplierNFT.sol";

/**
 * @title EscrowSupplierNFT
 * @notice Manages escrows and escrow offers for LoansNFT.
 * @custom:security-contact security@collarprotocol.xyz
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
 *
 * Post-Deployment Configuration:
 * - ConfigHub: Set valid collar duration range
 * - ConfigHub: Set setCanOpenPair() to authorize this contract for its asset
 * - ConfigHub: Set setCanOpenPair() to authorize its loans contracts
 * - This Contract: Set loans that can open escrows
 */
contract EscrowSupplierNFT is IEscrowSupplierNFT, BaseNFT {
    using SafeERC20 for IERC20;

    uint internal constant BIPS_BASE = 10_000;
    uint internal constant YEAR = 365 days;

    uint public constant MAX_INTEREST_APR_BIPS = BIPS_BASE; // 100% APR
    uint public constant MAX_LATE_FEE_APR_BIPS = BIPS_BASE * 12; // 1200% APR (100% for a max period of 30 days)
    uint public constant MIN_GRACE_PERIOD = 1 days;
    uint public constant MAX_GRACE_PERIOD = 30 days;
    // @notice max percentage of refunded interest fee, prevents free cancellation issues
    uint public constant MAX_FEE_REFUND_BIPS = 9500; // 95%

    string public constant VERSION = "0.2.0";

    // ----- IMMUTABLES ----- //
    IERC20 public immutable asset; // corresponds to Loans' underlying

    // ----- STATE ----- //
    // @dev this is NOT the NFT id, this is a  separate non transferrable ID
    uint public nextOfferId = 1; // starts from 1 so that 0 ID is not used

    // loans contracts allowed to start or switch escrows
    mapping(address loans => bool allowed) public loansCanOpen;

    mapping(uint offerId => OfferStored) internal offers;

    mapping(uint escrowId => EscrowStored) internal escrows;

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

    // ----- VIEWS ----- //

    /// @notice Returns the NFT ID of the next escrow to be minted
    function nextEscrowId() external view returns (uint) {
        return nextTokenId;
    }

    /// @notice Retrieves the details of a specific non-transferrable offer.
    function getOffer(uint offerId) public view returns (Offer memory) {
        OfferStored memory stored = offers[offerId];
        return Offer({
            supplier: stored.supplier,
            available: stored.available,
            duration: stored.duration,
            interestAPR: stored.interestAPR,
            gracePeriod: stored.gracePeriod,
            lateFeeAPR: stored.lateFeeAPR,
            minEscrow: stored.minEscrow
        });
    }

    /// @notice Retrieves the details of a specific escrow (corresponds to the NFT token ID)
    function getEscrow(uint escrowId) public view returns (Escrow memory) {
        EscrowStored memory stored = escrows[escrowId];
        // @dev this is checked because expiration is used in several places, and it's better to add
        // this check here instead of in each such place
        require(stored.expiration != 0, "escrow: position does not exist");
        Offer memory offer = getOffer(stored.offerId);
        return Escrow({
            offerId: stored.offerId,
            loans: stored.loans,
            loanId: stored.loanId,
            escrowed: stored.escrowed,
            gracePeriod: offer.gracePeriod,
            lateFeeAPR: offer.lateFeeAPR,
            duration: offer.duration,
            expiration: stored.expiration,
            feesHeld: stored.feesHeld,
            released: stored.released,
            withdrawable: stored.withdrawable
        });
    }

    /**
     * @notice Calculates the upfront interest fee and late fee held for an offer and escrow amount.
     * @param offerId The offer Id to use for calculations
     * @param escrowed The escrowed amount
     * @return total The calculated total fees (interest and late fee)
     * @return interestFee The calculated interest fee to hold
     * @return lateFee The calculated late fee to hold
     */
    function upfrontFees(uint offerId, uint escrowed)
        public
        view
        returns (uint total, uint interestFee, uint lateFee)
    {
        (interestFee, lateFee) = _upfrontFees(offerId, escrowed);
        total = interestFee + lateFee;
    }

    /**
     * @notice Previews the result of releasing an escrow if it is done now using endEscrow (with refund).
     * @param escrowId The ID of the escrow to preview
     * @param fromLoans The amount repaid from loans
     * @return withdrawal The amount to be withdrawn by the supplier
     * @return toLoans The amount to be returned to loans (includes refund)
     * @return feesRefund The refunded interest amount
     */
    function previewRelease(uint escrowId, uint fromLoans)
        external
        view
        returns (uint withdrawal, uint toLoans, uint feesRefund)
    {
        (withdrawal, toLoans, feesRefund) = _releaseCalculations(getEscrow(escrowId), fromLoans);
    }

    // ----- MUTATIVE ----- //

    // ----- Offer actions ----- //

    /**
     * @notice Creates a new escrow offer
     * @param amount The offered amount
     * @param duration The offer duration in seconds
     * @param interestAPR The annual interest rate in basis points
     * @param gracePeriod The maximum grace period duration in seconds
     * @param lateFeeAPR The annual late fee rate in basis points
     * @param minEscrow The minimum escrow amount. Protection from dust mints.
     * @return offerId The ID of the created offer
     */
    function createOffer(
        uint amount,
        uint duration,
        uint interestAPR,
        uint gracePeriod,
        uint lateFeeAPR,
        uint minEscrow
    ) external whenNotPaused returns (uint offerId) {
        // sanity checks
        require(interestAPR <= MAX_INTEREST_APR_BIPS, "escrow: interest APR too high");
        require(lateFeeAPR <= MAX_LATE_FEE_APR_BIPS, "escrow: late fee APR too high");
        require(gracePeriod >= MIN_GRACE_PERIOD, "escrow: grace period too short");
        require(gracePeriod <= MAX_GRACE_PERIOD, "escrow: grace period too long");

        offerId = nextOfferId++;
        offers[offerId] = OfferStored({
            supplier: msg.sender,
            duration: SafeCast.toUint32(duration),
            gracePeriod: SafeCast.toUint32(gracePeriod),
            interestAPR: SafeCast.toUint24(interestAPR),
            lateFeeAPR: SafeCast.toUint24(lateFeeAPR),
            minEscrow: minEscrow,
            available: amount
        });
        asset.safeTransferFrom(msg.sender, address(this), amount);
        emit OfferCreated(
            msg.sender, interestAPR, duration, gracePeriod, lateFeeAPR, amount, offerId, minEscrow
        );
    }

    /**
     * @notice Updates the total available amount of an existing offer. Update to 0 to fully withdraw.
     * @dev Can increase or decrease the offer amount. Must be from original offer supplier
     * @param offerId The ID of the offer to update
     * @param newAmount The new offer amount
     *
     * A "non-zero update frontrunning attack" (similar to the never-exploited ERC-20 approval issue),
     * can be a low likelihood concern on a network that exposes a public mempool.
     * Avoid it by not granting excessive ERC-20 approvals.
     */
    function updateOfferAmount(uint offerId, uint newAmount) external whenNotPaused {
        OfferStored storage offer = offers[offerId];
        require(msg.sender == offer.supplier, "escrow: not offer supplier");

        uint previousAmount = offer.available;
        if (newAmount > previousAmount) {
            // deposit more
            uint toAdd = newAmount - previousAmount;
            offer.available += toAdd;
            asset.safeTransferFrom(msg.sender, address(this), toAdd);
        } else if (newAmount < previousAmount) {
            // withdraw
            uint toRemove = previousAmount - newAmount;
            offer.available -= toRemove;
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
     * @param fees The upfront interest and late fees to hold. Checked to be sufficient.
     *   Will be partially refunded depending on escrow release time.
     * @param loanId The associated loan ID
     * @return escrowId The ID of the created escrow
     */
    function startEscrow(uint offerId, uint escrowed, uint fees, uint loanId)
        external
        whenNotPaused
        returns (uint escrowId)
    {
        // @dev msg.sender auth is checked vs. loansCanOpen in _startEscrow
        escrowId = _startEscrow(offerId, escrowed, fees, loanId);

        // @dev despite the fact that they partially cancel out, so can be done as just fee transfer,
        // these transfers are the whole point of this contract from product point of view.
        // The transfer events for the full amounts are needed such that the tokens used for the swap
        // in Loans should be "supplier's", and not "borrower's" from CGT tax laws perspective.
        // transfer "borrower's" funds in
        asset.safeTransferFrom(msg.sender, address(this), escrowed + fees);
        // transfer "supplier's" funds out
        asset.safeTransfer(msg.sender, escrowed);
    }

    /**
     * @notice Ends an escrow. Returns any refund beyond what's owed back to loans.
     * @dev Can only be called by the Loans contract that started the escrow
     * @param escrowId The ID of the escrow to end
     * @param repaid The amount repaid, can be more or less than original escrow amount, depending on
     * late fees (enforced by the loans contract), or position / slippage / default shortfall. The
     * supplier is guaranteed to withdraw at least the escrow amount + interest fees regardless.
     * @return toLoans Amount to be returned to loans (refund deducing shortfalls)
     */
    function endEscrow(uint escrowId, uint repaid) external whenNotPaused returns (uint toLoans) {
        // @dev msg.sender auth is checked vs. stored loans in _endEscrow
        // shouldRefund is true since this method returns the refund to loans
        toLoans = _endEscrow(escrowId, getEscrow(escrowId), repaid);

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
     * @param newFees The new interest fee amount
     * @param newLoanId The new loan ID
     * @return newEscrowId The ID of the new escrow
     * @return feesRefund The refunded fee amount from the old escrow's upfront interest
     */
    function switchEscrow(uint releaseEscrowId, uint offerId, uint newFees, uint newLoanId)
        external
        whenNotPaused
        returns (uint newEscrowId, uint feesRefund)
    {
        Escrow memory previousEscrow = getEscrow(releaseEscrowId);
        // do not allow expired escrow to be switched since 0 fromLoans is used for _endEscrow
        require(block.timestamp <= previousEscrow.expiration, "escrow: expired");

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
        feesRefund = _endEscrow(releaseEscrowId, previousEscrow, 0);

        // N (new escrow): Mint a new escrow from the offer (can be old or new offer).
        // The escrow funds are funds that have been escrowed in the ID being released ("O").
        // The offer is reduced (which is used to repay the previous supplier)
        // A new escrow ID is minted.
        newEscrowId = _startEscrow(offerId, previousEscrow.escrowed, newFees, newLoanId);

        // fee transfers
        asset.safeTransferFrom(msg.sender, address(this), newFees);
        asset.safeTransfer(msg.sender, feesRefund);

        emit EscrowsSwitched(releaseEscrowId, newEscrowId);
    }

    // ----- actions by escrow owner ----- //

    /// @notice Withdraws funds from a released escrow. Burns the NFT.
    /// @param escrowId The ID of the escrow to withdraw from
    function withdrawReleased(uint escrowId) external whenNotPaused {
        require(msg.sender == ownerOf(escrowId), "escrow: not escrow owner"); // will revert for burned

        Escrow memory escrow = getEscrow(escrowId);
        require(escrow.released, "escrow: not released");

        uint withdrawable = escrow.withdrawable;
        // store zeroed out withdrawable
        escrows[escrowId].withdrawable = 0;
        // burn token
        _burn(escrowId);
        // transfer tokens
        asset.safeTransfer(msg.sender, withdrawable);

        emit WithdrawalFromReleased(escrowId, msg.sender, withdrawable);
    }

    /**
     * @notice Seize escrow funds and any fees held after grace period end. Burns the NFT.
     * @param escrowId The ID of the escrow to seize
     */
    function seizeEscrow(uint escrowId) external whenNotPaused {
        require(msg.sender == ownerOf(escrowId), "escrow: not escrow owner"); // will revert for burned

        Escrow memory escrow = getEscrow(escrowId);
        require(!escrow.released, "escrow: already released");
        uint gracePeriodEnd = escrow.expiration + escrow.gracePeriod;
        require(block.timestamp > gracePeriodEnd, "escrow: grace period not elapsed");

        // update storage
        escrows[escrowId].released = true;

        // burn token because this is a withdrawal and a direct last action by NFT owner
        _burn(escrowId);

        // @dev withdrawal is immediate, so escrow.withdrawable is not set here (no _releaseEscrow call).
        // release escrowed and full interest
        uint withdrawal = escrow.escrowed + escrow.feesHeld;
        asset.safeTransfer(msg.sender, withdrawal);

        emit EscrowSeized(escrowId, msg.sender, withdrawal);
    }

    // ----- admin ----- //

    /// @notice Sets whether a Loans contract is allowed to interact with this contract
    function setLoansCanOpen(address loans, bool allowed) external onlyOwner {
        // @dev no checks for Loans interface since calls are only from Loans to this contract
        loansCanOpen[loans] = allowed;
        emit LoansCanOpenSet(loans, allowed);
    }

    // ----- INTERNAL MUTATIVE ----- //

    function _startEscrow(uint offerId, uint escrowed, uint fees, uint loanId)
        internal
        returns (uint escrowId)
    {
        require(loansCanOpen[msg.sender], "escrow: unauthorized loans contract");
        // @dev loans is not checked since is directly authed in this contract via setLoansAllowed
        require(configHub.canOpenSingle(asset, address(this)), "escrow: unsupported escrow");

        Offer memory offer = getOffer(offerId);
        require(offer.supplier != address(0), "escrow: invalid offer"); // revert here for clarity

        // check params are supported
        require(configHub.isValidCollarDuration(offer.duration), "escrow: unsupported duration");

        (uint expectedFees,,) = upfrontFees(offerId, escrowed);
        // we don't check equality to avoid revert due to minor inaccuracies to the upside,
        // even though exact value should be used from the view.
        // The overpayment is refunded when escrow is properly released (but not when seized).
        require(fees >= expectedFees, "escrow: insufficient upfront fees");

        // check amount
        require(escrowed >= offer.minEscrow, "escrow: amount too low");
        // @dev fee is not taken from offer, because it is transferred in from loans
        uint prevOfferAmount = offer.available;
        require(escrowed <= prevOfferAmount, "escrow: amount too high");

        // storage updates
        offers[offerId].available -= escrowed;
        escrowId = nextTokenId++;
        escrows[escrowId] = EscrowStored({
            offerId: SafeCast.toUint64(offerId),
            loanId: SafeCast.toUint64(loanId),
            expiration: SafeCast.toUint32(block.timestamp + offer.duration),
            released: false, // unset until release
            loans: msg.sender,
            escrowed: escrowed,
            feesHeld: fees,
            withdrawable: 0 // unset until release
         });

        // emit before token transfer event in mint for easier indexing
        emit EscrowCreated(escrowId, escrowed, fees, offerId);
        // mint the NFT to the supplier
        // @dev does not use _safeMint to avoid reentrancy
        _mint(offer.supplier, escrowId);

        emit OfferUpdated(offerId, offer.supplier, prevOfferAmount, prevOfferAmount - escrowed);
    }

    function _endEscrow(uint escrowId, Escrow memory escrow, uint fromLoans)
        internal
        returns (uint toLoans)
    {
        // @dev only allow the same loans contract to release. Also ensures this is previously allowed Loans.
        require(msg.sender == escrow.loans, "escrow: loans address mismatch");
        require(!escrow.released, "escrow: already released");

        uint withdrawable;
        (withdrawable, toLoans,) = _releaseCalculations(escrow, fromLoans);

        // storage updates
        escrows[escrowId].released = true;
        escrows[escrowId].withdrawable = withdrawable;

        emit EscrowReleased(escrowId, fromLoans, withdrawable, toLoans);
    }

    // ----- INTERNAL VIEWS ----- //

    function _releaseCalculations(Escrow memory escrow, uint fromLoans)
        internal
        view
        returns (uint withdrawal, uint toLoans, uint feesRefund)
    {
        // What we have available is what we held (escrow + upfront fees) and fromLoans.
        // FromLoans should be escrow principal only, such that the escrow amounts are
        // "exchanged" again, and any shortfall reduces the toLoans return amount.
        // @dev note that withdrawal of all escrow and fees (interest + late fee) is guaranteed
        uint available = escrow.escrowed + escrow.feesHeld + fromLoans;

        feesRefund = _feesRefund(escrow);

        // this handles under-payment (slippage, default) or over-payment (excessive late fees):
        // any shortfall is for the borrower (e.g., slippage) - taken out of the escrow funds held
        uint targetWithdrawal = escrow.escrowed + escrow.feesHeld - feesRefund;

        // use as much as possible from available up to target
        withdrawal = Math.min(available, targetWithdrawal);
        // refund the rest if anything is left: returned supplier's funds, interestRefund, overpayment.
        toLoans = available - withdrawal;

        // @dev for swtichEscrow, fromLoans is 0, and lateFee is 0, so toLoans is just the interest refund
    }

    function _upfrontFees(uint offerId, uint escrowed)
        internal
        view
        returns (uint interestFee, uint lateFee)
    {
        Offer memory offer = getOffer(offerId);
        // rounds up against the user
        interestFee = Math.ceilDiv(escrowed * offer.interestAPR * offer.duration, BIPS_BASE * YEAR);
        lateFee = Math.ceilDiv(escrowed * offer.lateFeeAPR * offer.gracePeriod, BIPS_BASE * YEAR);
    }

    function _feesRefund(Escrow memory escrow) internal view returns (uint) {
        // check how much was held for interest and late fees
        (uint interestHeld, uint lateFeeHeld) = _upfrontFees(escrow.offerId, escrow.escrowed);

        // refund any initial voluntary overpayment of fees. This cannot revert because
        // fee is checked vs. this sum on escrow start.
        uint overpaymentRefund = escrow.feesHeld - interestHeld - lateFeeHeld;
        uint interestRefund = _interestRefund(escrow, interestHeld);
        uint lateFeeRefund = _lateFeeRefund(escrow, lateFeeHeld);
        return interestRefund + lateFeeRefund + overpaymentRefund;
    }

    function _lateFeeRefund(Escrow memory escrow, uint lateFeeHeld) internal view returns (uint) {
        uint overdue = 0;
        // MIN_GRACE_PERIOD is grace period cliff, before which the full late fee is refunded
        if (block.timestamp > escrow.expiration + MIN_GRACE_PERIOD) {
            overdue = block.timestamp - escrow.expiration; // counts from expiration despite the cliff
            // cap at specified grace period
            overdue = Math.min(overdue, escrow.gracePeriod);
        }
        // round down against borrower
        return lateFeeHeld * (escrow.gracePeriod - overdue) / escrow.gracePeriod;
    }

    function _interestRefund(Escrow memory escrow, uint interestHeld) internal view returns (uint) {
        uint duration = escrow.duration;
        // elapsed = now - startTime; startTime = expiration - duration
        uint elapsed = block.timestamp + duration - escrow.expiration;
        // cap to duration
        elapsed = Math.min(elapsed, duration);
        // refund is for time remaining. round down against user.
        // no div-zero due to range checks in ConfigHub
        uint refund = interestHeld * (duration - elapsed) / duration;

        // ensure refund is not full, to prevent free cancellation (griefing, DoS)
        uint maxRefund = interestHeld * MAX_FEE_REFUND_BIPS / BIPS_BASE;
        return Math.min(refund, maxRefund);
    }
}
