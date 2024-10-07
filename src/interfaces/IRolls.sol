// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity 0.8.22;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { CollarTakerNFT } from "../CollarTakerNFT.sol";
import { CollarProviderNFT } from "../CollarProviderNFT.sol";

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
        CollarProviderNFT providerNFT;
        uint providerId;
        // state
        address provider;
        bool active;
    }

    // events
    event OfferCreated(
        uint indexed takerId,
        address indexed provider,
        CollarProviderNFT indexed providerNFT,
        uint providerId,
        int rollFeeAmount,
        uint rollId
    );
    event OfferCancelled(uint indexed rollId, uint indexed takerId, address indexed provider);
    event OfferExecuted(
        uint indexed rollId,
        uint indexed takerId,
        CollarProviderNFT indexed providerNFT,
        uint providerId,
        int toTaker,
        int toProvider,
        int rollFee,
        uint newTakerId,
        uint newProviderId
    );
}
