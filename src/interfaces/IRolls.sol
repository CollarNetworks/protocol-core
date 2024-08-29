// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity 0.8.22;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { CollarTakerNFT } from "../CollarTakerNFT.sol";
import { ShortProviderNFT } from "../ShortProviderNFT.sol";

interface IRolls {
    struct RollOffer {
        // terms
        uint takerId;
        int rollFeeAmount;
        int rollFeeDeltaFactorBIPS; // bips change of fee amount for delta (ratio) of price change
        uint rollFeeReferencePrice;
        // provider protection
        uint minPrice;
        uint maxPrice;
        int minToProvider;
        uint deadline;
        // somewhat redundant (since it comes from the taker ID), but safer for cancellations
        ShortProviderNFT providerNFT;
        uint providerId;
        // state
        address provider;
        bool active;
    }

    // events
    event OfferCreated(
        uint indexed takerId,
        address indexed provider,
        ShortProviderNFT indexed providerNFT,
        uint providerId,
        int rollFeeAmount,
        uint rollId
    );
    event OfferCancelled(uint indexed rollId, uint indexed takerId, address indexed provider);
    event OfferExecuted(
        uint indexed rollId,
        uint indexed takerId,
        ShortProviderNFT indexed providerNFT,
        uint providerId,
        int toTaker,
        int toProvider,
        int rollFee,
        uint newTakerId,
        uint newProviderId
    );

    // constants
    function VERSION() external view returns (string memory);
    // immutables
    function cashAsset() external view returns (IERC20);
    function takerNFT() external view returns (CollarTakerNFT);
    // state
    function nextRollId() external view returns (uint);
    function getRollOffer(uint rollId) external view returns (RollOffer memory);
    // views
    function calculateRollFee(RollOffer memory offer, uint currentPrice)
        external
        pure
        returns (int rollFee);
    function calculateTransferAmounts(uint rollId, uint price)
        external
        view
        returns (int toTaker, int toProvider, int rollFee);

    // mutative provider
    function createRollOffer(
        uint takerId,
        int rollFeeAmount,
        int rollFeeDeltaFactorBIPS,
        uint minPrice,
        uint maxPrice,
        int minToProvider,
        uint deadline
    ) external returns (uint rollId);
    function cancelOffer(uint rollId) external;
    // mutative user
    function executeRoll(uint rollId, int minToUser)
        external
        returns (uint newTakerId, uint newProviderId, int toTaker, int toProvider);
}
