// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity 0.8.21;

interface LenderPosition {
    struct Position {
        uint expiration;
        uint principal;
        uint strikeDeviation;
        bool finalized;
        uint withdrawable;
    }

    error AddressEmptyCode(address target);
    error AddressInsufficientBalance(address account);
    error ERC721EnumerableForbiddenBatchMint();
    error ERC721IncorrectOwner(address sender, uint tokenId, address owner);
    error ERC721InsufficientApproval(address operator, uint tokenId);
    error ERC721InvalidApprover(address approver);
    error ERC721InvalidOperator(address operator);
    error ERC721InvalidOwner(address owner);
    error ERC721InvalidReceiver(address receiver);
    error ERC721InvalidSender(address sender);
    error ERC721NonexistentToken(uint tokenId);
    error ERC721OutOfBoundsIndex(address owner, uint index);
    error EnforcedPause();
    error ExpectedPause();
    error FailedInnerCall();
    error OwnableInvalidOwner(address owner);
    error OwnableUnauthorizedAccount(address account);
    error SafeERC20FailedOperation(address token);

    event Approval(address indexed owner, address indexed approved, uint indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event Paused(address account);
    event Transfer(address indexed from, address indexed to, uint indexed tokenId);
    event Unpaused(address account);

    function approve(address to, uint tokenId) external;
    function balanceOf(address owner) external view returns (uint);
    function borrowPositionContract() external view returns (address);
    function cashAsset() external view returns (address);
    function closePosition(uint positionId, int positionNet) external;
    function collateralAsset() external view returns (address);
    function createOffer(uint strikeDeviation, uint amount) external returns (uint offerId);
    function duration() external view returns (uint);
    function engine() external view returns (address);
    function getApproved(uint tokenId) external view returns (address);
    function isApprovedForAll(address owner, address operator) external view returns (bool);
    function liquidityOffers(uint offerId)
        external
        view
        returns (address provider, uint available, uint strikeDeviation);
    function ltv() external view returns (uint);
    function name() external view returns (string memory);
    function nextOfferId() external view returns (uint);
    function nextPositionId() external view returns (uint);
    function openPosition(
        uint offerId,
        uint amount
    )
        external
        returns (uint positionId, Position memory position);
    function owner() external view returns (address);
    function ownerOf(uint tokenId) external view returns (address);
    function pause() external;
    function paused() external view returns (bool);
    function positions(uint positionId)
        external
        view
        returns (uint expiration, uint principal, uint strikeDeviation, bool finalized, uint withdrawable);
    function renounceOwnership() external;
    function safeTransferFrom(address from, address to, uint tokenId) external;
    function safeTransferFrom(address from, address to, uint tokenId, bytes memory data) external;
    function setApprovalForAll(address operator, bool approved) external;
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
    function symbol() external view returns (string memory);
    function tokenByIndex(uint index) external view returns (uint);
    function tokenOfOwnerByIndex(address owner, uint index) external view returns (uint);
    function tokenURI(uint tokenId) external view returns (string memory);
    function totalSupply() external view returns (uint);
    function transferFrom(address from, address to, uint tokenId) external;
    function transferOwnership(address newOwner) external;
    function unpause() external;
    function updateOfferAmount(uint offerId, int delta) external;
    function validateBorrowingContract() external view;
    function validateConfig() external view;
    function withdrawAndBurn(uint positionId) external;
}
