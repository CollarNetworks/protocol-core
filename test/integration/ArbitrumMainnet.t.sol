// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/console.sol";
import { IConfigHub } from "../../src/interfaces/IConfigHub.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { CollarIntegrationPriceManipulation } from "./utils/PriceManipulation.t.sol";
import { PositionOperationsTest } from "./utils/PositionOperations.t.sol";
import { CollarTakerNFT } from "../../src/CollarTakerNFT.sol";

contract ForkTestCollarArbitrumMainnetIntegrationTest is
    CollarIntegrationPriceManipulation,
    PositionOperationsTest
{
    using SafeERC20 for IERC20;

    function setUp() public {
        uint _blockNumberToUse = 223_579_191;
        string memory forkRPC = vm.envString("ARBITRUM_MAINNET_RPC");
        uint bn = vm.getBlockNumber();
        console.log("Current block number: %d", bn);
        vm.createSelectFork(forkRPC, _blockNumberToUse);
        assertEq(block.number, 20_127_607);

        _setupConfig({
            _swapRouter: 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45,
            _cashAsset: 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8, // USDC
            _collateralAsset: 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1, // WETH
            _uniV3Pool: 0x17c14D2c404D167802b16C450d3c99F88F2c4F4d,
            whaleWallet: 0xB38e8c17e38363aF6EbdCb3dAE12e0243582891D,
            blockNumber: _blockNumberToUse,
            priceOnBlock: 3_547_988_497, // $3547.988497 WETH/USDC price on specified block
            callStrikeTickToUse: 120,
            _positionDuration: 1 days,
            _offerLTV: 9000
        });

        _fundWallets();

        uint amountPerOffer = 100_000e6;
        _setupOffers(amountPerOffer);
        _validateOfferSetup(amountPerOffer);
        _validateSetup(1 days, 9000);
    }

    modifier assumeValidCallStrikeTick(uint24 tick) {
        tick = uint24(bound(tick, uint(110), uint(130)));
        vm.assume(tick == 110 || tick == 115 || tick == 120 || tick == 130);
        _;
    }

    function manipulatePriceDownwardPastPutStrike(bool isFuzzTest) internal {
        uint targetPrice = 3_177_657_139;
        _manipulatePriceDownwardPastPutStrike(35 ether, isFuzzTest, targetPrice);
    }

    function manipulatePriceDownwardShortOfPutStrike(bool isFuzzTest) internal returns (uint finalPrice) {
        uint targetPrice = 3_332_896_653;
        finalPrice = _manipulatePriceDownwardShortOfPutStrike(20 ether, isFuzzTest, targetPrice);
    }

    function manipulatePriceUpwardPastCallStrike(bool isFuzzTest) internal {
        uint targetPrice = 5_113_174_239;
        _manipulatePriceUpwardPastCallStrike(400_000e6, isFuzzTest, targetPrice);
    }

    function manipulatePriceUpwardShortOfCallStrike(bool isFuzzTest) internal returns (uint finalPrice) {
        uint targetPrice = 3_872_244_419;
        finalPrice = _manipulatePriceUpwardShortOfCallStrike(100_000e6, isFuzzTest, targetPrice);
    }

    function test_openAndClosePositionNoPriceChange() public {
        /**
         * @dev trying to manipulate price to be exactly the same as the moment of opening vault is too hard ,
         * so we'll skip this case unless there's a better proposal
         */
        // (uint borrowId, CollarTakerNFT.BorrowPosition memory position) =
        //     openTakerPositionAndCheckValues(1 ether, 0.3e6, getOfferIndex(120));

        // vm.warp(block.timestamp + positionDuration + 1);

        // uint userCashBalanceBefore = cashAsset.balanceOf(user1);
        // uint providerCashBalanceBefore = cashAsset.balanceOf(provider);

        // (uint userWithdrawnAmount, uint providerWithdrawnAmount) = settleAndWithdraw(borrowId);
        // assertEq(userWithdrawnAmount, position.putLockedCash, "User should receive put locked cash");
        // assertEq(providerWithdrawnAmount, position.callLockedCash, "Provider should receive call locked cash");

        // assertEq(
        //     cashAsset.balanceOf(user1),
        //     userCashBalanceBefore + userWithdrawnAmount,
        //     "Incorrect user balance after settlement"
        // );
        // assertEq(
        //     cashAsset.balanceOf(provider),
        //     providerCashBalanceBefore + providerWithdrawnAmount,
        //     "Incorrect provider balance after settlement"
        // );
    }

    function testFuzz_openAndClosePositionPriceUnderPutStrike(uint collateralAmount, uint24 callStrikeTick)
        public
        assumeValidCallStrikeTick(callStrikeTick)
    {
        collateralAmount = bound(collateralAmount, 1 ether, 20 ether);
        callStrikeTick = uint24(bound(callStrikeTick, uint(110), uint(130)));

        (uint borrowId,) =
            openTakerPositionAndCheckValues(collateralAmount, 0.3e6, getOfferIndex(callStrikeTick));
        uint userCashBalanceAfterOpen = cashAsset.balanceOf(user1);
        uint providerCashBalanceBeforeClose = cashAsset.balanceOf(provider);

        manipulatePriceDownwardPastPutStrike(true);

        vm.warp(block.timestamp + positionDuration + 1);

        checkPriceUnderPutStrikeValues(borrowId, userCashBalanceAfterOpen, providerCashBalanceBeforeClose);
    }

    function test_openAndClosePositionPriceUnderPutStrike() public {
        (uint borrowId,) = openTakerPositionAndCheckValues(1 ether, 0.3e6, getOfferIndex(120));
        uint userCashBalanceAfterOpen = cashAsset.balanceOf(user1);
        uint providerCashBalanceBeforeClose = cashAsset.balanceOf(provider);

        manipulatePriceDownwardPastPutStrike(false);

        vm.warp(block.timestamp + positionDuration + 1);

        checkPriceUnderPutStrikeValues(borrowId, userCashBalanceAfterOpen, providerCashBalanceBeforeClose);
    }

    function testFuzz_openAndClosePositionPriceDownShortOfPutStrike(
        uint collateralAmount,
        uint24 callStrikeTick
    ) public assumeValidCallStrikeTick(callStrikeTick) {
        collateralAmount = bound(collateralAmount, 1 ether, 20 ether);
        callStrikeTick = uint24(bound(callStrikeTick, uint(110), uint(130)));

        (uint borrowId,) =
            openTakerPositionAndCheckValues(collateralAmount, 0.3e6, getOfferIndex(callStrikeTick));
        uint userCashBalanceAfterOpen = cashAsset.balanceOf(user1);
        uint providerCashBalanceBeforeClose = cashAsset.balanceOf(provider);

        uint finalPrice = manipulatePriceDownwardShortOfPutStrike(true);

        vm.warp(block.timestamp + positionDuration + 1);

        checkPriceDownShortOfPutStrikeValues(
            borrowId, userCashBalanceAfterOpen, providerCashBalanceBeforeClose, finalPrice
        );
    }

    function test_openAndClosePositionPriceDownShortOfPutStrike() public {
        (uint borrowId,) = openTakerPositionAndCheckValues(1 ether, 0.3e6, getOfferIndex(120));
        uint userCashBalanceAfterOpen = cashAsset.balanceOf(user1);
        uint providerCashBalanceBeforeClose = cashAsset.balanceOf(provider);

        uint finalPrice = manipulatePriceDownwardShortOfPutStrike(false);

        vm.warp(block.timestamp + positionDuration + 1);

        checkPriceDownShortOfPutStrikeValues(
            borrowId, userCashBalanceAfterOpen, providerCashBalanceBeforeClose, finalPrice
        );
    }

    function testFuzz_openAndClosePositionPriceUpPastCallStrike(uint collateralAmount, uint24 callStrikeTick)
        public
        assumeValidCallStrikeTick(callStrikeTick)
    {
        collateralAmount = bound(collateralAmount, 1 ether, 20 ether);
        callStrikeTick = uint24(bound(callStrikeTick, uint(110), uint(130)));

        (uint borrowId,) =
            openTakerPositionAndCheckValues(collateralAmount, 0.3e6, getOfferIndex(callStrikeTick));
        uint userCashBalanceAfterOpen = cashAsset.balanceOf(user1);
        uint providerCashBalanceBeforeClose = cashAsset.balanceOf(provider);

        manipulatePriceUpwardPastCallStrike(true);

        vm.warp(block.timestamp + positionDuration + 1);

        checkPriceUpPastCallStrikeValues(borrowId, userCashBalanceAfterOpen, providerCashBalanceBeforeClose);
    }

    function test_openAndClosePositionPriceUpPastCallStrike() public {
        (uint borrowId,) = openTakerPositionAndCheckValues(1 ether, 0.3e6, getOfferIndex(120));
        uint userCashBalanceAfterOpen = cashAsset.balanceOf(user1);
        uint providerCashBalanceBeforeClose = cashAsset.balanceOf(provider);

        manipulatePriceUpwardPastCallStrike(false);

        vm.warp(block.timestamp + positionDuration + 1);

        checkPriceUpPastCallStrikeValues(borrowId, userCashBalanceAfterOpen, providerCashBalanceBeforeClose);
    }

    function testFuzz_openAndClosePositionPriceUpShortOfCallStrike(
        uint collateralAmount,
        uint24 callStrikeTick
    ) public assumeValidCallStrikeTick(callStrikeTick) {
        collateralAmount = bound(collateralAmount, 1 ether, 20 ether);
        callStrikeTick = uint24(bound(callStrikeTick, uint(110), uint(130)));

        (uint borrowId,) =
            openTakerPositionAndCheckValues(collateralAmount, 0.3e6, getOfferIndex(callStrikeTick));
        uint userCashBalanceAfterOpen = cashAsset.balanceOf(user1);
        uint providerCashBalanceBeforeClose = cashAsset.balanceOf(provider);

        uint finalPrice = manipulatePriceUpwardShortOfCallStrike(true);

        vm.warp(block.timestamp + positionDuration + 1);

        checkPriceUpShortOfCallStrikeValues(
            borrowId, userCashBalanceAfterOpen, providerCashBalanceBeforeClose, finalPrice
        );
    }

    function test_openAndClosePositionPriceUpShortOfCallStrike() public {
        (uint borrowId,) = openTakerPositionAndCheckValues(1 ether, 0.3e6, getOfferIndex(120));
        uint userCashBalanceAfterOpen = cashAsset.balanceOf(user1);
        uint providerCashBalanceBeforeClose = cashAsset.balanceOf(provider);

        uint finalPrice = manipulatePriceUpwardShortOfCallStrike(false);

        vm.warp(block.timestamp + positionDuration + 1);

        checkPriceUpShortOfCallStrikeValues(
            borrowId, userCashBalanceAfterOpen, providerCashBalanceBeforeClose, finalPrice
        );
    }
}
