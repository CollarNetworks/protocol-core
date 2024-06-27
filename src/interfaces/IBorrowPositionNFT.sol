// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity 0.8.21;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { CollarEngine } from "../implementations/CollarEngine.sol";
import { ProviderPositionNFT } from "../ProviderPositionNFT.sol";

interface IBorrowPositionNFT {
    // @dev Some data can be trimmed down from this struct, since some of the fields aren't needed on-chain,
    // and are stored for FE / usability since the assumption is that this is used on L2.
    struct BorrowPosition {
        // paired NFT info
        ProviderPositionNFT providerNFT;
        uint providerPositionId;
        // collar position info
        uint openedAt;
        uint expiration;
        uint initialPrice;
        uint putStrikePrice;
        uint callStrikePrice;
        uint putLockedCash;
        uint callLockedCash;
        // withdrawal state
        bool settled;
        uint withdrawable;
    }

    // events
    event PairedPositionOpened(
        uint indexed borrowId,
        address indexed providerNFT,
        uint indexed providerId,
        uint offerId,
        BorrowPosition borrowPosition
    );
    event PairedPositionSettled(
        uint indexed borrowId,
        address indexed providerNFT,
        uint indexed providerId,
        uint endPrice,
        uint withdrawable,
        int providerChange
    );
    event PairedPositionCanceled(
        uint indexed borrowId,
        address indexed providerNFT,
        uint indexed providerId,
        address recipient,
        uint withdrawn,
        uint expiration
    );
    event WithdrawalFromSettled(uint indexed borrowId, address indexed recipient, uint withdrawn);
    event BorrowedFromSwap(
        uint indexed borrowId,
        address indexed sender,
        uint collateralAmount,
        uint cashFromSwap,
        uint loanAmount
    );

    // constants
    function MAX_SWAP_TWAP_DEVIATION_BIPS() external view returns (uint);
    function TWAP_LENGTH() external view returns (uint32);
    function VERSION() external view returns (string memory);
    // immutables
    function cashAsset() external view returns (IERC20);
    function collateralAsset() external view returns (IERC20);
    function engine() external view returns (CollarEngine);
    // state
    function getPosition(uint borrowId) external view returns (BorrowPosition memory);
    function nextPositionId() external view returns (uint);
    // mutative
    function openPairedPosition(
        uint collateralAmount,
        uint minCashAmount,
        ProviderPositionNFT providerNFT,
        uint offerId
    ) external returns (uint borrowId, uint providerId, uint loanAmount);
    function settlePairedPosition(uint borrowId) external;
    function cancelPairedPosition(uint borrowId, address recipient) external;
    function withdrawFromSettled(uint borrowId, address recipient) external;
}
