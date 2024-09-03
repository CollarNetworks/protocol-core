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

contract EscrowedSupplierNFT is BaseEmergencyAdminNFT {
    using SafeERC20 for IERC20;

    uint internal constant BIPS_BASE = 10_000;
    uint public constant MIN_GRACE_PERIOD = 1 days;
    uint public constant MAX_GRACE_PERIOD = 30 days;
    uint public constant MAX_LATE_FEE_APR_BIPS = BIPS_BASE * 12; // 1200% APR (100% for a max period of 30 days)

    string public constant VERSION = "0.2.0";

    // ----- IMMUTABLES ----- //
    IERC20 public immutable asset;
    address public immutable loans;

    // ----- STATE ----- //
    uint public nextOfferId; // @dev this is NOT the NFT id, this is a  separate non transferrable ID

    struct Offer {
        address supplier;
        uint available;
        // terms
        uint duration;
        uint gracePeriod;
        uint lateFeeAPR;
    }

    mapping(uint offerId => Offer) internal offers;

    struct Escrow {
        // reference (for views)
        uint loanId;
        uint expiration;
        // terms
        uint escrowed;
        uint gracePeriod;
        uint lateFeeAPR;
        // withdrawal
        bool released;
        uint withdrawable;
    }

    mapping(uint escrowId => Escrow) internal escrows;

    constructor(
        address initialOwner,
        ConfigHub _configHub,
        IERC20 _asset,
        address _loans,
        string memory _name,
        string memory _symbol
    ) BaseEmergencyAdminNFT(initialOwner, _name, _symbol) {
        asset = _asset;
        loans = _loans;
        _setConfigHub(_configHub);
    }

    modifier onlyLoans() {
        require(msg.sender == loans, "unauthorized loans contract");
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
            uint overdue = block.timestamp - expiration; // counts from expiration despite the cliff
            // cap at specified grace period
            uint overdue = overdue > escrow.gracePeriod ? escrow.gracePeriod : overdue;
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
            gracePeriod = valueToTime < gracePeriod ? valueToTime : gracePeriod;
            // increase to min if below it (for consistency with late fee being 0 during that period)
            // @dev this means that even if no funds are available, min grace period is available
            gracePeriod = gracePeriod < MIN_GRACE_PERIOD ? MIN_GRACE_PERIOD : gracePeriod;
        }
    }

    // ----- MUTATIVE ----- //

    // ----- Offer actions ----- //

    function createOffer(uint amount, uint duration, uint gracePeriod, uint lateFeeAPR)
        external
        whenNotPaused
        returns (uint offerId)
    {
        // sanity checks
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
            gracePeriod: gracePeriod,
            lateFeeAPR: lateFeeAPR
        });
        asset.safeTransferFrom(msg.sender, address(this), amount);
        // TODO: event
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
            // TODO: event
    }

    // ----- Escrow actions ----- //

    // ----- actions through taker contract ----- //

    function escrowAndMint(uint offerId, uint amount, uint loanId)
        external
        whenNotPaused
        onlyLoans
        returns (uint escrowId, Escrow memory escrow)
    {
        (escrowId, escrow) = _mintFromOffer(offerId, amount, loanId);

        // @dev despite the fact that they cancel out, these transfers are the whole point of this contract
        // from product point of view. The end balance is the same, but the transfer events are needed.
        // take the escrow from loans
        asset.safeTransferFrom(loans, address(this), amount);
        // transfer the supplier's collateral to loans
        asset.safeTransfer(loans, amount);

        // TODO: event for offer update
    }

    function releaseEscrow(uint escrowId, uint repaid)
        external
        whenNotPaused
        onlyLoans
        returns (uint toLoans)
    {
        toLoans = _releaseEscrow(escrowId, repaid);

        // transfer in the repaid assets in - "original supplier's assets, plus any late fee"
        asset.safeTransferFrom(loans, address(this), repaid);
        // release the escrow (with possible loss to the borrower) - "user's assets, minus any shortfall"
        asset.safeTransfer(loans, toLoans);

        // TODO: event
    }

    function releaseAndMint(uint releaseEscrowId, uint offerId, uint newLoanId)
        external
        whenNotPaused
        onlyLoans
        returns (uint newEscrowId, Escrow memory newEscrow)
    {
        uint escrowAmount = escrows[releaseEscrowId].escrowed;

        // Mint a new escrow from the offer.
        // The escrow funds are the loan-escrow funds that have been escrowed in the ID being released.
        // The offer is reduced (which is used to repay the previous supplier)
        // A new escrow ID is minted.
        (newEscrowId, newEscrow) = _mintFromOffer(offerId, escrowAmount, newLoanId);

        // Release the escrow to the supplier of previous ID without an actual repayment to this contract.
        // The withdrawable for previous supplier comes from the new supplier's offer.
        // The escrowed loans-funds move into the new escrow of the new supplier.
        // @dev return value is ignored, because no transfers need to be done from/to loans contract
        // and there can be no shortfall or fees
        _releaseEscrow(releaseEscrowId, escrowAmount);

        // @dev no transfers need to happen, because the escrows are swapped internally.
        // The amounts match exactly, and the withdrawal for the previous supplier comes from the
        // new supplier's offer.

        // TODO: event for offer update
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

        // TODO: event
    }

    // ----- INTERNAL MUTATIVE ----- //

    function _mintFromOffer(uint offerId, uint amount, uint loanId)
        internal
        returns (uint escrowId, Escrow memory escrow)
    {
        require(configHub.canOpen(msg.sender), "unsupported loans contract");
        require(configHub.canOpen(address(this)), "unsupported supplier contract");

        Offer storage offer = offers[offerId];

        // check params are still supported
        _configHubValidations(offer.duration);

        // check amount
        uint prevOfferAmount = offer.available;
        require(amount <= prevOfferAmount, "amount too high");

        // storage updates
        offer.available = prevOfferAmount - amount;
        escrowId = nextTokenId++;
        escrow = Escrow({
            loanId: loanId,
            expiration: block.timestamp + offer.duration,
            escrowed: amount,
            gracePeriod: offer.gracePeriod,
            lateFeeAPR: offer.lateFeeAPR,
            released: false,
            withdrawable: 0
        });
        escrows[escrowId] = escrow;

        // TODO: event for escrow creation

        // mint the NFT to the supplier
        // @dev does not use _safeMint to avoid reentrancy
        _mint(offer.supplier, escrowId);
    }

    function _releaseEscrow(uint escrowId, uint repaid) internal returns (uint toLoans) {
        Escrow storage escrow = escrows[escrowId];
        require(!escrow.released, "already released");

        // update storage
        escrow.released = true;

        uint escrowed = escrow.escrowed;
        escrow.withdrawable = repaid > escrowed ? repaid : escrowed; // any gains are for the supplier (late fees)
        toLoans = repaid < escrowed ? repaid : escrowed; // any losses are for the borrower (slippage)

        // TODO: event
    }

    // ----- INTERNAL VIEWS ----- //

    function _configHubValidations(uint duration) internal view {
        // assets
        require(configHub.isSupportedCollateralAsset(address(asset)), "unsupported asset");
        // terms
        require(configHub.isValidCollarDuration(duration), "unsupported duration");
    }

    function _divUp(uint x, uint y) internal pure returns (uint) {
        return (x == 0) ? 0 : ((x - 1) / y) + 1; // divUp(x,y) = (x-1 / y) + 1
    }
}
