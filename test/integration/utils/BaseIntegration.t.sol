// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import { ConfigHub } from "../../../src/ConfigHub.sol";
import { CollarProviderNFT } from "../../../src/CollarProviderNFT.sol";
import { OracleUniV3TWAP } from "../../../src/OracleUniV3TWAP.sol";
import { CollarTakerNFT } from "../../../src/CollarTakerNFT.sol";
import { LoansNFT, ILoansNFT } from "../../../src/LoansNFT.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IV3SwapRouter } from "@uniswap/swap-router-contracts/contracts/interfaces/IV3SwapRouter.sol";
import { DeploymentHelper } from "../../../script/deployment-helper.sol";
import { SetupHelper } from "../../../script/setup-helper.sol";

abstract contract CollarBaseIntegrationTestConfig is Test, DeploymentHelper, SetupHelper {
    using SafeERC20 for IERC20;

    ConfigHub configHub;
    address owner;
    address user;
    address provider;
    DeploymentHelper.AssetPairContracts pair;
    address swapRouterAddress;
    address uniV3Pool;
    address whale;
    uint BLOCK_NUMBER_TO_USE;
    uint COLLATERAL_PRICE_ON_BLOCK;
    uint24 CALL_STRIKE_TICK = 120;
    uint positionDuration;
    uint offerLTV;
    uint bigNumber = 1_000_000 ether;

    function setup()
        internal
        returns (address deployer, address user1, address user2, address liquidityProvider)
    {
        uint deployerPrivKey = vm.envUint("PRIVKEY_DEV_DEPLOYER");
        uint user1PrivKey = vm.envUint("PRIVKEY_DEV_TEST1");
        uint user2PrivKey = vm.envUint("PRIVKEY_DEV_TEST2");
        uint liquidityProviderPrivKey = vm.envUint("LIQUIDITY_PROVIDER_KEY");

        deployer = vm.addr(deployerPrivKey);
        user1 = vm.addr(user1PrivKey);
        user2 = vm.addr(user2PrivKey);
        liquidityProvider = vm.addr(liquidityProviderPrivKey);

        vm.label(deployer, "Deployer");
        vm.label(user1, "User 1");
        vm.label(user2, "User 2");
        vm.label(liquidityProvider, "Liquidity Provider");

        console.log("\n # Dev Deployer Address: %s", deployer);
        console.log(" # Test Users");
        console.log(" - User 1 Address: %s", user1);
        console.log(" - User 2 Address: %s", user2);
        console.log(" - Liquidity provider Address: %s", liquidityProvider);

        return (deployer, user1, user2, liquidityProvider);
    }

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
        uint _offerLTV,
        string memory pairName
    ) internal {
        swapRouterAddress = _swapRouter;
        uniV3Pool = _uniV3Pool;
        whale = whaleWallet;
        BLOCK_NUMBER_TO_USE = blockNumber;
        COLLATERAL_PRICE_ON_BLOCK = priceOnBlock;
        CALL_STRIKE_TICK = callStrikeTickToUse;
        (address deployer, address user1,, address liquidityProvider) = setup();
        owner = deployer;
        provider = liquidityProvider;
        user = user1;
        positionDuration = _positionDuration;
        offerLTV = _offerLTV;
        _deployProtocolContracts(_cashAsset, _collateralAsset, pairName);
    }

    function _deployProtocolContracts(address _cashAsset, address _collateralAsset, string memory pairName)
        internal
    {
        startHoax(owner);
        configHub = deployConfigHub(owner);
        address[] memory collateralAssets = new address[](1);
        collateralAssets[0] = _collateralAsset;
        address[] memory cashAssets = new address[](1);
        cashAssets[0] = _cashAsset;
        setupConfigHub(
            configHub,
            SetupHelper.HubParams({
                cashAssets: cashAssets,
                collateralAssets: collateralAssets,
                minLTV: offerLTV,
                maxLTV: offerLTV,
                minDuration: positionDuration,
                maxDuration: positionDuration
            })
        );
        uint[] memory durations = new uint[](1);
        durations[0] = positionDuration;
        uint[] memory ltvs = new uint[](1);
        ltvs[0] = offerLTV;
        DeploymentHelper.PairConfig memory pairConfig = DeploymentHelper.PairConfig({
            name: pairName,
            durations: durations,
            ltvs: ltvs,
            cashAsset: IERC20(_cashAsset),
            collateralAsset: IERC20(_collateralAsset),
            oracleFeeTier: 3000,
            swapFeeTier: 3000,
            twapWindow: 15 minutes,
            swapRouter: swapRouterAddress
        });
        pair = deployContractPair(configHub, pairConfig, owner);
        setupContractPair(configHub, pair);
        pair.cashAsset.forceApprove(address(pair.takerNFT), type(uint).max);
        pair.collateralAsset.forceApprove(address(pair.takerNFT), type(uint).max);
    }

    function _fundWallets() internal {
        deal(address(pair.cashAsset), whale, bigNumber);
        deal(address(pair.cashAsset), user, bigNumber);
        deal(address(pair.cashAsset), provider, bigNumber);
        deal(address(pair.collateralAsset), user, bigNumber);
        deal(address(pair.collateralAsset), provider, bigNumber);
        deal(address(pair.collateralAsset), whale, bigNumber);
    }

    function _validateSetup(uint _duration, uint _offerLTV) internal view {
        assertEq(configHub.isValidCollarDuration(_duration), true);
        assertEq(configHub.isValidLTV(_offerLTV), true);
        assertEq(configHub.isSupportedCashAsset(address(pair.cashAsset)), true);
        assertEq(configHub.isSupportedCollateralAsset(address(pair.collateralAsset)), true);
        assertEq(configHub.canOpen(address(pair.takerNFT)), true);
        assertEq(configHub.canOpen(address(pair.providerNFT)), true);
    }
}
