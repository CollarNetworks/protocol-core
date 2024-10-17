// SPDX-License-Identifier: GPL 2.0
pragma solidity 0.8.22;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ConfigHub } from "../ConfigHub.sol";
import { CollarProviderNFT } from "../CollarProviderNFT.sol";
import { ITakerOracle } from "./ITakerOracle.sol";

interface ICollarTakerNFT {
    struct TakerPositionStored {
        // paired NFT info
        CollarProviderNFT providerNFT;
        uint providerId;
        // collar position info
        uint startPrice;
        uint takerLocked;
        // withdrawal state
        bool settled;
        uint withdrawable;
    }

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
        uint withdrawn,
        uint expiration
    );
    event WithdrawalFromSettled(uint indexed takerId, uint withdrawn);
    event OracleSet(ITakerOracle prevOracle, ITakerOracle newOracle);
}
