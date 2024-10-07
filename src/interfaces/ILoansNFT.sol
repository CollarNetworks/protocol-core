// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity 0.8.22;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ConfigHub } from "../ConfigHub.sol";
import { CollarTakerNFT } from "../CollarTakerNFT.sol";
import { ShortProviderNFT } from "../ShortProviderNFT.sol";
import { Rolls } from "../Rolls.sol";
import { EscrowSupplierNFT } from "../EscrowSupplierNFT.sol";

interface ILoansNFT {
    struct Loan {
        uint collateralAmount;
        uint loanAmount;
        bool usesEscrow;
        EscrowSupplierNFT escrowNFT; // optional, 0 address for non-escrow loans
        uint escrowId;
    }

    struct SwapParams {
        uint minAmountOut; // can be cash or collateral, in correct token units
        address swapper;
        bytes extraData;
    }

    // events
    event LoanOpened(
        uint indexed loanId,
        address indexed sender,
        uint indexed shortOfferId,
        uint collateralAmount,
        uint loanAmount
    );
    event LoanClosed(
        uint indexed loanId,
        address indexed sender,
        address indexed user,
        uint repayment,
        uint cashAmount,
        uint collateralOut
    );
    event LoanRolled(
        address indexed sender,
        uint indexed loanId,
        uint indexed rollId,
        uint newLoanId,
        uint prevLoanAmount,
        uint newLoanAmount,
        int transferAmount
    );
    event LoanCancelled(uint indexed loanId, address indexed sender);
    event ClosingKeeperAllowed(address indexed sender, bool indexed enabled);
    event ClosingKeeperUpdated(address indexed previousKeeper, address indexed newKeeper);
    event ContractsUpdated(
        Rolls indexed rolls, ShortProviderNFT indexed providerNFT, EscrowSupplierNFT indexed escrowNFT
    );
    event SwapperSet(address indexed swapper, bool indexed allowed, bool indexed setDefault);
    event EscrowSettled(uint indexed escrowId, uint lateFee, uint toEscrow, uint fromEscrow, uint leftOver);
    event LoanForeclosed(uint indexed loanId, uint indexed escrowId, uint fromSwap, uint toUser);
}
