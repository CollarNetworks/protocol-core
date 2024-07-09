// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

import "forge-std/console.sol";
import { ICollarEngine } from "../../src/interfaces/ICollarEngine.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { CollarIntegrationPriceManipulation } from "./utils/PriceManipulation.t.sol";
import { PositionOperationsTest } from "./utils/PositionOperations.t.sol";
import { CollarTakerNFT } from "../../src/CollarTakerNFT.sol";

contract ForkTestCollarPolygonMainnetIntegrationTest is
    CollarIntegrationPriceManipulation,
    PositionOperationsTest
{
    using SafeERC20 for IERC20;

    function setUp() public {
        uint _blockNumberToUse = 55_850_000;
        string memory forkRPC = vm.envString("POLYGON_MAINNET_RPC");
        vm.createSelectFork(forkRPC, _blockNumberToUse);
        assertEq(block.number, _blockNumberToUse);

        _setupConfig({
            _swapRouter: 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45,
            _cashAsset: 0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359, // USDC
            _collateralAsset: 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270, // WMATIC
            _uniV3Pool: 0x2DB87C4831B2fec2E35591221455834193b50D1B,
            whaleWallet: 0xe7804c37c13166fF0b37F5aE0BB07A3aEbb6e245,
            blockNumber: _blockNumberToUse,
            priceOnBlock: 739_504, // $0.739504 WMATIC/USDC price on specified block
            callStrikeTickToUse: 120,
            _positionDuration: 1 days,
            _offerLTV: 9000
        });

        _fundWallets();

        uint amountPerOffer = 10_000e6;
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
        uint targetPrice = 632_310;
        _manipulatePriceDownwardPastPutStrike(100_000e18, isFuzzTest, targetPrice);
    }

    function manipulatePriceDownwardShortOfPutStrike(bool isFuzzTest) internal returns (uint finalPrice) {
        uint targetPrice = 703_575;
        finalPrice = _manipulatePriceDownwardShortOfPutStrike(40_000e18, isFuzzTest, targetPrice);
    }

    function manipulatePriceUpwardPastCallStrike(bool isFuzzTest) internal {
        uint targetPrice = 987_778;
        _manipulatePriceUpwardPastCallStrike(200_000e6, isFuzzTest, targetPrice);
    }

    function manipulatePriceUpwardShortOfCallStrike(bool isFuzzTest) internal returns (uint finalPrice) {
        uint targetPrice = 794_385;
        finalPrice = _manipulatePriceUpwardShortOfCallStrike(40_000e6, isFuzzTest, targetPrice);
    }

    function testFuzz_openAndClosePositionPriceUnderPutStrike(uint collateralAmount, uint24 callStrikeTick)
        public
        assumeValidCallStrikeTick(callStrikeTick)
    {
        collateralAmount = bound(collateralAmount, 1 ether, 20_000 ether);
        callStrikeTick = uint24(bound(callStrikeTick, uint(110), uint(130)));

        (uint borrowId,) = openTakerPosition(collateralAmount, 0.3e6, getOfferIndex(callStrikeTick));
        uint userCashBalanceAfterOpen = cashAsset.balanceOf(user1);
        uint providerCashBalanceBeforeClose = cashAsset.balanceOf(provider);

        manipulatePriceDownwardPastPutStrike(true);

        vm.warp(block.timestamp + positionDuration + 1);

        checkPriceUnderPutStrikeValues(borrowId, userCashBalanceAfterOpen, providerCashBalanceBeforeClose);
    }

    function test_openAndClosePositionPriceUnderPutStrike() public {
        (uint borrowId,) = openTakerPosition(1000 ether, 0.3e6, getOfferIndex(120));
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
        collateralAmount = bound(collateralAmount, 1 ether, 20_000 ether);
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
        (uint borrowId,) = openTakerPosition(1000 ether, 0.3e6, getOfferIndex(120));
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
        collateralAmount = bound(collateralAmount, 1 ether, 20_000 ether);
        callStrikeTick = uint24(bound(callStrikeTick, uint(110), uint(130)));

        (uint borrowId,) = openTakerPosition(collateralAmount, 0.3e6, getOfferIndex(callStrikeTick));
        uint userCashBalanceAfterOpen = cashAsset.balanceOf(user1);
        uint providerCashBalanceBeforeClose = cashAsset.balanceOf(provider);

        manipulatePriceUpwardPastCallStrike(true);

        vm.warp(block.timestamp + positionDuration + 1);

        checkPriceUpPastCallStrikeValues(borrowId, userCashBalanceAfterOpen, providerCashBalanceBeforeClose);
    }

    function test_openAndClosePositionPriceUpPastCallStrike() public {
        (uint borrowId,) = openTakerPosition(1000 ether, 0.3e6, getOfferIndex(120));
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
        collateralAmount = bound(collateralAmount, 1 ether, 20_000 ether);
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
        (uint borrowId,) = openTakerPosition(1000 ether, 0.3e6, getOfferIndex(120));
        uint userCashBalanceAfterOpen = cashAsset.balanceOf(user1);
        uint providerCashBalanceBeforeClose = cashAsset.balanceOf(provider);

        uint finalPrice = manipulatePriceUpwardShortOfCallStrike(false);

        vm.warp(block.timestamp + positionDuration + 1);

        checkPriceUpShortOfCallStrikeValues(
            borrowId, userCashBalanceAfterOpen, providerCashBalanceBeforeClose, finalPrice
        );
    }
}
