// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import { ConfigHub, BaseNFT, CollarProviderNFT, Math, IERC20, SafeERC20 } from "./CollarProviderNFT.sol";
import { ITakerOracle } from "./interfaces/ITakerOracle.sol";
import { ICollarTakerNFT } from "./interfaces/ICollarTakerNFT.sol";
import { ICollarProviderNFT } from "./interfaces/ICollarProviderNFT.sol";

/**
 * @title CollarTakerNFT
 * @custom:security-contact security@collarprotocol.xyz
 *
 * Main Functionality:
 * 1. Manages the taker side of collar positions - handling position creation and settlement.
 * 2. Mints NFTs representing taker positions, allowing cancellations, rolls,
 *    and a secondary market for unexpired positions.
 * 3. Settles positions at expiry by calculating final payouts using oracle prices.
 * 4. Handles cancellation and withdrawal of settled positions.
 *
 * Role in the Protocol:
 * This contract acts as the core engine for the Collar Protocol, working in tandem with
 * CollarProviderNFT to create zero-sum paired positions. It holds and calculates the taker's side of
 * collars, which is typically wrapped by LoansNFT to create loan positions.
 *
 * Key Assumptions and Prerequisites:
 * 1. Takers must be able to receive ERC-721 tokens to withdraw earnings.
 * 2. The allowed provider contracts are trusted and properly implemented.
 * 3. The ConfigHub contract correctly manages protocol parameters and authorization.
 * 4. Asset (ERC-20) contracts are simple, non rebasing, do not allow reentrancy, balance changes
 *    correspond to transfer arguments.
 * 5. nonReentrant is used on all balance changing methods to prevent a malicious ProviderNFT
 *    from fooling balance checks.
 *
 * Post-Deployment Configuration:
 * - Oracle: If using Uniswap ensure adequate observation cardinality, if using Chainlink ensure correct config.
 * - ConfigHub: Set setCanOpenPair() to authorize this contract for its asset pair [underlying, cash, taker]
 * - ConfigHub: Set setCanOpenPair() to authorize the provider contract [underlying, cash, provider]
 * - CollarProviderNFT: Ensure properly configured
 */
