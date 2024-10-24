// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { BaseNFT, ConfigHub } from "./base/BaseNFT.sol";
import { ICollarProviderNFT } from "./interfaces/ICollarProviderNFT.sol";

/**
 * @title CollarProviderNFT
 * @custom:security-contact security@collarprotocol.xyz
 *
 * Main Functionality:
 * 1. Allows liquidity providers to create and manage offers for a specific Taker contract.
 * 2. Mints NFTs representing provider positions when offers are taken allowing cancellations, rolls,
 *    and a secondary market for unexpired positions.
 * 3. Handles settlement and cancellation of positions.
 * 4. Manages withdrawals of settled positions.
 *
 * Role in the Protocol:
 * This contract acts as the interface for liquidity providers in the Collar Protocol.
 * It works in tandem with a corresponding CollarTakerNFT contract, which is trusted by this contract
 * to manage the taker side of position, as well as calculating the positions' payouts.
 *
 * Key Assumptions and Prerequisites:
 * 1. Liquidity providers must be able to receive ERC-721 tokens and withdraw offers or earnings
 *    from this contract.
 * 2. The associated taker contract is trusted and properly implemented.
 * 3. The ConfigHub contract correctly manages protocol parameters and authorization.
 * 4. Put strike percent is assumed to always equal the Loan-to-Value (LTV) ratio.
 * 5. Asset (ERC-20) contracts are simple, non rebasing, do not allow reentrancy, balance changes
 *    correspond to transfer arguments.
 */
