// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity 0.8.21;

interface ILenderPosition {
    struct Position {
        uint expiration;
        uint principal;
        uint strikeDeviation;
        bool finalized;
        uint withdrawable;
    }

    // VIEWS

    // core logic views
    function borrowPositionContract() external view returns (address);
    function cashAsset() external view returns (address);
    function collateralAsset() external view returns (address);
    function duration() external view returns (uint);
    function engine() external view returns (address);
    function ltv() external view returns (uint);
    function nextOfferId() external view returns (uint);
    function nextPositionId() external view returns (uint);
    function validateConfig() external view;
    function validateBorrowingContract() external view;
    function liquidityOffers(uint offerId)
        external
        view
        returns (address provider, uint available, uint strikeDeviation);
    function positions(uint positionId)
        external
        view
        returns (uint expiration, uint principal, uint strikeDeviation, bool finalized, uint withdrawable);

    // ownable / pausable views
    function owner() external view returns (address);
    function paused() external view returns (bool);
    // NFT views
    function balanceOf(address owner) external view returns (uint);
    function ownerOf(uint tokenId) external view returns (address);
    function getApproved(uint tokenId) external view returns (address);
    function isApprovedForAll(address owner, address operator) external view returns (bool);
    function symbol() external view returns (string memory);
    function totalSupply() external view returns (uint);
    function tokenByIndex(uint index) external view returns (uint);
    function tokenOfOwnerByIndex(address owner, uint index) external view returns (uint);
    function tokenURI(uint tokenId) external view returns (string memory);
    function supportsInterface(bytes4 interfaceId) external view returns (bool);

    // MUTATIVE

    // lender mutative
    function createOffer(uint strikeDeviation, uint amount) external returns (uint offerId);
    function updateOfferAmount(uint offerId, int delta) external;
    function withdrawSettled(uint positionId) external;
    // borrower mutative
    function openPosition(
        uint offerId,
        uint amount
    )
        external
        returns (uint positionId, Position memory position);
    function settlePosition(uint positionId, int positionNet) external;
    // lender & borrower
    function cancelPosition(uint positionId) external;

    // ownable pausable mutative
    function pause() external;
    function unpause() external;
    function renounceOwnership() external;
    // NFT mutative
    function approve(address to, uint tokenId) external;
    function safeTransferFrom(address from, address to, uint tokenId) external;
    function safeTransferFrom(address from, address to, uint tokenId, bytes memory data) external;
    function setApprovalForAll(address operator, bool approved) external;
    function transferFrom(address from, address to, uint tokenId) external;
    function transferOwnership(address newOwner) external;
}