contract CollarTakerNFT is ICollarTakerNFT, BaseNFT, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using SafeCast for uint;

    uint internal constant BIPS_BASE = 10_000;

    /// @notice delay after expiry when positions can be settled to their original locked values.
    /// This is needed for the case of a prolonged oracle failure.
    uint public constant SETTLE_AS_CANCELLED_DELAY = 1 weeks;

    string public constant VERSION = "0.3.0";

    // ----- IMMUTABLES ----- //
    IERC20 public immutable cashAsset;
    IERC20 public immutable underlying; // not used as ERC20 here
    ITakerOracle public immutable oracle;

    // ----- STATE VARIABLES ----- //
    mapping(uint positionId => TakerPositionStored) internal positions;

    constructor(
        ConfigHub _configHub,
        IERC20 _cashAsset,
        IERC20 _underlying,
        ITakerOracle _oracle,
        string memory _name,
        string memory _symbol
    ) BaseNFT(_name, _symbol, _configHub) {
        cashAsset = _cashAsset;
        underlying = _underlying;
        _checkOracle(_oracle);
        oracle = _oracle;
    }

    // ----- VIEW FUNCTIONS ----- //

    /// @notice Returns the ID of the next taker position to be minted
    function nextPositionId() external view returns (uint) {
        return nextTokenId;
    }

    /// @notice Retrieves the details of a specific position (corresponds to the NFT token ID)
    function getPosition(uint takerId) public view returns (TakerPosition memory) {
        TakerPositionStored memory stored = positions[takerId];
        // do not try to call non-existent provider
        require(address(stored.providerNFT) != address(0), "taker: position does not exist");
        // @dev the provider position fields used here are assumed to be immutable (set once).
        // @dev a provider contract that manipulates these values should only be able to affect positions
        // that are paired with it, but no other positions or funds.
        ICollarProviderNFT.ProviderPosition memory providerPos =
            stored.providerNFT.getPosition(stored.providerId);
        return TakerPosition({
            providerNFT: stored.providerNFT,
            providerId: stored.providerId,
            duration: providerPos.duration, // comes from the offer, implicitly checked with expiration
            expiration: providerPos.expiration, // checked to match on creation
            startPrice: stored.startPrice,
            putStrikePercent: providerPos.putStrikePercent,
            callStrikePercent: providerPos.callStrikePercent,
            takerLocked: stored.takerLocked,
            providerLocked: providerPos.providerLocked, // assumed immutable
            settled: stored.settled,
            withdrawable: stored.withdrawable
        });
    }

    /// @notice Expiration time and settled state of a specific position (corresponds to the NFT token ID)
    /// @dev This is more gas efficient than SLOADing everything in getPosition if just expiration / settled
    /// is needed
    function expirationAndSettled(uint takerId) external view returns (uint expiration, bool settled) {
        TakerPositionStored storage stored = positions[takerId];
        return (stored.providerNFT.expiration(stored.providerId), stored.settled);
    }

    /**
     * @notice Calculates the amount of cash asset that will be locked on provider side
     * for a given amount of taker locked asset and strike percentages.
     * @param takerLocked The amount of cash asset locked by the taker
     * @param putStrikePercent The put strike percentage in basis points
     * @param callStrikePercent The call strike percentage in basis points
     * @return The amount of cash asset the provider will lock
     */
    function calculateProviderLocked(uint takerLocked, uint putStrikePercent, uint callStrikePercent)
        public
        pure
        returns (uint)
    {
        // cannot be 0 due to range checks in providerNFT and configHub
        uint putRange = BIPS_BASE - putStrikePercent;
        uint callRange = callStrikePercent - BIPS_BASE;
        // proportionally scaled according to ranges. Will div-zero panic for 0 putRange.
        // rounds down against of taker to prevent taker abuse by opening small positions
        return takerLocked * callRange / putRange;
    }

    /// @notice Returns the price used for opening and settling positions, which is current price from
    /// the oracle.
    /// @return Amount of cashAsset for a unit of underlying (i.e. 10**underlying.decimals())
    function currentOraclePrice() public view returns (uint) {
        return oracle.currentPrice();
    }

    /**
     * @notice Calculates the settlement results at a given price
     * @dev no validation, so may revert with division by zero for bad values
     * @param position The TakerPosition to calculate settlement for
     * @param endPrice The settlement price, as returned from the this contract's price views
     * @return takerBalance The amount the taker will be able to withdraw after settlement
     * @return providerDelta The amount transferred to/from provider position (positive or negative)
     */
    function previewSettlement(TakerPosition memory position, uint endPrice)
        external
        pure
        returns (uint takerBalance, int providerDelta)
    {
        return _settlementCalculations(position, endPrice);
    }

    // ----- STATE CHANGING FUNCTIONS ----- //

    /**
     * @notice Opens a new paired taker and provider position: minting taker NFT position to the caller,
     * and calling provider NFT mint provider position to the provider.
     * @dev The caller must have approved this contract to transfer the takerLocked amount
     * @param takerLocked The amount to pull from sender, to be locked on the taker side
     * @param providerNFT The CollarProviderNFT contract of the provider
     * @param offerId The offer ID on the provider side. Implies specific provider,
     * put & call percents, duration.
     * @return takerId The ID of the newly minted taker NFT
     * @return providerId The ID of the newly minted provider NFT
     */
    function openPairedPosition(uint takerLocked, CollarProviderNFT providerNFT, uint offerId)
        external
        nonReentrant
        returns (uint takerId, uint providerId)
    {
        // check asset & self allowed
        require(
            configHub.canOpenPair(address(underlying), address(cashAsset), address(this)),
            "taker: unsupported taker"
        );
        // check assets & provider allowed
        require(
            configHub.canOpenPair(address(underlying), address(cashAsset), address(providerNFT)),
            "taker: unsupported provider"
        );
        // check assets match
        require(providerNFT.underlying() == underlying, "taker: underlying mismatch");
        require(providerNFT.cashAsset() == cashAsset, "taker: cashAsset mismatch");
        // check this is the right taker (in case multiple are allowed). ProviderNFT checks too.
        require(providerNFT.taker() == address(this), "taker: taker mismatch");

        CollarProviderNFT.LiquidityOffer memory offer = providerNFT.getOffer(offerId);
        require(offer.duration != 0, "taker: invalid offer");
        uint providerLocked =
            calculateProviderLocked(takerLocked, offer.putStrikePercent, offer.callStrikePercent);

        // prices
        uint startPrice = currentOraclePrice();
        (uint putStrikePrice, uint callStrikePrice) =
            _strikePrices(offer.putStrikePercent, offer.callStrikePercent, startPrice);
        // avoid boolean edge cases and division by zero when settling
        require(
            putStrikePrice < startPrice && callStrikePrice > startPrice, "taker: strike prices not different"
        );

        // open the provider position for providerLocked amount (reverts if can't).
        // sends the provider NFT to the provider
        providerId = providerNFT.mintFromOffer(offerId, providerLocked, nextTokenId);

        // check expiration matches expected
        uint expiration = block.timestamp + offer.duration;
        require(expiration == providerNFT.expiration(providerId), "taker: expiration mismatch");

        // storage updates
        takerId = nextTokenId++;
        positions[takerId] = TakerPositionStored({
            providerNFT: providerNFT,
            providerId: SafeCast.toUint64(providerId),
            settled: false, // unset until settlement / cancellation
            startPrice: startPrice,
            takerLocked: takerLocked,
            withdrawable: 0 // unset until settlement
         });
        // mint the NFT to the sender, @dev does not use _safeMint to avoid reentrancy
        _mint(msg.sender, takerId);

        emit PairedPositionOpened(takerId, address(providerNFT), providerId, offerId, takerLocked, startPrice);

        // pull the user side of the locked cash
        cashAsset.safeTransferFrom(msg.sender, address(this), takerLocked);
    }

    /**
     * @notice Settles a paired position after expiry. Uses current oracle price at time of call.
     * @param takerId The ID of the taker position to settle
     *
     * @dev this should be called as soon after expiry as possible to minimize the difference between
     * price at expiry time and price at call time (which is used for payouts).
     * Both taker and provider are incentivised to call this method, however it's possible that
     * one side is not (e.g., due to being at max loss). For this reason a keeper should be run to
     * prevent users with gains from not settling their positions on time.
     */
    function settlePairedPosition(uint takerId) external nonReentrant {
        // @dev this checks position exists
        TakerPosition memory position = getPosition(takerId);

        require(block.timestamp >= position.expiration, "taker: not expired");
        require(!position.settled, "taker: already settled");

        // settlement price
        uint endPrice = currentOraclePrice();
        // settlement amounts
        (uint takerBalance, int providerDelta) = _settlementCalculations(position, endPrice);

        // store changes
        positions[takerId].settled = true;
        positions[takerId].withdrawable = takerBalance;

        // settle and transfer the funds via the provider
        (CollarProviderNFT providerNFT, uint providerId) = (position.providerNFT, position.providerId);
        // approve provider to pull cash if needed
        if (providerDelta > 0) cashAsset.forceApprove(address(providerNFT), uint(providerDelta));
        // expected balance change is current-balance + withdrawable - takerLocked
        uint expectedBalance = cashAsset.balanceOf(address(this)) + takerBalance - position.takerLocked;
        // call provider side
        providerNFT.settlePosition(providerId, providerDelta);
        // check balance update to prevent reducing resting balance
        require(cashAsset.balanceOf(address(this)) == expectedBalance, "taker: settle balance mismatch");

        emit PairedPositionSettled(
            takerId, address(providerNFT), providerId, endPrice, takerBalance, providerDelta
        );
    }

    /**
     * @notice Settles a paired position after expiry + SETTLE_AS_CANCELLED_DELAY if
     * settlePairedPosition was not called during the delay by anyone, presumably due to oracle failure.
     * @param takerId The ID of the taker position to settle
     *
     * @dev this method exists because if the oracle starts reverting, there is no way to update it.
     * Either taker or provider are incentivised to call settlePairedPosition prior to this method being callable,
     * and anyone else (like a keeper), can call settlePairedPosition too.
     * So if it wasn't called by anyone, we need to settle the positions without an oracle, and allow their withdrawal.
     * Callable by anyone for consistency with settlePairedPosition and to allow loan closure without unwrapping.
     */
    function settleAsCancelled(uint takerId) external nonReentrant {
        // @dev this checks position exists
        TakerPosition memory position = getPosition(takerId);
        (CollarProviderNFT providerNFT, uint providerId) = (position.providerNFT, position.providerId);

        require(
            block.timestamp >= position.expiration + SETTLE_AS_CANCELLED_DELAY,
            "taker: cannot be settled as cancelled yet"
        );
        require(!position.settled, "taker: already settled");

        // store changes
        positions[takerId].settled = true;
        positions[takerId].withdrawable = position.takerLocked;

        uint expectedBalance = cashAsset.balanceOf(address(this));
        // call provider side to settle with no balance change
        providerNFT.settlePosition(providerId, 0);
        // check no balance change
        require(cashAsset.balanceOf(address(this)) == expectedBalance, "taker: settle balance mismatch");

        // endPrice is 0 since is unavailable, technically settlement price is position.startPrice but
        // it would be incorrect to pass it as endPrice.
        // Also, 0 allows distinguishing this type of settlement in events.
        emit PairedPositionSettled(takerId, address(providerNFT), providerId, 0, position.takerLocked, 0);
    }

    /// @notice Withdraws funds from a settled position. Burns the NFT.
    /// @param takerId The ID of the settled position to withdraw from (NFT token ID).
    /// @return withdrawal The amount of cash asset withdrawn
    function withdrawFromSettled(uint takerId) external nonReentrant returns (uint withdrawal) {
        require(msg.sender == ownerOf(takerId), "taker: not position owner");

        TakerPosition memory position = getPosition(takerId);
        require(position.settled, "taker: not settled");

        withdrawal = position.withdrawable;
        // store zeroed out withdrawable
        positions[takerId].withdrawable = 0;
        // burn token
        _burn(takerId);
        // transfer tokens
        cashAsset.safeTransfer(msg.sender, withdrawal);

        emit WithdrawalFromSettled(takerId, withdrawal);
    }

    /**
     * @notice Cancels a paired position and withdraws funds
     * @dev Can only be called by the owner of BOTH taker and provider NFTs
     * @param takerId The ID of the taker position to cancel
     * @return withdrawal The amount of funds withdrawn from both positions together
     */
    function cancelPairedPosition(uint takerId) external nonReentrant returns (uint withdrawal) {
        TakerPosition memory position = getPosition(takerId);
        (CollarProviderNFT providerNFT, uint providerId) = (position.providerNFT, position.providerId);

        // must be taker NFT owner
        require(msg.sender == ownerOf(takerId), "taker: not owner of ID");
        // must be provider NFT owner as well
        require(msg.sender == providerNFT.ownerOf(providerId), "taker: not owner of provider ID");

        // must not be settled yet
        require(!position.settled, "taker: already settled");

        // storage changes. withdrawable is 0 before settlement, so needs no update
        positions[takerId].settled = true;
        // burn token
        _burn(takerId);

        // cancel and withdraw
        // record the balance
        uint balanceBefore = cashAsset.balanceOf(address(this));
        // cancel on provider side
        uint providerWithdrawal = providerNFT.cancelAndWithdraw(providerId);
        // check balance update to prevent reducing resting balance
        uint expectedBalance = balanceBefore + providerWithdrawal;
        require(cashAsset.balanceOf(address(this)) == expectedBalance, "taker: cancel balance mismatch");

        // transfer the tokens locked in this contract and the withdrawal from provider
        withdrawal = position.takerLocked + providerWithdrawal;
        cashAsset.safeTransfer(msg.sender, withdrawal);

        emit PairedPositionCanceled(
            takerId, address(providerNFT), providerId, withdrawal, position.expiration
        );
    }

    // ----- INTERNAL VIEWS ----- //

    function _checkOracle(ITakerOracle _oracle) internal view {
        // assets match
        require(_oracle.baseToken() == address(underlying), "taker: oracle underlying mismatch");
        require(_oracle.quoteToken() == address(cashAsset), "taker: oracle cashAsset mismatch");

        // Ensure price calls don't revert and return a non-zero price at least right now.
        // Only a sanity check, and the protocol should work even if the oracle is temporarily unavailable
        // in the future. For example, if a TWAP oracle is used, the observations buffer can be filled such that
        // the required time window is not available. If Chainlink oracle is used, the prices can be stale.
        uint price = _oracle.currentPrice();
        require(price != 0, "taker: invalid current price");

        // check these views don't revert (part of the interface used in Loans)
        // note: .convertToBaseAmount(price, price) should equal .baseUnitAmount(), but checking this
        // may be too strict for more complex oracles, and .baseUnitAmount() is not used internally now
        require(_oracle.convertToBaseAmount(price, price) != 0, "taker: invalid convertToBaseAmount");
    }

    // calculations

    // Rounding down precision loss is negligible, and the values (strike percentages, and price)
    // are outside of their control so this should not be possible to abuse assuming reasonable values.
    function _strikePrices(uint putStrikePercent, uint callStrikePercent, uint startPrice)
        internal
        pure
        returns (uint putStrikePrice, uint callStrikePrice)
    {
        putStrikePrice = startPrice * putStrikePercent / BIPS_BASE;
        callStrikePrice = startPrice * callStrikePercent / BIPS_BASE;
    }

    /**
     * @dev Note that linear price changes are used instead of geometric. This means that if geometric
     * (multiplicative) changes are assumed equi-probable (e.g., -10% corresponds to +11.1%)
     * the amounts locked on both sides of a symmetric position are increasingly unbalanced.
     * So no strict symmetry assumptions should be made, and takers and providers should choose
     * the strikes correctly to fit their needs.
     */
    function _settlementCalculations(TakerPosition memory position, uint endPrice)
        internal
        pure
        returns (uint takerBalance, int providerDelta)
    {
        uint startPrice = position.startPrice;
        (uint putStrikePrice, uint callStrikePrice) =
            _strikePrices(position.putStrikePercent, position.callStrikePercent, startPrice);

        // restrict endPrice to put-call range
        endPrice = Math.max(Math.min(endPrice, callStrikePrice), putStrikePrice);

        // start with locked (corresponds to endPrice == startPrice)
        takerBalance = position.takerLocked;
        // endPrice == startPrice is no-op in both branches
        if (endPrice < startPrice) {
            // takerLocked: divided between taker and provider
            // providerLocked: all goes to provider
            uint providerGainRange = startPrice - endPrice;
            uint putRange = startPrice - putStrikePrice;
            uint providerGain = position.takerLocked * providerGainRange / putRange; // no div-zero ensured on open
            takerBalance -= providerGain;
            providerDelta = providerGain.toInt256();
        } else {
            // takerLocked: all goes to taker
            // providerLocked: divided between taker and provider
            uint takerGainRange = endPrice - startPrice;
            uint callRange = callStrikePrice - startPrice;
            uint takerGain = position.providerLocked * takerGainRange / callRange; // no div-zero ensured on open

            takerBalance += takerGain;
            providerDelta = -takerGain.toInt256();
        }
    }
}
