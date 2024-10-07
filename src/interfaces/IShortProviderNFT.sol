// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity 0.8.22;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ConfigHub } from "../ConfigHub.sol";

interface IShortProviderNFT {
    struct LiquidityOffer {
        address provider;
        uint available;
        // terms
        uint putStrikeDeviation;
        uint callStrikeDeviation;
        uint duration;
    }

    struct ProviderPosition {
        uint takerId; // the corresponding paired ID for onchain / view reference
        // collar position terms
        uint expiration;
        uint principal;
        uint putStrikeDeviation;
        uint callStrikeDeviation;
        // withdrawal
        bool settled;
        uint withdrawable;
    }

    // events
    event ShortProviderNFTCreated(
        address indexed cashAsset, address indexed collateralAsset, address indexed takerContract
    );
    event OfferCreated(
        address indexed provider,
        uint indexed putStrikeDeviation,
        uint indexed duration,
        uint callStrikeDeviation,
        uint amount,
        uint offerId
    );
    event OfferUpdated(uint indexed offerId, address indexed provider, uint previousAmount, uint newAmount);
    event PositionCreated(
        uint indexed positionId,
        uint indexed putStrikeDeviation,
        uint indexed duration,
        uint callStrikeDeviation,
        uint amount,
        uint offerId,
        uint feeAmount
    );
    event PositionSettled(uint indexed positionId, int positionChange, uint withdrawable);
    event WithdrawalFromSettled(uint indexed positionId, address indexed recipient, uint withdrawn);
    event PositionCanceled(
        uint indexed positionId, address indexed recipient, uint withdrawn, uint expiration
    );
}
