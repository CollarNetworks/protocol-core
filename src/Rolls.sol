// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { SignedMath } from "@openzeppelin/contracts/utils/math/SignedMath.sol";

import { CollarTakerNFT, CollarProviderNFT } from "./CollarTakerNFT.sol";
import { BaseManaged } from "./base/BaseManaged.sol";
import { IRolls } from "./interfaces/IRolls.sol";

/**
 * @title Rolls
 * @dev This contract manages the "rolling" of existing collar positions before expiry to new strikes and
 * expiry.
 *
 * Main Functionality:
 * 1. Allows providers to create and cancel roll offers for existing positions.
 * 2. Allows takers to execute rolls, cancelling existing collar positions and creating new ones
 *    with updated terms.
 * 4. Manages the transfer of funds between takers and providers during rolls.
 *
 * Role in the Protocol:
 * Allows for the extension or modification of existing positions prior to expiry if both parties agree.
 *
 * Key Assumptions and Prerequisites:
 * 1. The CollarTakerNFT and CollarProviderNFT contracts are correctly implemented and authorized.
 * 2. The cash asset (ERC-20) used is simple (non-rebasing, no transfer fees, no callbacks).
 * 3. Providers must approve this contract to transfer their CollarProviderNFTs and cash when creating
 * an offer. The NFT is transferred on offer creation, and cash will be transferred on execution, if
 * and when the taker accepts the offer.
 * 4. Takers must approve this contract to transfer their CollarTakerNFTs and any cash that's needed
 * to be pulled.
 *
 * Security Considerations:
 * 1. Does not hold cash (only during execution), but will have approvals to spend cash.
 * 2. Signed integers are used for many input and output values, and proper care should be
 * taken in understanding the semantics of the positive and negative values.
 */
