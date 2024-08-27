// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

import "forge-std/Test.sol";
import { IERC721Errors } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { TestERC20 } from "../utils/TestERC20.sol";

import { BaseAssetPairTestSetup } from "./BaseAssetPairTestSetup.sol";

import { ProviderPositionNFT, IProviderPositionNFT } from "../../src/ProviderPositionNFT.sol";

contract ProviderPositionNFTTest is BaseAssetPairTestSetup {
    address takerContract;

    address recipient = makeAddr("recipient");

    uint putDeviation = ltv;

    bool expectNonZeroFee = true;

    function setUp() public override {
        super.setUp();
        takerContract = address(takerNFT);
        cashAsset.mint(takerContract, largeAmount * 10);
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
            provider, putDeviation, duration, callStrikeDeviation, amount, nextOfferId
        );
        offerId = providerNFT.createOffer(callStrikeDeviation, amount, putDeviation, duration);

        // offer ID
        assertEq(offerId, nextOfferId);
        assertEq(providerNFT.nextOfferId(), nextOfferId + 1);
        // offer
        offer = providerNFT.getOffer(offerId);
        assertEq(offer.provider, provider);
        assertEq(offer.available, amount);
        assertEq(offer.putStrikeDeviation, putDeviation);
        assertEq(offer.callStrikeDeviation, callStrikeDeviation);
        assertEq(offer.duration, duration);
        // balance
        assertEq(cashAsset.balanceOf(provider), balance - amount);
    }

    function checkProtocolFeeView(uint positionAmount) internal view returns (uint expectedFee) {
        // calculate expected
        uint numer = positionAmount * protocolFeeAPR * duration;
        // round up = ((x - 1) / y) + 1
        expectedFee = numer == 0 ? 0 : (1 + ((numer - 1) / BIPS_100PCT / 365 days));
        // no fee for 0 recipient
        expectedFee = (configHub.feeRecipient() == address(0)) ? 0 : expectedFee;
        if (expectNonZeroFee) {
            // do we expect zero fee?
            assertTrue(expectedFee > 0);
        }
        // check the view
        (uint feeView, address toView) = providerNFT.protocolFee(positionAmount, duration);
        assertEq(feeView, expectedFee);
        assertEq(toView, configHub.feeRecipient());
    }

    function createAndCheckPosition(address provider, uint offerAmount, uint positionAmount)
        public
        returns (uint positionId, ProviderPositionNFT.ProviderPosition memory position)
    {
        (uint offerId,) = createAndCheckOffer(provider, offerAmount);
        uint balanceBefore = cashAsset.balanceOf(address(providerNFT));
        uint feeBalanceBefore = cashAsset.balanceOf(protocolFeeRecipient);
        uint nextPosId = providerNFT.nextPositionId();

        uint fee = checkProtocolFeeView(positionAmount);

        startHoax(address(takerContract));
        vm.expectEmit(address(providerNFT));
        emit IProviderPositionNFT.PositionCreated(
            0, putDeviation, duration, callStrikeDeviation, positionAmount, offerId, fee
        );
        vm.expectEmit(address(providerNFT));
        emit IProviderPositionNFT.OfferUpdated(
            offerId, address(takerContract), offerAmount, offerAmount - positionAmount - fee
        );
        (positionId, position) = providerNFT.mintPositionFromOffer(offerId, positionAmount);

        // Check position details
        assertEq(positionId, nextPosId);
        assertEq(position.expiration, block.timestamp + duration);
        assertEq(position.principal, positionAmount);
        assertEq(position.putStrikeDeviation, putDeviation);
        assertEq(position.callStrikeDeviation, callStrikeDeviation);
        assertEq(position.settled, false);
        assertEq(position.withdrawable, 0);
        // check position view
        assertEq(abi.encode(providerNFT.getPosition(positionId)), abi.encode(position));

        // Check updated offer
        ProviderPositionNFT.LiquidityOffer memory updatedOffer = providerNFT.getOffer(offerId);
        assertEq(updatedOffer.available, offerAmount - positionAmount - fee);

        // Check NFT ownership
        assertEq(providerNFT.ownerOf(positionId), provider);

        // balance change
        assertEq(cashAsset.balanceOf(address(providerNFT)), balanceBefore - fee);
        assertEq(cashAsset.balanceOf(protocolFeeRecipient), feeBalanceBefore + fee);
    }

    function test_constructor() public {
        ProviderPositionNFT newProviderNFT = new ProviderPositionNFT(
            owner,
            configHub,
            cashAsset,
            collateralAsset,
            address(takerContract),
            "NewProviderPositionNFT",
            "NPRVNFT"
        );

        assertEq(address(newProviderNFT.owner()), owner);
        assertEq(address(newProviderNFT.configHub()), address(configHub));
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

    function checkSettlePosition(uint positionId, uint principal, int change)
        internal
        returns (uint withdrawal)
    {
        uint initialBalance = cashAsset.balanceOf(address(providerNFT));

        vm.startPrank(address(takerContract));
        if (change > 0) {
            cashAsset.approve(address(providerNFT), uint(change));
        }

        withdrawal = change > 0 ? principal + uint(change) : principal - uint(-change);
        vm.expectEmit(address(providerNFT));
        emit IProviderPositionNFT.PositionSettled(positionId, change, withdrawal);
        providerNFT.settlePosition(positionId, change);

        ProviderPositionNFT.ProviderPosition memory settledPosition = providerNFT.getPosition(positionId);
        assertEq(settledPosition.settled, true);
        assertEq(settledPosition.withdrawable, withdrawal);

        // Check contract balance
        assertEq(cashAsset.balanceOf(address(providerNFT)), initialBalance - principal + withdrawal);
    }

    function checkWithdraw(uint positionId, uint amountToMint, uint withdrawable) internal {
        uint providerBalance = cashAsset.balanceOf(provider);
        uint recipientBalance = cashAsset.balanceOf(recipient);
        uint contractBalance = cashAsset.balanceOf(address(providerNFT));

        vm.startPrank(provider);
        vm.expectEmit(address(providerNFT));
        emit IProviderPositionNFT.WithdrawalFromSettled(positionId, recipient, withdrawable);
        providerNFT.withdrawFromSettled(positionId, recipient);

        // Check balances
        assertEq(cashAsset.balanceOf(recipient), recipientBalance + withdrawable);
        assertEq(cashAsset.balanceOf(provider), providerBalance); // unchanged because sent to recipient
        assertEq(cashAsset.balanceOf(address(providerNFT)), contractBalance - withdrawable);

        // Check position is burned
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, positionId));
        providerNFT.ownerOf(positionId);

        // Check position is zeroed out
        ProviderPositionNFT.ProviderPosition memory settledPosition = providerNFT.getPosition(positionId);
        assertEq(settledPosition.withdrawable, 0);
    }

    function checkCancelAndWithdraw(uint positionId, uint amountToMint) internal {
        uint providerBalance = cashAsset.balanceOf(provider);
        uint recipientBalance = cashAsset.balanceOf(recipient);
        uint contractBalance = cashAsset.balanceOf(address(providerNFT));

        vm.startPrank(provider);
        // position must be owner by taker contract
        providerNFT.transferFrom(provider, takerContract, positionId);
        vm.startPrank(takerContract);
        vm.expectEmit(address(providerNFT));
        emit IProviderPositionNFT.PositionCanceled(
            positionId, recipient, amountToMint, providerNFT.getPosition(positionId).expiration
        );
        providerNFT.cancelAndWithdraw(positionId, recipient);

        // Check balances
        assertEq(cashAsset.balanceOf(recipient), recipientBalance + amountToMint);
        assertEq(cashAsset.balanceOf(provider), providerBalance); // unchanged because sent to recipient
        assertEq(cashAsset.balanceOf(address(providerNFT)), contractBalance - amountToMint);

        // Check position is burned
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, positionId));
        providerNFT.ownerOf(positionId);

        // Check position is zeroed out
        ProviderPositionNFT.ProviderPosition memory canceledPosition = providerNFT.getPosition(positionId);
        assertEq(canceledPosition.withdrawable, 0);
        assertEq(canceledPosition.settled, true);
    }

    /// Happy paths

    function test_createOffer() public returns (uint offerId) {
        (offerId,) = createAndCheckOffer(provider, largeAmount);
    }

    function test_updateOfferAmountIncrease() public {
        // start from an existing offer
        (uint offerId,) = createAndCheckOffer(provider, largeAmount);

        cashAsset.approve(address(providerNFT), largeAmount);
        uint newAmount = largeAmount * 2;
        uint balance = cashAsset.balanceOf(provider);

        vm.expectEmit(address(providerNFT));
        emit IProviderPositionNFT.OfferUpdated(offerId, provider, largeAmount, newAmount);
        providerNFT.updateOfferAmount(offerId, newAmount);

        // next offer id not impacted
        assertEq(providerNFT.nextOfferId(), offerId + 1);
        // offer
        ProviderPositionNFT.LiquidityOffer memory offer = providerNFT.getOffer(offerId);
        assertEq(offer.provider, provider);
        assertEq(offer.available, largeAmount * 2);
        assertEq(offer.putStrikeDeviation, putDeviation);
        assertEq(offer.callStrikeDeviation, callStrikeDeviation);
        assertEq(offer.duration, duration);
        // balance
        assertEq(cashAsset.balanceOf(provider), balance - largeAmount);
    }

    function test_updateOfferAmountDecrease() public {
        // start from an existing offer
        (uint offerId,) = createAndCheckOffer(provider, largeAmount);

        uint newAmount = largeAmount / 2;
        uint balance = cashAsset.balanceOf(provider);

        vm.expectEmit(address(providerNFT));
        emit IProviderPositionNFT.OfferUpdated(offerId, provider, largeAmount, newAmount);
        providerNFT.updateOfferAmount(offerId, newAmount);

        // next offer id not impacted
        assertEq(providerNFT.nextOfferId(), offerId + 1);
        // offer
        ProviderPositionNFT.LiquidityOffer memory offer = providerNFT.getOffer(offerId);
        assertEq(offer.provider, provider);
        assertEq(offer.available, largeAmount / 2);
        assertEq(offer.putStrikeDeviation, putDeviation);
        assertEq(offer.callStrikeDeviation, callStrikeDeviation);
        assertEq(offer.duration, duration);
        // balance
        assertEq(cashAsset.balanceOf(provider), balance + largeAmount / 2);
    }

    function test_updateOfferAmountNoChange() public {
        (uint offerId, ProviderPositionNFT.LiquidityOffer memory previousOffer) =
            createAndCheckOffer(provider, largeAmount);
        uint balance = cashAsset.balanceOf(provider);

        vm.expectEmit(address(providerNFT));
        emit IProviderPositionNFT.OfferUpdated(offerId, provider, largeAmount, largeAmount);
        providerNFT.updateOfferAmount(offerId, largeAmount);

        assertEq(abi.encode(providerNFT.getOffer(offerId)), abi.encode(previousOffer));
        // balance
        assertEq(cashAsset.balanceOf(provider), balance);
    }

    function test_updateOffer_fullAmount() public {
        (uint offerId,) = createAndCheckOffer(provider, largeAmount);
        vm.startPrank(provider);
        providerNFT.updateOfferAmount(offerId, 0);
        assertEq(providerNFT.getOffer(offerId).available, 0);
    }

    function test_mintPositionFromOffer()
        public
        returns (uint positionId, ProviderPositionNFT.ProviderPosition memory position)
    {
        (positionId, position) = createAndCheckPosition(provider, largeAmount, largeAmount / 2);
    }

    function test_mintPositionFromOffer_fullAmount()
        public
        returns (uint positionId, ProviderPositionNFT.ProviderPosition memory position)
    {
        uint fee = checkProtocolFeeView(largeAmount);
        cashAsset.mint(provider, fee);
        (positionId, position) = createAndCheckPosition(provider, largeAmount + fee, largeAmount);
    }

    function test_protocolFee_zeroAddressRecipient() public {
        // check fee is on
        assertFalse(configHub.feeRecipient() == address(0));
        assertFalse(configHub.protocolFeeAPR() == 0);

        // expect zero fee in createAndCheckPosition()
        expectNonZeroFee = false;
        uint amount = 1 ether;

        // zero recipient, non-zero fee (prevented by config-hub setter, so needs to be mocked)
        vm.mockCall(address(configHub), abi.encodeCall(configHub.feeRecipient, ()), abi.encode(address(0)));
        (uint fee, address feeRecipient) = providerNFT.protocolFee(amount, duration);
        assertEq(fee, 0);
        assertEq(feeRecipient, address(0));
        // this value is checked in the createAndCheckPosition helper to be deducted
        uint feeChecked = checkProtocolFeeView(amount);
        assertEq(feeChecked, 0);
        // check minting with 0 recipient non-zero APR works (doesn't try to transfer to zero-address)
        createAndCheckPosition(provider, largeAmount, amount);
    }

    function test_protocolFee_nonDefaultValues() public {
        // check fee is on
        assertFalse(configHub.feeRecipient() == address(0));
        assertFalse(configHub.protocolFeeAPR() == 0);

        // zero APR
        vm.startPrank(owner);
        configHub.setProtocolFeeParams(0, protocolFeeRecipient);
        (uint fee, address feeRecipient) = providerNFT.protocolFee(largeAmount, duration);
        assertEq(feeRecipient, protocolFeeRecipient);
        assertEq(fee, 0);

        // test round up
        configHub.setProtocolFeeParams(1, feeRecipient);
        (fee,) = providerNFT.protocolFee(1, 1); // very small fee
        assertEq(fee, 1); // rounded up

        // test zero numerator
        (fee,) = providerNFT.protocolFee(0, 1);
        assertEq(fee, 0);
        (fee,) = providerNFT.protocolFee(1, 0);
        assertEq(fee, 0);

        // check calculation for specific hardcoded value
        configHub.setProtocolFeeParams(1000, feeRecipient); // 10% per year
        (fee,) = providerNFT.protocolFee(10 ether, 365 days);
        assertEq(fee, 1 ether);
        (fee,) = providerNFT.protocolFee(10 ether + 1, 365 days);
        assertEq(fee, 1 ether + 1); // rounds up
    }

    function test_settlePositionIncrease() public {
        uint amountToMint = largeAmount / 2;
        (uint positionId,) = createAndCheckPosition(provider, largeAmount, amountToMint);

        skip(duration);

        checkSettlePosition(positionId, amountToMint, 1000 ether);
    }

    function test_settlePositionDecrease() public {
        uint amountToMint = largeAmount / 2;
        (uint positionId,) = createAndCheckPosition(provider, largeAmount, amountToMint);

        skip(duration);

        checkSettlePosition(positionId, amountToMint, -1000 ether);
    }

    function test_settlePosition_expirationTimeSensitivity() public {
        (uint positionId,) = createAndCheckPosition(provider, largeAmount, largeAmount / 2);
        skip(duration + 1); // 1 second after expiration still works
        checkSettlePosition(positionId, largeAmount / 2, -1 ether);
    }

    function test_settlePosition_maxLoss() public {
        (uint positionId,) = createAndCheckPosition(provider, largeAmount, largeAmount / 2);
        skip(duration);
        checkSettlePosition(positionId, largeAmount / 2, -int(largeAmount / 2));
        assertEq(providerNFT.getPosition(positionId).withdrawable, 0);
    }

    function test_withdrawFromSettled() public {
        // create settled position
        uint amountToMint = largeAmount / 2;
        (uint positionId,) = createAndCheckPosition(provider, largeAmount, amountToMint);
        skip(duration);
        int positionChange = 1000 ether;

        uint withdrawable = checkSettlePosition(positionId, amountToMint, positionChange);

        checkWithdraw(positionId, amountToMint, withdrawable);
    }

    function test_settleAndWithdraw_removedTaker() public {
        uint amountToMint = largeAmount / 2;
        (uint positionId,) = createAndCheckPosition(provider, largeAmount, amountToMint);
        skip(duration);
        vm.startPrank(owner);
        configHub.setTakerNFTCanOpen(takerContract, false);
        // should work
        uint withdrawable = checkSettlePosition(positionId, amountToMint, 0);
        // should work
        checkWithdraw(positionId, amountToMint, withdrawable);
    }

    function test_cancelAndWithdraw() public {
        uint amountToMint = largeAmount / 2;
        (uint positionId,) = createAndCheckPosition(provider, largeAmount, amountToMint);
        checkCancelAndWithdraw(positionId, amountToMint);
    }

    function test_cancelAndWithdraw_removedTaker() public {
        uint amountToMint = largeAmount / 2;
        (uint positionId,) = createAndCheckPosition(provider, largeAmount, amountToMint);
        skip(duration);
        vm.startPrank(owner);
        configHub.setTakerNFTCanOpen(takerContract, false);
        // should work
        checkCancelAndWithdraw(positionId, amountToMint);
    }

    function test_cancelAndWithdraw_afterExpiration() public {
        uint amountToMint = largeAmount / 2;
        (uint positionId, ProviderPositionNFT.ProviderPosition memory position) =
            createAndCheckPosition(provider, largeAmount, amountToMint);

        skip(duration + 1);

        vm.startPrank(provider);
        // position must be owner by taker contract
        providerNFT.transferFrom(provider, takerContract, positionId);
        vm.startPrank(takerContract);
        vm.expectEmit(address(providerNFT));
        emit IProviderPositionNFT.PositionCanceled(positionId, recipient, amountToMint, position.expiration);
        providerNFT.cancelAndWithdraw(positionId, recipient);
    }

    function test_unpause() public {
        vm.startPrank(owner);
        providerNFT.pause();
        vm.expectEmit(address(providerNFT));
        emit Pausable.Unpaused(owner);
        providerNFT.unpause();
        assertFalse(providerNFT.paused());
        // check at least one method workds now
        createAndCheckOffer(provider, largeAmount);
    }

    /// Interactions between multiple items

    function test_createMultipleOffersFromSameProvider() public {
        uint offerCount = 3;
        uint[] memory offerIds = new uint[](offerCount);

        for (uint i = 0; i < offerCount; i++) {
            uint amount = largeAmount / (i + 1);
            (offerIds[i],) = createAndCheckOffer(provider, amount);
        }

        for (uint i = 0; i < offerCount; i++) {
            ProviderPositionNFT.LiquidityOffer memory offer = providerNFT.getOffer(offerIds[i]);
            assertEq(offer.provider, provider);
            assertEq(offer.available, largeAmount / (i + 1));
            assertEq(offer.putStrikeDeviation, putDeviation);
            assertEq(offer.callStrikeDeviation, callStrikeDeviation);
            assertEq(offer.duration, duration);
        }

        assertEq(providerNFT.nextOfferId(), offerCount);
    }

    function test_mintMultiplePositionsFromSameOffer() public {
        uint positionCount = 3;
        uint[] memory positionIds = new uint[](positionCount);
        uint fee = checkProtocolFeeView(largeAmount);
        uint offerAmount = (largeAmount + fee) * positionCount;

        (uint offerId,) = createAndCheckOffer(provider, offerAmount);

        vm.startPrank(address(takerContract));
        for (uint i = 0; i < positionCount; i++) {
            uint amount = largeAmount;
            (positionIds[i],) = providerNFT.mintPositionFromOffer(offerId, amount);
        }

        ProviderPositionNFT.LiquidityOffer memory updatedOffer = providerNFT.getOffer(offerId);
        assertEq(updatedOffer.available, 0);

        assertEq(cashAsset.balanceOf(protocolFeeRecipient), fee * positionCount);

        for (uint i = 0; i < positionCount; i++) {
            ProviderPositionNFT.ProviderPosition memory position = providerNFT.getPosition(positionIds[i]);
            assertEq(position.principal, largeAmount);
            assertEq(position.putStrikeDeviation, putDeviation);
            assertEq(position.callStrikeDeviation, callStrikeDeviation);
            assertEq(position.settled, false);
            assertEq(position.withdrawable, 0);
            assertEq(providerNFT.ownerOf(positionIds[i]), provider);
        }

        assertEq(providerNFT.nextPositionId(), positionCount);
    }

    function test_transferSettleAndWithdrawPosition() public {
        address newOwner = makeAddr("newOwner");

        // Create and mint a position
        (uint positionId, ProviderPositionNFT.ProviderPosition memory position) =
            createAndCheckPosition(provider, largeAmount, largeAmount / 2);

        // Transfer the position to the new owner
        vm.startPrank(provider);
        providerNFT.transferFrom(provider, newOwner, positionId);

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

    function test_pausableMethods() public {
        // create a position
        (uint positionId,) = createAndCheckPosition(provider, largeAmount, largeAmount / 2);

        // pause
        vm.startPrank(owner);
        vm.expectEmit(address(providerNFT));
        emit Pausable.Paused(owner);
        providerNFT.pause();
        // paused view
        assertTrue(providerNFT.paused());
        // methods are paused
        vm.startPrank(provider);

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
        vm.startPrank(provider);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        providerNFT.transferFrom(provider, recipient, positionId);
    }

    function test_revert_createOffer_invalidCallStrike() public {
        uint minStrike = providerNFT.MIN_CALL_STRIKE_BIPS();
        vm.expectRevert("strike deviation too low");
        providerNFT.createOffer(minStrike - 1, largeAmount, putDeviation, duration);

        uint maxStrike = providerNFT.MAX_CALL_STRIKE_BIPS();
        vm.expectRevert("strike deviation too high");
        providerNFT.createOffer(maxStrike + 1, largeAmount, putDeviation, duration);
    }

    function test_revert_createOffer_ConfigHubValidations() public {
        uint maxPutStrike = providerNFT.MAX_PUT_STRIKE_BIPS();
        vm.expectRevert("invalid put strike deviation");
        providerNFT.createOffer(callStrikeDeviation, largeAmount, maxPutStrike + 1, duration);
        putDeviation = configHub.minLTV() - 1;
        vm.expectRevert("unsupported LTV");
        providerNFT.createOffer(callStrikeDeviation, largeAmount, putDeviation, duration);
        putDeviation = 9000;
        duration = configHub.maxDuration() + 1;
        vm.expectRevert("unsupported duration");
        providerNFT.createOffer(callStrikeDeviation, largeAmount, putDeviation, duration);

        vm.startPrank(owner);
        configHub.setCashAssetSupport(address(cashAsset), false);
        vm.expectRevert("unsupported asset");
        providerNFT.createOffer(callStrikeDeviation, largeAmount, putDeviation, duration);
        configHub.setCashAssetSupport(address(cashAsset), true);

        configHub.setCollateralAssetSupport(address(collateralAsset), false);
        vm.expectRevert("unsupported asset");
        providerNFT.createOffer(callStrikeDeviation, largeAmount, putDeviation, duration);
    }

    function test_revert_updateOfferAmount() public {
        (uint offerId,) = createAndCheckOffer(provider, largeAmount);

        vm.startPrank(address(0xdead));
        vm.expectRevert("not offer provider");
        providerNFT.updateOfferAmount(offerId, largeAmount * 2);
    }

    function test_revert_mintPositionFromOffer_notTrustedTakerContract() public {
        (uint offerId,) = createAndCheckOffer(provider, largeAmount);

        vm.startPrank(address(0xdead));
        vm.expectRevert("unauthorized taker contract");
        providerNFT.mintPositionFromOffer(offerId, largeAmount / 2);

        vm.startPrank(owner);
        configHub.setTakerNFTCanOpen(takerContract, false);
        vm.startPrank(takerContract);
        vm.expectRevert("unsupported taker contract");
        providerNFT.mintPositionFromOffer(offerId, largeAmount / 2);
    }

    function test_revert_mintPositionFromOffer_ConfigHubValidations() public {
        // set a putdeviation that willbe invalid later
        (uint offerId,) = createAndCheckOffer(provider, largeAmount);
        vm.startPrank(owner);
        putDeviation = putDeviation + 100;
        configHub.setLTVRange(putDeviation, putDeviation);
        vm.startPrank(address(takerContract));
        vm.expectRevert("unsupported LTV");
        providerNFT.mintPositionFromOffer(offerId, largeAmount / 2);
        vm.startPrank(owner);
        putDeviation = 9000;
        configHub.setLTVRange(putDeviation, configHub.maxLTV());
        // set a duration that will be invalid later
        configHub.setCollarDurationRange(duration, configHub.maxDuration());
        (offerId,) = createAndCheckOffer(provider, largeAmount);
        vm.startPrank(owner);
        duration = duration + 100;
        configHub.setCollarDurationRange(duration, duration);
        vm.startPrank(address(takerContract));
        vm.expectRevert("unsupported duration");
        providerNFT.mintPositionFromOffer(offerId, largeAmount / 2);
        vm.startPrank(owner);
        duration = 300;
        configHub.setCollarDurationRange(duration, configHub.maxDuration());
        configHub.setCashAssetSupport(address(cashAsset), false);
        vm.expectRevert("unsupported asset");
        vm.startPrank(address(takerContract));
        providerNFT.mintPositionFromOffer(offerId, largeAmount / 2);

        vm.startPrank(owner);
        configHub.setCashAssetSupport(address(cashAsset), true);
        configHub.setCollateralAssetSupport(address(collateralAsset), false);
        vm.startPrank(address(takerContract));
        vm.expectRevert("unsupported asset");
        providerNFT.mintPositionFromOffer(offerId, largeAmount / 2);
    }

    function test_revert_mintPositionFromOffer_amountTooHigh() public {
        (uint offerId,) = createAndCheckOffer(provider, largeAmount);

        vm.startPrank(address(takerContract));
        vm.expectRevert("amount too high");
        providerNFT.mintPositionFromOffer(offerId, largeAmount + 1);
    }

    function test_revert_settlePosition() public {
        (uint positionId,) = createAndCheckPosition(provider, largeAmount, largeAmount / 2);

        vm.startPrank(address(0xdead));
        vm.expectRevert("unauthorized taker contract");
        providerNFT.settlePosition(positionId, 0);

        // allow taker contract
        vm.startPrank(owner);
        configHub.setTakerNFTCanOpen(takerContract, true);

        vm.startPrank(address(takerContract));
        vm.expectRevert("not expired");
        providerNFT.settlePosition(positionId, 0);

        skip(duration);

        vm.expectRevert("loss is too high");
        providerNFT.settlePosition(positionId, -int(largeAmount / 2 + 1));

        vm.expectRevert(stdError.arithmeticError);
        providerNFT.settlePosition(positionId, type(int).min);

        // settle
        vm.startPrank(address(takerContract));
        providerNFT.settlePosition(positionId, 0);

        // can't settle twice
        vm.expectRevert("already settled");
        providerNFT.settlePosition(positionId, 0);
    }

    function test_revert_settlePosition_afterCancel() public {
        (uint positionId,) = createAndCheckPosition(provider, largeAmount, largeAmount / 2);

        skip(duration);

        // transfer the NFT to taker contract
        vm.startPrank(provider);
        providerNFT.transferFrom(provider, takerContract, positionId);
        vm.startPrank(address(takerContract));
        providerNFT.cancelAndWithdraw(positionId, provider);

        // can't settle twice
        vm.expectRevert("already settled");
        providerNFT.settlePosition(positionId, 0);
    }

    function test_revert_withdrawFromSettled() public {
        (uint positionId,) = createAndCheckPosition(provider, largeAmount, largeAmount / 2);

        // not yet minted
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, positionId + 1));
        providerNFT.withdrawFromSettled(positionId + 1, provider);

        // not owner
        vm.startPrank(address(0xdead));
        vm.expectRevert("not position owner");
        providerNFT.withdrawFromSettled(positionId, provider);

        // not settled
        vm.startPrank(provider);
        vm.expectRevert("not settled");
        providerNFT.withdrawFromSettled(positionId, provider);
    }

    function test_revert_cancelAndWithdraw() public {
        (uint positionId,) = createAndCheckPosition(provider, largeAmount, largeAmount / 2);

        vm.startPrank(address(0xdead));
        vm.expectRevert("unauthorized taker contract");
        providerNFT.cancelAndWithdraw(positionId, provider);

        vm.startPrank(owner);
        configHub.setTakerNFTCanOpen(takerContract, true);
        vm.startPrank(address(takerContract));
        vm.expectRevert("caller does not own token");
        providerNFT.cancelAndWithdraw(positionId, provider);

        skip(duration);
        providerNFT.settlePosition(positionId, 0);

        // transfer the NFT to taker contract
        vm.startPrank(provider);
        providerNFT.transferFrom(provider, takerContract, positionId);
        vm.startPrank(address(takerContract));
        vm.expectRevert("already settled");
        providerNFT.cancelAndWithdraw(positionId, provider);
    }
}
