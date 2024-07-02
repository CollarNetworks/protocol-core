// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity 0.8.22;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { CollarEngine } from "../implementations/CollarEngine.sol";

interface IProviderPositionNFT {
    struct LiquidityOffer {
        address provider;
        uint available;
        // terms
        uint putStrikeDeviation;
        uint callStrikeDeviation;
        uint duration;
    }

    struct ProviderPosition {
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
        uint offerId
    );
    event PositionSettled(uint indexed positionId, int positionChange, uint withdrawable);
    event WithdrawalFromSettled(uint indexed positionId, address indexed recipient, uint withdrawn);
    event PositionCanceled(
        uint indexed positionId, address indexed recipient, uint withdrawn, uint expiration
    );

    // constants
    function MAX_CALL_STRIKE_BIPS() external view returns (uint);
    function MIN_CALL_STRIKE_BIPS() external view returns (uint);
    function MAX_PUT_STRIKE_BIPS() external view returns (uint);
    function VERSION() external view returns (string memory);
    // immutables
    function borrowPositionContract() external view returns (address);
    function cashAsset() external view returns (IERC20);
    function collateralAsset() external view returns (IERC20);
    function engine() external view returns (CollarEngine);
    // state
    function nextOfferId() external view returns (uint);
    function nextPositionId() external view returns (uint);
    function getOffer(uint offerId) external view returns (LiquidityOffer memory);
    function getPosition(uint positionId) external view returns (ProviderPosition memory);

    // mutative liquidity
    function createOffer(uint callStrikeDeviation, uint amount, uint putStrikeDeviation, uint duration)
        external
        returns (uint offerId);
    function updateOfferAmount(uint offerId, uint newAmount) external;
    // mutative from borrow NFT
    function mintPositionFromOffer(uint offerId, uint amount)
        external
        returns (uint positionId, ProviderPosition memory position);
    function cancelAndWithdraw(uint positionId, address recipient) external;
    function settlePosition(uint positionId, int positionChange) external;
    // mutative by position NFT owner
    function withdrawFromSettled(uint positionId, address recipient) external;
}
