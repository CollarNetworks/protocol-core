// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

import "forge-std/console.sol";
import { ICollarEngine } from "../../src/interfaces/ICollarEngine.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { CollarIntegrationPriceManipulation } from "./utils/PriceManipulation.t.sol";
import { PositionOperationsTest } from "./utils/PositionOperations.t.sol";
import { CollarTakerNFT } from "../../src/CollarTakerNFT.sol";

contract ForkTestCollarEthereumMainnetIntegrationTest is
    CollarIntegrationPriceManipulation,
    PositionOperationsTest
{
    using SafeERC20 for IERC20;

    function setUp() public {
        uint _blockNumberToUse = 20_091_414;
        string memory forkRPC = vm.envString("ETHEREUM_MAINNET_RPC");
        vm.createSelectFork(forkRPC, _blockNumberToUse);
        assertEq(block.number, _blockNumberToUse);

        _setupConfig({
            _swapRouter: 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45,
            _cashAsset: 0xdAC17F958D2ee523a2206206994597C13D831ec7, // USDT
            _collateralAsset: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, //WETH
            _uniV3Pool: 0x4e68Ccd3E89f51C3074ca5072bbAC773960dFa36,
            whaleWallet: 0xF04a5cC80B1E94C69B48f5ee68a08CD2F09A7c3E,
            blockNumber: _blockNumberToUse,
            priceOnBlock: 3_393_819_954, // $3547.988497 the price for WETH in USDT on the specified block of Arbitrum mainnet
            callStrikeTickToUse: 120,
            _poolDuration: 1 days,
            _poolLTV: 9000
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
        uint targetPrice = 2_566_273_536;
        _manipulatePriceDownwardPastPutStrike(10_000 ether, isFuzzTest, targetPrice);
    }

    function manipulatePriceDownwardShortOfPutStrike(bool isFuzzTest) internal returns (uint finalPrice) {
        uint targetPrice = 3_146_355_099;
        finalPrice = _manipulatePriceDownwardShortOfPutStrike(5000 ether, isFuzzTest, targetPrice);
    }

    function manipulatePriceUpwardPastCallStrike(bool isFuzzTest) internal {
        uint targetPrice = 49_072_885_881_217;
        _manipulatePriceUpwardPastCallStrike(60_000_000e6, isFuzzTest, targetPrice);
    }

    function manipulatePriceUpwardShortOfCallStrike(bool isFuzzTest) internal returns (uint finalPrice) {
        uint targetPrice = 3_418_632_174;
        finalPrice = _manipulatePriceUpwardShortOfCallStrike(1_000_000e6, isFuzzTest, targetPrice);
    }

    function testFuzz_openAndClosePositionPriceUnderPutStrike(uint collateralAmount, uint24 callStrikeTick)
        public
        assumeValidCallStrikeTick(callStrikeTick)
    {
        collateralAmount = bound(collateralAmount, 1 ether, 20 ether);
        callStrikeTick = uint24(bound(callStrikeTick, uint(110), uint(130)));

        (uint borrowId,) = openTakerPosition(collateralAmount, 0.3e6, getOfferIndex(callStrikeTick));
        uint userCashBalanceAfterOpen = cashAsset.balanceOf(user1);
        uint providerCashBalanceBeforeClose = cashAsset.balanceOf(provider);

        manipulatePriceDownwardPastPutStrike(true);

        vm.warp(block.timestamp + positionDuration + 1);

        checkPriceUnderPutStrikeValues(borrowId, userCashBalanceAfterOpen, providerCashBalanceBeforeClose);
    }

    function test_openAndClosePositionPriceUnderPutStrike() public {
        (uint borrowId,) = openTakerPosition(1 ether, 0.3e6, getOfferIndex(120));
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

        (uint borrowId,) = openTakerPosition(collateralAmount, 0.3e6, getOfferIndex(callStrikeTick));
        uint userCashBalanceAfterOpen = cashAsset.balanceOf(user1);
        uint providerCashBalanceBeforeClose = cashAsset.balanceOf(provider);

        uint finalPrice = manipulatePriceDownwardShortOfPutStrike(true);

        vm.warp(block.timestamp + positionDuration + 1);

        checkPriceDownShortOfPutStrikeValues(
            borrowId, userCashBalanceAfterOpen, providerCashBalanceBeforeClose, finalPrice
        );
    }

    function test_openAndClosePositionPriceDownShortOfPutStrike() public {
        (uint borrowId,) = openTakerPosition(1 ether, 0.3e6, getOfferIndex(120));
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

        (uint borrowId,) = openTakerPosition(collateralAmount, 0.3e6, getOfferIndex(callStrikeTick));
        uint userCashBalanceAfterOpen = cashAsset.balanceOf(user1);
        uint providerCashBalanceBeforeClose = cashAsset.balanceOf(provider);

        manipulatePriceUpwardPastCallStrike(true);

        vm.warp(block.timestamp + positionDuration + 1);

        checkPriceUpPastCallStrikeValues(borrowId, userCashBalanceAfterOpen, providerCashBalanceBeforeClose);
    }

    function test_openAndClosePositionPriceUpPastCallStrike() public {
        (uint borrowId,) = openTakerPosition(1 ether, 0.3e6, getOfferIndex(120));
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

        (uint borrowId,) = openTakerPosition(collateralAmount, 0.3e6, getOfferIndex(callStrikeTick));
        uint userCashBalanceAfterOpen = cashAsset.balanceOf(user1);
        uint providerCashBalanceBeforeClose = cashAsset.balanceOf(provider);

        uint finalPrice = manipulatePriceUpwardShortOfCallStrike(true);

        vm.warp(block.timestamp + positionDuration + 1);

        checkPriceUpShortOfCallStrikeValues(
            borrowId, userCashBalanceAfterOpen, providerCashBalanceBeforeClose, finalPrice
        );
    }

    function test_openAndClosePositionPriceUpShortOfCallStrike() public {
        (uint borrowId,) = openTakerPosition(1 ether, 0.3e6, getOfferIndex(120));
        uint userCashBalanceAfterOpen = cashAsset.balanceOf(user1);
        uint providerCashBalanceBeforeClose = cashAsset.balanceOf(provider);

        uint finalPrice = manipulatePriceUpwardShortOfCallStrike(false);

        vm.warp(block.timestamp + positionDuration + 1);

        checkPriceUpShortOfCallStrikeValues(
            borrowId, userCashBalanceAfterOpen, providerCashBalanceBeforeClose, finalPrice
        );
    }
}
