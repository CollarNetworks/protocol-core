// SPDX-License-Identifier: GPL 2.0
pragma solidity 0.8.22;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ConfigHub } from "../ConfigHub.sol";

interface ICollarProviderNFT {
    struct LiquidityOfferStored {
        // packed first slot
        address provider;
        uint24 putStrikePercent; // supports up to 167,772 % (1677x)
        uint24 callStrikePercent; // supports up to 167,772 % (1677x)
        uint32 duration;
        // next slots
        uint minLocked;
        uint available;
    }

    struct LiquidityOffer {
        address provider;
        uint available;
        // terms
        uint duration;
        uint putStrikePercent;
        uint callStrikePercent;
        uint minLocked;
    }

    struct ProviderPositionStored {
        // packed first slot
        uint64 offerId; // assumes IDs are ordered
        uint64 takerId; // assumes IDs are ordered
        uint32 expiration;
        bool settled;
        // next slots
        uint providerLocked;
        uint withdrawable;
    }

    struct ProviderPosition {
        uint offerId; // the LiquidityOffer offerId
        uint takerId; // the corresponding paired ID for onchain / view reference
        // collar position terms
        uint duration;
        uint expiration;
        uint providerLocked;
        uint putStrikePercent;
        uint callStrikePercent;
        // withdrawal
        bool settled;
        uint withdrawable;
    }

    // events
    event OfferCreated(
        address indexed provider,
        uint indexed putStrikePercent,
        uint indexed duration,
        uint callStrikePercent,
        uint amount,
        uint offerId,
        uint minLocked
    );
    event OfferUpdated(uint indexed offerId, address indexed provider, uint previousAmount, uint newAmount);
    event PositionCreated(uint indexed positionId, uint indexed offerId, uint feeAmount, uint providerLocked);
    event PositionSettled(uint indexed positionId, int positionChange, uint withdrawable);
    event WithdrawalFromSettled(uint indexed positionId, uint withdrawn);
    event PositionCanceled(uint indexed positionId, uint withdrawn, uint expiration);
}
