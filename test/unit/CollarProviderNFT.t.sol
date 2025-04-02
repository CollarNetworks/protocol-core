// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

import "forge-std/Test.sol";
import { IERC721Errors, Strings } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { TestERC20 } from "../utils/TestERC20.sol";

import { BaseAssetPairTestSetup } from "./BaseAssetPairTestSetup.sol";

import { CollarProviderNFT, ICollarProviderNFT } from "../../src/CollarProviderNFT.sol";

contract CollarProviderNFTTest is BaseAssetPairTestSetup {
    address takerContract;

    uint putPercent = ltv;
    uint minLocked = 0;

    bool expectNonZeroFee = true;

    function setUp() public override {
        super.setUp();
        takerContract = address(takerNFT);
        cashAsset.mint(takerContract, largeCash * 10);
    }

    function createAndCheckOffer(address provider, uint amount)
        public
        returns (uint offerId, CollarProviderNFT.LiquidityOffer memory offer)
    {
        startHoax(provider);
        cashAsset.approve(address(providerNFT), amount);
        uint balance = cashAsset.balanceOf(provider);
        uint nextOfferId = providerNFT.nextOfferId();

        vm.expectEmit(address(providerNFT));
        emit ICollarProviderNFT.OfferCreated(
            provider, putPercent, duration, callStrikePercent, amount, nextOfferId, minLocked
        );
        offerId = providerNFT.createOffer(callStrikePercent, amount, putPercent, duration, minLocked);

        // offer ID
        assertEq(offerId, nextOfferId);
        assertEq(providerNFT.nextOfferId(), nextOfferId + 1);
        // offer
        offer = providerNFT.getOffer(offerId);
        assertEq(offer.provider, provider);
        assertEq(offer.available, amount);
        assertEq(offer.putStrikePercent, putPercent);
        assertEq(offer.callStrikePercent, callStrikePercent);
        assertEq(offer.duration, duration);
        // balance
        assertEq(cashAsset.balanceOf(provider), balance - amount);
    }

    function checkProtocolFeeView(uint positionAmount) internal view returns (uint expectedFee) {
        // calculate expected
        uint numer = positionAmount * protocolFeeAPR * duration;
        // round up = ((x - 1) / y) + 1
        expectedFee = numer == 0 ? 0 : (1 + ((numer - 1) / (callStrikePercent - BIPS_100PCT) / 365 days));
        // no fee for 0 recipient
        expectedFee = (configHub.feeRecipient() == address(0)) ? 0 : expectedFee;
        if (positionAmount != 0 && expectNonZeroFee) {
            // do we expect zero fee?
            assertTrue(expectedFee > 0);
        }
        // check the view
        (uint feeView, address toView) = providerNFT.protocolFee(positionAmount, duration, callStrikePercent);
        assertEq(feeView, expectedFee);
        assertEq(toView, configHub.feeRecipient());
    }

    struct Balances {
        uint providerContract;
        uint feeRecipient;
    }

    function createAndCheckPosition(address provider, uint offerAmount, uint positionAmount)
        public
        returns (uint positionId, CollarProviderNFT.ProviderPosition memory position)
    {
        (uint offerId,) = createAndCheckOffer(provider, offerAmount);
        Balances memory balances;
        balances.providerContract = cashAsset.balanceOf(address(providerNFT));
        balances.feeRecipient = cashAsset.balanceOf(protocolFeeRecipient);
        uint nextPosId = providerNFT.nextPositionId();

        uint fee = checkProtocolFeeView(positionAmount);
        uint takerId = 1000; // arbitrary

        CollarProviderNFT.ProviderPosition memory expectedPosition = ICollarProviderNFT.ProviderPosition({
            offerId: offerId,
            takerId: takerId,
            duration: duration,
            expiration: block.timestamp + duration,
            providerLocked: positionAmount,
            putStrikePercent: putPercent,
            callStrikePercent: callStrikePercent,
            settled: false,
            withdrawable: 0
        });
        startHoax(address(takerContract));
        vm.expectEmit(address(providerNFT));
        emit ICollarProviderNFT.OfferUpdated(
            offerId, provider, offerAmount, offerAmount - positionAmount - fee
        );
        vm.expectEmit(address(providerNFT));
        emit ICollarProviderNFT.PositionCreated(nextPosId, offerId, fee, positionAmount);
        positionId = providerNFT.mintFromOffer(offerId, positionAmount, takerId);
        position = providerNFT.getPosition(positionId);

        // Check position details
        assertEq(positionId, nextPosId);
        // check the position (from the view)
        assertEq(abi.encode(position), abi.encode(expectedPosition));
        assertEq(providerNFT.expiration(positionId), expectedPosition.expiration);

        // Check updated offer
        CollarProviderNFT.LiquidityOffer memory updatedOffer = providerNFT.getOffer(offerId);
        assertEq(updatedOffer.available, offerAmount - positionAmount - fee);

        // Check NFT ownership
        assertEq(providerNFT.ownerOf(positionId), provider);

        // balance change
        assertEq(cashAsset.balanceOf(address(providerNFT)), balances.providerContract - fee);
        assertEq(cashAsset.balanceOf(protocolFeeRecipient), balances.feeRecipient + fee);
    }

    function test_constructor() public {
        CollarProviderNFT newProviderNFT = new CollarProviderNFT(
            configHub, cashAsset, underlying, address(takerContract), "NewCollarProviderNFT", "NPRVNFT"
        );

        assertEq(address(newProviderNFT.configHubOwner()), owner);
        assertEq(address(newProviderNFT.configHub()), address(configHub));
        assertEq(address(newProviderNFT.cashAsset()), address(cashAsset));
        assertEq(address(newProviderNFT.underlying()), address(underlying));
        assertEq(address(newProviderNFT.taker()), takerContract);
        assertEq(newProviderNFT.MIN_CALL_STRIKE_BIPS(), 10_001);
        assertEq(newProviderNFT.MAX_CALL_STRIKE_BIPS(), 100_000);
        assertEq(newProviderNFT.MAX_PUT_STRIKE_BIPS(), 9999);
        assertEq(newProviderNFT.MAX_PROTOCOL_FEE_BIPS(), 100);
        assertEq(newProviderNFT.VERSION(), "0.3.0");
        assertEq(newProviderNFT.name(), "NewCollarProviderNFT");
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
        emit ICollarProviderNFT.PositionSettled(positionId, change, withdrawal);
        providerNFT.settlePosition(positionId, change);

        CollarProviderNFT.ProviderPosition memory settledPosition = providerNFT.getPosition(positionId);
        assertEq(settledPosition.settled, true);
        assertEq(settledPosition.withdrawable, withdrawal);

        // Check contract balance
        assertEq(cashAsset.balanceOf(address(providerNFT)), initialBalance - principal + withdrawal);
    }

    function checkWithdraw(uint positionId, uint withdrawable) internal {
        uint providerBalance = cashAsset.balanceOf(provider);
        uint contractBalance = cashAsset.balanceOf(address(providerNFT));

        vm.startPrank(provider);
        vm.expectEmit(address(providerNFT));
        emit ICollarProviderNFT.WithdrawalFromSettled(positionId, withdrawable);
        uint withdrawal = providerNFT.withdrawFromSettled(positionId);

        // return value
        assertEq(withdrawal, withdrawable);

        // Check balances
        assertEq(cashAsset.balanceOf(provider), providerBalance + withdrawable);
        assertEq(cashAsset.balanceOf(address(providerNFT)), contractBalance - withdrawable);

        // Check position is burned
        expectRevertERC721Nonexistent(positionId);
        providerNFT.ownerOf(positionId);

        // Check position is zeroed out
        CollarProviderNFT.ProviderPosition memory settledPosition = providerNFT.getPosition(positionId);
        assertEq(settledPosition.withdrawable, 0);
    }

    function checkCancelAndWithdraw(uint positionId, uint amountToMint) internal {
        uint providerBalance = cashAsset.balanceOf(provider);
        uint takerBalance = cashAsset.balanceOf(takerContract);
        uint contractBalance = cashAsset.balanceOf(address(providerNFT));

        vm.startPrank(provider);
        // position must be approved to taker contract
        providerNFT.approve(takerContract, positionId);
        vm.startPrank(takerContract);
        vm.expectEmit(address(providerNFT));
        emit ICollarProviderNFT.PositionCanceled(
            positionId, amountToMint, providerNFT.getPosition(positionId).expiration
        );
        uint withdrawal = providerNFT.cancelAndWithdraw(positionId);

        assertEq(withdrawal, amountToMint);
        // Check balances
        assertEq(cashAsset.balanceOf(provider), providerBalance); // unchanged since they are not owner
        assertEq(cashAsset.balanceOf(takerContract), takerBalance + amountToMint);
        assertEq(cashAsset.balanceOf(address(providerNFT)), contractBalance - amountToMint);

        // Check position is burned
        expectRevertERC721Nonexistent(positionId);
        providerNFT.ownerOf(positionId);

        // Check position is zeroed out
        CollarProviderNFT.ProviderPosition memory canceledPosition = providerNFT.getPosition(positionId);
        assertEq(canceledPosition.withdrawable, 0);
        assertEq(canceledPosition.settled, true);
    }

    /// Happy paths

    function test_createOffer() public returns (uint offerId) {
        (offerId,) = createAndCheckOffer(provider, largeCash);
    }

    function test_updateOfferAmountIncrease() public {
        // start from an existing offer
        (uint offerId,) = createAndCheckOffer(provider, largeCash);

        cashAsset.approve(address(providerNFT), largeCash);
        uint newAmount = largeCash * 2;
        uint balance = cashAsset.balanceOf(provider);

        vm.expectEmit(address(providerNFT));
        emit ICollarProviderNFT.OfferUpdated(offerId, provider, largeCash, newAmount);
        providerNFT.updateOfferAmount(offerId, newAmount);

        // next offer id not impacted
        assertEq(providerNFT.nextOfferId(), offerId + 1);
        // offer
        CollarProviderNFT.LiquidityOffer memory offer = providerNFT.getOffer(offerId);
        assertEq(offer.provider, provider);
        assertEq(offer.available, largeCash * 2);
        assertEq(offer.putStrikePercent, putPercent);
        assertEq(offer.callStrikePercent, callStrikePercent);
        assertEq(offer.duration, duration);
        // balance
        assertEq(cashAsset.balanceOf(provider), balance - largeCash);
    }

    function test_updateOfferAmountDecrease() public {
        // start from an existing offer
        (uint offerId,) = createAndCheckOffer(provider, largeCash);

        uint newAmount = largeCash / 2;
        uint balance = cashAsset.balanceOf(provider);

        vm.expectEmit(address(providerNFT));
        emit ICollarProviderNFT.OfferUpdated(offerId, provider, largeCash, newAmount);
        providerNFT.updateOfferAmount(offerId, newAmount);

        // next offer id not impacted
        assertEq(providerNFT.nextOfferId(), offerId + 1);
        // offer
        CollarProviderNFT.LiquidityOffer memory offer = providerNFT.getOffer(offerId);
        assertEq(offer.provider, provider);
        assertEq(offer.available, largeCash / 2);
        assertEq(offer.putStrikePercent, putPercent);
        assertEq(offer.callStrikePercent, callStrikePercent);
        assertEq(offer.duration, duration);
        // balance
        assertEq(cashAsset.balanceOf(provider), balance + largeCash / 2);
    }

    function test_updateOfferAmountNoChange() public {
        (uint offerId, CollarProviderNFT.LiquidityOffer memory previousOffer) =
            createAndCheckOffer(provider, largeCash);
        uint balance = cashAsset.balanceOf(provider);

        vm.expectEmit(address(providerNFT));
        emit ICollarProviderNFT.OfferUpdated(offerId, provider, largeCash, largeCash);
        providerNFT.updateOfferAmount(offerId, largeCash);

        assertEq(abi.encode(providerNFT.getOffer(offerId)), abi.encode(previousOffer));
        // balance
        assertEq(cashAsset.balanceOf(provider), balance);
    }

    function test_updateOffer_fullAmount() public {
        (uint offerId,) = createAndCheckOffer(provider, largeCash);
        vm.startPrank(provider);
        providerNFT.updateOfferAmount(offerId, 0);
        assertEq(providerNFT.getOffer(offerId).available, 0);
    }

    function test_mintPositionFromOffer() public {
        createAndCheckPosition(provider, largeCash, largeCash / 2);
    }

    function test_tokenURI() public {
        (uint positionId,) = createAndCheckPosition(provider, largeCash, largeCash / 2);
        string memory expected = string.concat(
            "https://services.collarprotocol.xyz/metadata/",
            Strings.toString(block.chainid),
            "/",
            Strings.toHexString(address(providerNFT)),
            "/",
            Strings.toString(positionId)
        );
        assertEq(providerNFT.tokenURI(positionId), expected);
    }

    function test_mintPositionFromOffer_fullAmount() public {
        uint fee = checkProtocolFeeView(largeCash);
        cashAsset.mint(provider, fee);
        createAndCheckPosition(provider, largeCash + fee, largeCash);
    }

    function test_mintFromOffer_minLocked() public {
        // 0 amount works when minLocked = 0
        createAndCheckPosition(provider, largeCash, 0);

        // check non-zero minLocked effects (event)
        minLocked = largeCash / 2;
        createAndCheckPosition(provider, largeCash, largeCash / 2);
    }

    function test_protocolFee_zeroAddressRecipient() public {
        // check fee is on
        assertFalse(configHub.feeRecipient() == address(0));
        assertFalse(configHub.protocolFeeAPR() == 0);

        // expect zero fee in createAndCheckPosition()
        expectNonZeroFee = false;
        uint amount = cashUnits(1);

        // zero recipient, non-zero fee (prevented by config-hub setter, so needs to be mocked)
        vm.mockCall(address(configHub), abi.encodeCall(configHub.feeRecipient, ()), abi.encode(address(0)));
        (uint fee, address feeRecipient) = providerNFT.protocolFee(amount, duration, callStrikePercent);
        assertEq(fee, 0);
        assertEq(feeRecipient, address(0));
        // this value is checked in the createAndCheckPosition helper to be deducted
        uint feeChecked = checkProtocolFeeView(amount);
        assertEq(feeChecked, 0);
        // check minting with 0 recipient non-zero APR works (doesn't try to transfer to zero-address)
        createAndCheckPosition(provider, largeCash, amount);
    }

    function test_protocolFee_nonDefaultValues() public {
        // check fee is on
        assertFalse(configHub.feeRecipient() == address(0));
        assertFalse(configHub.protocolFeeAPR() == 0);

        // zero APR
        vm.startPrank(owner);
        configHub.setProtocolFeeParams(0, protocolFeeRecipient);
        (uint fee, address feeRecipient) = providerNFT.protocolFee(largeCash, duration, callStrikePercent);
        assertEq(feeRecipient, protocolFeeRecipient);
        assertEq(fee, 0);

        // test round up
        configHub.setProtocolFeeParams(1, feeRecipient);
        (fee,) = providerNFT.protocolFee(1, 1, callStrikePercent); // very small fee
        assertEq(fee, 1); // rounded up

        // test zero numerator
        (fee,) = providerNFT.protocolFee(0, 1, callStrikePercent);
        assertEq(fee, 0);
        (fee,) = providerNFT.protocolFee(1, 0, callStrikePercent);
        assertEq(fee, 0);

        // check calculation for specific hardcoded value
        configHub.setProtocolFeeParams(50, feeRecipient); // 0.5% per year
        (fee,) = providerNFT.protocolFee(cashUnits(10), 365 days, 12_000);
        // 10 cash providerLocked, at 120% call strike, means 50 notional
        // 0.5% on 50 notional is 0.25
        assertEq(fee, cashFraction(0.25 ether));
        (fee,) = providerNFT.protocolFee(cashUnits(10) + 1, 365 days, 12_000);
        assertEq(fee, cashFraction(0.25 ether) + 1); // rounds up
    }

    function test_settlePositionIncrease() public {
        uint amountToMint = largeCash / 2;
        (uint positionId,) = createAndCheckPosition(provider, largeCash, amountToMint);

        skip(duration);

        checkSettlePosition(positionId, amountToMint, int(cashUnits(1000)));
    }

    function test_settlePositionDecrease() public {
        uint amountToMint = largeCash / 2;
        (uint positionId,) = createAndCheckPosition(provider, largeCash, amountToMint);

        skip(duration);

        checkSettlePosition(positionId, amountToMint, -int(cashUnits(1000)));
    }

    function test_settlePosition_expirationTimeSensitivity() public {
        (uint positionId,) = createAndCheckPosition(provider, largeCash, largeCash / 2);
        skip(duration + 1); // 1 second after expiration still works
        checkSettlePosition(positionId, largeCash / 2, -int(cashUnits(1)));
    }

    function test_settlePosition_maxLoss() public {
        (uint positionId,) = createAndCheckPosition(provider, largeCash, largeCash / 2);
        skip(duration);
        checkSettlePosition(positionId, largeCash / 2, -int(largeCash / 2));
        assertEq(providerNFT.getPosition(positionId).withdrawable, 0);
    }

    function test_withdrawFromSettled() public {
        // create settled position
        uint amountToMint = largeCash / 2;
        (uint positionId,) = createAndCheckPosition(provider, largeCash, amountToMint);
        skip(duration);
        int positionChange = int(cashUnits(1000));

        uint withdrawable = checkSettlePosition(positionId, amountToMint, positionChange);

        checkWithdraw(positionId, withdrawable);
    }

    function test_settleAndWithdraw_removedTaker() public {
        uint amountToMint = largeCash / 2;
        (uint positionId,) = createAndCheckPosition(provider, largeCash, amountToMint);
        skip(duration);
        setCanOpen(takerContract, false);
        // should work
        uint withdrawable = checkSettlePosition(positionId, amountToMint, 0);
        // should work
        checkWithdraw(positionId, withdrawable);
    }

    function test_cancelAndWithdraw() public {
        uint amountToMint = largeCash / 2;
        (uint positionId,) = createAndCheckPosition(provider, largeCash, amountToMint);
        checkCancelAndWithdraw(positionId, amountToMint);
    }

    function test_cancelAndWithdraw_removedTaker() public {
        uint amountToMint = largeCash / 2;
        (uint positionId,) = createAndCheckPosition(provider, largeCash, amountToMint);
        skip(duration);
        setCanOpen(takerContract, false);
        // should work
        checkCancelAndWithdraw(positionId, amountToMint);
    }

    function test_cancelAndWithdraw_afterExpiration() public {
        uint amountToMint = largeCash / 2;
        (uint positionId, CollarProviderNFT.ProviderPosition memory position) =
            createAndCheckPosition(provider, largeCash, amountToMint);

        skip(duration + 1);

        vm.startPrank(provider);
        // position must be approved to the taker contract
        providerNFT.approve(takerContract, positionId);
        vm.startPrank(takerContract);
        vm.expectEmit(address(providerNFT));
        emit ICollarProviderNFT.PositionCanceled(positionId, amountToMint, position.expiration);
        providerNFT.cancelAndWithdraw(positionId);
    }

    function test_cancelAndWithdraw_approvals() public {
        (uint positionId,) = createAndCheckPosition(provider, largeCash, largeCash / 10);
        // approve of ID works
        vm.startPrank(provider);
        providerNFT.approve(takerContract, positionId);
        vm.startPrank(takerContract);
        providerNFT.cancelAndWithdraw(positionId);

        (positionId,) = createAndCheckPosition(provider, largeCash, largeCash / 10);
        // ownership works
        vm.startPrank(provider);
        providerNFT.transferFrom(provider, takerContract, positionId);
        vm.startPrank(takerContract);
        providerNFT.cancelAndWithdraw(positionId);

        (positionId,) = createAndCheckPosition(provider, largeCash, largeCash / 10);
        // setApprovalForAll works
        vm.startPrank(provider);
        providerNFT.setApprovalForAll(takerContract, true);
        vm.startPrank(takerContract);
        providerNFT.cancelAndWithdraw(positionId);
    }

    /// Interactions between multiple items

    function test_createMultipleOffersFromSameProvider() public {
        uint offerCount = 3;
        uint[] memory offerIds = new uint[](offerCount);

        for (uint i = 0; i < offerCount; i++) {
            uint amount = largeCash / (i + 1);
            (offerIds[i],) = createAndCheckOffer(provider, amount);
        }

        for (uint i = 0; i < offerCount; i++) {
            CollarProviderNFT.LiquidityOffer memory offer = providerNFT.getOffer(offerIds[i]);
            assertEq(offer.provider, provider);
            assertEq(offer.available, largeCash / (i + 1));
            assertEq(offer.putStrikePercent, putPercent);
            assertEq(offer.callStrikePercent, callStrikePercent);
            assertEq(offer.duration, duration);
        }

        assertEq(providerNFT.nextOfferId(), offerIds[offerCount - 1] + 1);
    }

    function test_mintMultiplePositionsFromSameOffer() public {
        uint positionCount = 3;
        uint[] memory positionIds = new uint[](positionCount);
        uint fee = checkProtocolFeeView(largeCash);
        uint offerAmount = (largeCash + fee) * positionCount;
        uint feeRecipientBalance = cashAsset.balanceOf(protocolFeeRecipient);

        (uint offerId,) = createAndCheckOffer(provider, offerAmount);

        vm.startPrank(address(takerContract));
        for (uint i = 0; i < positionCount; i++) {
            uint amount = largeCash;
            positionIds[i] = providerNFT.mintFromOffer(offerId, amount, i);
        }

        CollarProviderNFT.LiquidityOffer memory updatedOffer = providerNFT.getOffer(offerId);
        assertEq(updatedOffer.available, 0);

        assertEq(cashAsset.balanceOf(protocolFeeRecipient), feeRecipientBalance + fee * positionCount);

        for (uint i = 0; i < positionCount; i++) {
            CollarProviderNFT.ProviderPosition memory position = providerNFT.getPosition(positionIds[i]);
            assertEq(position.offerId, offerId);
            assertEq(position.takerId, i);
            assertEq(position.providerLocked, largeCash);
            assertEq(position.putStrikePercent, putPercent);
            assertEq(position.callStrikePercent, callStrikePercent);
            assertEq(position.settled, false);
            assertEq(position.withdrawable, 0);
            assertEq(providerNFT.ownerOf(positionIds[i]), provider);
        }

        assertEq(providerNFT.nextPositionId(), positionIds[positionCount - 1] + 1);
    }

    function test_transferSettleAndWithdrawPosition() public {
        address newOwner = makeAddr("newOwner");

        // Create and mint a position
        (uint positionId, CollarProviderNFT.ProviderPosition memory position) =
            createAndCheckPosition(provider, largeCash, largeCash / 2);

        // Transfer the position to the new owner
        vm.startPrank(provider);
        providerNFT.transferFrom(provider, newOwner, positionId);

        assertEq(providerNFT.ownerOf(positionId), newOwner);

        // Skip to after expiration
        skip(duration);

        // Settle the position
        int positionChange = int(cashUnits(1000));
        vm.startPrank(address(takerContract));
        cashAsset.approve(address(providerNFT), uint(positionChange));
        providerNFT.settlePosition(positionId, positionChange);

        // Check that the position is settled
        CollarProviderNFT.ProviderPosition memory settledPosition = providerNFT.getPosition(positionId);
        assertEq(settledPosition.settled, true);
        assertEq(settledPosition.withdrawable, position.providerLocked + uint(positionChange));

        // Withdraw from the settled position
        uint newOwnerBalance = cashAsset.balanceOf(newOwner);
        vm.startPrank(newOwner);
        uint withdrwal = providerNFT.withdrawFromSettled(positionId);

        // Check that the withdrawal was successful
        assertEq(withdrwal, position.providerLocked + uint(positionChange));
        assertEq(
            cashAsset.balanceOf(newOwner) - newOwnerBalance, position.providerLocked + uint(positionChange)
        );

        // Check that the position is burned after withdrawal
        expectRevertERC721Nonexistent(positionId);
        providerNFT.ownerOf(positionId);
    }

    /// Reverts

    function test_revert_createOffer_invalidParams() public {
        uint minStrike = providerNFT.MIN_CALL_STRIKE_BIPS();
        vm.expectRevert("provider: strike percent too low");
        providerNFT.createOffer(minStrike - 1, largeCash, putPercent, duration, minLocked);

        uint maxStrike = providerNFT.MAX_CALL_STRIKE_BIPS();
        vm.expectRevert("provider: strike percent too high");
        providerNFT.createOffer(maxStrike + 1, largeCash, putPercent, duration, minLocked);

        uint maxPutStrike = providerNFT.MAX_PUT_STRIKE_BIPS();
        vm.expectRevert("provider: invalid put strike percent");
        providerNFT.createOffer(callStrikePercent, largeCash, maxPutStrike + 1, duration, minLocked);
    }

    function test_revert_updateOfferAmount() public {
        (uint offerId,) = createAndCheckOffer(provider, largeCash);

        vm.startPrank(address(0xdead));
        vm.expectRevert("provider: not offer provider");
        providerNFT.updateOfferAmount(offerId, largeCash * 2);
    }

    function test_revert_mintPositionFromOffer_configFlags() public {
        (uint offerId,) = createAndCheckOffer(provider, largeCash);

        vm.startPrank(address(0xdead));
        vm.expectRevert("provider: unauthorized taker contract");
        providerNFT.mintFromOffer(offerId, 0, 0);

        setCanOpen(takerContract, false);
        vm.startPrank(takerContract);
        vm.expectRevert("provider: unsupported taker");
        providerNFT.mintFromOffer(offerId, 0, 0);
        // allowed for different assets, still reverts
        vm.startPrank(owner);
        configHub.setCanOpenPair(address(cashAsset), address(underlying), takerContract, true);
        vm.startPrank(takerContract);
        vm.expectRevert("provider: unsupported taker");
        providerNFT.mintFromOffer(offerId, 0, 0);

        setCanOpen(takerContract, true);
        setCanOpen(address(providerNFT), false);
        vm.startPrank(takerContract);
        vm.expectRevert("provider: unsupported provider");
        providerNFT.mintFromOffer(offerId, 0, 0);
        // allowed for different assets, still reverts
        vm.startPrank(owner);
        configHub.setCanOpenPair(address(cashAsset), address(underlying), address(providerNFT), true);
        vm.startPrank(takerContract);
        vm.expectRevert("provider: unsupported provider");
        providerNFT.mintFromOffer(offerId, 0, 0);
    }

    function test_revert_mintFromOffer_ConfigHubValidations() public {
        // set a putpercent that willbe invalid later
        (uint offerId,) = createAndCheckOffer(provider, largeCash);
        vm.startPrank(owner);
        putPercent = putPercent + 100;
        configHub.setLTVRange(putPercent, putPercent);
        vm.startPrank(address(takerContract));
        vm.expectRevert("provider: unsupported LTV");
        providerNFT.mintFromOffer(offerId, largeCash / 2, 0);
        vm.startPrank(owner);
        putPercent = 9000;
        configHub.setLTVRange(putPercent, configHub.maxLTV());
        // set a duration that will be invalid later
        configHub.setCollarDurationRange(duration, configHub.maxDuration());
        (offerId,) = createAndCheckOffer(provider, largeCash);
        vm.startPrank(owner);
        duration = duration + 100;
        configHub.setCollarDurationRange(duration, duration);
        vm.startPrank(address(takerContract));
        vm.expectRevert("provider: unsupported duration");
        providerNFT.mintFromOffer(offerId, largeCash / 2, 0);
    }

    function test_revert_mintPositionFromOffer_amountTooHigh() public {
        (uint offerId,) = createAndCheckOffer(provider, largeCash);

        vm.startPrank(address(takerContract));
        vm.expectRevert("provider: offer < position + fee");
        providerNFT.mintFromOffer(offerId, largeCash + 1, 0);
    }

    function test_revert_mintFromOffer_amountTooLow() public {
        minLocked = 1;
        (uint offerId,) = createAndCheckOffer(provider, largeCash);

        vm.startPrank(address(takerContract));
        vm.expectRevert("provider: amount too low");
        providerNFT.mintFromOffer(offerId, 0, 0);

        minLocked = largeCash / 2;
        (offerId,) = createAndCheckOffer(provider, largeCash);

        vm.startPrank(address(takerContract));
        vm.expectRevert("provider: amount too low");
        providerNFT.mintFromOffer(offerId, minLocked - 1, 0);
    }

    function test_reverts_protocolFeeAPRTooHigh() public {
        (uint offerId,) = createAndCheckOffer(provider, largeCash);

        uint limit = providerNFT.MAX_PROTOCOL_FEE_BIPS();
        assertEq(limit, 100);

        vm.startPrank(address(takerContract));
        vm.mockCall(address(configHub), abi.encodeCall(configHub.protocolFeeAPR, ()), abi.encode(limit + 1));
        vm.expectRevert("provider: protocol fee APR too high");
        providerNFT.mintFromOffer(offerId, largeCash, 0);
        vm.expectRevert("provider: protocol fee APR too high");
        providerNFT.protocolFee(offerId, 0, callStrikePercent);
    }

    function test_revert_settlePosition() public {
        (uint positionId,) = createAndCheckPosition(provider, largeCash, largeCash / 2);

        vm.startPrank(address(0xdead));
        vm.expectRevert("provider: unauthorized taker contract");
        providerNFT.settlePosition(positionId, 0);

        // allow taker contract
        setCanOpen(takerContract, true);

        vm.startPrank(takerContract);
        vm.expectRevert("provider: not expired");
        providerNFT.settlePosition(positionId, 0);

        skip(duration);

        vm.expectRevert("provider: loss is too high");
        providerNFT.settlePosition(positionId, -int(largeCash / 2 + 1));

        vm.expectRevert(stdError.arithmeticError);
        providerNFT.settlePosition(positionId, type(int).min);

        // settle
        vm.startPrank(address(takerContract));
        providerNFT.settlePosition(positionId, 0);

        // can't settle twice
        vm.expectRevert("provider: already settled");
        providerNFT.settlePosition(positionId, 0);
    }

    function test_revert_nonExistentID() public {
        vm.startPrank(takerContract);
        vm.expectRevert("provider: position does not exist");
        providerNFT.settlePosition(1000, 0);

        vm.expectRevert("provider: position does not exist");
        providerNFT.cancelAndWithdraw(1000);
    }

    function test_revert_settlePosition_afterCancel() public {
        (uint positionId,) = createAndCheckPosition(provider, largeCash, largeCash / 2);

        skip(duration);

        // approve the NFT to taker contract
        vm.startPrank(provider);
        providerNFT.approve(takerContract, positionId);
        vm.startPrank(address(takerContract));
        providerNFT.cancelAndWithdraw(positionId);

        // can't settle twice
        vm.expectRevert("provider: already settled");
        providerNFT.settlePosition(positionId, 0);
    }

    function test_revert_withdrawFromSettled() public {
        (uint positionId,) = createAndCheckPosition(provider, largeCash, largeCash / 2);

        // not yet minted
        expectRevertERC721Nonexistent(positionId + 1);
        providerNFT.withdrawFromSettled(positionId + 1);

        // not owner
        vm.startPrank(address(0xdead));
        vm.expectRevert("provider: not position owner");
        providerNFT.withdrawFromSettled(positionId);

        // not settled
        vm.startPrank(provider);
        vm.expectRevert("provider: not settled");
        providerNFT.withdrawFromSettled(positionId);
    }

    function test_revert_cancelAndWithdraw() public {
        (uint positionId,) = createAndCheckPosition(provider, largeCash, largeCash / 2);

        vm.startPrank(address(0xdead));
        vm.expectRevert("provider: unauthorized taker contract");
        providerNFT.cancelAndWithdraw(positionId);
        setCanOpen(takerContract, true);
        vm.startPrank(address(takerContract));
        vm.expectRevert("provider: caller not approved for ID");
        providerNFT.cancelAndWithdraw(positionId);

        skip(duration);
        providerNFT.settlePosition(positionId, 0);

        // approve the NFT to taker contract
        vm.startPrank(provider);
        providerNFT.approve(takerContract, positionId);
        vm.startPrank(address(takerContract));
        vm.expectRevert("provider: already settled");
        providerNFT.cancelAndWithdraw(positionId);
    }
}
