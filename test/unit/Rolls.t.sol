// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

import "forge-std/Test.sol";
import { IERC721Errors } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { IERC20Errors } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { TestERC20 } from "../utils/TestERC20.sol";
import { MockEngine } from "../../test/utils/MockEngine.sol";

import { Rolls, IRolls } from "../../src/Rolls.sol";
import { CollarTakerNFT } from "../../src/CollarTakerNFT.sol";
import { ProviderPositionNFT } from "../../src/ProviderPositionNFT.sol";

contract RollsTest is Test {
    TestERC20 cashAsset;
    TestERC20 collateralAsset;
    MockEngine engine;
    CollarTakerNFT takerNFT;
    ProviderPositionNFT providerNFT;
    ProviderPositionNFT providerNFT2;
    Rolls rolls;

    address owner = makeAddr("owner");
    address user1 = makeAddr("user1");
    address provider = makeAddr("provider");

    uint constant BIPS_100PCT = 10_000;
    uint ltv = 9000;
    uint duration = 300;
    uint callStrikeDeviation = 12_000;

    uint twapPrice = 1000 ether;
    uint collateralAmount = 1 ether;
    uint swapAmount = collateralAmount * twapPrice / 1e18; // 1000
    uint putLocked = swapAmount * (BIPS_100PCT - ltv) / BIPS_100PCT; // 100
    uint callLocked = swapAmount * (callStrikeDeviation - BIPS_100PCT) / BIPS_100PCT; // 100
    uint amountToProvide = 100_000 ether;

    // roll offer params
    int rollFeeAmount = 1 ether;
    int rollFeeDeltaFactorBIPS = 5000; // 50%
    uint minPrice = twapPrice * 9 / 10;
    uint maxPrice = twapPrice * 11 / 10;
    int minToProvider = -int(callLocked) / 2;
    uint deadline = block.timestamp + 1 days;

    function setUp() public {
        cashAsset = new TestERC20("TestCash", "TestCash");
        collateralAsset = new TestERC20("TestCollat", "TestCollat");
        engine = new MockEngine(address(0));
        setupEngine();

        takerNFT = new CollarTakerNFT(owner, engine, cashAsset, collateralAsset, "CollarTakerNFT", "TKRNFT");
        providerNFT = new ProviderPositionNFT(
            owner, engine, cashAsset, collateralAsset, address(takerNFT), "ProviderNFT", "PRVNFT"
        );
        rolls = new Rolls(owner, takerNFT, cashAsset);
        // this is to avoid having the paired IDs being equal
        providerNFT2 = new ProviderPositionNFT(
            owner, engine, cashAsset, collateralAsset, address(takerNFT), "ProviderNFT-2", "PRVNFT-2"
        );

        engine.setCollarTakerContractAuth(address(takerNFT), true);
        engine.setProviderContractAuth(address(providerNFT), true);
        engine.setProviderContractAuth(address(providerNFT2), true);

        cashAsset.mint(user1, putLocked * 10);
        cashAsset.mint(provider, amountToProvide * 10);

        engine.setHistoricalAssetPrice(address(collateralAsset), block.timestamp, twapPrice);

        vm.label(address(cashAsset), "TestCash");
        vm.label(address(collateralAsset), "TestCollat");
        vm.label(address(engine), "CollarEngine");
        vm.label(address(takerNFT), "CollarTakerNFT");
        vm.label(address(providerNFT), "ProviderNFT");
        vm.label(address(providerNFT2), "ProviderNFT-2");
        vm.label(address(rolls), "Rolls");
    }

    function setupEngine() public {
        engine.addLTV(ltv);
        engine.addCollarDuration(duration);
        engine.addSupportedCashAsset(address(cashAsset));
        engine.addSupportedCollateralAsset(address(collateralAsset));
    }

    function createProviderOffers() internal returns (uint offerId, uint offerId2) {
        startHoax(provider);
        cashAsset.approve(address(providerNFT), amountToProvide);
        offerId = providerNFT.createOffer(callStrikeDeviation, amountToProvide, ltv, duration);
        // another provider NFT
        cashAsset.approve(address(providerNFT2), amountToProvide);
        offerId2 = providerNFT2.createOffer(callStrikeDeviation, amountToProvide, ltv, duration);
    }

    function createTakerPositions() internal returns (uint takerId, uint providerId) {
        (uint offerId, uint offerId2) = createProviderOffers();
        startHoax(user1);
        cashAsset.approve(address(takerNFT), 2 * putLocked);
        // open "second" position first, such that the taker ID is incremented
        takerNFT.openPairedPosition(putLocked, providerNFT2, offerId2);
        // now open the position to be used in tests
        (takerId, providerId) = takerNFT.openPairedPosition(putLocked, providerNFT, offerId);
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
        emit IRolls.OfferCreated(takerId, provider, providerNFT, providerId, rollFeeAmount, nextRollId);
        rollId = rolls.createRollOffer(
            takerId, rollFeeAmount, rollFeeDeltaFactorBIPS, minPrice, maxPrice, minToProvider, deadline
        );

        // return values
        assertEq(rollId, nextRollId);
        assertEq(rolls.nextRollId(), nextRollId + 1);
        // state
        offer = rolls.getRollOffer(rollId);
        assertEq(offer.takerId, takerId);
        assertEq(offer.rollFeeAmount, rollFeeAmount);
        assertEq(offer.rollFeeDeltaFactorBIPS, rollFeeDeltaFactorBIPS);
        assertEq(offer.rollFeeReferencePrice, twapPrice);
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
        uint newPutLocked;
        uint newCallLocked;
        int toTaker;
        int toProvider;
        int rollFee;
    }

    function calculateRollAmounts(uint rollId, uint newPrice, int rollFee)
        internal
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
        expected.newPutLocked = putLocked * newPrice / twapPrice;
        expected.newCallLocked =
            expected.newPutLocked * (callStrikeDeviation - BIPS_100PCT) / (BIPS_100PCT - ltv);
        // check against taker NFT calc
        assertEq(
            expected.newCallLocked,
            takerNFT.calculateProviderLocked(expected.newPutLocked, ltv, callStrikeDeviation)
        );
        // _calculateTransferAmounts
        (uint takerSettled, int providerChange) = takerNFT.previewSettlement(oldTakerPos, newPrice);
        int providerSettled = int(oldTakerPos.callLockedCash) + providerChange;
        expected.toTaker = int(takerSettled) - int(expected.newPutLocked) - rollFee;
        expected.toProvider = providerSettled - int(expected.newCallLocked) + rollFee;
        return expected; // linter wasn't happy without this
    }

    function checkCalculateTransferAmounts(ExpectedRoll memory expected, uint rollId, uint newPrice)
        internal
    {
        // compare to view
        (int toTakerView, int toProviderView, int rollFeeView) =
            rolls.calculateTransferAmounts(rollId, newPrice);
        assertEq(toTakerView, expected.toTaker);
        assertEq(toProviderView, expected.toProvider);
        assertEq(rollFeeView, expected.rollFee);
    }

    function checkExecuteRoll(uint rollId, uint newPrice, ExpectedRoll memory expected) internal {
        IRolls.RollOffer memory offer = rolls.getRollOffer(rollId);
        // ids
        uint nextTakerId = takerNFT.nextPositionId();
        uint nextProviderId = providerNFT.nextPositionId();
        uint newTakerId;
        uint newProviderId;

        // balances
        uint userBalance = cashAsset.balanceOf(user1);
        uint providerBalance = cashAsset.balanceOf(provider);
        uint rollsBalance = cashAsset.balanceOf(address(rolls));

        // update to new price
        engine.setHistoricalAssetPrice(address(collateralAsset), block.timestamp, newPrice);
        // Execute roll
        startHoax(user1);
        takerNFT.approve(address(rolls), offer.takerId);
        cashAsset.approve(address(rolls), expected.toTaker < 0 ? uint(-expected.toTaker) : 0);
        vm.expectEmit(address(rolls));
        emit IRolls.OfferExecuted(
            rollId,
            offer.takerId,
            offer.providerNFT,
            offer.providerId,
            expected.toTaker,
            expected.toProvider,
            expected.rollFee,
            nextTakerId,
            nextProviderId
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
        assertEq(cashAsset.balanceOf(user1), uint(int(userBalance) + expected.toTaker));
        assertEq(cashAsset.balanceOf(provider), uint(int(providerBalance) + expected.toProvider));
        assertEq(cashAsset.balanceOf(address(rolls)), rollsBalance); // no change

        // Check offer is no longer active
        assertFalse(rolls.getRollOffer(rollId).active);

        // Check old positions are burned
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, offer.takerId));
        takerNFT.ownerOf(offer.takerId);
        vm.expectRevert(
            abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, offer.providerId)
        );
        providerNFT.ownerOf(offer.providerId);

        // Check new nft owners
        assertEq(takerNFT.ownerOf(newTakerId), user1);
        assertEq(providerNFT.ownerOf(newProviderId), provider);

        // check positions
        checkNewPositions(newTakerId, newProviderId, newPrice, expected);
    }

    function checkNewPositions(
        uint newTakerId,
        uint newProviderId,
        uint newPrice,
        ExpectedRoll memory expected
    ) internal {
        // Check new taker position details
        CollarTakerNFT.TakerPosition memory newTakerPos = takerNFT.getPosition(newTakerId);
        assertEq(address(newTakerPos.providerNFT), address(providerNFT));
        assertEq(newTakerPos.providerPositionId, newProviderId);
        assertEq(newTakerPos.initialPrice, newPrice);
        assertEq(newTakerPos.putLockedCash, expected.newPutLocked);
        assertEq(newTakerPos.callLockedCash, expected.newCallLocked);
        assertEq(newTakerPos.duration, duration);
        assertEq(newTakerPos.expiration, block.timestamp + duration);
        assertFalse(newTakerPos.settled);
        assertEq(newTakerPos.withdrawable, 0);

        // Check new provider position details
        ProviderPositionNFT.ProviderPosition memory newProviderPos = providerNFT.getPosition(newProviderId);
        assertEq(newProviderPos.expiration, block.timestamp + duration);
        assertEq(newProviderPos.principal, expected.newCallLocked);
        assertEq(newProviderPos.putStrikeDeviation, ltv);
        assertEq(newProviderPos.callStrikeDeviation, callStrikeDeviation);
        assertFalse(newProviderPos.settled);
        assertEq(newProviderPos.withdrawable, 0);
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
        Rolls newRolls = new Rolls(owner, takerNFT, cashAsset);
        assertEq(address(newRolls.takerNFT()), address(takerNFT));
        assertEq(address(newRolls.cashAsset()), address(cashAsset));
        assertEq(newRolls.VERSION(), "0.2.0");
        assertEq(newRolls.owner(), owner);
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
        ExpectedRoll memory expected = checkExecuteRollForPriceChange(twapPrice);

        /* check specific amounts
        - start 1000 at price 1000, 100 user locked, 200 provider locked
        - no changes except fee being charged
        */
        assertEq(expected.newPutLocked, 100e18);
        assertEq(expected.newCallLocked, 200e18);
        assertEq(expected.toTaker, -expected.rollFee);
        assertEq(expected.toProvider, expected.rollFee);
    }

    function test_executeRoll_no_change_no_fee() public {
        rollFeeAmount = 0;
        ExpectedRoll memory expected = checkExecuteRollForPriceChange(twapPrice);

        /* check specific amounts
        - start 1000 at price 1000, 100 user locked, 200 provider locked
        - no changes except fee being charged
        */
        assertEq(expected.newPutLocked, 100e18);
        assertEq(expected.newCallLocked, 200e18);
        assertEq(expected.toTaker, 0);
        assertEq(expected.toProvider, 0);
    }

    function test_executeRoll_5_pct_up_simple() public {
        // Move the price up by 5%
        ExpectedRoll memory expected = checkExecuteRollForPriceChange(twapPrice * 105 / 100);

        /* check specific amounts
        - start 1000 at price 1000, 100 user locked, 200 provider locked
        - price updated from 1000 to 1050
        - user settles 150, provider 150
        - new user locked is 105 (10%), 210 (210%)
        - toTaker = 150 - 105 = 45
        - toProvider = 150 - 210 = -60
        */
        assertEq(expected.newPutLocked, 105e18);
        assertEq(expected.newCallLocked, 210e18);
        assertEq(expected.toTaker, 45e18 - expected.rollFee);
        assertEq(expected.toProvider, -60e18 + expected.rollFee);
    }

    function test_executeRoll_5_pct_down_simple() public {
        // Move the price down by 5%
        ExpectedRoll memory expected = checkExecuteRollForPriceChange(twapPrice * 95 / 100);

        /* check specific amounts
        - start 1000 at price 1000, 100 user locked, 200 provider locked
        - price updated from 1000 to 950
        - user settles 50, provider 250
        - new user locked is 95 (10%), 190 (210%)
        - toTaker = 50 - 95 = -45
        - toProvider = 250 - 190 = 60
        */
        assertEq(expected.newPutLocked, 95e18);
        assertEq(expected.newCallLocked, 190e18);
        assertEq(expected.toTaker, -45e18 - expected.rollFee);
        assertEq(expected.toProvider, 60e18 + expected.rollFee);
    }

    function test_executeRoll_30_pct_up_simple() public {
        // increase price tolerance
        maxPrice = twapPrice * 2;
        minToProvider = -260e18;
        // Move the price up by 30%
        ExpectedRoll memory expected = checkExecuteRollForPriceChange(twapPrice * 130 / 100);

        /* check specific amounts
        - start 1000 at price 1000, 100 user locked, 200 provider locked
        - price updated from 1000 to 1300
        - user settles 300, provider 0
        - new user locked is 130 (10%), 260 (210%)
        - toTaker = 300 - 130 = 170
        - toProvider = 0 - 260 = -260
        */
        assertEq(expected.newPutLocked, 130e18);
        assertEq(expected.newCallLocked, 260e18);
        assertEq(expected.toTaker, 170e18 - expected.rollFee);
        assertEq(expected.toProvider, -260e18 + expected.rollFee);
    }

    function test_executeRoll_20_pct_down_simple() public {
        // increase price tolerance
        minPrice = twapPrice / 2;
        // Move the price down by 20%
        ExpectedRoll memory expected = checkExecuteRollForPriceChange(twapPrice * 80 / 100);

        /* check specific amounts
        - start 1000 at price 1000, 100 user locked, 200 provider locked
        - price updated from 1000 to 800
        - user settles 0, provider 300
        - new user locked is 80 (10%), 160 (210%)
        - toTaker = 0 - 80 = -80
        - toProvider = 300 - 160 = 140
        */
        assertEq(expected.newPutLocked, 80e18);
        assertEq(expected.newCallLocked, 160e18);
        assertEq(expected.toTaker, -80e18 - expected.rollFee);
        assertEq(expected.toProvider, 140e18 + expected.rollFee);
    }

    function test_calculateRollFee() public {
        (, uint rollId, IRolls.RollOffer memory offer) = createAndCheckRollOffer();

        // No price change
        assertEq(rolls.calculateRollFee(offer, twapPrice), rollFeeAmount, "no price change");

        // Price increase, positive fee, positive delta factor
        uint newPrice = twapPrice * 110 / 100; // 10% increase
        // Expected: 1 ether + (1 ether * 50% * 10%) = 1.05 ether
        assertEq(rolls.calculateRollFee(offer, newPrice), 1.05 ether, "f+ p+ d+");

        // Price increase, positive fee, negative delta factor
        offer.rollFeeAmount = 1 ether;
        offer.rollFeeDeltaFactorBIPS = -5000; // -50%
        newPrice = twapPrice * 110 / 100;
        // Expected: 1 ether - (1 ether * 50% * 10%) = 0.95 ether
        assertEq(rolls.calculateRollFee(offer, newPrice), 0.95 ether, "f+ p+ d-");

        // Price decrease, positive fee, negative delta factor
        newPrice = twapPrice * 90 / 100; // 10% decrease
        offer.rollFeeDeltaFactorBIPS = -5000;
        // Expected: 1 ether + (1 ether * 50% * 10%) = 1.05 ether
        assertEq(rolls.calculateRollFee(offer, newPrice), 1.05 ether, "f+ p- d-");

        // Price decrease, positive fee, positive delta factor
        newPrice = twapPrice * 90 / 100; // 10% decrease
        offer.rollFeeDeltaFactorBIPS = 5000;
        // Expected: 1 ether - (1 ether * 50% * 10%) = 0.95 ether
        assertEq(rolls.calculateRollFee(offer, newPrice), 0.95 ether, "f+ p- d+");

        // Price increase, negative fee, positive delta factor
        offer.rollFeeAmount = -1 ether;
        newPrice = twapPrice * 110 / 100;
        // Expected: -1 ether + (1 ether * 50% * 10%) = -0.95 ether
        assertEq(rolls.calculateRollFee(offer, newPrice), -0.95 ether, "f- p+ d+");

        // Price increase, negative fee, positive delta factor
        offer.rollFeeAmount = -1 ether;
        newPrice = twapPrice * 110 / 100;
        offer.rollFeeDeltaFactorBIPS = -5000;
        // Expected: -1 ether - (1 ether * 50% * 10%) = -1.05 ether
        assertEq(rolls.calculateRollFee(offer, newPrice), -1.05 ether, "f- p+ d-");

        // Price decrease, negative fee, negative delta factor
        offer.rollFeeAmount = -1 ether;
        newPrice = twapPrice * 90 / 100; // 10% decrease
        offer.rollFeeDeltaFactorBIPS = 5000;
        // Expected: -1 ether - (1 ether * 50% * 10%) = -1.05 ether
        assertEq(rolls.calculateRollFee(offer, newPrice), -1.05 ether, "f- p- d+");

        // Price decrease, negative fee, negative delta factor
        offer.rollFeeAmount = -1 ether;
        newPrice = twapPrice * 90 / 100; // 10% decrease
        offer.rollFeeDeltaFactorBIPS = -5000;
        // Expected: -1 ether + (1 ether * 50% * 10%) = -0.95 ether
        assertEq(rolls.calculateRollFee(offer, newPrice), -0.95 ether, "f- p- d-");

        // Large price change (100% increase)
        offer.rollFeeAmount = 1 ether;
        newPrice = twapPrice * 200 / 100;
        offer.rollFeeDeltaFactorBIPS = 5000; // 50%
        // Expected: 1 ether + (1 ether * 50% * 100%) = 1.5 ether
        assertEq(rolls.calculateRollFee(offer, newPrice), 1.5 ether, "+100%");

        // Zero fee
        offer.rollFeeAmount = 0;
        assertEq(rolls.calculateRollFee(offer, twapPrice * 150 / 100), 0, "0 fee");

        // Test case 9: Zero delta factor
        offer.rollFeeAmount = 1 ether;
        offer.rollFeeDeltaFactorBIPS = 0;
        assertEq(rolls.calculateRollFee(offer, twapPrice * 150 / 100), 1 ether, "0 delta");
    }

    function test_calculateRollFee_additional() public {
        (, uint rollId, IRolls.RollOffer memory offer) = createAndCheckRollOffer();

        // Edge cases for price changes
        assertEq(rolls.calculateRollFee(offer, 0), 0.5 ether, "-100% price");

        assertEq(rolls.calculateRollFee(offer, twapPrice * 2), 1.5 ether, "+100%");

        // Edge cases for fee amounts
        offer.rollFeeAmount = type(int).min;
        vm.expectRevert(stdError.arithmeticError);
        rolls.calculateRollFee(offer, twapPrice * 110 / 100);

        offer.rollFeeAmount = type(int).max;
        vm.expectRevert(stdError.arithmeticError);
        rolls.calculateRollFee(offer, twapPrice * 110 / 100);

        // Edge cases for delta factors
        offer.rollFeeAmount = 1 ether;
        offer.rollFeeDeltaFactorBIPS = 10_000; // 100%
        assertEq(rolls.calculateRollFee(offer, 0), 0, "full delta factor no fee");

        offer.rollFeeDeltaFactorBIPS = 10_000; // 100%
        assertEq(rolls.calculateRollFee(offer, twapPrice * 110 / 100), 1.1 ether, "linear fee");

        // Precision check
        offer.rollFeeDeltaFactorBIPS = 10_000; // 100%
        assertGt(rolls.calculateRollFee(offer, 10_001 * twapPrice / 10_000), 1 ether, "tiny price change");
    }

    function test_pause() public {
        // pause
        vm.startPrank(owner);
        vm.expectEmit(address(rolls));
        emit Pausable.Paused(owner);
        rolls.pause();
        // paused view
        assertTrue(rolls.paused());
        // methods are paused
        vm.startPrank(user1);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        rolls.createRollOffer(0, 0, 0, 0, 0, 0, 0);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        rolls.cancelOffer(0);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        rolls.executeRoll(0, 0);
    }

    function test_unpause() public {
        vm.startPrank(owner);
        rolls.pause();
        vm.expectEmit(address(rolls));
        emit Pausable.Unpaused(owner);
        rolls.unpause();
        assertFalse(rolls.paused());
        // check at least one method works now
        createAndCheckRollOffer();
    }

    // reverts

    function test_onlyOwnerMethods() public {
        vm.startPrank(user1);
        bytes4 selector = Ownable.OwnableUnauthorizedAccount.selector;
        vm.expectRevert(abi.encodeWithSelector(selector, user1));
        rolls.pause();
        vm.expectRevert(abi.encodeWithSelector(selector, user1));
        rolls.unpause();
    }

    function test_revert_createRollOffer() public {
        (uint takerId, uint providerId) = createTakerPositions();

        // Setup for valid offer
        startHoax(provider);
        providerNFT.approve(address(rolls), providerId);
        cashAsset.approve(address(rolls), uint(-minToProvider));

        // Non-existent taker position
        vm.expectRevert("taker position doesn't exist");
        rolls.createRollOffer(
            999, rollFeeAmount, rollFeeDeltaFactorBIPS, minPrice, maxPrice, minToProvider, deadline
        );

        // Settled taker position
        skip(duration);
        takerNFT.settlePairedPosition(takerId);
        vm.expectRevert("taker position settled");
        rolls.createRollOffer(
            takerId, rollFeeAmount, rollFeeDeltaFactorBIPS, minPrice, maxPrice, minToProvider, deadline
        );

        // new taker position
        engine.setHistoricalAssetPrice(address(collateralAsset), block.timestamp, twapPrice);
        (takerId, providerId) = createTakerPositions();
        startHoax(provider);
        providerNFT.approve(address(rolls), providerId);

        // Caller is not the provider position owner
        startHoax(user1);
        vm.expectRevert("not provider ID owner");
        rolls.createRollOffer(
            takerId, rollFeeAmount, rollFeeDeltaFactorBIPS, minPrice, maxPrice, minToProvider, deadline
        );

        // Invalid price bounds
        startHoax(provider);
        vm.expectRevert("max price not higher than min price");
        rolls.createRollOffer(
            takerId, rollFeeAmount, rollFeeDeltaFactorBIPS, maxPrice, minPrice, minToProvider, deadline
        );

        // Invalid fee delta change
        vm.expectRevert("invalid fee delta change");
        rolls.createRollOffer(takerId, rollFeeAmount, 10_001, minPrice, maxPrice, minToProvider, deadline);

        vm.expectRevert("invalid fee delta change");
        rolls.createRollOffer(takerId, rollFeeAmount, -10_001, minPrice, maxPrice, minToProvider, deadline);

        // Deadline in the past
        vm.expectRevert("deadline passed");
        rolls.createRollOffer(
            takerId,
            rollFeeAmount,
            rollFeeDeltaFactorBIPS,
            minPrice,
            maxPrice,
            minToProvider,
            block.timestamp - 1
        );

        // Insufficient cash balance for potential payment
        int largeNegativeMinToProvider = -int(cashAsset.balanceOf(provider)) - 1;
        vm.expectRevert("insufficient cash balance");
        rolls.createRollOffer(
            takerId,
            rollFeeAmount,
            rollFeeDeltaFactorBIPS,
            minPrice,
            maxPrice,
            largeNegativeMinToProvider,
            deadline
        );

        // Insufficient cash allowance for potential payment
        cashAsset.approve(address(rolls), uint(-minToProvider) - 1);
        vm.expectRevert("insufficient cash allowance");
        rolls.createRollOffer(
            takerId, rollFeeAmount, rollFeeDeltaFactorBIPS, minPrice, maxPrice, minToProvider, deadline
        );
        cashAsset.approve(address(rolls), uint(-minToProvider));

        // NFT not approved
        providerNFT.approve(address(0), providerId);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC721Errors.ERC721InsufficientApproval.selector, address(rolls), providerId
            )
        );
        rolls.createRollOffer(
            takerId, rollFeeAmount, rollFeeDeltaFactorBIPS, minPrice, maxPrice, minToProvider, deadline
        );

        // cannot create twice
        providerNFT.approve(address(rolls), providerId);
        rolls.createRollOffer(
            takerId, rollFeeAmount, rollFeeDeltaFactorBIPS, minPrice, maxPrice, minToProvider, deadline
        );
        vm.expectRevert("not provider ID owner");
        rolls.createRollOffer(
            takerId, rollFeeAmount, rollFeeDeltaFactorBIPS, minPrice, maxPrice, minToProvider, deadline
        );
    }

    function test_revert_cancelOffer() public {
        (uint takerId, uint rollId, IRolls.RollOffer memory offer) = createAndCheckRollOffer();

        // Non-existent offer
        uint nonExistentRollId = rollId + 1;
        vm.expectRevert("not initial provider");
        rolls.cancelOffer(nonExistentRollId);

        // Caller is not the initial provider
        startHoax(user1);
        vm.expectRevert("not initial provider");
        rolls.cancelOffer(rollId);

        // Offer already executed
        startHoax(user1);
        takerNFT.approve(address(rolls), takerId);
        cashAsset.approve(address(rolls), type(uint).max);
        rolls.executeRoll(rollId, type(int).min);

        startHoax(provider);
        vm.expectRevert("offer not active");
        rolls.cancelOffer(rollId);

        // create a new offer
        (takerId, rollId, offer) = createAndCheckRollOffer();

        // Offer already cancelled
        startHoax(provider);
        rolls.cancelOffer(rollId);

        vm.expectRevert("offer not active");
        rolls.cancelOffer(rollId);
    }

    function test_revert_executeRoll_basic_checks() public {
        (uint takerId, uint rollId, IRolls.RollOffer memory offer) = createAndCheckRollOffer();

        // Non-existent offer
        startHoax(user1);
        vm.expectRevert("invalid offer");
        rolls.executeRoll(rollId + 1, type(int).min);

        // Caller is not the taker NFT owner
        startHoax(provider);
        vm.expectRevert("not taker ID owner");
        rolls.executeRoll(rollId, type(int).min);

        // Taker position already settled
        startHoax(user1);
        skip(duration);
        takerNFT.settlePairedPosition(takerId);
        vm.expectRevert("taker position settled");
        rolls.executeRoll(rollId, type(int).min);

        // new offer
        engine.setHistoricalAssetPrice(address(collateralAsset), block.timestamp, twapPrice);
        (takerId, rollId, offer) = createAndCheckRollOffer();
        // Offer already executed
        startHoax(user1);
        takerNFT.approve(address(rolls), takerId);
        cashAsset.approve(address(rolls), type(uint).max);
        rolls.executeRoll(rollId, type(int).min);
        vm.expectRevert("invalid offer");
        rolls.executeRoll(rollId, type(int).min);
    }

    function test_revert_executeRoll_offer_terms() public {
        (uint takerId, uint rollId, IRolls.RollOffer memory offer) = createAndCheckRollOffer();

        // Price too high
        uint highPrice = offer.maxPrice + 1;
        engine.setHistoricalAssetPrice(address(collateralAsset), block.timestamp, highPrice);
        startHoax(user1);
        vm.expectRevert("price too high");
        rolls.executeRoll(rollId, type(int).min);

        // Price too low
        uint lowPrice = offer.minPrice - 1;
        engine.setHistoricalAssetPrice(address(collateralAsset), block.timestamp, lowPrice);
        vm.expectRevert("price too low");
        rolls.executeRoll(rollId, type(int).min);

        // Deadline passed
        skip(deadline + 1);
        engine.setHistoricalAssetPrice(address(collateralAsset), block.timestamp, twapPrice);
        vm.expectRevert("deadline passed");
        rolls.executeRoll(rollId, type(int).min);
    }

    function test_revert_executeRoll_slippage() public {
        (uint takerId, uint rollId, IRolls.RollOffer memory offer) = createAndCheckRollOffer();

        // Taker transfer slippage
        startHoax(user1);
        takerNFT.approve(address(rolls), takerId);
        cashAsset.approve(address(rolls), type(uint).max);
        (int toTaker,,) = rolls.calculateTransferAmounts(rollId, twapPrice);
        vm.expectRevert("taker transfer slippage");
        rolls.executeRoll(rollId, toTaker + 1);

        minToProvider = minToProvider + 1;
        (takerId, rollId, offer) = createAndCheckRollOffer();
        cashAsset.approve(address(rolls), type(uint).max);

        // Provider transfer slippage
        startHoax(user1);
        takerNFT.approve(address(rolls), takerId);
        cashAsset.approve(address(rolls), type(uint).max);
        uint newPrice = twapPrice * 110 / 100;
        engine.setHistoricalAssetPrice(address(collateralAsset), block.timestamp, newPrice);
        vm.expectRevert("provider transfer slippage");
        rolls.executeRoll(rollId, type(int).min);
    }

    function test_revert_executeRoll_taker_approvals() public {
        (uint takerId, uint rollId, IRolls.RollOffer memory offer) = createAndCheckRollOffer();

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
        uint lowPrice = twapPrice * 9 / 10;
        engine.setHistoricalAssetPrice(address(collateralAsset), block.timestamp, lowPrice);
        (int toTaker,,) = rolls.calculateTransferAmounts(rollId, lowPrice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, address(rolls), 0, uint(-toTaker)
            )
        );
        rolls.executeRoll(rollId, type(int).min);
    }

    function test_revert_executeRoll_provider_approval() public {
        (uint takerId, uint rollId, IRolls.RollOffer memory offer) = createAndCheckRollOffer();

        uint highPrice = twapPrice * 11 / 10;
        engine.setHistoricalAssetPrice(address(collateralAsset), block.timestamp, highPrice);
        (, int toProvider,) = rolls.calculateTransferAmounts(rollId, highPrice);

        // provider revoked approval
        cashAsset.approve(address(rolls), uint(-toProvider) - 1);

        startHoax(user1);
        takerNFT.approve(address(rolls), takerId);
        cashAsset.approve(address(rolls), type(uint).max);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector,
                address(rolls),
                uint(-toProvider) - 1,
                uint(-toProvider)
            )
        );
        rolls.executeRoll(rollId, type(int).min);
    }

    function test_revert_executeRoll_unexpected_withdrawal_amount() public {
        (uint takerId, uint rollId, IRolls.RollOffer memory offer) = createAndCheckRollOffer();

        startHoax(user1);
        takerNFT.approve(address(rolls), takerId);
        cashAsset.approve(address(rolls), type(uint).max);

        // Mock the cancelPairedPosition function to do nothing
        vm.mockCall(
            address(takerNFT),
            abi.encodeWithSelector(takerNFT.cancelPairedPosition.selector, takerId, address(rolls)),
            "" // does nothing
        );

        // Attempt to execute the roll
        vm.expectRevert("unexpected withdrawal amount");
        rolls.executeRoll(rollId, type(int).min);
    }
}
