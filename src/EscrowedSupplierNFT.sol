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
        uint takerId;
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
    ) BaseEmergencyAdminNFT(initialOwner, _configHub, _name, _symbol) {
        asset = _asset;
        loans = _loans;
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

    function escrowAndMint(uint offerId, uint amount, uint takerId)
        external
        whenNotPaused
        onlyLoans
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
            takerId: takerId,
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

        // @dev despite the fact that they cancel out, these transfers are the whole point of this contract
        // from product point of view. The end balance is the same, but the transfer events are needed.
        // take the escrow from loans
        asset.safeTransferFrom(loans, address(this), amount);
        // transfer the supplier's collateral to loans
        asset.safeTransfer(loans, amount);

        // TODO: event for offer update
    }

    function releaseEscrow(uint escrowId, uint repaid) external whenNotPaused onlyLoans {
        Escrow storage escrow = escrows[escrowId];
        require(!escrow.released, "already released");

        // update storage
        escrow.released = true;

        uint escrowed = escrow.escrowed;
        escrow.withdrawable = repaid > escrowed ? repaid : escrowed; // any gains are for the supplier (late fees)
        uint toRelease = repaid < escrowed ? repaid : escrowed; // any losses are for the borrower (slippage)

        // transfer in the repaid assets
        asset.safeTransferFrom(loans, address(this), repaid);
        // release the escrow (with possible loss to the borrower)
        asset.safeTransfer(loans, toRelease);

        // TODO: event
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

    // ----- INTERNAL VIEWS ----- //

    function _configHubValidations(uint duration) internal view {
        // assets
        require(configHub.isSupportedCollateralAsset(address(asset)), "unsupported asset");
        // terms
        require(configHub.isValidCollarDuration(duration), "unsupported duration");
    }
}
