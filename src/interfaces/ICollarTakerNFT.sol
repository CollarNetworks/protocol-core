// SPDX-License-Identifier: GPL 2.0
pragma solidity 0.8.22;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ConfigHub } from "../ConfigHub.sol";
import { CollarProviderNFT } from "../CollarProviderNFT.sol";
import { ITakerOracle } from "./ITakerOracle.sol";

interface ICollarTakerNFT {
    struct TakerPositionStored {
        // packed first slot
        CollarProviderNFT providerNFT;
        uint64 providerId; // assumes IDs are ordered
        bool settled;
        // next slots
        uint startPrice;
        uint takerLocked;
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
        uint putStrikePercent;
        uint callStrikePercent;
        uint takerLocked;
        uint providerLocked;
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
        uint takerLocked,
        uint startPrice
    );
    event PairedPositionSettled(
        uint indexed takerId,
        address indexed providerNFT,
        uint indexed providerId,
        uint endPrice,
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
}
