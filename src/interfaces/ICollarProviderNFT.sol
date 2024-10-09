// SPDX-License-Identifier: GPL 2.0
pragma solidity 0.8.22;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ConfigHub } from "../ConfigHub.sol";

interface ICollarProviderNFT {
    struct LiquidityOffer {
        address provider;
        uint available;
        // terms
        uint putStrikePercent;
        uint callStrikePercent;
        uint duration;
    }

    struct ProviderPosition {
        uint takerId; // the corresponding paired ID for onchain / view reference
        // collar position terms
        uint expiration;
        uint principal;
        uint putStrikePercent;
        uint callStrikePercent;
        // withdrawal
        bool settled;
        uint withdrawable;
    }

    // events
    event CollarProviderNFTCreated(
        address indexed cashAsset, address indexed underlying, address indexed takerContract
    );
    event OfferCreated(
        address indexed provider,
        uint indexed putStrikePercent,
        uint indexed duration,
        uint callStrikePercent,
        uint amount,
        uint offerId
    );
    event OfferUpdated(uint indexed offerId, address indexed provider, uint previousAmount, uint newAmount);
    event PositionCreated(
        uint indexed positionId, uint indexed offerId, uint feeAmount, ProviderPosition position
    );
    event PositionSettled(uint indexed positionId, int positionChange, uint withdrawable);
    event WithdrawalFromSettled(uint indexed positionId, uint withdrawn);
    event PositionCanceled(uint indexed positionId, uint withdrawn, uint expiration);
}
