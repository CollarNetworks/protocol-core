// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

import "forge-std/Test.sol";
import { IERC721Errors } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { IERC20Errors } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { TestERC20 } from "../utils/TestERC20.sol";
import { MockEngine } from "../../test/utils/MockEngine.sol";
import { MockUniRouter } from "../../test/utils/MockUniRouter.sol";

import { Rolls, IRolls } from "../../src/Rolls.sol";
import { CollarTakerNFT } from "../../src/CollarTakerNFT.sol";
import { ProviderPositionNFT } from "../../src/ProviderPositionNFT.sol";

contract RollsTest is Test {
    TestERC20 cashAsset;
    TestERC20 collateralAsset;
    MockEngine engine;
    MockUniRouter uniRouter;
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
    uint minPrice = twapPrice * 9 / BIPS_100PCT;
    uint maxPrice = twapPrice * 11 / 10;
    int minToProvider = -int(callLocked) / 2;
    uint deadline = block.timestamp + 1 days;

    function setUp() public {
        cashAsset = new TestERC20("TestCash", "TestCash");
        collateralAsset = new TestERC20("TestCollat", "TestCollat");
        uniRouter = new MockUniRouter();
        engine = new MockEngine(address(uniRouter));
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
        vm.label(address(uniRouter), "UniRouter");
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

        uint nextRollId = rolls.nextRollId();

        cashAsset.approve(address(rolls), uint(-minToProvider));

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
            takerNFT.calculateProviderLocked(expected.newPutLocked, ltv, callStrikeDeviation);
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
        // stack to deep
        {
            // balances
            uint userBalance = cashAsset.balanceOf(user1);
            uint providerBalance = cashAsset.balanceOf(provider);
            uint rollsBalance = cashAsset.balanceOf(address(rolls));

            // update to new price
            engine.setHistoricalAssetPrice(address(collateralAsset), block.timestamp, newPrice);
            // Execute roll
            startHoax(user1);
            takerNFT.approve(address(rolls), offer.takerId);
            cashAsset.approve(address(rolls), 0);
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
        }

        // Check offer is no longer active
        offer = rolls.getRollOffer(rollId);
        assertFalse(offer.active);

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

    function test_executeRoll_5_pct_up_simple() public {
        // create offer at initial price
        (, uint rollId, IRolls.RollOffer memory offer) = createAndCheckRollOffer();

        // Move the price up by 5%
        uint newPrice = twapPrice * 105 / 100;
        // not testing the fee calc itself here, so using the view directly
        int rollFee = rolls.calculateRollFee(offer, newPrice);
        // Calculate expected values
        ExpectedRoll memory expected = calculateRollAmounts(rollId, newPrice, rollFee);

        // check specific amounts
        assertEq(expected.newPutLocked, 105e18);
        assertEq(expected.newCallLocked, 210e18);
        assertEq(expected.toTaker, 45e18 - rollFee);
        assertEq(expected.toProvider, -60e18 + rollFee);
        assertEq(expected.rollFee, rollFee);

        // check the view
        checkCalculateTransferAmounts(expected, rollId, newPrice);

        // check execute effects
        checkExecuteRoll(rollId, newPrice, expected);
    }
}