contract CollarProviderNFT is ICollarProviderNFT, BaseNFT {
    using SafeERC20 for IERC20;

    uint internal constant BIPS_BASE = 10_000;
    uint public constant MIN_CALL_STRIKE_BIPS = BIPS_BASE + 1; // 1 more than 1x
    uint public constant MAX_CALL_STRIKE_BIPS = 10 * BIPS_BASE; // 10x or 1000%
    uint public constant MAX_PUT_STRIKE_BIPS = BIPS_BASE - 1; // 1 less than 1x

    string public constant VERSION = "0.2.0";

    // ----- IMMUTABLES ----- //
    IERC20 public immutable cashAsset;
    IERC20 public immutable underlying; // not used as ERC20 here
    // the trusted CollarTakerNFT contract. no interface is assumed because calls are only inbound
    address public immutable taker;

    // ----- STATE ----- //
    // @dev this is NOT the NFT id, this is separate ID for offers
    uint public nextOfferId = 1; // starts from 1 so that 0 ID is not used
    // non transferrable offers
    mapping(uint offerId => LiquidityOfferStored) internal liquidityOffers;
    // positionId is the NFT token ID (defined in BaseNFT)
    mapping(uint positionId => ProviderPositionStored) internal positions;

    constructor(
        address initialOwner,
        ConfigHub _configHub,
        IERC20 _cashAsset,
        IERC20 _underlying,
        address _taker,
        string memory _name,
        string memory _symbol
    ) BaseNFT(initialOwner, _name, _symbol) {
        cashAsset = _cashAsset;
        underlying = _underlying;
        taker = _taker;
        _setConfigHub(_configHub);
        emit CollarProviderNFTCreated(address(_cashAsset), address(_underlying), _taker);
    }

    modifier onlyTaker() {
        require(msg.sender == taker, "provider: unauthorized taker contract");
        _;
    }

    // ----- VIEWS ----- //

    /// @notice Returns the ID of the next provider position to be minted
    function nextPositionId() external view returns (uint) {
        return nextTokenId;
    }

    /// @notice Retrieves the details of a specific position (corresponds to the NFT token ID)
    function getPosition(uint positionId) public view returns (ProviderPosition memory) {
        ProviderPositionStored memory stored = positions[positionId];
        LiquidityOffer memory offer = getOffer(stored.offerId);
        return ProviderPosition({
            takerId: stored.takerId,
            offerId: stored.offerId,
            duration: offer.duration,
            expiration: stored.expiration,
            providerLocked: stored.providerLocked,
            putStrikePercent: offer.putStrikePercent,
            callStrikePercent: offer.callStrikePercent,
            settled: stored.settled,
            withdrawable: stored.withdrawable
        });
    }

    /// @notice Expiration time of a specific position
    /// @dev This is more gas efficient than SLOADing everything in getPosition if just expiration is needed
    function expiration(uint positionId) external view returns (uint) {
        return positions[positionId].expiration;
    }

    /// @notice Retrieves the details of a specific non-transferrable offer.
    function getOffer(uint offerId) public view returns (LiquidityOffer memory) {
        LiquidityOfferStored memory stored = liquidityOffers[offerId];
        return LiquidityOffer({
            provider: stored.provider,
            available: stored.available,
            duration: stored.duration,
            putStrikePercent: stored.putStrikePercent,
            callStrikePercent: stored.callStrikePercent,
            minLocked: stored.minLocked
        });
    }

    /// @notice Calculates the protocol fee charged from offers on position creation.
    /// @dev fee is set to 0 if recipient is zero because no transfer will be done
    function protocolFee(uint providerLocked, uint duration) public view returns (uint fee, address to) {
        to = configHub.feeRecipient();
        // prevents non-zero fee to zero-recipient.
        fee = to == address(0)
            ? 0
            // rounds up to prevent avoiding fee using many small positions.
            : Math.ceilDiv(providerLocked * configHub.protocolFeeAPR() * duration, BIPS_BASE * 365 days);
    }

    // ----- MUTATIVE ----- //

    // ----- Liquidity actions ----- //

    /// @notice Creates a new non transferrable liquidity offer of cash asset, for specific terms.
    /// The cash is held at the contract, but can be withdrawn at any time if unused.
    /// The caller MUST be able to handle ERC-721 and interact with this contract later.
    /// @param callStrikePercent The call strike percent in basis points
    /// @param amount The amount of cash asset to offer
    /// @param putStrikePercent The put strike percent in basis points
    /// @param duration The duration of the offer in seconds
    /// @param minLocked The minimum position amount. Protection from dust mints.
    /// @return offerId The ID of the newly created offer
    function createOffer(
        uint callStrikePercent,
        uint amount,
        uint putStrikePercent,
        uint duration,
        uint minLocked
    ) external whenNotPaused returns (uint offerId) {
        // sanity checks
        require(callStrikePercent >= MIN_CALL_STRIKE_BIPS, "provider: strike percent too low");
        require(callStrikePercent <= MAX_CALL_STRIKE_BIPS, "provider: strike percent too high");
        require(putStrikePercent <= MAX_PUT_STRIKE_BIPS, "provider: invalid put strike percent");

        offerId = nextOfferId++;
        liquidityOffers[offerId] = LiquidityOfferStored({
            provider: msg.sender,
            putStrikePercent: SafeCast.toUint24(putStrikePercent),
            callStrikePercent: SafeCast.toUint24(callStrikePercent),
            duration: SafeCast.toUint32(duration),
            minLocked: minLocked,
            available: amount
        });
        cashAsset.safeTransferFrom(msg.sender, address(this), amount);
        emit OfferCreated(
            msg.sender, putStrikePercent, duration, callStrikePercent, amount, offerId, minLocked
        );
    }

    /// @notice Updates the amount of an existing offer by either transferring from the offer
    /// owner into the contract (when the new amount is higher), or transferring to the owner from the
    /// contract when the new amount is lower. Only available to the original owner of the offer.
    /// @dev An offer is never deleted, so can always be reused if more cash is deposited into it.
    /// @param offerId The ID of the offer to update
    /// @param newAmount The new amount of cash asset for the offer
    function updateOfferAmount(uint offerId, uint newAmount) external whenNotPaused {
        LiquidityOfferStored storage offer = liquidityOffers[offerId];
        require(msg.sender == offer.provider, "provider: not offer provider");

        uint previousAmount = offer.available;
        if (newAmount > previousAmount) {
            // deposit more
            uint toAdd = newAmount - previousAmount;
            offer.available += toAdd;
            cashAsset.safeTransferFrom(msg.sender, address(this), toAdd);
        } else if (newAmount < previousAmount) {
            // withdraw
            uint toRemove = previousAmount - newAmount;
            offer.available -= toRemove;
            cashAsset.safeTransfer(msg.sender, toRemove);
        } else { } // no change
        emit OfferUpdated(offerId, msg.sender, previousAmount, newAmount);
    }

    // ----- Position actions ----- //

    // ----- actions through collar taker NFT ----- //

    /// @notice Mints a new position from an existing offer. Can ONLY be called through the
    /// taker contract, which is trusted to open and settle the offer according to the terms.
    /// Offer parameters are checked vs. the global config to ensure they are still supported.
    /// Protocol fee (based on the provider amount and duration) is deducted from offer, and sent
    /// to fee recipient. Offer amount is updated as well.
    /// The NFT, representing ownership of the position, is minted to original provider of the offer.
    /// @param offerId The ID of the offer to mint from
    /// @param providerLocked The amount of cash asset to use for the new position
    /// @param takerId The ID of the taker position for which this position is minted
    /// @return positionId The ID of the newly created position (NFT token ID)
    function mintFromOffer(uint offerId, uint providerLocked, uint takerId)
        external
        whenNotPaused
        onlyTaker
        returns (uint positionId)
    {
        // @dev only checked on open, not checked later on settle / cancel to allow withdraw-only mode.
        // not checked on createOffer, so invalid offers can be created but not minted from
        require(configHub.canOpenPair(underlying, cashAsset, msg.sender), "provider: unsupported taker");
        require(configHub.canOpenPair(underlying, cashAsset, address(this)), "provider: unsupported provider");

        LiquidityOffer memory offer = getOffer(offerId);
        // check terms
        uint ltv = offer.putStrikePercent; // assumed to be always equal
        require(configHub.isValidLTV(ltv), "provider: unsupported LTV");
        require(configHub.isValidCollarDuration(offer.duration), "provider: unsupported duration");

        // calc protocol fee to subtract from offer (on top of amount)
        (uint fee, address feeRecipient) = protocolFee(providerLocked, offer.duration);

        // check amount
        require(providerLocked >= offer.minLocked, "provider: amount too low");
        uint prevOfferAmount = offer.available;
        require(providerLocked + fee <= prevOfferAmount, "provider: amount too high");
        uint newAvailable = prevOfferAmount - providerLocked - fee;

        // storage updates
        liquidityOffers[offerId].available = newAvailable;
        positionId = nextTokenId++;
        positions[positionId] = ProviderPositionStored({
            offerId: SafeCast.toUint64(offerId),
            takerId: SafeCast.toUint64(takerId),
            expiration: SafeCast.toUint32(block.timestamp + offer.duration),
            settled: false, // unset until settlement
            providerLocked: providerLocked,
            withdrawable: 0 // unset until settlement
         });

        emit OfferUpdated(offerId, msg.sender, prevOfferAmount, newAvailable);

        // emit creation before transfer. No need to emit takerId, because it's emitted by the taker event
        emit PositionCreated(positionId, offerId, fee, providerLocked);

        // mint the NFT to the provider
        // @dev does not use _safeMint to avoid reentrancy
        _mint(offer.provider, positionId);

        // zero-fee transfer is prevented because recipient can be zero address, which reverts for many ERC20s.
        // zero-recipient for non-zero fee is prevented in protocolFee view.
        if (fee != 0) cashAsset.safeTransfer(feeRecipient, fee);
    }

    /// @notice Settles an existing position. Can ONLY be called through the
    /// taker contract, which is trusted to open and settle the offer according to the terms.
    /// Cash assets are transferred between this contract and the taker contract according to the
    /// settlement logic. The assets earned by the position become withdrawable by the NFT owner.
    /// @dev note that settlement MUST NOT trigger a withdrawal to the provider. This is because
    /// this method is called via the taker contract and can be called by anyone.
    /// Allowing a third-party caller to trigger transfer of funds on behalf of the provider
    /// introduces several risks: 1) if the provider is a contract it may have its own bookkeeping,
    /// 2) if the NFT is traded on a NFT-market or in an escrow - that contract will not handle
    /// settlement funds correctly 3) the provider may want to choose the timing or destination
    /// of the withdrawal themselves 4) In the NFT-market case, this can be used to front-run an order
    /// because it changes the underlying value of the NFT. Conversely, withdrawal (later) must burn the NFT
    /// to prevent the last issue.
    /// The funds that are transferred here are between the two contracts, and don't change the value
    /// of the NFT abruptly (only prevent settlement at future price).
    /// @param positionId The ID of the position to settle (NFT token ID)
    /// @param cashDelta The change in position value (positive or negative)
    function settlePosition(uint positionId, int cashDelta) external whenNotPaused onlyTaker {
        ProviderPositionStored storage position = positions[positionId];

        require(position.expiration != 0, "provider: position does not exist");
        // taker will check expiry, but this ensures an invariant and guards against taker bugs
        require(block.timestamp >= position.expiration, "provider: not expired");

        require(!position.settled, "provider: already settled");
        position.settled = true; // done here as CEI

        uint initial = position.providerLocked;
        if (cashDelta > 0) {
            uint toAdd = uint(cashDelta);
            position.withdrawable = initial + toAdd;
            // the taker owes us some tokens, requires approval
            cashAsset.safeTransferFrom(taker, address(this), toAdd);
        } else {
            // handles no-change as well (zero-value-transfer ok)
            uint toRemove = uint(-cashDelta); // will revert for type(int).min
            require(toRemove <= initial, "provider: loss is too high");
            position.withdrawable = initial - toRemove;
            // we owe the taker some tokens
            cashAsset.safeTransfer(taker, toRemove);
        }

        emit PositionSettled(positionId, cashDelta, position.withdrawable);
    }

    /// @notice Cancels a position and withdraws providerLocked to current owner. Burns the NFT.
    /// Can ONLY be called through the taker, which should check that BOTH NFTs are owned by its caller.
    /// This contract double-checks that this NFT was approved to taker by the owner
    /// when the call is made (which ensures a consenting provider).
    /// @dev note that a withdrawal is triggerred (and the NFT is burned) because in contrast
    /// to settlement, during cancellation the taker's caller MUST be the NFT owner (is the provider),
    /// so is assumed to specify the withdrawal correctly for their funds.
    /// @param positionId The ID of the position to cancel (NFT token ID)
    function cancelAndWithdraw(uint positionId) external whenNotPaused onlyTaker returns (uint withdrawal) {
        ProviderPositionStored storage position = positions[positionId];
        require(position.expiration != 0, "provider: position does not exist");
        require(!position.settled, "provider: already settled");

        /* @dev Ensure caller is BOTH taker contract (`onlyTaker`), and was approved by NFT owner
        While taker contract is trusted here, and must check ownership of BOTH tokens, its this contract's
        responsibility (and invariant) to ensure the token owner's consent to cancel.
        While it can't check that the owner is taker's caller, it can at least check an approval to guard
        against taker implementation bug. Here `_isAuthorized` returns `true` if `msg.sender` is:
            1) owner
            2) operator (isApprovedForAll for owner)
            3) was approved for the specific ID (getApproved for positionId).
        */
        bool callerApprovedForId = _isAuthorized(ownerOf(positionId), msg.sender, positionId);
        require(callerApprovedForId, "provider: caller not approved for ID");

        // store changes
        position.settled = true; // done here as CEI

        // burn token
        _burn(positionId);

        withdrawal = position.providerLocked;
        cashAsset.safeTransfer(msg.sender, withdrawal);

        emit PositionCanceled(positionId, withdrawal, position.expiration);
    }

    // ----- actions by position owner ----- //

    /// @notice Withdraws funds from a settled position. Can only be called for a settled position
    /// (and not a cancelled one), and checks the ownership of the NFT. Burns the NFT.
    /// @param positionId The ID of the settled position to withdraw from (NFT token ID).
    function withdrawFromSettled(uint positionId) external whenNotPaused returns (uint withdrawal) {
        require(msg.sender == ownerOf(positionId), "provider: not position owner");

        ProviderPositionStored storage position = positions[positionId];
        require(position.settled, "provider: not settled");

        withdrawal = position.withdrawable;
        // zero out withdrawable
        position.withdrawable = 0;
        // burn token
        _burn(positionId);
        // transfer tokens
        cashAsset.safeTransfer(msg.sender, withdrawal);

        emit WithdrawalFromSettled(positionId, withdrawal);
    }
}
