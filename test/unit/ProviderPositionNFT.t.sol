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
    address borrowContract = makeAddr("borrowContract");
    address provider1 = makeAddr("provider");
    address recipient1 = makeAddr("recipient");
    uint largeAmount = 100_000 ether;
    uint putDeviation = 9000;
    uint duration = 300;
    uint callDeviation = 12_000;

    function setUp() public {
        cashAsset = new TestERC20("TestCash", "TestCash");
        collateralAsset = new TestERC20("TestCollat", "TestCollat");
        cashAsset.mint(borrowContract, 1_000_000 ether);
        cashAsset.mint(provider1, 1_000_000 ether);
        collateralAsset.mint(user1, 1_000_000 ether);
        engine = setupMockEngine();
        engine.addSupportedCashAsset(address(cashAsset));
        engine.addSupportedCollateralAsset(address(collateralAsset));
        providerNFT = new ProviderPositionNFT(
            owner, engine, cashAsset, collateralAsset, address(borrowContract), "ProviderNFT", "ProviderNFT"
        );
        engine.setBorrowContractAuth(address(borrowContract), true);
        engine.setProviderContractAuth(address(providerNFT), true);
    }

    function setupMockEngine() public returns (MockEngine mockEngine) {
        mockEngine = new MockEngine(address(0));
        mockEngine.addLTV(putDeviation);
        mockEngine.addCollarDuration(duration);
    }

    function test_constructor() public {
        ProviderPositionNFT newProviderNFT = new ProviderPositionNFT(
            owner,
            engine,
            cashAsset,
            collateralAsset,
            address(borrowContract),
            "NewProviderPositionNFT",
            "NPRVNFT"
        );

        assertEq(address(newProviderNFT.owner()), owner);
        assertEq(address(newProviderNFT.engine()), address(engine));
        assertEq(address(newProviderNFT.cashAsset()), address(cashAsset));
        assertEq(address(newProviderNFT.collateralAsset()), address(collateralAsset));
        assertEq(address(newProviderNFT.borrowPositionContract()), borrowContract);
        assertEq(newProviderNFT.name(), "NewProviderPositionNFT");
        assertEq(newProviderNFT.symbol(), "NPRVNFT");
    }

    function createAndCheckOffer(
        address provider,
        uint amount
    )
        public
        returns (uint offerId, ProviderPositionNFT.LiquidityOffer memory offer)
    {
        startHoax(provider);
        cashAsset.approve(address(providerNFT), amount);
        uint balance = cashAsset.balanceOf(provider);
        uint nextOfferId = providerNFT.nextOfferId();

        vm.expectEmit(address(providerNFT));
        emit IProviderPositionNFT.OfferCreated(
            provider, putDeviation, duration, callDeviation, amount, nextOfferId
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

    function createAndCheckPosition(
        address provider,
        uint offerAmount,
        uint positionAmount
    )
        public
        returns (uint positionId, ProviderPositionNFT.ProviderPosition memory position)
    {
        (uint offerId,) = createAndCheckOffer(provider, offerAmount);
        uint initialBalance = cashAsset.balanceOf(address(providerNFT));
        uint nextPosId = providerNFT.nextPositionId();

        startHoax(address(borrowContract));
        vm.expectEmit(address(providerNFT));
        emit IProviderPositionNFT.OfferUpdated(
            offerId, address(borrowContract), offerAmount, offerAmount - positionAmount
        );
        vm.expectEmit(address(providerNFT));
        emit IProviderPositionNFT.PositionCreated(
            0, putDeviation, duration, callDeviation, positionAmount, offerId
        );
        (positionId, position) = providerNFT.mintPositionFromOffer(offerId, positionAmount);

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

    function test_mintPositionFromOffer()
        public
        returns (uint positionId, ProviderPositionNFT.ProviderPosition memory position)
    {
        (positionId, position) = createAndCheckPosition(provider1, largeAmount, largeAmount / 2);
    }

    function test_settlePositionIncrease() public {
        uint amountToMint = largeAmount / 2;
        (uint positionId, ProviderPositionNFT.ProviderPosition memory position) =
            createAndCheckPosition(provider1, largeAmount, amountToMint);

        skip(duration + 1);

        int positionChange = 1000 ether;
        uint initialBalance = cashAsset.balanceOf(address(providerNFT));

        vm.startPrank(address(borrowContract));
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

        skip(duration + 1);

        int positionChange = -1000 ether;
        uint balanceDecrease = uint(-positionChange);
        uint initialBalance = cashAsset.balanceOf(address(providerNFT));

        vm.startPrank(address(borrowContract));
        vm.expectEmit(address(providerNFT));
        emit IProviderPositionNFT.PositionSettled(positionId, positionChange, amountToMint - balanceDecrease);
        providerNFT.settlePosition(positionId, positionChange);

        ProviderPositionNFT.ProviderPosition memory settledPosition = providerNFT.getPosition(positionId);
        assertEq(settledPosition.settled, true);
        assertEq(settledPosition.withdrawable, amountToMint - balanceDecrease);

        // Check contract balance
        assertEq(cashAsset.balanceOf(address(providerNFT)), initialBalance - balanceDecrease);
    }

    function test_withdrawFromSettled() public {
        // create settled position
        uint amountToMint = largeAmount / 2;
        (uint positionId, ProviderPositionNFT.ProviderPosition memory position) =
            createAndCheckPosition(provider1, largeAmount, amountToMint);
        skip(duration + 1);
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
        // position must be owner by borrow contract
        providerNFT.transferFrom(provider1, borrowContract, positionId);
        vm.startPrank(borrowContract);
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

    function test_pause() public {
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

    function test_onlyOwnerCanPauseUnpause() public {
        vm.startPrank(provider1);
        bytes4 selector = Ownable.OwnableUnauthorizedAccount.selector;
        vm.expectRevert(abi.encodeWithSelector(selector, provider1));
        providerNFT.pause();
        vm.expectRevert(abi.encodeWithSelector(selector, provider1));
        providerNFT.unpause();
    }
}
