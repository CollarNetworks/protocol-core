// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { ConfigHub, BaseNFT, CollarProviderNFT, Math, IERC20, SafeERC20 } from "./CollarProviderNFT.sol";
import { ITakerOracle } from "./interfaces/ITakerOracle.sol";
import { ICollarTakerNFT } from "./interfaces/ICollarTakerNFT.sol";
import { ICollarProviderNFT } from "./interfaces/ICollarProviderNFT.sol";

contract CollarTakerNFT is ICollarTakerNFT, BaseNFT {
    using SafeERC20 for IERC20;
    using SafeCast for uint;

    uint internal constant BIPS_BASE = 10_000;

    string public constant VERSION = "0.2.0";

    // ----- IMMUTABLES ----- //
    IERC20 public immutable cashAsset;
    address public immutable underlying; // not used as ERC20 here

    // ----- STATE VARIABLES ----- //
    ITakerOracle public oracle;
    mapping(uint positionId => TakerPositionStored) internal positions;

    constructor(
        address initialOwner,
        ConfigHub _configHub,
        IERC20 _cashAsset,
        IERC20 _underlying,
        ITakerOracle _oracle,
        string memory _name,
        string memory _symbol
    ) BaseNFT(initialOwner, _name, _symbol) {
        cashAsset = _cashAsset;
        underlying = address(_underlying);
        _setConfigHub(_configHub);
        _setOracle(_oracle);
        emit CollarTakerNFTCreated(address(_cashAsset), address(_underlying), address(_oracle));
    }

    // ----- VIEW FUNCTIONS ----- //

    /// @notice Returns the ID of the next taker position to be minted
    function nextPositionId() external view returns (uint) {
        return nextTokenId;
    }

    /// @notice Retrieves the details of a specific position (corresponds to the NFT token ID)
    /// @dev This is used instead of the default getter because the default getter returns a tuple
    function getPosition(uint takerId) public view returns (TakerPosition memory) {
        TakerPositionStored memory stored = positions[takerId];
        require(address(stored.providerNFT) != address(0), "taker position does not exist");
        // @dev the provider position fields that are used are assumed to be immutable (set once)
        ICollarProviderNFT.ProviderPosition memory providerPos =
            stored.providerNFT.getPosition(stored.providerId);
        // calculation is static (pure) from immutable values
        (uint putStrikePrice, uint callStrikePrice) =
            _strikePrices(providerPos.putStrikePercent, providerPos.callStrikePercent, stored.startPrice);
        return TakerPosition({
            providerNFT: stored.providerNFT,
            providerId: stored.providerId,
            duration: providerPos.duration, // comes from the offer, implicitly checked with expiration
            expiration: providerPos.expiration, // checked to match on creation
            startPrice: stored.startPrice,
            putStrikePrice: putStrikePrice, // calculated here
            callStrikePrice: callStrikePrice, // calculated here
            takerLocked: stored.takerLocked,
            providerLocked: providerPos.providerLocked, // assumed immutable
            settled: stored.settled,
            withdrawable: stored.withdrawable
        });
    }

    /// @dev calculate the amount of cash the provider will lock for specific terms and taker
    /// locked amount
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

    /// @dev TWAP price that's used in this contract for opening positions
    function currentOraclePrice() public view returns (uint) {
        return oracle.currentPrice();
    }

    /// @dev TWAP price that's used in this contract for settling positions. Falls back to current
    /// TWAP price if historical price is no longer available.
    function historicalOraclePrice(uint timestamp) public view returns (uint price, bool historical) {
        return oracle.pastPriceWithFallback(timestamp.toUint32());
    }

    /// @dev preview the settlement calculation updates at a particular price
    /// @dev no validation, so may revert with division by zero for bad values
    function previewSettlement(uint takerId, uint endPrice)
        external
        view
        returns (uint takerBalance, int providerDelta)
    {
        return _settlementCalculations(getPosition(takerId), endPrice);
    }

    // ----- STATE CHANGING FUNCTIONS ----- //

    function openPairedPosition(
        uint takerLocked, // user portion of collar position
        CollarProviderNFT providerNFT,
        uint offerId // @dev implies specific provider, put & call percents, duration
    ) external whenNotPaused returns (uint takerId, uint providerId) {
        // check assets allowed
        require(configHub.isSupportedCashAsset(address(cashAsset)), "unsupported asset");
        require(configHub.isSupportedUnderlying(underlying), "unsupported asset");
        // check self allowed
        require(configHub.canOpen(address(this)), "unsupported taker contract");
        // check provider allowed
        require(configHub.canOpen(address(providerNFT)), "unsupported provider contract");
        // check assets match
        require(providerNFT.underlying() == underlying, "asset mismatch");
        require(providerNFT.cashAsset() == cashAsset, "asset mismatch");

        CollarProviderNFT.LiquidityOffer memory offer = providerNFT.getOffer(offerId);
        require(offer.duration != 0, "invalid offer");
        uint providerLocked =
            calculateProviderLocked(takerLocked, offer.putStrikePercent, offer.callStrikePercent);

        // prices
        uint startPrice = currentOraclePrice();
        (uint putStrikePrice, uint callStrikePrice) =
            _strikePrices(offer.putStrikePercent, offer.callStrikePercent, startPrice);
        // avoid boolean edge cases and division by zero when settling
        require(putStrikePrice < startPrice && callStrikePrice > startPrice, "strike prices not different");

        // open the provider position for providerLocked amount (reverts if can't).
        // sends the provider NFT to the provider
        providerId = providerNFT.mintFromOffer(offerId, providerLocked, nextTokenId);

        // check expiration matches expected
        uint expiration = block.timestamp + offer.duration;
        require(expiration == providerNFT.getPosition(providerId).expiration, "expiration mismatch");

        // increment ID
        takerId = nextTokenId++;
        // store position data
        positions[takerId] = TakerPositionStored({
            providerNFT: providerNFT,
            providerId: providerId,
            startPrice: startPrice,
            takerLocked: takerLocked,
            // unset until settlement
            settled: false,
            withdrawable: 0
        });
        // mint the NFT to the sender, @dev does not use _safeMint to avoid reentrancy
        _mint(msg.sender, takerId);

        emit PairedPositionOpened(takerId, address(providerNFT), providerId, offerId, getPosition(takerId));

        // pull the user side of the locked cash
        cashAsset.safeTransferFrom(msg.sender, address(this), takerLocked);
    }

    /// @dev this should be called as soon after expiry as possible, because if the expiry TWAP price becomes
    /// unavailable in the UniV3 oracle, the current price will be used instead of it.
    /// Both taker and provider are incentivised to call this method, however it's possible that
    /// one side is not (e.g., due to being at max loss). For this reason a keeper should be run to
    /// prevent users with gains from not settling their positions on time.
    /// @dev To increase the timespan during which the historical price is available use
    /// `oracle.increaseCardinality` (or the pool's `increaseObservationCardinalityNext`).
    function settlePairedPosition(uint takerId) external whenNotPaused {
        // @dev this checks position exists
        TakerPosition memory position = getPosition(takerId);

        require(block.timestamp >= position.expiration, "not expired");
        require(!position.settled, "already settled");

        // settlement price
        (uint endPrice, bool historical) = historicalOraclePrice(position.expiration);
        // settlement amounts
        (uint takerBalance, int providerDelta) = _settlementCalculations(position, endPrice);

        // store changes
        positions[takerId].settled = true;
        positions[takerId].withdrawable = takerBalance;

        (CollarProviderNFT providerNFT, uint providerId) = (position.providerNFT, position.providerId);
        // settle paired and make the transfers
        if (providerDelta > 0) cashAsset.forceApprove(address(providerNFT), uint(providerDelta));
        providerNFT.settlePosition(providerId, providerDelta);

        emit PairedPositionSettled(
            takerId, address(providerNFT), providerId, endPrice, historical, takerBalance, providerDelta
        );
    }

    function withdrawFromSettled(uint takerId) external whenNotPaused returns (uint withdrawal) {
        require(msg.sender == ownerOf(takerId), "not position owner");

        TakerPosition memory position = getPosition(takerId);
        require(position.settled, "not settled");

        withdrawal = position.withdrawable;
        // store zeroed out withdrawable
        positions[takerId].withdrawable = 0;
        // burn token
        _burn(takerId);
        // transfer tokens
        cashAsset.safeTransfer(msg.sender, withdrawal);

        emit WithdrawalFromSettled(takerId, withdrawal);
    }

    function cancelPairedPosition(uint takerId) external whenNotPaused returns (uint withdrawal) {
        require(msg.sender == ownerOf(takerId), "not owner of taker ID");

        TakerPosition memory position = getPosition(takerId);
        require(!position.settled, "already settled");

        (CollarProviderNFT providerNFT, uint providerId) = (position.providerNFT, position.providerId);
        // this is redundant due to NFT transfer from msg.sender later, but is a clearer error.
        require(msg.sender == providerNFT.ownerOf(providerId), "not owner of provider ID");

        // storage changes. withdrawable is 0 before settlement, so needs no update
        positions[takerId].settled = true;
        // burn token
        _burn(takerId);

        // pull the provider NFT to this contract
        providerNFT.transferFrom(msg.sender, address(this), providerId);

        // now that this contract has the provider NFT - cancel it and withdraw
        uint providerWithdrawal = providerNFT.cancelAndWithdraw(providerId);

        // transfer the tokens locked in this contract and the withdrawal from provider
        withdrawal = position.takerLocked + providerWithdrawal;
        cashAsset.safeTransfer(msg.sender, withdrawal);

        emit PairedPositionCanceled(
            takerId, address(providerNFT), providerId, withdrawal, position.expiration
        );
    }

    // ----- Owner Mutative ----- //

    function setOracle(ITakerOracle _oracle) external onlyOwner {
        _setOracle(_oracle);
    }

    // ----- INTERNAL MUTATIVE ----- //

    // internal owner

    function _setOracle(ITakerOracle _oracle) internal {
        // assets match
        require(_oracle.baseToken() == underlying, "oracle asset mismatch");
        require(_oracle.quoteToken() == address(cashAsset), "oracle asset mismatch");

        // Ensure price calls don't revert and return a non-zero price at least right now.
        // Only a sanity check, since this doesn't ensure that it will work in the future,
        // since the observations buffer can be filled such that the required time window is not available.
        // @dev this means this contract can be temporarily DoSed unless the cardinality is set
        // to at least twap-window. For 5 minutes TWAP on Arbitrum this is 300 (obs. are set by timestamps)
        require(_oracle.currentPrice() != 0, "invalid current price");
        (uint price,) = _oracle.pastPriceWithFallback(uint32(block.timestamp));
        require(price != 0, "invalid past price");

        // check these views don't revert (part of the interface used in Loans)
        // note: .convertToBaseAmount(price, price) should equal .baseUnitAmount(), but checking this
        // may be too strict for more complex oracles, and .baseUnitAmount() is not used internally now
        require(_oracle.convertToBaseAmount(price, price) != 0, "invalid convertToBaseAmount");

        emit OracleSet(oracle, _oracle); // emit before for the prev value
        oracle = _oracle;
    }

    // ----- INTERNAL VIEWS ----- //

    // calculations

    function _strikePrices(uint putStrikePercent, uint callStrikePercent, uint startPrice)
        internal
        pure
        returns (uint putStrikePrice, uint callStrikePrice)
    {
        putStrikePrice = startPrice * putStrikePercent / BIPS_BASE;
        callStrikePrice = startPrice * callStrikePercent / BIPS_BASE;
    }

    function _settlementCalculations(TakerPosition memory position, uint endPrice)
        internal
        pure
        returns (uint takerBalance, int providerDelta)
    {
        uint startPrice = position.startPrice;
        uint putPrice = position.putStrikePrice;
        uint callPrice = position.callStrikePrice;

        // restrict endPrice to put-call range
        endPrice = Math.max(Math.min(endPrice, callPrice), putPrice);

        // start with locked (corresponds to endPrice == startPrice)
        takerBalance = position.takerLocked;
        // endPrice == startPrice is no-op in both branches
        if (endPrice < startPrice) {
            // takerLocked: divided between taker and provider
            // providerLocked: all goes to provider
            uint providerGainRange = startPrice - endPrice;
            uint putRange = startPrice - putPrice;
            uint providerGain = position.takerLocked * providerGainRange / putRange; // no div-zero ensured on open
            takerBalance -= providerGain;
            providerDelta = providerGain.toInt256();
        } else {
            // takerLocked: all goes to taker
            // providerLocked: divided between taker and provider
            uint takerGainRange = endPrice - startPrice;
            uint callRange = callPrice - startPrice;
            uint takerGain = position.providerLocked * takerGainRange / callRange; // no div-zero ensured on open

            takerBalance += takerGain;
            providerDelta = -takerGain.toInt256();
        }
    }
}
