// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

import "forge-std/Test.sol";
import { IERC721Errors } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { TestERC20 } from "../utils/TestERC20.sol";
import { MockEngine } from "../../test/utils/MockEngine.sol";

import { ProviderPositionNFT, IProviderPositionNFT } from "../../src/ProviderPositionNFT.sol";

contract ProviderPositionNFTTest is Test {
    TestERC20 cashAsset;
    TestERC20 collateralAsset;
    MockEngine engine;
    ProviderPositionNFT providerNFT;
    address owner = makeAddr("owner");
    address takerContract = makeAddr("takerContract");
    address provider1 = makeAddr("provider");
    address recipient1 = makeAddr("recipient");
    uint largeAmount = 100_000 ether;
    uint putDeviation = 9000;
    uint duration = 300;
    uint callDeviation = 12_000;

    function setUp() public {
        cashAsset = new TestERC20("TestCash", "TestCash");
        collateralAsset = new TestERC20("TestCollat", "TestCollat");
        cashAsset.mint(takerContract, 1_000_000 ether);
        cashAsset.mint(provider1, 1_000_000 ether);
        engine = setupMockEngine();
        engine.addSupportedCashAsset(address(cashAsset));
        engine.addSupportedCollateralAsset(address(collateralAsset));
        providerNFT = new ProviderPositionNFT(
            owner, engine, cashAsset, collateralAsset, address(takerContract), "ProviderNFT", "ProviderNFT"
        );
        engine.setCollarTakerContractAuth(address(takerContract), true);
        engine.setProviderContractAuth(address(providerNFT), true);
    }

    function setupMockEngine() public returns (MockEngine mockEngine) {
        mockEngine = new MockEngine(address(0));
        mockEngine.addLTV(putDeviation);
        mockEngine.addCollarDuration(duration);
    }

    function createAndCheckOffer(address provider, uint amount)
        public
        returns (uint offerId, ProviderPositionNFT.LiquidityOffer memory offer)
    {
        startHoax(provider);
        cashAsset.approve(address(providerNFT), amount);
        uint balance = cashAsset.balanceOf(provider);
        uint nextOfferId = providerNFT.nextOfferId();

        vm.expectEmit(address(providerNFT));
        emit IProviderPositionNFT.OfferCreated(
            provider,
            putDeviation,
            duration,
            callDeviation,
            amount,
            nextOfferId,
            address(cashAsset),
            address(collateralAsset)
        );
        offerId = providerNFT.createOffer(callDeviation, amount, putDeviation, duration);

        // offer ID
        assertEq(offerId, nextOfferId);
        assertEq(providerNFT.nextOfferId(), nextOfferId + 1);
        // offer
        offer = providerNFT.getOffer(offerId);
        assertEq(offer.provider, provider);
        assertEq(offer.available, amount);
        assertEq(offer.putStrikeDeviation, putDeviation);
        assertEq(offer.callStrikeDeviation, callDeviation);
        assertEq(offer.duration, duration);
        // balance
        assertEq(cashAsset.balanceOf(provider), balance - amount);
    }

    function createAndCheckPosition(address provider, uint offerAmount, uint positionAmount)
        public
        returns (uint positionId, ProviderPositionNFT.ProviderPosition memory position)
    {
        (uint offerId,) = createAndCheckOffer(provider, offerAmount);
        uint initialBalance = cashAsset.balanceOf(address(providerNFT));
        uint nextPosId = providerNFT.nextPositionId();

        startHoax(address(takerContract));
        vm.expectEmit(address(providerNFT));
        emit IProviderPositionNFT.OfferUpdated(
            offerId, address(takerContract), offerAmount, offerAmount - positionAmount
        );
        vm.expectEmit(address(providerNFT));
        emit IProviderPositionNFT.PositionCreated(
            provider, 0, putDeviation, duration, callDeviation, positionAmount, offerId
        );
        (positionId, position,) = providerNFT.mintPositionFromOffer(offerId, positionAmount);

        // Check position details
        assertEq(positionId, nextPosId);
        assertEq(position.expiration, block.timestamp + duration);
        assertEq(position.principal, positionAmount);
        assertEq(position.putStrikeDeviation, putDeviation);
        assertEq(position.callStrikeDeviation, callDeviation);
        assertEq(position.settled, false);
        assertEq(position.withdrawable, 0);
        // check position view
        assertEq(abi.encode(providerNFT.getPosition(positionId)), abi.encode(position));

        // Check updated offer
        ProviderPositionNFT.LiquidityOffer memory updatedOffer = providerNFT.getOffer(offerId);
        assertEq(updatedOffer.available, offerAmount - positionAmount);

        // Check NFT ownership
        assertEq(providerNFT.ownerOf(positionId), provider);

        // no balance change
        assertEq(cashAsset.balanceOf(address(providerNFT)), initialBalance);
    }

    function test_constructor() public {
        ProviderPositionNFT newProviderNFT = new ProviderPositionNFT(
            owner,
            engine,
            cashAsset,
            collateralAsset,
            address(takerContract),
            "NewProviderPositionNFT",
            "NPRVNFT"
        );

        assertEq(address(newProviderNFT.owner()), owner);
        assertEq(address(newProviderNFT.engine()), address(engine));
        assertEq(address(newProviderNFT.cashAsset()), address(cashAsset));
        assertEq(address(newProviderNFT.collateralAsset()), address(collateralAsset));
        assertEq(address(newProviderNFT.collarTakerContract()), takerContract);
        assertEq(newProviderNFT.MIN_CALL_STRIKE_BIPS(), 10_001);
        assertEq(newProviderNFT.MAX_CALL_STRIKE_BIPS(), 100_000);
        assertEq(newProviderNFT.MAX_PUT_STRIKE_BIPS(), 9999);
        assertEq(newProviderNFT.VERSION(), "0.2.0");
        assertEq(newProviderNFT.name(), "NewProviderPositionNFT");
        assertEq(newProviderNFT.symbol(), "NPRVNFT");
    }

    /// Happy paths

    function test_createOffer() public returns (uint offerId) {
        (offerId,) = createAndCheckOffer(provider1, largeAmount);
    }

    function test_updateOfferAmountIncrease() public {
        // start from an existing offer
        (uint offerId,) = createAndCheckOffer(provider1, largeAmount);

        cashAsset.approve(address(providerNFT), largeAmount);
        uint newAmount = largeAmount * 2;
        uint balance = cashAsset.balanceOf(provider1);

        vm.expectEmit(address(providerNFT));
        emit IProviderPositionNFT.OfferUpdated(offerId, provider1, largeAmount, newAmount);
        providerNFT.updateOfferAmount(offerId, newAmount);

        // next offer id not impacted
        assertEq(providerNFT.nextOfferId(), offerId + 1);
        // offer
        ProviderPositionNFT.LiquidityOffer memory offer = providerNFT.getOffer(offerId);
        assertEq(offer.provider, provider1);
        assertEq(offer.available, largeAmount * 2);
        assertEq(offer.putStrikeDeviation, putDeviation);
        assertEq(offer.callStrikeDeviation, callDeviation);
        assertEq(offer.duration, duration);
        // balance
        assertEq(cashAsset.balanceOf(provider1), balance - largeAmount);
    }

    function test_updateOfferAmountDecrease() public {
        // start from an existing offer
        (uint offerId,) = createAndCheckOffer(provider1, largeAmount);

        uint newAmount = largeAmount / 2;
        uint balance = cashAsset.balanceOf(provider1);

        vm.expectEmit(address(providerNFT));
        emit IProviderPositionNFT.OfferUpdated(offerId, provider1, largeAmount, newAmount);
        providerNFT.updateOfferAmount(offerId, newAmount);

        // next offer id not impacted
        assertEq(providerNFT.nextOfferId(), offerId + 1);
        // offer
        ProviderPositionNFT.LiquidityOffer memory offer = providerNFT.getOffer(offerId);
        assertEq(offer.provider, provider1);
        assertEq(offer.available, largeAmount / 2);
        assertEq(offer.putStrikeDeviation, putDeviation);
        assertEq(offer.callStrikeDeviation, callDeviation);
        assertEq(offer.duration, duration);
        // balance
        assertEq(cashAsset.balanceOf(provider1), balance + largeAmount / 2);
    }

    function test_updateOfferAmountNoChange() public {
        (uint offerId, ProviderPositionNFT.LiquidityOffer memory previousOffer) =
            createAndCheckOffer(provider1, largeAmount);
        uint balance = cashAsset.balanceOf(provider1);

        vm.expectEmit(address(providerNFT));
        emit IProviderPositionNFT.OfferUpdated(offerId, provider1, largeAmount, largeAmount);
        providerNFT.updateOfferAmount(offerId, largeAmount);

        assertEq(abi.encode(providerNFT.getOffer(offerId)), abi.encode(previousOffer));
        // balance
        assertEq(cashAsset.balanceOf(provider1), balance);
    }

    function test_updateOffer_fullAmount() public {
        (uint offerId,) = createAndCheckOffer(provider1, largeAmount);
        vm.startPrank(provider1);
        providerNFT.updateOfferAmount(offerId, 0);
        assertEq(providerNFT.getOffer(offerId).available, 0);
    }

    function test_mintPositionFromOffer()
        public
        returns (uint positionId, ProviderPositionNFT.ProviderPosition memory position)
    {
        (positionId, position) = createAndCheckPosition(provider1, largeAmount, largeAmount / 2);
    }

    function test_mintPositionFromOffer_fullAmount()
        public
        returns (uint positionId, ProviderPositionNFT.ProviderPosition memory position)
    {
        (positionId, position) = createAndCheckPosition(provider1, largeAmount, largeAmount);
    }

    function test_settlePositionIncrease() public {
        uint amountToMint = largeAmount / 2;
        (uint positionId, ProviderPositionNFT.ProviderPosition memory position) =
            createAndCheckPosition(provider1, largeAmount, amountToMint);

        skip(duration);

        int positionChange = 1000 ether;
        uint initialBalance = cashAsset.balanceOf(address(providerNFT));

        vm.startPrank(address(takerContract));
        cashAsset.approve(address(providerNFT), uint(positionChange));
        vm.expectEmit(address(providerNFT));
        emit IProviderPositionNFT.PositionSettled(
            positionId, positionChange, amountToMint + uint(positionChange)
        );
        providerNFT.settlePosition(positionId, positionChange);

        ProviderPositionNFT.ProviderPosition memory settledPosition = providerNFT.getPosition(positionId);
        assertEq(settledPosition.settled, true);
        assertEq(settledPosition.withdrawable, amountToMint + uint(positionChange));

        // Check contract balance
        assertEq(cashAsset.balanceOf(address(providerNFT)), initialBalance + uint(positionChange));
    }

    function test_settlePositionDecrease() public {
        uint amountToMint = largeAmount / 2;
        (uint positionId, ProviderPositionNFT.ProviderPosition memory position) =
            createAndCheckPosition(provider1, largeAmount, amountToMint);

        skip(duration);

        int positionChange = -1000 ether;
        uint balanceDecrease = uint(-positionChange);
        uint initialBalance = cashAsset.balanceOf(address(providerNFT));

        vm.startPrank(address(takerContract));
        vm.expectEmit(address(providerNFT));
        emit IProviderPositionNFT.PositionSettled(positionId, positionChange, amountToMint - balanceDecrease);
        providerNFT.settlePosition(positionId, positionChange);

        ProviderPositionNFT.ProviderPosition memory settledPosition = providerNFT.getPosition(positionId);
        assertEq(settledPosition.settled, true);
        assertEq(settledPosition.withdrawable, amountToMint - balanceDecrease);

        // Check contract balance
        assertEq(cashAsset.balanceOf(address(providerNFT)), initialBalance - balanceDecrease);
    }

    function test_settlePosition_expirationTimeSensitivity() public {
        (uint positionId, ProviderPositionNFT.ProviderPosition memory position) =
            createAndCheckPosition(provider1, largeAmount, largeAmount);
        skip(duration + 1); // 1 second after expiration still works
        providerNFT.settlePosition(positionId, -1 ether);
    }

    function test_settlePosition_maxLoss() public {
        (uint positionId, ProviderPositionNFT.ProviderPosition memory position) =
            createAndCheckPosition(provider1, largeAmount, largeAmount);
        skip(duration);
        providerNFT.settlePosition(positionId, -int(largeAmount));
        assertEq(providerNFT.getPosition(positionId).withdrawable, 0);
    }

    function test_withdrawFromSettled() public {
        // create settled position
        uint amountToMint = largeAmount / 2;
        (uint positionId, ProviderPositionNFT.ProviderPosition memory position) =
            createAndCheckPosition(provider1, largeAmount, amountToMint);
        skip(duration);
        int positionChange = 1000 ether;
        cashAsset.approve(address(providerNFT), uint(positionChange));
        providerNFT.settlePosition(positionId, positionChange);

        uint providerBalance = cashAsset.balanceOf(provider1);
        uint recipientBalance = cashAsset.balanceOf(recipient1);
        uint contractBalance = cashAsset.balanceOf(address(providerNFT));

        vm.startPrank(provider1);
        vm.expectEmit(address(providerNFT));
        emit IProviderPositionNFT.WithdrawalFromSettled(
            positionId, recipient1, amountToMint + uint(positionChange)
        );
        providerNFT.withdrawFromSettled(positionId, recipient1);

        // Check balances
        uint withdrawable = amountToMint + uint(positionChange);
        assertEq(cashAsset.balanceOf(recipient1), recipientBalance + withdrawable);
        assertEq(cashAsset.balanceOf(provider1), providerBalance); // unchanged because sent to recipient
        assertEq(cashAsset.balanceOf(address(providerNFT)), contractBalance - withdrawable);

        // Check position is burned
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, positionId));
        providerNFT.ownerOf(positionId);

        // Check position is zeroed out
        ProviderPositionNFT.ProviderPosition memory settledPosition = providerNFT.getPosition(positionId);
        assertEq(settledPosition.withdrawable, 0);
    }

    function test_cancelAndWithdraw() public {
        uint amountToMint = largeAmount / 2;
        (uint positionId, ProviderPositionNFT.ProviderPosition memory position) =
            createAndCheckPosition(provider1, largeAmount, amountToMint);

        uint providerBalance = cashAsset.balanceOf(provider1);
        uint recipientBalance = cashAsset.balanceOf(recipient1);
        uint contractBalance = cashAsset.balanceOf(address(providerNFT));

        vm.startPrank(provider1);
        // position must be owner by taker contract
        providerNFT.transferFrom(provider1, takerContract, positionId);
        vm.startPrank(takerContract);
        vm.expectEmit(address(providerNFT));
        emit IProviderPositionNFT.PositionCanceled(positionId, recipient1, amountToMint, position.expiration);
        providerNFT.cancelAndWithdraw(positionId, recipient1);

        // Check balances
        assertEq(cashAsset.balanceOf(recipient1), recipientBalance + amountToMint);
        assertEq(cashAsset.balanceOf(provider1), providerBalance); // unchanged because sent to recipient
        assertEq(cashAsset.balanceOf(address(providerNFT)), contractBalance - amountToMint);

        // Check position is burned
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, positionId));
        providerNFT.ownerOf(positionId);

        // Check position is zeroed out
        ProviderPositionNFT.ProviderPosition memory canceledPosition = providerNFT.getPosition(positionId);
        assertEq(canceledPosition.withdrawable, 0);
        assertEq(canceledPosition.settled, true);
    }

    function test_cancelAndWithdraw_afterExpiration() public {
        uint amountToMint = largeAmount / 2;
        (uint positionId, ProviderPositionNFT.ProviderPosition memory position) =
            createAndCheckPosition(provider1, largeAmount, amountToMint);

        skip(duration + 1);

        vm.startPrank(provider1);
        // position must be owner by taker contract
        providerNFT.transferFrom(provider1, takerContract, positionId);
        vm.startPrank(takerContract);
        vm.expectEmit(address(providerNFT));
        emit IProviderPositionNFT.PositionCanceled(positionId, recipient1, amountToMint, position.expiration);
        providerNFT.cancelAndWithdraw(positionId, recipient1);
    }

    function test_unpause() public {
        vm.startPrank(owner);
        providerNFT.pause();
        vm.expectEmit(address(providerNFT));
        emit Pausable.Unpaused(owner);
        providerNFT.unpause();
        assertFalse(providerNFT.paused());
        // check at least one method workds now
        createAndCheckOffer(provider1, largeAmount);
    }

    /// Interactions between multiple items

    function test_createMultipleOffersFromSameProvider() public {
        uint offerCount = 3;
        uint[] memory offerIds = new uint[](offerCount);

        for (uint i = 0; i < offerCount; i++) {
            uint amount = largeAmount / (i + 1);
            (offerIds[i],) = createAndCheckOffer(provider1, amount);
        }

        for (uint i = 0; i < offerCount; i++) {
            ProviderPositionNFT.LiquidityOffer memory offer = providerNFT.getOffer(offerIds[i]);
            assertEq(offer.provider, provider1);
            assertEq(offer.available, largeAmount / (i + 1));
            assertEq(offer.putStrikeDeviation, putDeviation);
            assertEq(offer.callStrikeDeviation, callDeviation);
            assertEq(offer.duration, duration);
        }

        assertEq(providerNFT.nextOfferId(), offerCount);
    }

    function test_mintMultiplePositionsFromSameOffer() public {
        uint positionCount = 3;
        uint[] memory positionIds = new uint[](positionCount);
        uint offerAmount = largeAmount * positionCount;

        (uint offerId,) = createAndCheckOffer(provider1, offerAmount);

        vm.startPrank(address(takerContract));
        for (uint i = 0; i < positionCount; i++) {
            uint amount = largeAmount;
            (positionIds[i],,) = providerNFT.mintPositionFromOffer(offerId, amount);
        }

        ProviderPositionNFT.LiquidityOffer memory updatedOffer = providerNFT.getOffer(offerId);
        assertEq(updatedOffer.available, 0);

        for (uint i = 0; i < positionCount; i++) {
            ProviderPositionNFT.ProviderPosition memory position = providerNFT.getPosition(positionIds[i]);
            assertEq(position.principal, largeAmount);
            assertEq(position.putStrikeDeviation, putDeviation);
            assertEq(position.callStrikeDeviation, callDeviation);
            assertEq(position.settled, false);
            assertEq(position.withdrawable, 0);
            assertEq(providerNFT.ownerOf(positionIds[i]), provider1);
        }

        assertEq(providerNFT.nextPositionId(), positionCount);
    }

    function test_transferSettleAndWithdrawPosition() public {
        address newOwner = makeAddr("newOwner");

        // Create and mint a position
        (uint positionId, ProviderPositionNFT.ProviderPosition memory position) =
            createAndCheckPosition(provider1, largeAmount, largeAmount / 2);

        // Transfer the position to the new owner
        vm.startPrank(provider1);
        providerNFT.transferFrom(provider1, newOwner, positionId);

        assertEq(providerNFT.ownerOf(positionId), newOwner);

        // Skip to after expiration
        skip(duration);

        // Settle the position
        int positionChange = 1000 ether;
        vm.startPrank(address(takerContract));
        cashAsset.approve(address(providerNFT), uint(positionChange));
        providerNFT.settlePosition(positionId, positionChange);

        // Check that the position is settled
        ProviderPositionNFT.ProviderPosition memory settledPosition = providerNFT.getPosition(positionId);
        assertEq(settledPosition.settled, true);
        assertEq(settledPosition.withdrawable, position.principal + uint(positionChange));

        // Withdraw from the settled position
        uint newOwnerBalance = cashAsset.balanceOf(newOwner);
        vm.startPrank(newOwner);
        providerNFT.withdrawFromSettled(positionId, newOwner);

        // Check that the withdrawal was successful
        assertEq(cashAsset.balanceOf(newOwner) - newOwnerBalance, position.principal + uint(positionChange));

        // Check that the position is burned after withdrawal
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, positionId));
        providerNFT.ownerOf(positionId);
    }

    /// Reverts

    function test_constructor_reverts() public {
        vm.expectRevert("unsupported asset");
        new ProviderPositionNFT(
            owner,
            engine,
            TestERC20(address(0xdead)),
            collateralAsset,
            address(takerContract),
            "NewProviderPositionNFT",
            "NPRVNFT"
        );

        vm.expectRevert("unsupported asset");
        new ProviderPositionNFT(
            owner,
            engine,
            cashAsset,
            TestERC20(address(0xdead)),
            address(takerContract),
            "NewProviderPositionNFT",
            "NPRVNFT"
        );
    }

    function test_pause() public {
        // create a position
        (uint positionId,) = createAndCheckPosition(provider1, largeAmount, largeAmount);

        // pause
        vm.startPrank(owner);
        vm.expectEmit(address(providerNFT));
        emit Pausable.Paused(owner);
        providerNFT.pause();
        // paused view
        assertTrue(providerNFT.paused());
        // methods are paused
        vm.startPrank(provider1);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        providerNFT.createOffer(0, 0, 0, 0);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        providerNFT.updateOfferAmount(0, 0);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        providerNFT.mintPositionFromOffer(0, 0);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        providerNFT.settlePosition(0, 0);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        providerNFT.withdrawFromSettled(0, address(0));
        vm.expectRevert(Pausable.EnforcedPause.selector);
        providerNFT.cancelAndWithdraw(0, address(0));

        // transfers are paused
        vm.startPrank(provider1);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        providerNFT.transferFrom(provider1, recipient1, positionId);
    }

    function test_onlyOwnerCanPauseUnpause() public {
        vm.startPrank(provider1);
        bytes4 selector = Ownable.OwnableUnauthorizedAccount.selector;
        vm.expectRevert(abi.encodeWithSelector(selector, provider1));
        providerNFT.pause();
        vm.expectRevert(abi.encodeWithSelector(selector, provider1));
        providerNFT.unpause();
    }

    function test_revert_createOffer_invalidCallStrike() public {
        uint minStrike = providerNFT.MIN_CALL_STRIKE_BIPS();
        vm.expectRevert("strike deviation too low");
        providerNFT.createOffer(minStrike - 1, largeAmount, putDeviation, duration);

        uint maxStrike = providerNFT.MAX_CALL_STRIKE_BIPS();
        vm.expectRevert("strike deviation too high");
        providerNFT.createOffer(maxStrike + 1, largeAmount, putDeviation, duration);
    }

    function test_revert_createOffer_EngineValidations() public {
        uint maxPutStrike = providerNFT.MAX_PUT_STRIKE_BIPS();
        vm.expectRevert("invalid put strike deviation");
        providerNFT.createOffer(callDeviation, largeAmount, maxPutStrike + 1, duration);

        vm.expectRevert("unsupported LTV");
        providerNFT.createOffer(callDeviation, largeAmount, putDeviation + 1, duration);

        vm.expectRevert("unsupported duration");
        providerNFT.createOffer(callDeviation, largeAmount, putDeviation, duration + 1);

        engine.removeSupportedCashAsset(address(cashAsset));
        vm.expectRevert("unsupported asset");
        providerNFT.createOffer(callDeviation, largeAmount, putDeviation, duration);
        engine.addSupportedCashAsset(address(cashAsset));

        engine.removeSupportedCollateralAsset(address(collateralAsset));
        vm.expectRevert("unsupported asset");
        providerNFT.createOffer(callDeviation, largeAmount, putDeviation, duration);
    }

    function test_revert_updateOfferAmount() public {
        (uint offerId,) = createAndCheckOffer(provider1, largeAmount);

        vm.startPrank(address(0xdead));
        vm.expectRevert("not offer provider");
        providerNFT.updateOfferAmount(offerId, largeAmount * 2);
    }

    function test_revert_mintPositionFromOffer_notTrustedTakerContract() public {
        (uint offerId,) = createAndCheckOffer(provider1, largeAmount);

        vm.startPrank(address(0xdead));
        vm.expectRevert("unauthorized taker contract");
        providerNFT.mintPositionFromOffer(offerId, largeAmount / 2);

        vm.stopPrank();
        engine.setCollarTakerContractAuth(takerContract, false);
        vm.expectRevert("unsupported taker contract");
        providerNFT.mintPositionFromOffer(offerId, largeAmount / 2);
    }

    function test_revert_mintPositionFromOffer_EngineValidations() public {
        (uint offerId,) = createAndCheckOffer(provider1, largeAmount);

        vm.stopPrank(); // sender is engine owner
        engine.removeLTV(putDeviation);
        vm.startPrank(address(takerContract));
        vm.expectRevert("unsupported LTV");
        providerNFT.mintPositionFromOffer(offerId, largeAmount / 2);

        vm.stopPrank();
        engine.addLTV(putDeviation);
        engine.removeCollarDuration(duration);
        vm.startPrank(address(takerContract));
        vm.expectRevert("unsupported duration");
        providerNFT.mintPositionFromOffer(offerId, largeAmount / 2);

        vm.stopPrank();
        engine.addCollarDuration(duration);
        engine.removeSupportedCashAsset(address(cashAsset));
        vm.expectRevert("unsupported asset");
        vm.startPrank(address(takerContract));
        providerNFT.mintPositionFromOffer(offerId, largeAmount / 2);

        vm.stopPrank();
        engine.addSupportedCashAsset(address(cashAsset));
        engine.removeSupportedCollateralAsset(address(collateralAsset));
        vm.startPrank(address(takerContract));
        vm.expectRevert("unsupported asset");
        providerNFT.mintPositionFromOffer(offerId, largeAmount / 2);
    }

    function test_revert_mintPositionFromOffer_amountTooHigh() public {
        (uint offerId,) = createAndCheckOffer(provider1, largeAmount);

        vm.startPrank(address(takerContract));
        vm.expectRevert("amount too high");
        providerNFT.mintPositionFromOffer(offerId, largeAmount + 1);
    }

    function test_revert_settlePosition() public {
        (uint positionId,) = createAndCheckPosition(provider1, largeAmount, largeAmount / 2);

        vm.startPrank(address(0xdead));
        vm.expectRevert("unauthorized taker contract");
        providerNFT.settlePosition(positionId, 0);

        vm.stopPrank();
        engine.setCollarTakerContractAuth(takerContract, false);
        vm.expectRevert("unsupported taker contract");
        providerNFT.settlePosition(positionId, 0);

        // allow taker contract
        vm.stopPrank();
        engine.setCollarTakerContractAuth(takerContract, true);

        vm.startPrank(address(takerContract));
        vm.expectRevert("not expired");
        providerNFT.settlePosition(positionId, 0);

        skip(duration);

        vm.expectRevert("loss is too high");
        providerNFT.settlePosition(positionId, -int(largeAmount / 2 + 1));

        // settle
        vm.startPrank(address(takerContract));
        providerNFT.settlePosition(positionId, 0);

        // can't settle twice
        vm.expectRevert("already settled");
        providerNFT.settlePosition(positionId, 0);
    }

    function test_revert_settlePosition_afterCancel() public {
        (uint positionId,) = createAndCheckPosition(provider1, largeAmount, largeAmount / 2);

        skip(duration);

        // transfer the NFT to taker contract
        vm.startPrank(provider1);
        providerNFT.transferFrom(provider1, takerContract, positionId);
        vm.startPrank(address(takerContract));
        providerNFT.cancelAndWithdraw(positionId, provider1);

        // can't settle twice
        vm.expectRevert("already settled");
        providerNFT.settlePosition(positionId, 0);
    }

    function test_revert_withdrawFromSettled() public {
        (uint positionId,) = createAndCheckPosition(provider1, largeAmount, largeAmount / 2);

        // not yet minted
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, positionId + 1));
        providerNFT.withdrawFromSettled(positionId + 1, provider1);

        // not owner
        vm.startPrank(address(0xdead));
        vm.expectRevert("not position owner");
        providerNFT.withdrawFromSettled(positionId, provider1);

        // not settled
        vm.startPrank(provider1);
        vm.expectRevert("not settled");
        providerNFT.withdrawFromSettled(positionId, provider1);
    }

    function test_revert_cancelAndWithdraw() public {
        (uint positionId,) = createAndCheckPosition(provider1, largeAmount, largeAmount / 2);

        vm.startPrank(address(0xdead));
        vm.expectRevert("unauthorized taker contract");
        providerNFT.cancelAndWithdraw(positionId, provider1);

        vm.stopPrank();
        engine.setCollarTakerContractAuth(takerContract, false);
        vm.expectRevert("unsupported taker contract");
        providerNFT.cancelAndWithdraw(positionId, provider1);

        engine.setCollarTakerContractAuth(takerContract, true);
        vm.startPrank(address(takerContract));
        vm.expectRevert("caller does not own token");
        providerNFT.cancelAndWithdraw(positionId, provider1);

        skip(duration);
        providerNFT.settlePosition(positionId, 0);

        // transfer the NFT to taker contract
        vm.startPrank(provider1);
        providerNFT.transferFrom(provider1, takerContract, positionId);
        vm.startPrank(address(takerContract));
        vm.expectRevert("already settled");
        providerNFT.cancelAndWithdraw(positionId, provider1);
    }
}
