// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "forge-std/Test.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { Strings } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

import { TestERC20 } from "../utils/TestERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { BaseAssetPairTestSetup, BaseTakerOracle } from "./BaseAssetPairTestSetup.sol";

import { CollarTakerNFT, ICollarTakerNFT } from "../../src/CollarTakerNFT.sol";
import { ICollarTakerNFT } from "../../src/interfaces/ICollarTakerNFT.sol";
import { CollarProviderNFT } from "../../src/CollarProviderNFT.sol";
import { ICollarProviderNFT } from "../../src/interfaces/ICollarProviderNFT.sol";
import { ITakerOracle } from "../../src/interfaces/ITakerOracle.sol";

contract CollarTakerNFTTest is BaseAssetPairTestSetup {
    uint takerLocked = 1000 ether;
    uint providerLocked = 2000 ether;
    uint callStrikePrice = 1200 ether; // 120% of the price
    uint putStrikePrice = 900 ether; // 90% of the price corresponding to 9000 LTV

    uint offerId = 999; // stores latest ID, init to invalid

    function createOffer() internal {
        startHoax(provider);
        cashAsset.approve(address(providerNFT), largeAmount);

        uint expectedOfferId = providerNFT.nextPositionId();
        vm.expectEmit(address(providerNFT));
        emit ICollarProviderNFT.OfferCreated(
            provider, ltv, duration, callStrikePercent, largeAmount, expectedOfferId, 0
        );
        offerId = providerNFT.createOffer(callStrikePercent, largeAmount, ltv, duration, 0);
        CollarProviderNFT.LiquidityOffer memory offer = providerNFT.getOffer(offerId);
        assertEq(offer.callStrikePercent, callStrikePercent);
        assertEq(offer.available, largeAmount);
        assertEq(offer.provider, provider);
        assertEq(offer.duration, duration);
        assertEq(offer.callStrikePercent, callStrikePercent);
        assertEq(offer.putStrikePercent, ltv);
    }

    function checkOpenPairedPosition() internal returns (uint takerId, uint providerNFTId) {
        createOffer();

        startHoax(user1);
        cashAsset.approve(address(takerNFT), takerLocked);

        // expected values
        uint expectedTakerId = takerNFT.nextPositionId();
        uint expectedProviderId = providerNFT.nextPositionId();
        uint _providerLocked = checkCalculateProviderLocked(takerLocked, ltv, callStrikePercent);

        ICollarTakerNFT.TakerPosition memory expectedTakerPos = ICollarTakerNFT.TakerPosition({
            providerNFT: providerNFT,
            providerId: expectedProviderId,
            duration: duration,
            expiration: block.timestamp + duration,
            startPrice: oraclePrice,
            putStrikePercent: ltv,
            callStrikePercent: callStrikePercent,
            takerLocked: takerLocked,
            providerLocked: _providerLocked,
            settled: false,
            withdrawable: 0
        });
        vm.expectEmit(address(takerNFT));
        emit ICollarTakerNFT.PairedPositionOpened(
            expectedTakerId, address(providerNFT), expectedProviderId, offerId, takerLocked, oraclePrice
        );
        (takerId, providerNFTId) = takerNFT.openPairedPosition(takerLocked, providerNFT, offerId);
        // return values
        assertEq(takerId, expectedTakerId);
        assertEq(providerNFTId, expectedProviderId);

        // position view
        CollarTakerNFT.TakerPosition memory takerPos = takerNFT.getPosition(takerId);
        assertEq(abi.encode(takerPos), abi.encode(expectedTakerPos));
        (uint expiration, bool settled) = takerNFT.expirationAndSettled(takerId);
        assertEq(expiration, expectedTakerPos.expiration);
        assertEq(settled, expectedTakerPos.settled);

        // provider position
        CollarProviderNFT.ProviderPosition memory providerPos = providerNFT.getPosition(providerNFTId);
        assertEq(providerPos.duration, duration);
        assertEq(providerPos.expiration, block.timestamp + duration);
        assertEq(providerPos.providerLocked, providerLocked);
        assertEq(providerPos.putStrikePercent, ltv);
        assertEq(providerPos.callStrikePercent, callStrikePercent);
        assertEq(providerPos.settled, false);
        assertEq(providerPos.withdrawable, 0);
    }

    function checkCalculateProviderLocked(uint _takerLocked, uint putStrike, uint callStrike)
        internal
        view
        returns (uint _providerLocked)
    {
        // calculate
        uint putRange = BIPS_100PCT - putStrike;
        uint callRange = callStrike - BIPS_100PCT;
        _providerLocked = callRange * _takerLocked / putRange;
        // check view agrees
        assertEq(_providerLocked, takerNFT.calculateProviderLocked(_takerLocked, putStrike, callStrike));
    }

    function createAndSettlePosition(uint priceToSettleAt, int expectedProviderChange)
        internal
        returns (uint takerId)
    {
        (takerId,) = checkOpenPairedPosition();
        skip(duration);
        // set settlement price
        updatePrice(priceToSettleAt);
        checkSettlePosition(takerId, priceToSettleAt, expectedProviderChange);
    }

    function checkSettlePosition(uint takerId, uint expectedSettlePrice, int expectedProviderChange)
        internal
    {
        CollarTakerNFT.TakerPosition memory takerPos = takerNFT.getPosition(takerId);
        uint providerNFTId = takerPos.providerId;
        uint expectedTakerOut = uint(int(takerLocked) - expectedProviderChange);
        uint expectedProviderOut = uint(int(providerLocked) + expectedProviderChange);

        // check the view
        {
            (uint takerBalanceView, int providerChangeView) =
                takerNFT.previewSettlement(takerPos, expectedSettlePrice);
            assertEq(takerBalanceView, expectedTakerOut);
            assertEq(providerChangeView, expectedProviderChange);
        }

        uint takerNFTBalanceBefore = cashAsset.balanceOf(address(takerNFT));
        uint providerNFTBalanceBefore = cashAsset.balanceOf(address(providerNFT));

        startHoax(user1);
        vm.expectEmit(address(providerNFT));
        emit ICollarProviderNFT.PositionSettled(providerNFTId, expectedProviderChange, expectedProviderOut);
        vm.expectEmit(address(takerNFT));
        emit ICollarTakerNFT.PairedPositionSettled(
            takerId,
            address(providerNFT),
            providerNFTId,
            expectedSettlePrice,
            expectedTakerOut,
            expectedProviderChange
        );
        takerNFT.settlePairedPosition(takerId);

        // balance changes
        assertEq(
            int(cashAsset.balanceOf(address(takerNFT))), int(takerNFTBalanceBefore) - expectedProviderChange
        );
        assertEq(
            int(cashAsset.balanceOf(address(providerNFT))),
            int(providerNFTBalanceBefore) + expectedProviderChange
        );

        // positions changes
        CollarTakerNFT.TakerPosition memory takerPosAfter = takerNFT.getPosition(takerId);
        assertEq(takerPosAfter.settled, true);
        assertEq(takerPosAfter.withdrawable, expectedTakerOut);
        (, bool settled) = takerNFT.expirationAndSettled(takerId);
        assertEq(settled, true);

        CollarProviderNFT.ProviderPosition memory providerPosAfter = providerNFT.getPosition(providerNFTId);
        assertEq(providerPosAfter.settled, true);
        assertEq(providerPosAfter.withdrawable, expectedProviderOut);
    }

    function checkWithdrawFromSettled(uint takerId, uint expectedTakerOut) public {
        uint cashBalanceBefore = cashAsset.balanceOf(user1);
        vm.expectEmit(address(takerNFT));
        emit ICollarTakerNFT.WithdrawalFromSettled(takerId, expectedTakerOut);
        uint withdrawal = takerNFT.withdrawFromSettled(takerId);
        assertEq(withdrawal, expectedTakerOut);
        assertEq(cashAsset.balanceOf(user1), cashBalanceBefore + expectedTakerOut);
        CollarTakerNFT.TakerPosition memory position = takerNFT.getPosition(takerId);
        assertEq(position.withdrawable, 0);
    }

    // tests

    function test_constructor() public {
        vm.expectEmit();
        emit ICollarTakerNFT.OracleSet(BaseTakerOracle(address(0)), chainlinkOracle);
        vm.expectEmit();
        emit ICollarTakerNFT.CollarTakerNFTCreated(
            address(cashAsset), address(underlying), address(chainlinkOracle)
        );
        CollarTakerNFT takerNFT = new CollarTakerNFT(
            owner, configHub, cashAsset, underlying, chainlinkOracle, "NewCollarTakerNFT", "NBPNFT"
        );

        assertEq(takerNFT.owner(), owner);
        assertEq(takerNFT.pendingOwner(), address(0));
        assertEq(address(takerNFT.configHub()), address(configHub));
        assertEq(address(takerNFT.cashAsset()), address(cashAsset));
        assertEq(address(takerNFT.underlying()), address(underlying));
        assertEq(address(takerNFT.oracle()), address(chainlinkOracle));
        assertEq(takerNFT.VERSION(), "0.2.0");
        assertEq(takerNFT.name(), "NewCollarTakerNFT");
        assertEq(takerNFT.symbol(), "NBPNFT");
        assertEq(takerNFT.nextPositionId(), 1);
    }

    function test_revert_constructor() public {
        // Create an oracle with mismatched assets
        BaseTakerOracle invalidOracle = createMockFeedOracle(address(cashAsset), address(underlying));
        vm.expectRevert("taker: oracle underlying mismatch");
        new CollarTakerNFT(
            owner, configHub, cashAsset, underlying, invalidOracle, "NewCollarTakerNFT", "NBPNFT"
        );

        invalidOracle = createMockFeedOracle(address(cashAsset), address(cashAsset));
        vm.expectRevert("taker: oracle underlying mismatch");
        new CollarTakerNFT(
            owner, configHub, cashAsset, underlying, invalidOracle, "NewCollarTakerNFT", "NBPNFT"
        );

        invalidOracle = createMockFeedOracle(address(underlying), address(underlying));
        vm.expectRevert("taker: oracle cashAsset mismatch");
        new CollarTakerNFT(
            owner, configHub, cashAsset, underlying, invalidOracle, "NewCollarTakerNFT", "NBPNFT"
        );

        vm.mockCall(address(100), abi.encodeCall(IERC20Metadata.decimals, ()), abi.encode(18));
        invalidOracle = createMockFeedOracle(address(underlying), address(100));
        vm.expectRevert("taker: oracle cashAsset mismatch");
        new CollarTakerNFT(
            owner, configHub, cashAsset, underlying, invalidOracle, "NewCollarTakerNFT", "NBPNFT"
        );

        BaseTakerOracle newOracle = createMockFeedOracle(address(underlying), address(cashAsset));
        vm.mockCall(address(newOracle), abi.encodeCall(ITakerOracle.currentPrice, ()), abi.encode(0));
        vm.expectRevert("taker: invalid current price");
        new CollarTakerNFT(owner, configHub, cashAsset, underlying, newOracle, "NewCollarTakerNFT", "NBPNFT");
        vm.clearMockedCalls();

        updatePrice(1);
        // 0 conversion view
        vm.mockCall(address(newOracle), abi.encodeCall(newOracle.convertToBaseAmount, (1, 1)), abi.encode(0));
        vm.expectRevert("taker: invalid convertToBaseAmount");
        new CollarTakerNFT(owner, configHub, cashAsset, underlying, newOracle, "NewCollarTakerNFT", "NBPNFT");
        vm.clearMockedCalls();

        // reverting conversion view
        vm.mockCallRevert(address(newOracle), abi.encodeCall(newOracle.convertToBaseAmount, (1, 1)), "mocked");
        vm.expectRevert("mocked");
        new CollarTakerNFT(owner, configHub, cashAsset, underlying, newOracle, "NewCollarTakerNFT", "NBPNFT");
    }

    function test_pausableMethods() public {
        // create a position
        (uint takerId,) = checkOpenPairedPosition();

        startHoax(owner);
        takerNFT.pause();
        assertTrue(takerNFT.paused());

        // Try to open a position while paused
        vm.expectRevert(Pausable.EnforcedPause.selector);
        takerNFT.openPairedPosition(takerLocked, providerNFT, 0);
        // Try to settle a position while paused
        vm.expectRevert(Pausable.EnforcedPause.selector);
        takerNFT.settlePairedPosition(0);

        // Try to withdraw from settled while paused
        vm.expectRevert(Pausable.EnforcedPause.selector);
        takerNFT.withdrawFromSettled(0);

        // Try to cancel a paired position while paused
        vm.expectRevert(Pausable.EnforcedPause.selector);
        takerNFT.cancelPairedPosition(0);

        // transfers are paused
        vm.startPrank(user1);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        takerNFT.transferFrom(user1, provider, takerId);
    }

    function test_unpause() public {
        startHoax(owner);
        takerNFT.pause();
        takerNFT.unpause();
        assertFalse(takerNFT.paused());
        // Should be able to open a position after unpausing
        checkOpenPairedPosition();
    }

    function test_supportsInterface() public view {
        bool supportsERC721 = takerNFT.supportsInterface(0x80ac58cd); // ERC721 interface id
        bool supportsERC165 = takerNFT.supportsInterface(0x01ffc9a7); // ERC165 interface id

        assertTrue(supportsERC721);
        assertTrue(supportsERC165);

        // Test for an unsupported interface
        bool supportsUnsupported = takerNFT.supportsInterface(0xffffffff);
        assertFalse(supportsUnsupported);
    }

    function test_revert_nonExistentID() public {
        vm.expectRevert("taker: position does not exist");
        takerNFT.getPosition(1000);

        vm.expectRevert("taker: position does not exist");
        takerNFT.settlePairedPosition(1000);
    }

    function test_openPairedPosition() public {
        uint nextTakertId = takerNFT.nextPositionId();
        uint nextProviderId = providerNFT.nextPositionId();
        uint userBalanceBefore = cashAsset.balanceOf(user1);
        (uint takerId, uint providerNFTId) = checkOpenPairedPosition();
        assertEq(takerId, nextTakertId);
        assertEq(providerNFTId, nextProviderId);
        assertEq(cashAsset.balanceOf(user1), userBalanceBefore - takerLocked);
    }

    function test_tokenURI() public {
        (uint takerId,) = checkOpenPairedPosition();
        string memory expected = string.concat(
            "https://services.collarprotocol.xyz/metadata/",
            Strings.toString(block.chainid),
            "/",
            Strings.toHexString(address(takerNFT)),
            "/",
            Strings.toString(takerId)
        );
        assertEq(takerNFT.tokenURI(takerId), expected);
    }

    function test_openPairedPositionUnsupportedTakerContract() public {
        createOffer();
        setCanOpen(address(takerNFT), false);
        startHoax(user1);
        vm.expectRevert("taker: unsupported taker");
        takerNFT.openPairedPosition(takerLocked, providerNFT, 0);
        // allowed for different assets, still reverts
        vm.startPrank(owner);
        configHub.setCanOpenPair(cashAsset, underlying, address(takerNFT), true);
        vm.startPrank(user1);
        vm.expectRevert("taker: unsupported taker");
        takerNFT.openPairedPosition(takerLocked, providerNFT, 0);
    }

    function test_openPairedPositionUnsupportedProviderContract() public {
        createOffer();
        setCanOpen(address(providerNFT), false);
        startHoax(user1);
        vm.expectRevert("taker: unsupported provider");
        takerNFT.openPairedPosition(takerLocked, providerNFT, 0);
        // allowed for different assets, still reverts
        vm.startPrank(owner);
        configHub.setCanOpenPair(cashAsset, underlying, address(providerNFT), true);
        vm.startPrank(user1);
        vm.expectRevert("taker: unsupported provider");
        takerNFT.openPairedPosition(takerLocked, providerNFT, 0);
    }

    function test_openPairedPosition_badOfferId() public {
        createOffer();
        startHoax(user1);
        cashAsset.approve(address(takerNFT), takerLocked);
        vm.expectRevert("taker: invalid offer");
        takerNFT.openPairedPosition(takerLocked, providerNFT, 1000);
    }

    function test_openPairedPosition_expirationMistmatch() public {
        createOffer();
        startHoax(user1);
        uint badExpiration = block.timestamp + duration + 1;
        vm.mockCall(
            address(providerNFT),
            abi.encodeCall(providerNFT.expiration, (providerNFT.nextPositionId())),
            abi.encode(badExpiration)
        );
        vm.expectRevert("taker: expiration mismatch");
        takerNFT.openPairedPosition(takerLocked, providerNFT, offerId);
    }

    function test_openPairedPositionBadCashAssetMismatch() public {
        createOffer();
        CollarProviderNFT providerNFTBad = new CollarProviderNFT(
            owner, configHub, underlying, underlying, address(takerNFT), "CollarTakerNFTBad", "BRWTSTBAD"
        );
        setCanOpen(address(providerNFTBad), true);
        startHoax(user1);
        cashAsset.approve(address(takerNFT), takerLocked);
        vm.expectRevert("taker: cashAsset mismatch");
        takerNFT.openPairedPosition(takerLocked, providerNFTBad, 0);
    }

    function test_openPairedPositionBadUnderlyingMismatch() public {
        createOffer();
        CollarProviderNFT providerNFTBad = new CollarProviderNFT(
            owner, configHub, cashAsset, cashAsset, address(takerNFT), "CollarTakerNFTBad", "BRWTSTBAD"
        );
        setCanOpen(address(providerNFTBad), true);
        startHoax(user1);
        cashAsset.approve(address(takerNFT), takerLocked);
        vm.expectRevert("taker: underlying mismatch");
        takerNFT.openPairedPosition(takerLocked, providerNFTBad, 0);
    }

    function test_openPairedPositionStrikePricesArentDifferent() public {
        vm.startPrank(owner);
        configHub.setLTVRange(9990, 9990);
        callStrikePercent = 10_010;
        ltv = 9990;
        createOffer();
        updatePrice(991);
        startHoax(user1);
        cashAsset.approve(address(takerNFT), takerLocked);
        vm.expectRevert("taker: strike prices not different");
        takerNFT.openPairedPosition(takerLocked, providerNFT, offerId);
    }

    function test_settleAndWIthdrawNoChange() public {
        uint takerId = createAndSettlePosition(oraclePrice, 0);
        checkWithdrawFromSettled(takerId, takerLocked);
    }

    function test_settleAndWIthdrawPriceAboveCall() public {
        uint newPrice = callStrikePrice * 11 / 10;
        uint takerId = createAndSettlePosition(newPrice, -int(providerLocked));
        checkWithdrawFromSettled(takerId, takerLocked + providerLocked);
    }

    function test_settleAndWIthdrawPriceUp() public {
        uint newPrice = oraclePrice * 110 / 100;
        uint takerId = createAndSettlePosition(newPrice, -int(providerLocked / 2));
        checkWithdrawFromSettled(takerId, takerLocked + providerLocked / 2);
    }

    function test_settleAndWIthdrawPriceBelowPut() public {
        uint newPrice = putStrikePrice * 9 / 10;
        uint takerId = createAndSettlePosition(newPrice, int(takerLocked));
        checkWithdrawFromSettled(takerId, 0);
    }

    function test_settleAndWIthdrawPriceDown() public {
        uint newPrice = oraclePrice * 95 / 100;
        uint takerId = createAndSettlePosition(newPrice, int(takerLocked / 2));
        checkWithdrawFromSettled(takerId, takerLocked / 2);
    }

    function test_settleAndWIthdrawLate_usesCurrentPrice() public {
        uint currentPrice = oraclePrice * 120 / 100;

        (uint takerId,) = checkOpenPairedPosition();
        skip(10 * duration);
        updatePrice(currentPrice);
        assertEq(takerNFT.currentOraclePrice(), currentPrice);
        // settled at current price and got 100% of providerLocked
        checkSettlePosition(takerId, currentPrice, -int(providerLocked));
        checkWithdrawFromSettled(takerId, takerLocked + providerLocked);
    }

    function test_settlePairedPosition_NotExpired() public {
        (uint takerId,) = checkOpenPairedPosition();

        // Try to settle before expiration
        startHoax(user1);
        vm.expectRevert("taker: not expired");
        takerNFT.settlePairedPosition(takerId);
    }

    function test_settlePairedPosition_AlreadySettled() public {
        (uint takerId,) = checkOpenPairedPosition();

        // Settle the position
        skip(301);
        startHoax(user1);
        takerNFT.settlePairedPosition(takerId);

        // Try to settle again
        vm.expectRevert("taker: already settled");
        takerNFT.settlePairedPosition(takerId);
    }

    function test_withdrawFromSettled_NotOwner() public {
        (uint takerId,) = checkOpenPairedPosition();

        // Settle the position
        skip(301);
        startHoax(user1);
        takerNFT.settlePairedPosition(takerId);

        // Try to withdraw with a different address
        startHoax(address(0xdead));
        vm.expectRevert("taker: not position owner");
        takerNFT.withdrawFromSettled(takerId);
    }

    function test_withdrawFromSettled_NotSettled() public {
        (uint takerId,) = checkOpenPairedPosition();

        // Try to withdraw before settling
        startHoax(user1);
        vm.expectRevert("taker: not settled");
        takerNFT.withdrawFromSettled(takerId);
    }

    function test_cancelPairedPosition() public {
        (uint takerId, uint providerNFTId) = checkOpenPairedPosition();

        uint userCashBefore = cashAsset.balanceOf(user1);
        uint providerCashBefore = cashAsset.balanceOf(provider);

        uint expectedWithdrawal = takerLocked + providerLocked;

        startHoax(user1);
        takerNFT.safeTransferFrom(user1, provider, takerId);
        startHoax(provider);
        takerNFT.approve(address(takerNFT), takerId);
        providerNFT.approve(address(takerNFT), providerNFTId);
        vm.expectEmit(address(takerNFT));
        emit ICollarTakerNFT.PairedPositionCanceled(
            takerId, address(providerNFT), providerNFTId, expectedWithdrawal, block.timestamp + duration
        );
        uint withdrawal = takerNFT.cancelPairedPosition(takerId);

        assertEq(withdrawal, expectedWithdrawal);

        // view
        CollarTakerNFT.TakerPosition memory position = takerNFT.getPosition(takerId);
        assertEq(position.settled, true);
        assertEq(position.withdrawable, 0);
        (, bool settled) = takerNFT.expirationAndSettled(takerId);
        assertEq(settled, true);

        // balances
        assertEq(cashAsset.balanceOf(user1), userCashBefore);
        assertEq(cashAsset.balanceOf(provider), providerCashBefore + expectedWithdrawal);
    }

    function test_cancelIfBrokenOracle() public {
        // exit cases when the oracle is broken or if it reverts due to sequencer checks
        (uint takerId, uint providerNFTId) = checkOpenPairedPosition();

        // disable oracle
        vm.startPrank(owner);
        mockCLFeed.setReverts(true);
        vm.expectRevert("oracle reverts");
        takerNFT.currentOraclePrice();

        // cancel works
        vm.startPrank(provider);
        providerNFT.transferFrom(provider, user1, providerNFTId);
        vm.startPrank(user1);
        providerNFT.approve(address(takerNFT), providerNFTId);
        takerNFT.cancelPairedPosition(takerId);
    }

    function test_cancelPairedPosition_NotOwnerOfTakerID() public {
        (uint takerId,) = checkOpenPairedPosition();

        // Try to cancel with a different address
        startHoax(address(0xdead));
        vm.expectRevert("taker: not owner of ID");
        takerNFT.cancelPairedPosition(takerId);
    }

    function test_cancelPairedPosition_NotOwnerOfProviderID() public {
        (uint takerId,) = checkOpenPairedPosition();

        // Transfer the taker NFT to another address, but not the provider NFT
        startHoax(user1);
        takerNFT.transferFrom(user1, address(0xbeef), takerId);

        // Try to cancel with the new taker NFT owner
        startHoax(address(0xbeef));
        vm.expectRevert("taker: not owner of provider ID");
        takerNFT.cancelPairedPosition(takerId);
    }

    function test_cancelPairedPosition_AlreadySettled() public {
        (uint takerId,) = checkOpenPairedPosition();

        // Settle the position
        skip(301);
        startHoax(user1);
        takerNFT.settlePairedPosition(takerId);
        // Try to cancel the settled position
        takerNFT.safeTransferFrom(user1, provider, takerId);
        startHoax(provider);
        vm.expectRevert("taker: already settled");
        takerNFT.cancelPairedPosition(takerId);
    }

    function test_setOracle() public {
        // new oracle
        BaseTakerOracle newOracle = createMockFeedOracle(address(underlying), address(cashAsset));

        uint newPrice = 1500 ether;
        updatePrice(newPrice);

        startHoax(owner);
        vm.expectEmit(address(takerNFT));
        emit ICollarTakerNFT.OracleSet(chainlinkOracle, newOracle);
        takerNFT.setOracle(newOracle);

        assertEq(address(takerNFT.oracle()), address(newOracle));
        assertEq(takerNFT.currentOraclePrice(), newPrice);
    }

    function test_revert_setOracle() public {
        startHoax(user1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        takerNFT.setOracle(chainlinkOracle);

        startHoax(owner);

        // Create an oracle with mismatched assets
        BaseTakerOracle invalidOracle = createMockFeedOracle(address(cashAsset), address(underlying));
        vm.expectRevert("taker: oracle underlying mismatch");
        takerNFT.setOracle(invalidOracle);

        invalidOracle = createMockFeedOracle(address(cashAsset), address(cashAsset));
        vm.expectRevert("taker: oracle underlying mismatch");
        takerNFT.setOracle(invalidOracle);

        invalidOracle = createMockFeedOracle(address(underlying), address(underlying));
        vm.expectRevert("taker: oracle cashAsset mismatch");
        takerNFT.setOracle(invalidOracle);

        vm.mockCall(address(100), abi.encodeCall(IERC20Metadata.decimals, ()), abi.encode(18));
        invalidOracle = createMockFeedOracle(address(underlying), address(100));
        vm.expectRevert("taker: oracle cashAsset mismatch");
        takerNFT.setOracle(invalidOracle);

        BaseTakerOracle newOracle = createMockFeedOracle(address(underlying), address(cashAsset));
        vm.mockCall(address(newOracle), abi.encodeCall(ITakerOracle.currentPrice, ()), abi.encode(0));
        vm.expectRevert("taker: invalid current price");
        takerNFT.setOracle(newOracle);
        vm.clearMockedCalls();

        updatePrice(1);
        // 0 conversion view
        vm.mockCall(address(newOracle), abi.encodeCall(newOracle.convertToBaseAmount, (1, 1)), abi.encode(0));
        vm.expectRevert("taker: invalid convertToBaseAmount");
        takerNFT.setOracle(newOracle);
        vm.clearMockedCalls();

        // reverting conversion view
        vm.mockCallRevert(address(newOracle), abi.encodeCall(newOracle.convertToBaseAmount, (1, 1)), "mocked");
        vm.expectRevert("mocked");
        takerNFT.setOracle(newOracle);
        vm.clearMockedCalls();
    }
}
