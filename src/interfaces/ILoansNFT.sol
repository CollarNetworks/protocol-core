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
        EscrowSupplierNFT escrowNFT; // optional, 0 address for non-escrow loans
        uint escrowId;
    }

    struct SwapParams {
        uint minAmountOut; // can be cash or collateral, in correct token units
        address swapper;
        bytes extraData;
    }

    struct OpenLoanParams {
        uint collateralAmount;
        uint minLoanAmount;
        SwapParams swapParams;
        ShortProviderNFT providerNFT;
        uint shortOffer;
        EscrowSupplierNFT escrowNFT; // optional
        uint escrowOffer;
        uint escrowFee;
    }

    struct RollLoanParams {
        uint loanId;
        Rolls rolls;
        uint rollId;
        int minToUser; // cash
        EscrowSupplierNFT newEscrowNFT; // optional
        uint newEscrowOffer;
        uint newEscrowFee; // collateral
    }

    // events
    event LoanOpened(
        address indexed sender,
        address indexed providerNFT,
        uint indexed shortOfferId,
        uint collateralAmount,
        uint loanAmount,
        uint loanId,
        uint providerId
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
    event RollsContractUpdated(Rolls indexed previousRolls, Rolls indexed newRolls);
    event SwapperSet(address indexed swapper, bool indexed allowed, bool indexed setDefault);
    event EscrowSettled(uint indexed escrowId, uint toEscrow, uint fromEscrow, uint leftOver);

    // constants
    function MAX_SWAP_TWAP_DEVIATION_BIPS() external view returns (uint);
    function VERSION() external view returns (string memory);

    // immutables
    function cashAsset() external view returns (IERC20);
    function collateralAsset() external view returns (IERC20);
    function takerNFT() external view returns (CollarTakerNFT);
    // state
    function getLoan(uint loanId) external view returns (Loan memory);
    function closingKeeper() external view returns (address);
    // mutative contract owner
    function setKeeper(address keeper) external;
    function setRollsContract(Rolls rolls) external;
    // mutative user (+ some keeper)
    function setKeeperAllowed(bool enabled) external;
    function openLoan(
        uint collateralAmount,
        uint minLoanAmount,
        SwapParams calldata swapParams,
        ShortProviderNFT providerNFT,
        uint offerId
    ) external returns (uint loanId, uint providerId, uint loanAmount);
    function closeLoan(uint loanId, SwapParams calldata swapParams)
        external
        returns (uint collateralReturned);
    function rollLoan(uint loanId, Rolls rolls, uint rollId, int minToUser)
        external
        returns (uint newLoanId, uint newLoanAmount, int transferAmount);
    function unwrapAndCancelLoan(uint loanId) external;
}
