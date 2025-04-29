// SPDX-License-Identifier: GPL 2.0
pragma solidity 0.8.22;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ConfigHub } from "../ConfigHub.sol";
import { CollarTakerNFT } from "../CollarTakerNFT.sol";
import { CollarProviderNFT } from "../CollarProviderNFT.sol";
import { Rolls } from "../Rolls.sol";
import { EscrowSupplierNFT } from "../EscrowSupplierNFT.sol";

interface ILoansNFT {
    // storage struct
    struct LoanStored {
        uint underlyingAmount; // initial amount used, may not correspond to loan value due to swaps
        uint loanAmount;
        // third slot
        bool usesEscrow;
        EscrowSupplierNFT escrowNFT;
        uint64 escrowId; // assumes sequential IDs
    }

    // view struct
    struct Loan {
        uint underlyingAmount; // initial amount used, may not correspond to loan value due to swaps
        uint loanAmount;
        bool usesEscrow;
        EscrowSupplierNFT escrowNFT; // optional, 0 address for non-escrow loans (`usesEscrow` == false)
        uint escrowId;
    }

    // input structs
    struct SwapParams {
        uint minAmountOut; // can be cash or underlying
        address swapper;
        bytes extraData;
    }

    struct ProviderOffer {
        CollarProviderNFT providerNFT;
        uint id;
    }

    struct EscrowOffer {
        EscrowSupplierNFT escrowNFT;
        uint id;
    }

    struct RollOffer {
        Rolls rolls;
        uint id;
    }

    // events
    event LoanOpened(
        uint indexed loanId,
        address indexed sender,
        uint underlyingAmount,
        uint loanAmount,
        bool usesEscrow,
        uint escrowId,
        address escrowNFT
    );
    event LoanClosed(
        uint indexed loanId,
        address indexed sender,
        address indexed borrower,
        uint repayment,
        uint cashAmount,
        uint underlyingFromSwap
    );
    event LoanRolled(
        address indexed sender,
        uint indexed loanId,
        uint indexed rollId,
        uint newLoanId,
        uint prevLoanAmount,
        uint newLoanAmount,
        int transferAmount,
        uint escrowId
    );
    event LoanCancelled(uint indexed loanId, address indexed sender);
    event ClosingKeeperApproved(address indexed sender, uint indexed loanId, address indexed keeper);
    event SwapperSet(address indexed swapper, bool indexed allowed, bool indexed setDefault);
    event EscrowSettled(uint indexed escrowId, uint toEscrow, uint fromEscrow, uint leftOver);
}
