// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity 0.8.21;

// OZ
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {
    ERC721, ERC721Enumerable
} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import { ERC721Pausable } from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Pausable.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
// internal
import { CollarEngine } from "./implementations/CollarEngine.sol";

contract LenderPosition is Ownable, ERC721, ERC721Enumerable, ERC721Pausable {
    using SafeERC20 for IERC20;

    // ----- IMMUTABLES ----- //
    CollarEngine public immutable engine;
    IERC20 public immutable cashAsset;
    IERC20 public immutable collateralAsset;
    uint public immutable duration;
    uint public immutable ltv;
    address public immutable borrowPositionContract;

    // ----- State ----- //
    uint public nextPositionId; // NFT token ID

    uint public nextOfferId; // non transferrable

    struct Position {
        // terms
        uint expiration;
        uint principal;
        uint strikeDeviation;
        // withdrawal
        bool finalized;
        uint withdrawable;
    }

    mapping(uint positionId => Position) public positions;

    struct Liquidity {
        address provider;
        uint available;
        // terms
        uint strikeDeviation;
    }
    // TODO: duration, ltv should be part of offer instead of part of config??

    mapping(uint offerId => Liquidity) public liquidityOffers;

    // TODO: add liquidity info mappings for frontend's needs: strikes to offers, strikes to totals

    constructor(
        address initialOwner,
        CollarEngine _engine,
        IERC20 _cashAsset,
        IERC20 _collateralAsset,
        uint _duration,
        uint _ltv,
        address _borrowPositionContract,
        string memory _name,
        string memory _symbol
    )
        ERC721(_name, _symbol)
        Ownable(initialOwner)
    {
        engine = _engine;
        cashAsset = _cashAsset;
        collateralAsset = _collateralAsset;
        duration = _duration;
        ltv = _ltv;
        borrowPositionContract = _borrowPositionContract;
        // check params are supported
        validateConfig();
    }

    /// @dev used by openPosition, and can be used externally to check this is available
    function validateConfig() public view {
        require(engine.isValidLTV(ltv), "invalid LTV");
        require(engine.isSupportedCashAsset(address(cashAsset)), "unsupported asset");
        require(engine.isSupportedCollateralAsset(address(collateralAsset)), "unsupported asset");
        require(engine.isValidCollarDuration(duration), "unsupported duration");
        validateBorrowingContractTrusted();
    }

    function validateBorrowingContractTrusted() public view {
        // TODO: use the right auth view instead of isVaultManager
        require(engine.isVaultManager(borrowPositionContract), "unsupported duration");
    }

    // ----- MUTATIVE ----- //

    // ----- Liquidity ----- //

    function createOffer(uint strikeDeviation, uint amount) external whenNotPaused returns (uint offerId) {
        // TODO validation: strikeDeviation
        // TODO validate provider can receive NFTs (via the same check that's in _safeMint)
        offerId = nextOfferId++;
        liquidityOffers[offerId] =
            Liquidity({ provider: msg.sender, available: amount, strikeDeviation: strikeDeviation });
        cashAsset.safeTransferFrom(msg.sender, address(this), amount);
        // TODO: event
    }

    function updateOfferAmount(uint offerId, uint newAmount) public whenNotPaused {
        require(msg.sender == liquidityOffers[offerId].provider, "not offer provider");
        uint currentAmount = liquidityOffers[offerId].available;

        if (newAmount > currentAmount) {
            // deposit more
            uint toAdd = newAmount - currentAmount;
            liquidityOffers[offerId].available += toAdd;
            cashAsset.safeTransferFrom(msg.sender, address(this), toAdd);
        } else if (newAmount < currentAmount) {
            // withdraw
            uint toRemove = currentAmount - newAmount;
            liquidityOffers[offerId].available -= toRemove;
            cashAsset.safeTransfer(msg.sender, toRemove);
        } else {
            // no change
        }
        // TODO: event prev amount, new amount
    }

    //    /// TODO: optional convenience around updateOfferAmount, enable and test after updateOfferAmount is
    // tested
    //    function withdrawOffer(uint offerId) external {
    //        // cast is safe because updateOfferAmount assumed to validate amount
    //        // @dev this doesn't "delete" anything, and offer can be re-filled later if needed
    //        updateOfferAmount(offerId, -int(liquidityOffers[offerId].available));
    //    }

    // ----- Positions ----- //

    function openPosition(
        uint offerId,
        uint amount
    )
        external
        whenNotPaused
        returns (uint positionId, Position memory position)
    {
        validateConfig(); // ensure values are still allowed by the config

        require(msg.sender == borrowPositionContract, "only borrow contract");

        Liquidity storage offer = liquidityOffers[offerId];

        // handle liquidity
        /// @dev this will revert if request is for too much
        offer.available -= amount;

        // create position
        position = Position({
            expiration: block.timestamp + duration,
            principal: amount,
            strikeDeviation: offer.strikeDeviation,
            finalized: false,
            withdrawable: 0
        });

        positionId = nextPositionId++;
        // store position data
        positions[positionId] = position;
        // mint the NFT to the provider
        // @dev does not use _safeMint to avoid reentrancy
        _mint(offer.provider, positionId);

        // TODO: emit event
        return (positionId, position);
    }

    //  TODO: optional convenience for saving on repeated validation checks. add and test after openPosition
    // is tested
    //    function openPositions(uint[] memory offerId, uint[] memory amount)
    //        external
    //        returns (uint[] memory positionIds, Position[] memory positions)
    //    {
    //      // refactor non-validation logic into _openPosition and loop it here
    //    }

    function settlePosition(uint positionId, int positionNet) external whenNotPaused {
        // don't validate full config because maybe some values are no longer supported
        validateBorrowingContractTrusted();
        require(msg.sender == borrowPositionContract, "unauthorized borrow contract");

        Position storage position = positions[positionId];

        require(block.timestamp >= position.expiration, "position not finalizable");
        require(!position.finalized, "already finalized");

        position.finalized = true; // done here as this also acts as reentrancy protection

        uint withdrawable = position.principal;
        if (positionNet < 0) {
            uint toRemove = uint(-positionNet);
            /// @dev will revert if too much is requested
            withdrawable -= toRemove;
            // we owe the borrower some tokens
            cashAsset.safeTransfer(borrowPositionContract, toRemove);
        } else if (positionNet > 0) {
            uint toAdd = uint(positionNet);
            withdrawable += toAdd;
            // the borrower owes us some tokens, requires approval
            cashAsset.safeTransferFrom(borrowPositionContract, address(this), toAdd);
        } else {
            // no change
        }

        // store the updated state
        position.withdrawable = withdrawable;
        // TODO: emit event
    }

    function withdrawSettled(uint positionId) external whenNotPaused {
        require(msg.sender == ownerOf(positionId), "not position owner");

        Position storage position = positions[positionId];
        require(position.finalized, "not finalized");

        uint withdrawable = position.withdrawable;
        // zero out withdrawable
        position.withdrawable = 0;
        // burn token
        _burn(positionId);
        // transfer tokens
        cashAsset.safeTransfer(msg.sender, withdrawable);
        // TODO: emit event
    }

    /// @dev for unwinds / rolls when the borrow contract is also the owner of this NFT
    /// callable through borrow position because only it is receiver of funds
    function cancelPosition(uint positionId) external whenNotPaused {
        // don't validate full config because maybe some values are no longer supported
        validateBorrowingContractTrusted();
        require(msg.sender == borrowPositionContract, "unauthorized borrow contract");
        require(borrowPositionContract == ownerOf(positionId), "caller does not own token");

        Position storage position = positions[positionId];

        require(!position.finalized, "already finalized");
        position.finalized = true; // done here as this also acts as reentrancy protection

        // burn token
        _burn(positionId);

        cashAsset.safeTransfer(borrowPositionContract, position.principal);
        // TODO: emit event
    }

    // ----- INTERNAL MUTATIVE ----- //

    // Emergency actions

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    // Internal overrides required by Solidity for ERC721

    function _update(
        address to,
        uint tokenId,
        address auth
    )
        internal
        override(ERC721, ERC721Enumerable, ERC721Pausable)
        returns (address)
    {
        return super._update(to, tokenId, auth);
    }

    function _increaseBalance(address account, uint128 value) internal override(ERC721, ERC721Enumerable) {
        super._increaseBalance(account, value);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}