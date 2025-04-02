// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

import "forge-std/Test.sol";
import { IERC721Errors } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { BaseAssetPairTestSetup, CollarTakerNFT, CollarProviderNFT } from "./BaseAssetPairTestSetup.sol";

import { Rolls, IRolls, ICollarTakerNFT } from "../../src/Rolls.sol";

contract RollsTest is BaseAssetPairTestSetup {
    uint takerLocked = swapCashAmount * (BIPS_100PCT - ltv) / BIPS_100PCT; // 100
    uint providerLocked = swapCashAmount * (callStrikePercent - BIPS_100PCT) / BIPS_100PCT; // 100

    // roll offer params
    int feeAmount = int(cashUnits(1));
    int feeDeltaFactorBIPS = 5000; // 50%
    uint minPrice = oraclePrice * 9 / 10;
    uint maxPrice = oraclePrice * 11 / 10;
    int minToProvider = -int(providerLocked) / 2;
    uint deadline = block.timestamp + 1 days;

    function createProviderOffers() internal returns (uint offerId, uint offerId2) {
        startHoax(provider);
        cashAsset.approve(address(providerNFT), largeCash);
        offerId = providerNFT.createOffer(callStrikePercent, largeCash, ltv, duration, 0);
        // another provider NFT
        cashAsset.approve(address(providerNFT2), largeCash);
        offerId2 = providerNFT2.createOffer(callStrikePercent, largeCash, ltv, duration, 0);
    }

    function createTakerPositions() internal returns (uint takerId, uint providerId) {
        (uint offerId, uint offerId2) = createProviderOffers();
        startHoax(user1);
        cashAsset.approve(address(takerNFT), 2 * takerLocked);
        // open "second" position first, such that the taker ID is incremented
        takerNFT.openPairedPosition(takerLocked, providerNFT2, offerId2);
        // now open the position to be used in tests
        (takerId, providerId) = takerNFT.openPairedPosition(takerLocked, providerNFT, offerId);
    }

    function createAndCheckRollOffer()
        internal
        returns (uint takerId, uint rollId, IRolls.RollOffer memory offer)
    {
        uint providerId;
        (takerId, providerId) = createTakerPositions();

        startHoax(provider);
        providerNFT.approve(address(rolls), providerId);
        cashAsset.approve(address(rolls), uint(-minToProvider));

        uint nextRollId = rolls.nextRollId();
        vm.expectEmit(address(rolls));

        emit IRolls.OfferCreated(
            provider,
            nextRollId,
            IRolls.RollOfferStored({
                providerNFT: providerNFT,
                providerId: uint64(providerId),
                deadline: uint32(deadline),
                takerId: uint64(takerId),
                feeDeltaFactorBIPS: int24(feeDeltaFactorBIPS),
                active: true,
                provider: provider,
                feeAmount: feeAmount,
                feeReferencePrice: oraclePrice,
                minPrice: minPrice,
                maxPrice: maxPrice,
                minToProvider: minToProvider
            })
        );
        rollId = rolls.createOffer(
            takerId, feeAmount, feeDeltaFactorBIPS, minPrice, maxPrice, minToProvider, deadline
        );

        // return values
        assertEq(rollId, nextRollId);
        assertEq(rolls.nextRollId(), nextRollId + 1);
        // state
        offer = rolls.getRollOffer(rollId);
        assertEq(offer.takerId, takerId);
        assertEq(offer.feeAmount, feeAmount);
        assertEq(offer.feeDeltaFactorBIPS, feeDeltaFactorBIPS);
        assertEq(offer.feeReferencePrice, oraclePrice);
        assertEq(offer.minPrice, minPrice);
        assertEq(offer.maxPrice, maxPrice);
        assertEq(offer.minToProvider, minToProvider);
        assertEq(offer.deadline, deadline);
        assertEq(address(offer.providerNFT), address(providerNFT));
        assertEq(offer.providerId, providerId);
        assertEq(offer.provider, provider);
        assertTrue(offer.active);
        // nft owner
        assertEq(providerNFT.ownerOf(providerId), address(rolls));
    }

    // avoiding stack too deep errors
    struct ExpectedRoll {
        uint newTakerLocked;
        uint newProviderLocked;
        int toTaker;
        int toProvider;
        int rollFee;
        uint toProtocol;
    }

    function calculateRollAmounts(uint rollId, uint newPrice, int rollFee)
        internal
        view
        returns (ExpectedRoll memory expected)
    {
        // set the fee, whose calculation is NOT tested here
        // only that it's consistent with view and transfer calculations
        expected.rollFee = rollFee;
        // takerId
        uint takerId = rolls.getRollOffer(rollId).takerId;
        // taker position
        CollarTakerNFT.TakerPosition memory oldTakerPos = takerNFT.getPosition(takerId);
        // _newLockedAmounts
        expected.newTakerLocked = takerLocked * newPrice / oraclePrice;
        expected.newProviderLocked =
            expected.newTakerLocked * (callStrikePercent - BIPS_100PCT) / (BIPS_100PCT - ltv);
        // check against taker NFT calc
        assertEq(
            expected.newProviderLocked,
            takerNFT.calculateProviderLocked(expected.newTakerLocked, ltv, callStrikePercent)
        );
        // protocol fee
        (expected.toProtocol,) =
            providerNFT.protocolFee(expected.newProviderLocked, duration, callStrikePercent);
        // _calculateTransferAmounts
        (uint takerSettled, int providerChange) = takerNFT.previewSettlement(oldTakerPos, newPrice);
        int providerSettled = int(oldTakerPos.providerLocked) + providerChange;
        expected.toTaker = int(takerSettled) - int(expected.newTakerLocked) - rollFee;
        expected.toProvider =
            providerSettled - int(expected.newProviderLocked) + rollFee - int(expected.toProtocol);
        return expected; // linter wasn't happy without this
    }

    function checkCalculateTransferAmounts(ExpectedRoll memory expected, uint rollId, uint newPrice)
        internal
        view
    {
        // compare to view
        IRolls.PreviewResults memory preview = rolls.previewRoll(rollId, newPrice);
        assertEq(preview.toTaker, expected.toTaker);
        assertEq(preview.toProvider, expected.toProvider);
        assertEq(preview.rollFee, expected.rollFee);
        assertEq(preview.newTakerLocked, expected.newTakerLocked);
        assertEq(preview.newProviderLocked, expected.newProviderLocked);
        assertEq(preview.protocolFee, expected.toProtocol);

        // check both views are equivalent
        IRolls.PreviewResults memory preview2 = rolls.previewOffer(rolls.getRollOffer(rollId), newPrice);
        assertEq(abi.encode(preview), abi.encode(preview2));
    }

    // stack too deep
    struct Balances {
        uint user;
        uint provider;
        uint rolls;
        uint feeRecipient;
    }

    function checkExecuteRoll(uint rollId, uint newPrice, ExpectedRoll memory expected) internal {
        IRolls.RollOffer memory offer = rolls.getRollOffer(rollId);
        // ids
        uint nextProviderOfferId = providerNFT.nextOfferId();
        uint nextTakerId = takerNFT.nextPositionId();
        uint nextProviderId = providerNFT.nextPositionId();
        uint newTakerId;
        uint newProviderId;

        // balances
        Balances memory balances = Balances({
            user: cashAsset.balanceOf(user1),
            provider: cashAsset.balanceOf(provider),
            rolls: cashAsset.balanceOf(address(rolls)),
            feeRecipient: cashAsset.balanceOf(protocolFeeRecipient)
        });

        // update to new price
        updatePrice(newPrice);
        // Execute roll
        startHoax(user1);
        takerNFT.approve(address(rolls), offer.takerId);
        cashAsset.approve(address(rolls), expected.toTaker < 0 ? uint(-expected.toTaker) : 0);
        vm.expectEmit(address(rolls));
        emit IRolls.OfferExecuted(
            rollId, expected.toTaker, expected.toProvider, expected.rollFee, nextTakerId, nextProviderId
        );
        int toTaker;
        int toProvider;
        (newTakerId, newProviderId, toTaker, toProvider) = rolls.executeRoll(rollId, expected.toTaker);

        // Check return values
        assertEq(newTakerId, nextTakerId);
        assertEq(newProviderId, nextProviderId);
        assertEq(toTaker, expected.toTaker);
        assertEq(toProvider, expected.toProvider);

        // check balances
        assertEq(cashAsset.balanceOf(user1), uint(int(balances.user) + expected.toTaker));
        assertEq(cashAsset.balanceOf(provider), uint(int(balances.provider) + expected.toProvider));
        assertEq(cashAsset.balanceOf(protocolFeeRecipient), balances.feeRecipient + expected.toProtocol);
        assertEq(cashAsset.balanceOf(address(rolls)), balances.rolls); // no change

        // Check offer is no longer active
        assertFalse(rolls.getRollOffer(rollId).active);

        // Check old positions are burned
        expectRevertERC721Nonexistent(offer.takerId);
        takerNFT.ownerOf(offer.takerId);
        expectRevertERC721Nonexistent(offer.providerId);
        providerNFT.ownerOf(offer.providerId);

        // Check new nft owners
        assertEq(takerNFT.ownerOf(newTakerId), user1);
        assertEq(providerNFT.ownerOf(newProviderId), provider);

        // check positions
        checkNewPositions(newTakerId, newProviderId, nextProviderOfferId, newPrice, expected);
    }

    function checkNewPositions(
        uint newTakerId,
        uint newProviderId,
        uint nextProviderOfferId,
        uint newPrice,
        ExpectedRoll memory expected
    ) internal view {
        // Check new taker position details
        CollarTakerNFT.TakerPosition memory newTakerPos = takerNFT.getPosition(newTakerId);
        assertEq(address(newTakerPos.providerNFT), address(providerNFT));
        assertEq(newTakerPos.providerId, newProviderId);
        assertEq(newTakerPos.startPrice, newPrice);
        assertEq(newTakerPos.takerLocked, expected.newTakerLocked);
        assertEq(newTakerPos.providerLocked, expected.newProviderLocked);
        assertEq(newTakerPos.duration, duration);
        assertEq(newTakerPos.expiration, block.timestamp + duration);
        assertFalse(newTakerPos.settled);
        assertEq(newTakerPos.withdrawable, 0);

        // Check new provider position details
        CollarProviderNFT.ProviderPosition memory newProviderPos = providerNFT.getPosition(newProviderId);
        assertEq(newProviderPos.offerId, nextProviderOfferId);
        assertEq(newProviderPos.takerId, newTakerId);
        assertEq(newProviderPos.duration, duration);
        assertEq(newProviderPos.expiration, block.timestamp + duration);
        assertEq(newProviderPos.providerLocked, expected.newProviderLocked);
        assertEq(newProviderPos.putStrikePercent, ltv);
        assertEq(newProviderPos.callStrikePercent, callStrikePercent);
        assertFalse(newProviderPos.settled);
        assertEq(newProviderPos.withdrawable, 0);

        // check miLocked for offer was 0
        assertEq(providerNFT.getOffer(nextProviderOfferId).minLocked, 0);
    }

    function checkExecuteRollForPriceChange(uint newPrice) internal returns (ExpectedRoll memory expected) {
        // create offer at initial price
        (, uint rollId, IRolls.RollOffer memory offer) = createAndCheckRollOffer();
        // not testing the fee calc itself here, so using the view directly
        int rollFee = rolls.calculateRollFee(offer, newPrice);
        // Calculate expected values
        expected = calculateRollAmounts(rollId, newPrice, rollFee);
        // check the view
        checkCalculateTransferAmounts(expected, rollId, newPrice);
        // check execute effects
        checkExecuteRoll(rollId, newPrice, expected);
    }

    // happy cases

    function test_constructor() public {
        Rolls newRolls = new Rolls(takerNFT);
        assertEq(address(newRolls.takerNFT()), address(takerNFT));
        assertEq(address(newRolls.cashAsset()), address(cashAsset));
        assertEq(newRolls.VERSION(), "0.3.0");
    }

    function test_createRollOffer() public {
        createAndCheckRollOffer();
    }

    function test_cancelOffer() public {
        (, uint rollId, IRolls.RollOffer memory offer) = createAndCheckRollOffer();

        startHoax(provider);

        vm.expectEmit(address(rolls));
        emit IRolls.OfferCancelled(rollId, offer.takerId, provider);
        rolls.cancelOffer(rollId);

        offer = rolls.getRollOffer(rollId);
        assertFalse(offer.active);
        // nft owner
        assertEq(providerNFT.ownerOf(offer.providerId), provider);
    }

    function test_executeRoll_no_change_simple() public {
        ExpectedRoll memory expected = checkExecuteRollForPriceChange(oraclePrice);

        /* check specific amounts
        - start 1000 at price 1000, 100 user locked, 200 provider locked
        - no changes except fee being charged
        */
        assertEq(expected.newTakerLocked, cashUnits(100));
        assertEq(expected.newProviderLocked, cashUnits(200));
        assertEq(expected.toTaker, -expected.rollFee);
        assertEq(expected.toProvider, expected.rollFee - int(expected.toProtocol));
    }

    function test_executeRoll_no_change_no_fee() public {
        feeAmount = 0;
        ExpectedRoll memory expected = checkExecuteRollForPriceChange(oraclePrice);

        /* check specific amounts
        - start 1000 at price 1000, 100 user locked, 200 provider locked
        - no changes except fee being charged
        */
        assertEq(expected.newTakerLocked, cashUnits(100));
        assertEq(expected.newProviderLocked, cashUnits(200));
        assertEq(expected.toTaker, 0);
        assertEq(expected.toProvider, -int(expected.toProtocol));
    }

    function test_executeRoll_5_pct_up_simple() public {
        // Move the price up by 5%
        ExpectedRoll memory expected = checkExecuteRollForPriceChange(oraclePrice * 105 / 100);

        /* check specific amounts
        - start 1000 at price 1000, 100 user locked, 200 provider locked
        - price updated from 1000 to 1050
        - user settles 150, provider 150
        - new user locked is 105 (10%), 210 (210%)
        - toTaker = 150 - 105 = 45
        - toProvider = 150 - 210 = -60
        */
        assertEq(expected.newTakerLocked, cashUnits(105));
        assertEq(expected.newProviderLocked, cashUnits(210));
        assertEq(expected.toTaker, int(cashUnits(45)) - expected.rollFee);
        assertEq(expected.toProvider, -int(cashUnits(60)) + expected.rollFee - int(expected.toProtocol));
    }

    function test_executeRoll_5_pct_down_simple() public {
        // Move the price down by 5%
        ExpectedRoll memory expected = checkExecuteRollForPriceChange(oraclePrice * 95 / 100);

        /* check specific amounts
        - start 1000 at price 1000, 100 user locked, 200 provider locked
        - price updated from 1000 to 950
        - user settles 50, provider 250
        - new user locked is 95 (10%), 190 (210%)
        - toTaker = 50 - 95 = -45
        - toProvider = 250 - 190 = 60
        */
        assertEq(expected.newTakerLocked, cashUnits(95));
        assertEq(expected.newProviderLocked, cashUnits(190));
        assertEq(expected.toTaker, -int(cashUnits(45)) - expected.rollFee);
        assertEq(expected.toProvider, int(cashUnits(60)) + expected.rollFee - int(expected.toProtocol));
    }

    function test_executeRoll_30_pct_up_simple() public {
        // increase price tolerance
        maxPrice = oraclePrice * 2;
        minToProvider = -int(cashUnits(260));
        // Move the price up by 30%
        ExpectedRoll memory expected = checkExecuteRollForPriceChange(oraclePrice * 130 / 100);

        /* check specific amounts
        - start 1000 at price 1000, 100 user locked, 200 provider locked
        - price updated from 1000 to 1300
        - user settles 300, provider 0
        - new user locked is 130 (10%), 260 (210%)
        - toTaker = 300 - 130 = 170
        - toProvider = 0 - 260 = -260
        */
        assertEq(expected.newTakerLocked, cashUnits(130));
        assertEq(expected.newProviderLocked, cashUnits(260));
        assertEq(expected.toTaker, int(cashUnits(170)) - expected.rollFee);
        assertEq(expected.toProvider, -int(cashUnits(260)) + expected.rollFee - int(expected.toProtocol));
    }

    function test_executeRoll_20_pct_down_simple() public {
        // increase price tolerance
        minPrice = oraclePrice / 2;
        // Move the price down by 20%
        ExpectedRoll memory expected = checkExecuteRollForPriceChange(oraclePrice * 80 / 100);

        /* check specific amounts
        - start 1000 at price 1000, 100 user locked, 200 provider locked
        - price updated from 1000 to 800
        - user settles 0, provider 300
        - new user locked is 80 (10%), 160 (210%)
        - toTaker = 0 - 80 = -80
        - toProvider = 300 - 160 = 140
        */
        assertEq(expected.newTakerLocked, cashUnits(80));
        assertEq(expected.newProviderLocked, cashUnits(160));
        assertEq(expected.toTaker, -int(cashUnits(80)) - expected.rollFee);
        assertEq(expected.toProvider, int(cashUnits(140)) + expected.rollFee - int(expected.toProtocol));
    }

    function test_calculateRollFee() public {
        (,, IRolls.RollOffer memory offer) = createAndCheckRollOffer();

        // No price change
        assertEq(rolls.calculateRollFee(offer, oraclePrice), feeAmount, "no price change");

        // Price increase, positive fee, positive delta factor
        uint newPrice = oraclePrice * 110 / 100; // 10% increase
        // Expected: 1 + (1 * 50% * 10%) = 1.05
        assertEq(rolls.calculateRollFee(offer, newPrice), int(cashFraction(1.05 ether)), "f+ p+ d+");

        // Price increase, positive fee, negative delta factor
        offer.feeAmount = int(cashUnits(1));
        offer.feeDeltaFactorBIPS = -5000; // -50%
        newPrice = oraclePrice * 110 / 100;
        // Expected: 1 - (1 * 50% * 10%) = 0.95
        assertEq(rolls.calculateRollFee(offer, newPrice), int(cashFraction(0.95 ether)), "f+ p+ d-");

        // Price decrease, positive fee, negative delta factor
        newPrice = oraclePrice * 90 / 100; // 10% decrease
        offer.feeDeltaFactorBIPS = -5000;
        // Expected: 1 + (1 * 50% * 10%) = 1.05
        assertEq(rolls.calculateRollFee(offer, newPrice), int(cashFraction(1.05 ether)), "f+ p- d-");

        // Price decrease, positive fee, positive delta factor
        newPrice = oraclePrice * 90 / 100; // 10% decrease
        offer.feeDeltaFactorBIPS = 5000;
        // Expected: 1 - (1  * 50% * 10%) = 0.95
        assertEq(rolls.calculateRollFee(offer, newPrice), int(cashFraction(0.95 ether)), "f+ p- d+");

        // Price increase, negative fee, positive delta factor
        offer.feeAmount = -int(cashUnits(1));
        newPrice = oraclePrice * 110 / 100;
        // Expected: -1 + (1 * 50% * 10%) = -0.95
        assertEq(rolls.calculateRollFee(offer, newPrice), -int(cashFraction(0.95 ether)), "f- p+ d+");

        // Price increase, negative fee, positive delta factor
        offer.feeAmount = -int(cashUnits(1));
        newPrice = oraclePrice * 110 / 100;
        offer.feeDeltaFactorBIPS = -5000;
        // Expected: -1 - (1 * 50% * 10%) = -1.05
        assertEq(rolls.calculateRollFee(offer, newPrice), -int(cashFraction(1.05 ether)), "f- p+ d-");

        // Price decrease, negative fee, negative delta factor
        offer.feeAmount = -int(cashUnits(1));
        newPrice = oraclePrice * 90 / 100; // 10% decrease
        offer.feeDeltaFactorBIPS = 5000;
        // Expected: -1 - (1 * 50% * 10%) = -1.05
        assertEq(rolls.calculateRollFee(offer, newPrice), -int(cashFraction(1.05 ether)), "f- p- d+");

        // Price decrease, negative fee, negative delta factor
        offer.feeAmount = -int(cashUnits(1));
        newPrice = oraclePrice * 90 / 100; // 10% decrease
        offer.feeDeltaFactorBIPS = -5000;
        // Expected: -1 + (1 * 50% * 10%) = -0.95
        assertEq(rolls.calculateRollFee(offer, newPrice), -int(cashFraction(0.95 ether)), "f- p- d-");

        // Large price change (100% increase)
        offer.feeAmount = int(cashUnits(1));
        newPrice = oraclePrice * 200 / 100;
        offer.feeDeltaFactorBIPS = 5000; // 50%
        // Expected: 1 + (1 * 50% * 100%) = 1.5
        assertEq(rolls.calculateRollFee(offer, newPrice), int(cashFraction(1.5 ether)), "+100%");

        // Zero fee
        offer.feeAmount = 0;
        assertEq(rolls.calculateRollFee(offer, oraclePrice * 150 / 100), 0, "0 fee");

        // Test case 9: Zero delta factor
        offer.feeAmount = int(cashUnits(1));
        offer.feeDeltaFactorBIPS = 0;
        assertEq(rolls.calculateRollFee(offer, oraclePrice * 150 / 100), int(cashUnits(1)), "0 delta");
    }

    function test_calculateRollFee_additional() public {
        (,, IRolls.RollOffer memory offer) = createAndCheckRollOffer();

        // Edge cases for price changes
        assertEq(rolls.calculateRollFee(offer, 0), int(cashFraction(0.5 ether)), "-100% price");

        assertEq(rolls.calculateRollFee(offer, oraclePrice * 2), int(cashFraction(1.5 ether)), "+100%");

        // Edge cases for fee amounts
        offer.feeAmount = type(int).min;
        vm.expectRevert(); // SafeCastOverflowedUintToInt
        rolls.calculateRollFee(offer, oraclePrice * 110 / 100);

        offer.feeAmount = type(int).max;
        vm.expectRevert(); // SafeCastOverflowedUintToInt
        rolls.calculateRollFee(offer, oraclePrice * 110 / 100);

        // Edge cases for delta factors
        offer.feeAmount = int(cashUnits(1));
        offer.feeDeltaFactorBIPS = 10_000; // 100%
        assertEq(rolls.calculateRollFee(offer, 0), 0, "full delta factor no fee");

        offer.feeDeltaFactorBIPS = 10_000; // 100%
        assertEq(
            rolls.calculateRollFee(offer, oraclePrice * 110 / 100), int(cashFraction(1.1 ether)), "linear fee"
        );

        // Precision check
        offer.feeDeltaFactorBIPS = 10_000; // 100%
        assertGt(
            rolls.calculateRollFee(offer, 10_001 * oraclePrice / 10_000),
            int(cashUnits(1)),
            "tiny price change"
        );
    }

    // reverts

    function test_revert_createRollOffer() public {
        (uint takerId, uint providerId) = createTakerPositions();

        // Setup for valid offer
        startHoax(provider);
        providerNFT.approve(address(rolls), providerId);
        cashAsset.approve(address(rolls), uint(-minToProvider));

        // Non-existent taker position
        vm.mockCall(
            address(takerNFT),
            abi.encodeCall(takerNFT.getPosition, (999)),
            abi.encode(ICollarTakerNFT.TakerPosition(providerNFT, 0, 0, 0, 0, 0, 0, 0, 0, false, 0))
        );
        vm.expectRevert("rolls: taker position does not exist");
        rolls.createOffer(999, feeAmount, feeDeltaFactorBIPS, minPrice, maxPrice, minToProvider, deadline);

        // expired taker position
        skip(duration + 1);
        vm.expectRevert("rolls: taker position expired");
        rolls.createOffer(takerId, feeAmount, feeDeltaFactorBIPS, minPrice, maxPrice, minToProvider, deadline);

        // Settled taker position
        takerNFT.settlePairedPosition(takerId);
        vm.expectRevert("rolls: taker position settled");
        rolls.createOffer(takerId, feeAmount, feeDeltaFactorBIPS, minPrice, maxPrice, minToProvider, deadline);

        // new taker position
        updatePrice();
        (takerId, providerId) = createTakerPositions();
        startHoax(provider);
        providerNFT.approve(address(rolls), providerId);

        // Caller is not the provider position owner
        startHoax(user1);
        vm.expectRevert("rolls: not provider ID owner");
        rolls.createOffer(takerId, feeAmount, feeDeltaFactorBIPS, minPrice, maxPrice, minToProvider, deadline);

        // Invalid price bounds
        startHoax(provider);
        vm.expectRevert("rolls: max price lower than min price");
        rolls.createOffer(takerId, feeAmount, feeDeltaFactorBIPS, maxPrice, minPrice, minToProvider, deadline);

        // Invalid fee delta change
        vm.expectRevert("rolls: invalid fee delta change");
        rolls.createOffer(takerId, feeAmount, 10_001, minPrice, maxPrice, minToProvider, deadline);

        vm.expectRevert("rolls: invalid fee delta change");
        rolls.createOffer(takerId, feeAmount, -10_001, minPrice, maxPrice, minToProvider, deadline);

        // Deadline in the past
        vm.expectRevert("rolls: deadline passed");
        rolls.createOffer(
            takerId, feeAmount, feeDeltaFactorBIPS, minPrice, maxPrice, minToProvider, block.timestamp - 1
        );

        // NFT not approved
        providerNFT.approve(address(0), providerId);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC721Errors.ERC721InsufficientApproval.selector, address(rolls), providerId
            )
        );
        rolls.createOffer(takerId, feeAmount, feeDeltaFactorBIPS, minPrice, maxPrice, minToProvider, deadline);

        // cannot create twice
        providerNFT.approve(address(rolls), providerId);
        rolls.createOffer(takerId, feeAmount, feeDeltaFactorBIPS, minPrice, maxPrice, minToProvider, deadline);
        vm.expectRevert("rolls: not provider ID owner");
        rolls.createOffer(takerId, feeAmount, feeDeltaFactorBIPS, minPrice, maxPrice, minToProvider, deadline);
    }

    function test_revert_cancelOffer() public {
        (uint takerId, uint rollId, IRolls.RollOffer memory offer) = createAndCheckRollOffer();

        // Non-existent offer
        uint nonExistentRollId = rollId + 1;
        vm.expectRevert("rolls: not offer provider");
        rolls.cancelOffer(nonExistentRollId);

        // Caller is not the initial provider
        startHoax(user1);
        vm.expectRevert("rolls: not offer provider");
        rolls.cancelOffer(rollId);

        // Offer already executed
        startHoax(user1);
        takerNFT.approve(address(rolls), takerId);
        cashAsset.approve(address(rolls), type(uint).max);
        rolls.executeRoll(rollId, type(int).min);

        startHoax(provider);
        vm.expectRevert("rolls: offer not active");
        rolls.cancelOffer(rollId);

        // create a new offer
        (takerId, rollId, offer) = createAndCheckRollOffer();

        // Offer already cancelled
        startHoax(provider);
        rolls.cancelOffer(rollId);

        vm.expectRevert("rolls: offer not active");
        rolls.cancelOffer(rollId);
    }

    function test_revert_executeRoll_basic_checks() public {
        (uint takerId, uint rollId, IRolls.RollOffer memory offer) = createAndCheckRollOffer();

        // Non-existent offer
        startHoax(user1);
        vm.expectRevert("rolls: invalid offer");
        rolls.executeRoll(rollId + 1, type(int).min);

        // Caller is not the taker NFT owner
        startHoax(provider);
        vm.expectRevert("rolls: not taker ID owner");
        rolls.executeRoll(rollId, type(int).min);

        // Taker position expired
        startHoax(user1);
        skip(duration + 1);
        updatePrice();
        vm.expectRevert("rolls: taker position expired");
        rolls.executeRoll(rollId, type(int).min);

        // new offer
        (takerId, rollId, offer) = createAndCheckRollOffer();
        // Offer already executed
        startHoax(user1);
        takerNFT.approve(address(rolls), takerId);
        cashAsset.approve(address(rolls), type(uint).max);
        rolls.executeRoll(rollId, type(int).min);
        vm.expectRevert("rolls: invalid offer");
        rolls.executeRoll(rollId, type(int).min);
    }

    function test_revert_executeRoll_offer_terms() public {
        (, uint rollId, IRolls.RollOffer memory offer) = createAndCheckRollOffer();

        // Price too high
        uint highPrice = offer.maxPrice + 1;
        updatePrice(highPrice);
        startHoax(user1);
        vm.expectRevert("rolls: price too high");
        rolls.executeRoll(rollId, type(int).min);

        // Price too low
        uint lowPrice = offer.minPrice - 1;
        updatePrice(lowPrice);
        vm.expectRevert("rolls: price too low");
        rolls.executeRoll(rollId, type(int).min);

        // Deadline passed
        deadline = block.timestamp + 1;
        updatePrice(oraclePrice);
        (, rollId,) = createAndCheckRollOffer();
        skip(deadline + 1);
        updatePrice(oraclePrice);
        startHoax(user1);
        vm.expectRevert("rolls: deadline passed");
        rolls.executeRoll(rollId, type(int).min);
    }

    function test_revert_executeRoll_slippage() public {
        (uint takerId, uint rollId, IRolls.RollOffer memory offer) = createAndCheckRollOffer();

        // Taker transfer slippage
        startHoax(user1);
        takerNFT.approve(address(rolls), takerId);
        cashAsset.approve(address(rolls), type(uint).max);
        int toTaker = rolls.previewRoll(rollId, oraclePrice).toTaker;
        vm.expectRevert("rolls: taker transfer slippage");
        rolls.executeRoll(rollId, toTaker + 1);

        minToProvider = minToProvider + 1;
        (takerId, rollId, offer) = createAndCheckRollOffer();
        cashAsset.approve(address(rolls), type(uint).max);

        // Provider transfer slippage
        startHoax(user1);
        takerNFT.approve(address(rolls), takerId);
        cashAsset.approve(address(rolls), type(uint).max);
        uint newPrice = oraclePrice * 110 / 100;
        updatePrice(newPrice);
        vm.expectRevert("rolls: provider transfer slippage");
        rolls.executeRoll(rollId, type(int).min);
    }

    function test_revert_executeRoll_taker_approvals() public {
        (uint takerId, uint rollId,) = createAndCheckRollOffer();

        // Insufficient taker NFT approval
        startHoax(user1);
        cashAsset.approve(address(rolls), type(uint).max);
        vm.expectRevert(
            abi.encodeWithSelector(IERC721Errors.ERC721InsufficientApproval.selector, address(rolls), takerId)
        );
        rolls.executeRoll(rollId, type(int).min);

        // Insufficient cash approval (when taker needs to pay)
        takerNFT.approve(address(rolls), takerId);
        cashAsset.approve(address(rolls), 0);
        uint lowPrice = oraclePrice * 9 / 10;
        updatePrice(lowPrice);
        int toTaker = rolls.previewRoll(rollId, lowPrice).toTaker;
        expectRevertERC20Allowance(address(rolls), 0, uint(-toTaker));
        rolls.executeRoll(rollId, type(int).min);
    }

    function test_revert_executeRoll_provider_approval() public {
        // avoid tripping slippage check
        minToProvider = -int(providerLocked);
        (uint takerId, uint rollId,) = createAndCheckRollOffer();

        // price is higher so that provider will need to pay
        uint highPrice = oraclePrice * 11 / 10;
        updatePrice(highPrice);
        int toProvider = rolls.previewRoll(rollId, highPrice).toProvider;

        // provider revoked approval
        cashAsset.approve(address(rolls), uint(-toProvider) - 1);

        startHoax(user1);
        takerNFT.approve(address(rolls), takerId);
        cashAsset.approve(address(rolls), type(uint).max);
        expectRevertERC20Allowance(address(rolls), uint(-toProvider) - 1, uint(-toProvider));
        rolls.executeRoll(rollId, type(int).min);
    }

    function test_revert_executeRoll_unexpected_withdrawal_amount() public {
        (uint takerId, uint rollId,) = createAndCheckRollOffer();

        startHoax(user1);
        takerNFT.approve(address(rolls), takerId);
        cashAsset.approve(address(rolls), type(uint).max);

        // Mock the cancelPairedPosition function to do nothing
        vm.mockCall(
            address(takerNFT),
            abi.encodeCall(takerNFT.cancelPairedPosition, (takerId)),
            abi.encode(0) // 0 withdrawal
        );

        // Attempt to execute the roll
        vm.expectRevert("rolls: unexpected withdrawal amount");
        rolls.executeRoll(rollId, type(int).min);
    }
}
