// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity 0.8.22;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ConfigHub } from "../ConfigHub.sol";

interface IEscrowSupplierNFT {
    struct Offer {
        address supplier;
        uint available;
        // terms
        uint duration;
        uint interestAPR;
        uint gracePeriod;
        uint lateFeeAPR;
    }

    struct Escrow {
        // reference (for views)
        address loans;
        uint loanId;
        // terms
        uint escrowed;
        uint gracePeriod;
        uint lateFeeAPR;
        // interest & refund
        uint duration;
        uint expiration;
        uint interestHeld;
        // withdrawal
        bool released;
        uint withdrawable;
    }

    // events
    event OfferCreated(
        address indexed supplier,
        uint indexed interestAPR,
        uint indexed duration,
        uint gracePeriod,
        uint lateFeeAPR,
        uint available,
        uint offerId
    );
    event OfferUpdated(uint indexed offerId, address indexed supplier, uint previousAmount, uint newAmount);
    event EscrowCreated(
        uint indexed escrowId,
        uint indexed amount,
        uint indexed duration,
        uint interestFee,
        uint gracePeriod,
        uint offerId
    );
    event EscrowReleased(uint indexed escrowId, uint repaid, uint withdrawable, uint toLoans);
    event EscrowsSwitched(uint indexed oldEscrowId, uint indexed newEscrowId);
    event WithdrawalFromReleased(uint indexed escrowId, address indexed recipient, uint withdrawn);
    event EscrowSeizedLastResort(uint indexed escrowId, address indexed recipient, uint withdrawn);
    event LoansAllowedSet(address indexed loansAddress, bool indexed allowed);
}
