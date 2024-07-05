// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity 0.8.22;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { CollarEngine } from "../implementations/CollarEngine.sol";
import { ProviderPositionNFT } from "../ProviderPositionNFT.sol";

interface ICollarTakerNFT {
    // @dev Some data can be trimmed down from this struct, since some of the fields aren't needed on-chain,
    // and are stored for FE / usability since the assumption is that this is used on L2.
    struct TakerPosition {
        // paired NFT info
        ProviderPositionNFT providerNFT;
        uint providerPositionId;
        // collar position info
        uint duration;
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
        uint indexed takerId,
        address indexed providerNFT,
        uint indexed providerId,
        uint offerId,
        TakerPosition takerPosition
    );
    event PairedPositionSettled(
        uint indexed takerId,
        address indexed providerNFT,
        uint indexed providerId,
        uint endPrice,
        uint withdrawable,
        int providerChange
    );
    event PairedPositionCanceled(
        uint indexed takerId,
        address indexed providerNFT,
        uint indexed providerId,
        address recipient,
        uint withdrawn,
        uint expiration
    );
    event WithdrawalFromSettled(uint indexed takerId, address indexed recipient, uint withdrawn);

    // constants
    function TWAP_LENGTH() external view returns (uint32);
    function VERSION() external view returns (string memory);
    // immutables
    function cashAsset() external view returns (IERC20);
    function collateralAsset() external view returns (IERC20);
    function engine() external view returns (CollarEngine);
    // state
    function getPosition(uint takerId) external view returns (TakerPosition memory);
    function nextPositionId() external view returns (uint);
    // mutative
    function openPairedPosition(
        uint putLockedCash,
        ProviderPositionNFT providerNFT,
        uint offerId
        ) external returns (uint takerId, uint providerId);
    function settlePairedPosition(uint takerId) external;
    function cancelPairedPosition(uint takerId, address recipient) external;
    function withdrawFromSettled(uint takerId, address recipient) external returns (uint amount);
}
