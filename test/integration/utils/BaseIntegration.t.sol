// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import { CollarEngine } from "../../../src/implementations/CollarEngine.sol";
import { ProviderPositionNFT } from "../../../src/ProviderPositionNFT.sol";
import { CollarTakerNFT } from "../../../src/CollarTakerNFT.sol";
import { Loans } from "../../../src/Loans.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IV3SwapRouter } from "@uniswap/swap-router-contracts/contracts/interfaces/IV3SwapRouter.sol";

abstract contract CollarBaseIntegrationTestConfig is Test {
    using SafeERC20 for IERC20;

    address user1 = makeAddr("user1");
    address provider = makeAddr("provider");
    address swapRouterAddress;
    address collateralAssetAddress;
    address cashAssetAddress;
    address uniV3Pool;
    address whale;
    uint BLOCK_NUMBER_TO_USE;
    uint COLLATERAL_PRICE_ON_BLOCK;
    uint24 CALL_STRIKE_TICK = 120;
    uint positionDuration;
    uint offerLTV;
    IERC20 collateralAsset;
    IERC20 cashAsset;
    IV3SwapRouter swapRouter;

    CollarEngine engine;
    ProviderPositionNFT providerNFT;
    CollarTakerNFT takerNFT;
    Loans loanContract;

    function _setupConfig(
        address _swapRouter,
        address _cashAsset,
        address _collateralAsset,
        address _uniV3Pool,
        address whaleWallet,
        uint blockNumber,
        uint priceOnBlock,
        uint24 callStrikeTickToUse,
        uint _positionDuration,
        uint _offerLTV
    ) internal {
        swapRouterAddress = _swapRouter;
        cashAssetAddress = _cashAsset;
        collateralAssetAddress = _collateralAsset;
        collateralAsset = IERC20(collateralAssetAddress);
        cashAsset = IERC20(cashAssetAddress);
        uniV3Pool = _uniV3Pool;
        whale = whaleWallet;
        BLOCK_NUMBER_TO_USE = blockNumber;
        COLLATERAL_PRICE_ON_BLOCK = priceOnBlock;
        CALL_STRIKE_TICK = callStrikeTickToUse;

        engine = new CollarEngine(swapRouterAddress);
        engine.setCashAssetSupport(cashAssetAddress, true);
        engine.setCollateralAssetSupport(collateralAssetAddress, true);
        engine.setLTVRange(_offerLTV, _offerLTV + 1);
        engine.setCollarDurationRange(_positionDuration, _positionDuration + 1);
        takerNFT = new CollarTakerNFT(address(this), engine, cashAsset, collateralAsset, "Borrow NFT", "BNFT");

        loanContract = new Loans(address(this), engine, takerNFT, cashAsset, collateralAsset);
        engine.setCollarTakerContractAuth(address(takerNFT), true);
        providerNFT = new ProviderPositionNFT(
            address(this), engine, cashAsset, collateralAsset, address(takerNFT), "Provider NFT", "PNFT"
        );
        engine.setProviderContractAuth(address(providerNFT), true);

        positionDuration = _positionDuration;
        offerLTV = _offerLTV;

        vm.label(user1, "USER");
        vm.label(provider, "LIQUIDITY PROVIDER");
        vm.label(address(engine), "ENGINE");
        vm.label(address(providerNFT), "PROVIDER NFT");
        vm.label(address(takerNFT), "BORROW NFT");
        vm.label(swapRouterAddress, "SWAP ROUTER 02");
        vm.label(cashAssetAddress, "Cash asset address");
        vm.label(collateralAssetAddress, "collateral asset address");

        cashAsset.forceApprove(address(takerNFT), type(uint).max);
        collateralAsset.forceApprove(address(takerNFT), type(uint).max);
    }

    function _fundWallets() internal {
        deal(cashAssetAddress, whale, 1_000_000 ether);
        deal(cashAssetAddress, user1, 100_000 ether);
        deal(cashAssetAddress, provider, 100_000 ether);
        deal(collateralAssetAddress, user1, 100_000 ether);
        deal(collateralAssetAddress, provider, 100_000 ether);
        deal(collateralAssetAddress, whale, 1_000_000 ether);
    }

    function _validateSetup(uint _duration, uint _offerLTV) internal view {
        assertEq(engine.isValidCollarDuration(_duration), true);
        assertEq(engine.isValidLTV(_offerLTV), true);
        assertEq(engine.isSupportedCashAsset(cashAssetAddress), true);
        assertEq(engine.isSupportedCollateralAsset(collateralAssetAddress), true);
        assertEq(engine.isCollarTakerNFT(address(takerNFT)), true);
        assertEq(engine.isProviderNFT(address(providerNFT)), true);
    }
}
