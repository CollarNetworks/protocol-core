// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity 0.8.22;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ConfigHub } from "../ConfigHub.sol";
import { CollarProviderNFT } from "../CollarProviderNFT.sol";
import { OracleUniV3TWAP } from "../OracleUniV3TWAP.sol";

interface ICollarTakerNFT {
    // @dev Some data can be trimmed down from this struct, since some of the fields aren't needed on-chain,
    // and are stored for FE / usability since the assumption is that this is used on L2.
    struct TakerPosition {
        // paired NFT info
        CollarProviderNFT providerNFT;
        uint providerId;
        // collar position info
        uint duration;
        uint expiration;
        uint startPrice;
        uint putStrikePrice;
        uint callStrikePrice;
        uint takerLocked;
        uint providerLocked;
        // withdrawal state
        bool settled;
        uint withdrawable;
    }

    // events
    event CollarTakerNFTCreated(
        address indexed cashAsset, address indexed underlying, address indexed oracle
    );
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
        bool historicalPriceUsed,
        uint withdrawable,
        int toProvider
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
    event OracleSet(OracleUniV3TWAP prevOracle, OracleUniV3TWAP newOracle);
}
