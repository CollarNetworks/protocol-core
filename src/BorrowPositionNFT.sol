// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity 0.8.22;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { IV3SwapRouter } from "@uniswap/swap-router-contracts/contracts/interfaces/IV3SwapRouter.sol";
// internal imports
import { ProviderPositionNFT } from "./ProviderPositionNFT.sol";
import { BaseGovernedNFT } from "./base/BaseGovernedNFT.sol";
import { CollarEngine } from "./implementations/CollarEngine.sol";
import { IBorrowPositionNFT } from "./interfaces/IBorrowPositionNFT.sol";

contract BorrowPositionNFT is IBorrowPositionNFT, BaseGovernedNFT {
    using SafeERC20 for IERC20;
    using SafeCast for uint;

    uint24 internal constant FEE_TIER_30_BIPS = 3000;
    uint internal constant BIPS_BASE = 10_000;

    uint32 public constant TWAP_LENGTH = 15 minutes;
    /// should be set to not be overly restrictive since is mostly sanity-check
    uint public constant MAX_SWAP_TWAP_DEVIATION_BIPS = 100;

    string public constant VERSION = "0.1.0"; // allow checking version on-chain

    // ----- IMMUTABLES ----- //
    CollarEngine public immutable engine;
    IERC20 public immutable cashAsset;
    IERC20 public immutable collateralAsset;

    // ----- STATE VARIABLES ----- //
    mapping(uint positionId => BorrowPosition) internal positions;

    constructor(
        address initialOwner,
        CollarEngine _engine,
        IERC20 _cashAsset,
        IERC20 _collateralAsset,
        string memory _name,
        string memory _symbol
    ) BaseGovernedNFT(initialOwner, _name, _symbol) {
        engine = _engine;
        cashAsset = _cashAsset;
        collateralAsset = _collateralAsset;
        // check params are supported
        _validateAssetsSupported();
    }

    // ----- VIEW FUNCTIONS ----- //
    // @dev return memory struct (the default getter returns tuple)
    function getPosition(uint borrowId) external view returns (BorrowPosition memory) {
        return positions[borrowId];
    }

    function nextPositionId() external view returns (uint) {
        return nextTokenId;
    }

    // ----- STATE CHANGING FUNCTIONS ----- //
    function openPairedPosition(
        uint collateralAmount,
        uint minCashAmount, // slippage control
        ProviderPositionNFT providerNFT,
        uint offerId // @dev implies specific provider, put & call deviations, duration
    ) external whenNotPaused returns (uint borrowId, uint providerId, uint loanAmount) {
        require(collateralAmount > 0, "zero collateral");
        _openPositionValidations(providerNFT);

        // get TWAP price
        uint twapPrice = _getTWAPPrice(block.timestamp);

        // transfer and swap collateral
        // reentrancy assumptions: router is trusted + swap path is direct (not through multiple pools)
        uint cashFromSwap = _pullAndSwap(msg.sender, collateralAmount, minCashAmount, twapPrice);

        uint putLockedCash;
        (loanAmount, putLockedCash) = _splitSwappedCash(cashFromSwap, providerNFT, offerId);

        // stores, mints, calls providerNFT and mints there, emits the event
        (borrowId, providerId) = _openPairedPositionInternal(twapPrice, putLockedCash, providerNFT, offerId);

        // transfer the full loan amount on open
        cashAsset.safeTransfer(msg.sender, loanAmount);

        emit BorrowedFromSwap(borrowId, msg.sender, collateralAmount, cashFromSwap, loanAmount);
    }

    /// @dev this is for use in rolls to open positions without repaying or swapping
    function openPairedPositionWithoutSwap(
        uint putLockedCash, // user portion of collar position
        ProviderPositionNFT providerNFT,
        uint offerId // @dev implies specific provider, put & call deviations, duration
    ) external whenNotPaused returns (uint borrowId, uint providerId) {
        _openPositionValidations(providerNFT);

        // pull the user side of the locked cash
        cashAsset.safeTransferFrom(msg.sender, address(this), putLockedCash);

        // get TWAP price
        uint twapPrice = _getTWAPPrice(block.timestamp);

        // stores, mints, calls providerNFT and mints there, emits the event
        (borrowId, providerId) = _openPairedPositionInternal(twapPrice, putLockedCash, providerNFT, offerId);
    }

    function settlePairedPosition(uint borrowId) external whenNotPaused {
        BorrowPosition storage position = positions[borrowId];
        ProviderPositionNFT providerNFT = position.providerNFT;
        uint providerId = position.providerPositionId;

        require(position.openedAt != 0, "position doesn't exist");
        // access is restricted because NFT owners might want to cancel (unwind) instead
        require(
            msg.sender == ownerOf(borrowId) || msg.sender == providerNFT.ownerOf(providerId),
            "not owner of either position"
        );
        require(block.timestamp >= position.expiration, "not expired");
        require(!position.settled, "already settled");

        position.settled = true; // set here to prevent reentrancy

        // get settlement price
        uint endPrice = _getTWAPPrice(position.expiration);

        (uint withdrawable, int providerChange) = _settlementCalculations(position, endPrice);

        _settleProviderPosition(position, providerChange);

        // set withdrawable for user
        position.withdrawable = withdrawable;

        emit PairedPositionSettled(
            borrowId, address(providerNFT), providerId, endPrice, withdrawable, providerChange
        );
    }

    function withdrawFromSettled(uint borrowId, address recipient) external whenNotPaused {
        require(msg.sender == ownerOf(borrowId), "not position owner");

        BorrowPosition storage position = positions[borrowId];
        require(position.settled, "not settled");

        uint withdrawable = position.withdrawable;
        // zero out withdrawable
        position.withdrawable = 0;
        // burn token
        _burn(borrowId);
        // transfer tokens
        cashAsset.safeTransfer(recipient, withdrawable);

        emit WithdrawalFromSettled(borrowId, recipient, withdrawable);
    }

    function cancelPairedPosition(uint borrowId, address recipient) external whenNotPaused {
        BorrowPosition storage position = positions[borrowId];
        ProviderPositionNFT providerNFT = position.providerNFT;
        uint providerId = position.providerPositionId;

        require(msg.sender == ownerOf(borrowId), "not owner of borrow ID");
        // this is redundant due to NFT transfer from msg.sender later, but is clearer.
        require(msg.sender == providerNFT.ownerOf(providerId), "not owner of provider ID");

        require(!position.settled, "already settled");
        position.settled = true; // set here to prevent reentrancy

        // burn token
        _burn(borrowId);

        // pull the provider NFT to this contract
        providerNFT.transferFrom(msg.sender, address(this), providerId);

        // now that this contract has the provider NFT - cancel it and withdraw funds to sender
        providerNFT.cancelAndWithdraw(providerId, recipient);

        // transfer the tokens locked in this contract
        cashAsset.safeTransfer(recipient, position.putLockedCash);

        emit PairedPositionCanceled(
            borrowId, address(providerNFT), providerId, recipient, position.putLockedCash, position.expiration
        );
    }

    // ----- INTERNAL MUTATIVE ----- //

    function _pullAndSwap(address sender, uint collateralAmount, uint minCashAmount, uint twapPrice)
        internal
        returns (uint cashFromSwap)
    {
        collateralAsset.safeTransferFrom(sender, address(this), collateralAmount);

        // approve the dex router so we can swap the collateral to cash
        collateralAsset.forceApprove(engine.univ3SwapRouter(), collateralAmount);

        // build the swap transaction
        IV3SwapRouter.ExactInputSingleParams memory swapParams = IV3SwapRouter.ExactInputSingleParams({
            tokenIn: address(collateralAsset),
            tokenOut: address(cashAsset),
            fee: FEE_TIER_30_BIPS,
            recipient: address(this),
            amountIn: collateralAmount,
            amountOutMinimum: minCashAmount,
            sqrtPriceLimitX96: 0
        });

        uint balanceBefore = cashAsset.balanceOf(address(this));
        // reentrancy assumptions: router is trusted + swap path is direct (not through multiple pools)
        uint amountOutRouter = IV3SwapRouter(payable(engine.univ3SwapRouter())).exactInputSingle(swapParams);
        // Calculate the actual amount of cash received
        cashFromSwap = cashAsset.balanceOf(address(this)) - balanceBefore;
        // check balance is updated as expected and as reported by router (no other balance changes)
        // cash-asset cannot be fee-on-transfer or rebasing (e.g., internal shares accounting)
        require(cashFromSwap == amountOutRouter, "balance update mismatch");
        // check amount is as expected by user
        require(cashFromSwap >= minCashAmount, "slippage exceeded");

        // @dev note that only TWAP price is used for payout decision later, and swap price should
        // only affect the "pot sizing" (so does not affect the provider, only the borrower)
        _checkSwapPrice(twapPrice, cashFromSwap, collateralAmount);
    }

    function _openPairedPositionInternal(
        uint twapPrice,
        uint putLockedCash,
        ProviderPositionNFT providerNFT,
        uint offerId
    ) internal returns (uint borrowId, uint providerId) {
        uint callLockedCash = _calculateProviderLocked(putLockedCash, providerNFT, offerId);

        // open the provider position with duration and callLockedCash locked liquidity (reverts if can't)
        // and sends the provider NFT to the provider
        ProviderPositionNFT.ProviderPosition memory providerPosition;
        (providerId, providerPosition) = providerNFT.mintPositionFromOffer(offerId, callLockedCash);

        // put and call deviations are assumed to be identical for offer and resulting position
        uint putStrikePrice = twapPrice * providerPosition.putStrikeDeviation / BIPS_BASE;
        uint callStrikePrice = twapPrice * providerPosition.callStrikeDeviation / BIPS_BASE;
        // avoid boolean edge cases and division by zero when settling
        require(putStrikePrice < twapPrice && callStrikePrice > twapPrice, "strike prices aren't different");

        BorrowPosition memory borrowPosition = BorrowPosition({
            providerNFT: providerNFT,
            providerPositionId: providerId,
            openedAt: block.timestamp,
            expiration: providerPosition.expiration,
            initialPrice: twapPrice,
            putStrikePrice: putStrikePrice,
            callStrikePrice: callStrikePrice,
            putLockedCash: putLockedCash,
            callLockedCash: callLockedCash,
            // unset until settlement
            settled: false,
            withdrawable: 0
        });

        // increment ID
        borrowId = nextTokenId++;
        // store position data
        positions[borrowId] = borrowPosition;
        // mint the NFT to the sender
        // @dev does not use _safeMint to avoid reentrancy
        _mint(msg.sender, borrowId);

        emit PairedPositionOpened(borrowId, address(providerNFT), providerId, offerId, borrowPosition);
    }

    function _settleProviderPosition(BorrowPosition storage position, int providerChange) internal {
        if (providerChange > 0) {
            cashAsset.forceApprove(address(position.providerNFT), uint(providerChange));
        }

        position.providerNFT.settlePosition(position.providerPositionId, providerChange);
    }

    // ----- INTERNAL VIEWS ----- //

    function _validateAssetsSupported() internal view {
        require(engine.isSupportedCashAsset(address(cashAsset)), "unsupported asset");
        require(engine.isSupportedCollateralAsset(address(collateralAsset)), "unsupported asset");
    }

    function _openPositionValidations(ProviderPositionNFT providerNFT) internal view {
        _validateAssetsSupported();

        // check self (provider will check too)
        require(engine.isBorrowNFT(address(this)), "unsupported borrow contract");

        // check provider
        require(engine.isProviderNFT(address(providerNFT)), "unsupported provider contract");
        // check assets match
        require(providerNFT.collateralAsset() == collateralAsset, "asset mismatch");
        require(providerNFT.cashAsset() == cashAsset, "asset mismatch");

        // checking LTV and duration (from provider offer) is redundant since provider offer
        // is trusted by user (passed in input), and trusted by engine (was checked vs. engine above)
    }

    function _getTWAPPrice(uint twapEndTime) internal view returns (uint price) {
        return engine.getHistoricalAssetPriceViaTWAP(
            address(collateralAsset), address(cashAsset), uint32(twapEndTime), TWAP_LENGTH
        );
    }

    /// The swap price is only used for "pot sizing", but not for payouts division on expiry.
    /// Due to this, price manipulation *should* NOT leak value from provider / protocol.
    /// The caller (user) is protected via a slippage parameter, and SHOULD use it to avoid MEV (if present).
    /// So, this check is just extra precaution and avoidance of manipulation edge-cases.
    function _checkSwapPrice(uint twapPrice, uint cashFromSwap, uint collateralAmount) internal view {
        uint swapPrice = cashFromSwap * engine.TWAP_BASE_TOKEN_AMOUNT() / collateralAmount;
        uint diff = swapPrice > twapPrice ? swapPrice - twapPrice : twapPrice - swapPrice;
        uint deviation = diff * BIPS_BASE / twapPrice;

        require(deviation <= MAX_SWAP_TWAP_DEVIATION_BIPS, "swap and twap price too different");
    }

    // calculations

    function _splitSwappedCash(uint cashFromSwap, ProviderPositionNFT providerNFT, uint offerId)
        internal
        view
        returns (uint loanAmount, uint putLockedCash)
    {
        uint putStrikeDeviation = providerNFT.getOffer(offerId).putStrikeDeviation;
        require(putStrikeDeviation != 0, "invalid put strike deviation");
        // this assumes LTV === put strike price
        loanAmount = putStrikeDeviation * cashFromSwap / BIPS_BASE;
        // everything that remains is locked on the put side
        putLockedCash = cashFromSwap - loanAmount;
    }

    function _calculateProviderLocked(uint putLockedCash, ProviderPositionNFT providerNFT, uint offerId)
        internal
        view
        returns (uint)
    {
        ProviderPositionNFT.LiquidityOffer memory offer = providerNFT.getOffer(offerId);
        uint putRange = BIPS_BASE - offer.putStrikeDeviation;
        uint callRange = offer.callStrikeDeviation - BIPS_BASE;
        require(putRange != 0, "invalid put strike deviation"); // avoid division by zero
        return callRange * putLockedCash / putRange; // proportionally scaled according to ranges
    }

    function _settlementCalculations(BorrowPosition storage position, uint endPrice)
        internal
        view
        returns (uint withdrawable, int providerChange)
    {
        uint startPrice = position.initialPrice;
        uint putPrice = position.putStrikePrice;
        uint callPrice = position.callStrikePrice;

        // restrict endPrice to put-call range
        endPrice = endPrice < putPrice ? putPrice : endPrice;
        endPrice = endPrice > callPrice ? callPrice : endPrice;

        withdrawable = position.putLockedCash;
        if (endPrice < startPrice) {
            // put range: divide between user and LP, call range: goes to LP
            uint lpPart = startPrice - endPrice;
            uint putRange = startPrice - putPrice;
            uint lpGain = position.putLockedCash * lpPart / putRange; // no div-zero ensured on open
            withdrawable -= lpGain;
            providerChange = lpGain.toInt256();
        } else {
            // put range: goes to user, call range: divide between user and LP
            uint userPart = endPrice - startPrice;
            uint callRange = callPrice - startPrice;
            uint userGain = position.callLockedCash * userPart / callRange; // no div-zero ensured on open
            withdrawable += userGain;
            providerChange = -userGain.toInt256();
        }
    }
}
