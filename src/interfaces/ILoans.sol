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

interface ILoans {
    struct Loan {
        uint collateralAmount;
        uint loanAmount;
        address keeperAllowedBy;
        bool active;
    }

    struct SwapParams {
        uint minAmountOut; // can be cash or collateral, in correct token units
        address swapper;
        bytes extraData;
    }

    // events
    event LoanOpened(
        address indexed sender,
        address indexed providerNFT,
        uint indexed offerId,
        uint collateralAmount,
        uint loanAmount,
        uint takerId,
        uint providerId
    );
    event LoanClosed(
        uint indexed takerId,
        address indexed sender,
        address indexed user,
        uint repayment,
        uint cashAmount,
        uint collateralOut
    );
    event LoanRolled(
        address indexed sender,
        uint indexed takerId,
        uint indexed rollId,
        uint newTakerId,
        uint prevLoanAmount,
        uint newLoanAmount,
        int transferAmount
    );
    event LoanCancelled(uint indexed takerId, address indexed sender);
    event ClosingKeeperAllowed(address indexed sender, uint indexed takerId, bool indexed enabled);
    event ClosingKeeperUpdated(address indexed previousKeeper, address indexed newKeeper);
    event RollsContractUpdated(Rolls indexed previousRolls, Rolls indexed newRolls);
    event SwapperSet(address indexed swapper, bool indexed allowed, bool indexed setDefault);

    // constants
    function MAX_SWAP_TWAP_DEVIATION_BIPS() external view returns (uint);
    function VERSION() external view returns (string memory);

    // immutables
    function cashAsset() external view returns (IERC20);
    function collateralAsset() external view returns (IERC20);
    function takerNFT() external view returns (CollarTakerNFT);
    // state
    function getLoan(uint takerId) external view returns (Loan memory);
    function closingKeeper() external view returns (address);
    // mutative contract owner
    function setKeeper(address keeper) external;
    function setRollsContract(Rolls rolls) external;
    // mutative user / keeper
    function openLoan(
        uint collateralAmount,
        uint minLoanAmount,
        SwapParams calldata swapParams,
        ShortProviderNFT providerNFT,
        uint offerId
    ) external returns (uint takerId, uint providerId, uint loanAmount);
    function setKeeperAllowedBy(uint takerId, bool enabled) external;
    function closeLoan(uint takerId, SwapParams calldata swapParams)
        external
        returns (uint collateralReturned);
    function rollLoan(uint takerId, Rolls rolls, uint rollId, int minToUser)
        external
        returns (uint newTakerId, uint newLoanAmount, int transferAmount);
}
