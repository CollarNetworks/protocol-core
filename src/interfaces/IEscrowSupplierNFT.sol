// SPDX-License-Identifier: GPL 2.0
pragma solidity 0.8.22;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ConfigHub } from "../ConfigHub.sol";

interface IEscrowSupplierNFT {
    struct OfferStored {
        // packed first slot
        uint32 duration;
        uint32 gracePeriod;
        uint24 interestAPR; // allows up to 167,772%, must allow MAX_INTEREST_APR_BIPS
        uint24 lateFeeAPR; // allows up to 167,772%, must allow MAX_LATE_FEE_APR_BIPS
        // Note that `gracePeriod` can also be u24 (194 days), and `interestAPR` can be u16 (650%) and
        // they will all fit into one slot with provider, but the impact is minimal, so not worth the
        // messiness (coupling, mental overhead).
        // second slot
        address supplier;
        // next slots
        uint minEscrow;
        uint available;
    }

    struct Offer {
        address supplier;
        uint available;
        // terms
        uint duration;
        uint interestAPR;
        uint gracePeriod;
        uint lateFeeAPR;
        uint minEscrow;
    }

    struct EscrowStored {
        // packed first slot
        uint64 offerId; // assumes sequential IDs
        uint64 loanId; // assumes sequential IDs
        uint32 expiration;
        bool released;
        // second slot
        address loans;
        // rest of slots
        uint escrowed;
        uint feesHeld;
        uint withdrawable;
    }

    struct Escrow {
        uint offerId;
        // reference
        address loans;
        uint loanId;
        // terms
        uint escrowed;
        uint gracePeriod;
        uint lateFeeAPR;
        // interest & refund
        uint duration;
        uint expiration;
        uint feesHeld;
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
        uint offerId,
        uint minEscrow
    );
    event OfferUpdated(uint indexed offerId, address indexed supplier, uint previousAmount, uint newAmount);
    event EscrowCreated(uint indexed escrowId, uint indexed amount, uint feesHeld, uint offerId);
    event EscrowReleased(uint indexed escrowId, uint fromLoans, uint withdrawable, uint toLoans);
    event EscrowsSwitched(uint indexed oldEscrowId, uint indexed newEscrowId);
    event WithdrawalFromReleased(uint indexed escrowId, address indexed recipient, uint withdrawn);
    event EscrowSeized(uint indexed escrowId, address indexed recipient, uint withdrawn);
}
