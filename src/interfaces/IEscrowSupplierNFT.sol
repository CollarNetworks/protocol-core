// SPDX-License-Identifier: GPL 2.0
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
        uint maxGracePeriod;
        uint lateFeeAPR;
    }

    struct EscrowStored {
        uint offerId;
        // reference
        address loans;
        uint loanId;
        // terms
        uint escrowed;
        // interest & refund
        uint expiration;
        uint interestHeld;
        // withdrawal
        bool released;
        uint withdrawable;
    }

    struct Escrow {
        uint offerId;
        // reference
        address loans;
        uint loanId;
        // terms
        uint escrowed;
        uint maxGracePeriod;
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
        uint maxGracePeriod,
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
        uint maxGracePeriod,
        uint offerId
    );
    event EscrowReleased(uint indexed escrowId, uint fromLoans, uint withdrawable, uint toLoans);
    event EscrowsSwitched(uint indexed oldEscrowId, uint indexed newEscrowId);
    event WithdrawalFromReleased(uint indexed escrowId, address indexed recipient, uint withdrawn);
    event EscrowSeizedLastResort(uint indexed escrowId, address indexed recipient, uint withdrawn);
    event LoansAllowedSet(address indexed loansAddress, bool indexed allowed);
}
