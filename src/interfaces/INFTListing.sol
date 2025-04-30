// SPDX-License-Identifier: GPL 2.0
pragma solidity 0.8.22;

/// @title INFTListing
/// @notice Interface for the NFT listing and buying contract

interface INFTListing {
    /// @dev listing struct
    struct Listing {
        address seller;
        address nftContract;
        uint tokenId;
        uint paymentAmount;
        address paymentToken;
        uint expiration;
        bool available;
    }
    /// @notice Emitted when an NFT is listed for sale

    event NFTListed(
        address indexed seller,
        address indexed nftContract,
        uint indexed tokenId,
        uint paymentAmount,
        address paymentToken,
        uint expiration,
        uint listingId
    );

    /// @notice Emitted when an NFT is purchased
    event NFTPurchased(
        address indexed buyer, address indexed nftContract, uint indexed tokenId, uint listingId
    );

    /// @notice Emitted when a listing is cancelled by the seller
    event NFTListingCancelled(
        address indexed seller, address indexed nftContract, uint indexed tokenId, uint listingId
    );
}
