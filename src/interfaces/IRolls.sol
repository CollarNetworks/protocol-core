// SPDX-License-Identifier: GPL 2.0
pragma solidity 0.8.22;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { CollarTakerNFT, ICollarTakerNFT } from "../CollarTakerNFT.sol";
import { CollarProviderNFT, ICollarProviderNFT } from "../CollarProviderNFT.sol";

interface IRolls {
    struct PreviewResults {
        int toTaker;
        int toProvider;
        int rollFee;
        ICollarTakerNFT.TakerPosition takerPos;
        uint newTakerLocked;
        uint newProviderLocked;
        uint protocolFee;
    }

    struct RollOfferStored {
        // first slot
        CollarProviderNFT providerNFT;
        uint64 providerId;
        uint32 deadline;
        // second slot
        uint64 takerId;
        int24 feeDeltaFactorBIPS; // allows up to +-838%, must allow at least BIPS_BASE
        bool active;
        address provider;
        // rest of slots
        int feeAmount;
        uint feeReferencePrice;
        uint minPrice;
        uint maxPrice;
        int minToProvider;
    }

    struct RollOffer {
        // terms
        uint takerId;
        int feeAmount;
        int feeDeltaFactorBIPS; // bips change of fee amount for delta (ratio) of price change
        uint feeReferencePrice;
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
    event OfferCreated(address indexed provider, uint rollId, RollOfferStored offer);
    event OfferCancelled(uint indexed rollId, uint indexed takerId, address indexed provider);
    event OfferExecuted(
        uint indexed rollId, int toTaker, int toProvider, int rollFee, uint newTakerId, uint newProviderId
    );
}