contract Rolls is IRolls, BaseManaged {
    using SafeERC20 for IERC20;
    using SafeCast for uint;

    uint internal constant BIPS_BASE = 10_000;

    string public constant VERSION = "0.2.0";

    // ----- IMMUTABLES ----- //
    CollarTakerNFT public immutable takerNFT;
    IERC20 public immutable cashAsset;

    // ----- STATE VARIABLES ----- //

    uint public nextRollId = 1; // starts from 1 so that 0 ID is not used

    mapping(uint rollId => RollOffer) internal rollOffers;

    /// @dev Rolls needs BaseManaged for pausing since is approved by users, and holds NFTs.
    /// Does not need `canOpen` auth because its auth usage is set directly on Loans,
    /// and it has no long-lived functionality so doesn't need a close-only migration mode.
    constructor(address initialOwner, CollarTakerNFT _takerNFT) BaseManaged(initialOwner) {
        takerNFT = _takerNFT;
        cashAsset = _takerNFT.cashAsset();
        _setConfigHub(_takerNFT.configHub());
    }

    // ----- VIEW FUNCTIONS ----- //

    /// @dev return memory struct (the default getter returns tuple)
    function getRollOffer(uint rollId) external view returns (RollOffer memory) {
        return rollOffers[rollId];
    }

    /**
     * @notice Calculates the roll fee based on the price
     * @dev The fee changes based on the price change since the offer was created.
     * All three of - price change, roll fee, and delta-factor - can be negative. The fee is adjusted
     * such that positive `price-change x delta-factor` increases the fee (provider benefits),
     * and negative decreases the fee (taker benefits).
     * 0 delta-factor means the fee is constant, 100% delta-factor (10_000 in bips), means the price
     * linearly scales the fee (according to the sign logic).
     * @param offer The roll offer to calculate the fee for
     * @param price The price to use for the calculation, in ITakerOracle price units
     * @return rollFee The calculated roll fee (in cash amount), positive if paid to provider
     */
    function calculateRollFee(RollOffer memory offer, uint price) public pure returns (int rollFee) {
        int prevPrice = offer.feeReferencePrice.toInt256();
        int priceChange = price.toInt256() - prevPrice;
        // Scaling the fee magnitude by the delta (price change) multiplied by the factor.
        // For deltaFactor of 100%, this results in linear scaling of the fee with price.
        // So for BIPS_BASE the result moves with the price. E.g., 5% price increase, 5% fee increase.
        // If factor is, e.g., 50% the fee increases only 2.5% for a 5% price increase.
        int feeSize = SignedMath.abs(offer.feeAmount).toInt256();
        int change = feeSize * offer.feeDeltaFactorBIPS * priceChange / prevPrice / int(BIPS_BASE);
        // Apply the change depending on the sign of the delta * price-change.
        // Positive factor means provider gets more money with higher price.
        // Negative factor means user gets more money with higher price.
        // E.g., if the fee is -5, the sign of the factor specifies whether provider gains (+5% -> -4.75)
        // or user gains (+5% -> -5.25) with price increase.
        rollFee = offer.feeAmount + change;
    }

    /**
     * @notice Calculates the amounts to be transferred during a roll execution at a specific price.
     * This does not check any validity conditions (existence, deadline, price range, etc...).
     * @dev If validity is important, a staticcall to the executeRoll method should be used instead of
     * this view.
     * @param rollId The ID of the roll offer
     * @param price The price to use for the calculation
     * @return toTaker The amount that would be transferred to (or from, if negative) the taker
     * @return toProvider The amount that would be transferred to (or from, if negative) the provider
     * @return rollFee The roll fee that would be applied
     */
    function previewTransferAmounts(uint rollId, uint price)
        external
        view
        returns (int toTaker, int toProvider, int rollFee)
    {
        RollOffer memory offer = rollOffers[rollId];
        rollFee = calculateRollFee(offer, price);
        (toTaker, toProvider) = _previewTransferAmounts(offer.takerId, price, rollFee);
    }

    // ----- MUTATIVE FUNCTIONS ----- //

    /**
     * @notice Creates a new roll offer for an existing taker NFT position and pulls the provider NFT.
     * @dev The provider must own the CollarProviderNFT for the position to be rolled
     * @param takerId The ID of the CollarTakerNFT position to be rolled
     * @param feeAmount The base fee for the roll, can be positive (paid by taker) or
     *     negative (paid by provider)
     * @param feeDeltaFactorBIPS How much the fee changes with price, in basis points, can be
     *     negative. Positive means asset price increase benefits provider, and negative benefits user.
     * @param minPrice The minimum acceptable price for roll execution
     * @param maxPrice The maximum acceptable price for roll execution
     * @param minToProvider The minimum amount the provider is willing to receive, or maximum willing to pay
     *     if negative. The execution transfer (in or out) will be checked to be >= this value.
     * @param deadline The timestamp after which this offer can no longer be created or executed
     * @return rollId The ID of the newly created roll offer
     *
     * @dev if the provider will need to provide cash on execution, they must approve the contract to pull that
     * cash when submitting the offer (and have those funds available), so that it is executable.
     * If offer becomes unexecutable due to insufficient provider cash approval or balance it should ideally be
     * filtered out by the FE as not executable (and provider be made aware).
     */
    function createOffer(
        uint takerId,
        int feeAmount,
        int feeDeltaFactorBIPS,
        // provider protection
        uint minPrice,
        uint maxPrice,
        int minToProvider,
        uint deadline
    ) external whenNotPaused returns (uint rollId) {
        // taker position is valid
        CollarTakerNFT.TakerPosition memory takerPos = takerNFT.getPosition(takerId);
        require(takerPos.expiration != 0, "taker position doesn't exist");
        require(!takerPos.settled, "taker position settled");
        require(block.timestamp <= takerPos.expiration, "taker position expired");

        CollarProviderNFT providerNFT = takerPos.providerNFT;
        uint providerId = takerPos.providerId;
        // caller is owner
        require(msg.sender == providerNFT.ownerOf(providerId), "not provider ID owner");

        // sanity check bounds
        require(minPrice <= maxPrice, "max price lower than min price");
        require(SignedMath.abs(feeDeltaFactorBIPS) <= BIPS_BASE, "invalid fee delta change");
        require(block.timestamp <= deadline, "deadline passed");

        // pull the NFT
        providerNFT.transferFrom(msg.sender, address(this), providerId);

        // store the offer
        rollId = nextRollId++;
        rollOffers[rollId] = RollOffer({
            takerId: takerId,
            feeAmount: feeAmount,
            feeDeltaFactorBIPS: feeDeltaFactorBIPS,
            feeReferencePrice: takerNFT.currentOraclePrice(), // the roll offer fees are for current price
            minPrice: minPrice,
            maxPrice: maxPrice,
            minToProvider: minToProvider,
            deadline: deadline,
            providerNFT: providerNFT,
            providerId: providerId,
            provider: msg.sender,
            active: true
        });

        emit OfferCreated(takerId, msg.sender, providerNFT, providerId, feeAmount, rollId);
    }

    /**
     * @notice Cancels an existing roll offer and returns the provider NFT to the sender.
     * @dev Can only be called by the original offer creator
     * @param rollId The ID of the roll offer to cancel
     *
     * @dev only cancel and no updating, to prevent frontrunning a user's acceptance
     * The risk of update is different here from providerNFT.updateOfferAmount because
     * the most an update can cause there is a revert of taking the offer.
     */
    function cancelOffer(uint rollId) external whenNotPaused {
        RollOffer storage offer = rollOffers[rollId];
        require(msg.sender == offer.provider, "not offer provider");
        require(offer.active, "offer not active");
        // cancel offer
        offer.active = false;
        // return the NFT
        offer.providerNFT.transferFrom(address(this), msg.sender, offer.providerId);
        emit OfferCancelled(rollId, offer.takerId, offer.provider);
    }

    /**
     * @notice Executes a roll, settling the existing paired position and creating a new one.
     * This pulls cash, pulls taker NFT, sends out new taker and provider NFTs, and pays cash.
     * @dev The caller must be the owner of the CollarTakerNFT for the position being rolled,
     * and must have approved sufficient cash if cash needs to be paid (depends on offer and current price)
     * @param rollId The ID of the roll offer to execute
     * @param minToTaker The minimum amount the user (taker) is willing to receive, or maximum willing to
     *     pay if negative. The transfer (in or out, signed int too) will be checked to be >= this value.
     * @return newTakerId The ID of the newly created CollarTakerNFT position
     * @return newProviderId The ID of the newly created CollarProviderNFT position
     * @return toTaker The amount transferred to (or from, if negative) the taker
     * @return toProvider The amount transferred to (or from, if negative) the provider
     */
    function executeRoll(uint rollId, int minToTaker)
        external
        whenNotPaused
        returns (uint newTakerId, uint newProviderId, int toTaker, int toProvider)
    {
        RollOffer memory offer = rollOffers[rollId];

        // offer doesn't exist, was cancelled, or executed
        require(offer.active, "invalid offer");
        // auth, will revert if takerId was burned already
        require(msg.sender == takerNFT.ownerOf(offer.takerId), "not taker ID owner");

        // @dev an expired position should settle at some past price, so if rolling after expiry is allowed,
        // a different price may be used in settlement calculations instead of current price.
        // This is prevented by this check, since supporting the complexity of such scenarios is not needed.
        uint expiration = takerNFT.getPosition(offer.takerId).expiration;
        require(block.timestamp <= expiration, "taker position expired");

        // offer is within its terms
        uint newPrice = takerNFT.currentOraclePrice();
        require(newPrice <= offer.maxPrice, "price too high");
        require(newPrice >= offer.minPrice, "price too low");
        require(block.timestamp <= offer.deadline, "deadline passed");

        // @dev only this line writes to storage. Update storage here for CEI
        rollOffers[rollId].active = false;

        int rollFee = calculateRollFee(offer, newPrice);

        // preview the transfer amounts first, because cash may need to be pulled first
        (toTaker, toProvider) = _previewTransferAmounts(offer.takerId, newPrice, rollFee);
        // check transfers are sufficient / or pulls are not excessive. Only the preview
        // values will be used to pull / pay cash, so checking them is correct.
        // This contract does not hold any resting balance, so no other assets are available.
        // If preview amounts do not match actual amounts, _executeRoll will revert.
        require(toTaker >= minToTaker, "taker transfer slippage");
        require(toProvider >= offer.minToProvider, "provider transfer slippage");

        (newTakerId, newProviderId) = _executeRoll(offer, newPrice, toTaker, toProvider);

        emit OfferExecuted(rollId, toTaker, toProvider, rollFee, newTakerId, newProviderId);
    }

    // ----- INTERNAL MUTATIVE ----- //

    function _executeRoll(RollOffer memory offer, uint newPrice, int toTaker, int toProvider)
        internal
        returns (uint newTakerId, uint newProviderId)
    {
        // pull the taker NFT from the user (we already have the provider NFT)
        takerNFT.transferFrom(msg.sender, address(this), offer.takerId);

        // now that we have both NFTs, cancel the positions and withdraw
        _cancelPairedPositionAndWithdraw(offer.takerId);

        // pull cash as needed. This needs to be done before opening new positions
        address provider = offer.provider;
        // assumes approval from the taker, Reverts for type(int).min
        if (toTaker < 0) cashAsset.safeTransferFrom(msg.sender, address(this), uint(-toTaker));
        // assumes approval from the provider. Reverts for type(int).min
        if (toProvider < 0) cashAsset.safeTransferFrom(provider, address(this), uint(-toProvider));

        // open the new positions
        (newTakerId, newProviderId) = _openNewPairedPosition(newPrice, offer.takerId);

        // pay cash as needed
        if (toTaker > 0) cashAsset.safeTransfer(msg.sender, uint(toTaker));
        if (toProvider > 0) cashAsset.safeTransfer(provider, uint(toProvider));

        // we now own both of the new NFT IDs, so send them out to their new proud owners
        takerNFT.transferFrom(address(this), msg.sender, newTakerId);
        offer.providerNFT.transferFrom(address(this), offer.provider, newProviderId);
    }

    function _cancelPairedPositionAndWithdraw(uint takerId) internal {
        CollarTakerNFT.TakerPosition memory takerPos = takerNFT.getPosition(takerId);
        // approve the takerNFT to pull the provider NFT, as both NFTs are needed for cancellation
        takerPos.providerNFT.approve(address(takerNFT), takerPos.providerId);
        // cancel and withdraw the cash from the existing paired position
        // @dev this relies on being the owner of both NFTs. it burns both NFTs, and withdraws
        // both put and locked cash to this contract
        uint withdrawn = takerNFT.cancelPairedPosition(takerId);
        uint expectedAmount = takerPos.takerLocked + takerPos.providerLocked;
        // @dev this invariant is assumed by the transfer calculations
        require(withdrawn == expectedAmount, "unexpected withdrawal amount");
    }

    function _openNewPairedPosition(uint newPrice, uint takerId)
        internal
        returns (uint newTakerId, uint newProviderId)
    {
        CollarTakerNFT.TakerPosition memory takerPos = takerNFT.getPosition(takerId);
        CollarProviderNFT providerNFT = takerPos.providerNFT;
        CollarProviderNFT.ProviderPosition memory providerPos = providerNFT.getPosition(takerPos.providerId);

        // calculate locked amounts for new positions
        (uint newTakerLocked, uint newProviderLocked) = _newLockedAmounts(takerPos, providerPos, newPrice);

        // add the protocol fee that will be taken from the offer
        (uint protocolFee,) = providerNFT.protocolFee(newProviderLocked, takerPos.duration);
        uint offerAmount = newProviderLocked + protocolFee;

        // create a liquidity offer just for this roll
        cashAsset.forceApprove(address(providerNFT), offerAmount);
        uint liquidityOfferId = providerNFT.createOffer({
            callStrikePercent: providerPos.callStrikePercent,
            amount: offerAmount,
            putStrikePercent: providerPos.putStrikePercent,
            duration: takerPos.duration
        });

        // take the liquidity offer as taker
        cashAsset.forceApprove(address(takerNFT), newTakerLocked);
        (newTakerId, newProviderId) =
            takerNFT.openPairedPosition(newTakerLocked, providerNFT, liquidityOfferId);
    }

    // ----- INTERNAL VIEWS ----- //

    /// @dev calculates everything that will happen in _executeRoll. This assumes full, down to the wei,
    /// match of all amounts between "preview" and actual "execution". If implementations change, a different
    /// Rolls contracts will need to be used for them. Roll contracts are assumed
    /// to be easy to replace and migrate (only unexecuted offers need to be cancelled)
    function _previewTransferAmounts(uint takerId, uint newPrice, int rollFeeAmount)
        internal
        view
        returns (int toTaker, int toProvider)
    {
        CollarTakerNFT.TakerPosition memory takerPos = takerNFT.getPosition(takerId);
        CollarProviderNFT providerNFT = takerPos.providerNFT;
        CollarProviderNFT.ProviderPosition memory providerPos = providerNFT.getPosition(takerPos.providerId);

        // what would the taker and provider get from a settlement of the old position at current price
        (uint takerSettled, int providerGain) = takerNFT.previewSettlement(takerId, newPrice);
        // provider settled is locked + its settlement gain
        int providerSettled = takerPos.providerLocked.toInt256() + providerGain;

        // what are the new locked amounts as they will be calculated when opening the new positions
        (uint newTakerLocked, uint newProviderLocked) = _newLockedAmounts(takerPos, providerPos, newPrice);

        // new protocol fee. @dev there is no refund for previously paid protocol fee
        (uint protocolFee,) = providerNFT.protocolFee(newProviderLocked, takerPos.duration);

        // The taker and provider external balances (before fee) should be updated as if
        // they settled and withdrawn the old positions, and opened the new positions.
        // The roll-fee is paid to the provider by the taker, and can represent any arbitrary adjustment
        // to this (that's expressed by the offer).
        toTaker = takerSettled.toInt256() - newTakerLocked.toInt256() - rollFeeAmount;
        toProvider = providerSettled - newProviderLocked.toInt256() + rollFeeAmount - protocolFee.toInt256();

        /*  Proof.

            Vars:
                Ts: takerSettled, Ps: providerSettled, put: newTakerLocked,
                call: newProviderLocked, rollFee: rollFee, proFee: protocolFee

            After settlement (after cancelling and withdrawing old position):
                Contract balance = Ts + Ps

            Then contract receives / pays:
            1.  toPairedPosition =           put + call
            2.  toTaker          = Ts      - put        - rollFee
            3.  toProvider       =      Ps       - call + rollFee - proFee
            4.  toProtocol       =                                + proFee

            All payments summed  = Ts + Ps

            So the contract pays out everything it receives, and everyone gets their correct updates.
        */
    }

    // @dev the amounts needed for a new position given the old position
    function _newLockedAmounts(
        CollarTakerNFT.TakerPosition memory takerPos,
        CollarProviderNFT.ProviderPosition memory providerPos,
        uint newPrice
    ) internal view returns (uint newTakerLocked, uint newProviderLocked) {
        // New position is determined by calculating newTakerLocked, since it is the input argument.
        // Scale up using price to maintain same level of exposure to underlying asset.
        // The reason this needs to be scaled with price, is that this can should fit the loans use-case
        // where the position should track the value of the initial amount of underlying asset
        // (price exposure), instead of (for example) initial cash amount.
        newTakerLocked = takerPos.takerLocked * newPrice / takerPos.startPrice; // zero start price is invalid and will cause panic
        // use the method that CollarTakerNFT will use to calculate the provider part
        newProviderLocked = takerNFT.calculateProviderLocked(
            newTakerLocked, providerPos.putStrikePercent, providerPos.callStrikePercent
        );
    }
}
