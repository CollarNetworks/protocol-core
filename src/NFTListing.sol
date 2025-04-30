// SPDX-License-Identifier: GPL 2.0
pragma solidity 0.8.22;

import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { INFTListing } from "./interfaces/INFTListing.sol";
/// @title NFT Listing Contract
/// @notice Enables sellers (takers) to list NFTs with a fixed ERC20 price
/// @dev Buyers acquire NFTs by paying the fixed amount before expiration

contract NFTListing is INFTListing {
    using SafeERC20 for IERC20;

    /// @dev mapping from unique NFT key to listing
    mapping(uint listingId => Listing) public listings;

    uint public nextListingId = 1; // starts from 1 so that 0 ID is not used

    /// @notice Creates a fixed-price listing for an ERC721
    /// @param nftContract Address of the ERC721 contract
    /// @param tokenId Token ID to list
    /// @param paymentAmount Amount of ERC20 tokens required for purchase
    /// @param paymentToken ERC20 token used for payment
    /// @param expiration Timestamp after which listing is invalid
    function listNFT(
        address nftContract,
        uint tokenId,
        uint paymentAmount,
        address paymentToken,
        uint expiration
    ) external returns (uint listingId) {
        require(expiration > block.timestamp, "Expiration must be in the future");
        // Transfer the NFT into escrow
        ERC721(nftContract).transferFrom(msg.sender, address(this), tokenId);

        Listing memory listing = Listing({
            seller: msg.sender,
            nftContract: nftContract,
            tokenId: tokenId,
            paymentAmount: paymentAmount,
            paymentToken: paymentToken,
            expiration: expiration,
            available: true
        });

        listingId = nextListingId++;
        listings[listingId] = listing;

        emit NFTListed(msg.sender, nftContract, tokenId, paymentAmount, paymentToken, expiration, listingId);
    }

    /// @notice Purchases a listed NFT by paying the fixed ERC20 amount
    /// @param listingId ID of the listing to purchase
    function buyNFT(uint listingId) external {
        Listing memory listing = listings[listingId];

        require(listing.seller != address(0), "Listing does not exist");
        require(block.timestamp <= listing.expiration, "Listing expired");
        require(listing.available, "Listing is not available");
        // Transfer ERC20 from buyer to seller
        IERC20(listing.paymentToken).transferFrom(msg.sender, listing.seller, listing.paymentAmount);

        // Transfer NFT to buyer
        ERC721(listing.nftContract).transferFrom(address(this), msg.sender, listing.tokenId);

        listing.available = false;

        emit NFTPurchased(msg.sender, listing.nftContract, listing.tokenId, listingId);
    }

    /// @notice Cancels an existing NFT listing (only callable by seller)
    /// @param listingId ID of the listing to cancel
    function cancelListing(uint listingId) external {
        Listing memory listing = listings[listingId];

        require(listing.seller == msg.sender, "Only seller can cancel");

        // Return NFT to seller
        ERC721(listing.nftContract).transferFrom(address(this), listing.seller, listing.tokenId);

        listing.available = false;

        emit NFTListingCancelled(msg.sender, listing.nftContract, listing.tokenId, listingId);
    }
}
