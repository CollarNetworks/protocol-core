// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import { ICollarVaultState } from "../src/interfaces/ICollarVaultState.sol";
import { CollarPool } from "../src/implementations/CollarPool.sol";
import { CollarVaultManager } from "../src/implementations/CollarVaultManager.sol";
import { CollarEngine } from "../src/implementations/CollarEngine.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
/**
 * THIS SCRIPT ASSUMES A POLYGON MAINNET FORK ENVIRONMENT
 *
 * 1. deploys the following contracts:
 * cashToken:  cash asset for the collar pool
 * collateralToken :  colaterall asset for the collar pool
 * router: uniswap router for the engine
 * engine: collar engine
 * oneDayPool: Collar pool with 1 day duration
 * oneWeekPool: Collar pool with 7 days duration
 *
 * 2. adds liquidity pools,assets and durations to the engine
 * 3. mints a million of each asset to the router
 * 4. mints 100k and 200k to test addresses
 * 5. creates vault managers for two test addresses
 * 6. adds liquidity to the slots `11_100,11_200,11_500,12_000` for both pools
 */

contract DeployInitializedDevnetProtocol is Script {
    using SafeERC20 for IERC20;

    address router;
    address engine;

    /**
     * @dev config for script:
     * setup token addresses depending on the forked network
     * setup the swap router address
     * setup the number of pools to create (modify if `_createPools` is modified)
     * setup chainId for the forked network to use
     * CURRENT FORKED NETWORK: ETHEREUM MAINNET
     */
    uint chainId = 137_999; // id for ethereum mainnet fork on tenderly
    address USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address stETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address eETH = 0x35fA164735182de50811E8e2E824cFb9B6118ac2;
    address WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address MATIC = 0x7D1AfA7B718fb893dB30A3aBc0Cfc608AaCfeBB0;
    address swapRouterAddress = address(0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45);
    uint constant numOfPools = 11;

    function setup()
        internal
        returns (address deployer, address user1, address user2, address liquidityProvider)
    {
        VmSafe.Wallet memory deployerWallet = vm.createWallet(vm.envUint("PRIVKEY_DEV_DEPLOYER"));
        VmSafe.Wallet memory user1Wallet = vm.createWallet(vm.envUint("PRIVKEY_DEV_TEST1"));
        VmSafe.Wallet memory user2Wallet = vm.createWallet(vm.envUint("PRIVKEY_DEV_TEST2"));
        VmSafe.Wallet memory liquidityProviderWallet = vm.createWallet(vm.envUint("PRIVKEY_DEV_TEST3"));

        vm.rememberKey(deployerWallet.privateKey);
        vm.rememberKey(user1Wallet.privateKey);
        vm.rememberKey(user2Wallet.privateKey);
        vm.rememberKey(liquidityProviderWallet.privateKey);
        console.log("\n # Dev Deployer Address: %x", deployerWallet.addr);
        console.log("\n # Dev Deployer Key:     %x", deployerWallet.privateKey);
        console.log("\n # Test Users\n");
        console.log(" - User 1 Address: %s", user1Wallet.addr);
        console.log(" - User 1 Privkey: %x", user1Wallet.privateKey);
        console.log(" - User 2 Address: %s", user2Wallet.addr);
        console.log(" - User 2 Privkey: %x", user2Wallet.privateKey);
        console.log(" - Liquidity provider Address: %s", liquidityProviderWallet.addr);
        console.log(" - Liquidity provider Privkey: %x", liquidityProviderWallet.privateKey);
        return (deployerWallet.addr, user1Wallet.addr, user2Wallet.addr, liquidityProviderWallet.addr);
    }

    function _deployandSetupEngine() internal {
        router = swapRouterAddress;
        engine = address(new CollarEngine(router));

        // add supported LTV values
        CollarEngine(engine).addLTV(9000);
        CollarEngine(engine).addLTV(5000);
        // add supported durations
        CollarEngine(engine).addCollarDuration(5 minutes);
        CollarEngine(engine).addCollarDuration(30 days);
        CollarEngine(engine).addCollarDuration(12 * 30 days);
        // add supported cash assets
        CollarEngine(engine).addSupportedCashAsset(USDC);
        CollarEngine(engine).addSupportedCashAsset(USDT);
        // add supported collateral assets
        CollarEngine(engine).addSupportedCollateralAsset(WETH);
        CollarEngine(engine).addSupportedCollateralAsset(WBTC);
        CollarEngine(engine).addSupportedCollateralAsset(MATIC);
        CollarEngine(engine).addSupportedCollateralAsset(stETH);
        CollarEngine(engine).addSupportedCollateralAsset(eETH);
        console.log("\n --- Dev Environment Deployed ---");
        console.log("\n # Contract Addresses\n");
        console.log(" - Router:  - - - - - - ", router);
        console.log(" - Engine - - - - - - - ", engine);
    }

    function _createPools() internal returns (address[numOfPools] memory pools) {
        // create main WETH pools
        address fiveMin90ltvPool = address(new CollarPool(engine, 1, USDC, WETH, 5 minutes, 9000));
        address fiveMin90LTVTetherPool = address(new CollarPool(engine, 1, USDT, WETH, 5 minutes, 9000));
        address fiveMin50LTVPool = address(new CollarPool(engine, 1, USDC, WETH, 5 minutes, 5000));
        address oneMonth90LTVPool = address(new CollarPool(engine, 1, USDC, WETH, 30 days, 9000));
        address oneMonth50LTVPool = address(new CollarPool(engine, 1, USDC, WETH, 30 days, 5000));
        address oneYear90LTVPool = address(new CollarPool(engine, 1, USDC, WETH, 12 * 30 days, 9000));
        address oneYear50LTVPool = address(new CollarPool(engine, 1, USDC, WETH, 12 * 30 days, 5000));

        CollarEngine(engine).addLiquidityPool(fiveMin90ltvPool);
        CollarEngine(engine).addLiquidityPool(fiveMin90LTVTetherPool);
        CollarEngine(engine).addLiquidityPool(fiveMin50LTVPool);
        CollarEngine(engine).addLiquidityPool(oneMonth90LTVPool);
        CollarEngine(engine).addLiquidityPool(oneMonth50LTVPool);
        CollarEngine(engine).addLiquidityPool(oneYear90LTVPool);
        CollarEngine(engine).addLiquidityPool(oneYear50LTVPool);

        // rest of pools all 5 minutes with usdc

        address fiveMin90LTVWBTCPool = address(new CollarPool(engine, 1, USDC, WBTC, 5 minutes, 9000));
        address fiveMin90LTVMATICPool = address(new CollarPool(engine, 1, USDC, MATIC, 5 minutes, 9000));
        address fiveMin90LTVstETHPool = address(new CollarPool(engine, 1, USDC, stETH, 5 minutes, 9000));
        address fiveMin90LTVeETHPool = address(new CollarPool(engine, 1, USDC, eETH, 5 minutes, 9000));

        CollarEngine(engine).addLiquidityPool(fiveMin90LTVWBTCPool);
        CollarEngine(engine).addLiquidityPool(fiveMin90LTVMATICPool);
        CollarEngine(engine).addLiquidityPool(fiveMin90LTVstETHPool);
        CollarEngine(engine).addLiquidityPool(fiveMin90LTVeETHPool);
        console.log(" - Collar 5 minutes 90LTV WETH/USDC Pool - - - - - - - ", fiveMin90ltvPool);
        console.log(" - Collar 5 minutes 90LTV USDT/WETH Pool - - - - - - - ", fiveMin90LTVTetherPool);
        console.log(" - Collar 5 minutes 50LTV WETH/USDC Pool - - - - - - - ", fiveMin50LTVPool);
        console.log(" - Collar 30 days 90LTV WETH/USDC Pool - - - - - - - - ", oneMonth90LTVPool);
        console.log(" - Collar 30 days 50LTV WETH/USDC Pool - - - - - - - - ", oneMonth50LTVPool);
        console.log(" - Collar 12 months 90LTV WETH/USDC Pool - - - - - - - ", oneYear90LTVPool);
        console.log(" - Collar 12 months 50LTV WETH/USDC Pool - - - - - - - ", oneYear50LTVPool);
        console.log(" - Collar 5 minutes 90LTV WBTC/USDC Pool - - - - - - - ", fiveMin90LTVWBTCPool);
        console.log(" - Collar 5 minutes 90LTV MATIC/USDC Pool - - - - - - - ", fiveMin90LTVMATICPool);
        console.log(" - Collar 5 minutes 90LTV stETH/USDC Pool - - - - - - - ", fiveMin90LTVstETHPool);
        console.log(" - Collar 5 minutes 90LTV eETH/USDC Pool - - - - - - - ", fiveMin90LTVeETHPool);
        pools = [
            fiveMin90ltvPool,
            fiveMin90LTVTetherPool,
            fiveMin50LTVPool,
            oneMonth90LTVPool,
            oneMonth50LTVPool,
            oneYear90LTVPool,
            oneYear50LTVPool,
            fiveMin90LTVWBTCPool,
            fiveMin90LTVMATICPool,
            fiveMin90LTVstETHPool,
            fiveMin90LTVeETHPool
        ];
        require(
            pools.length == numOfPools,
            "config error: number of pools created does not match the number of pools expected"
        );
    }

    function _verifyVaultManagerCreation(address user1, address user2) internal {
        vm.startBroadcast(user1);

        address user1VaultManager = address(CollarEngine(engine).createVaultManager());

        vm.stopBroadcast();

        vm.startBroadcast(user2);

        address user2VaultManager = address(CollarEngine(engine).createVaultManager());

        vm.stopBroadcast();

        require(CollarEngine(engine).addressToVaultManager(user1) == user1VaultManager);
        require(CollarEngine(engine).addressToVaultManager(user2) == user2VaultManager);
        console.log("\n # Vault Managers\n");
        console.log(" - User 1 Vault Manager: ", user1VaultManager);
        console.log(" - User 2 Vault Manager: ", user2VaultManager);
    }

    function _verifyPoolCreation(uint expectedLength, address firstPool, address lastPool) internal view {
        // supportedLiquidityPoolsLength
        uint shouldBePoolLength = CollarEngine(engine).supportedLiquidityPoolsLength();
        console.log(" shouldBePoolLength", shouldBePoolLength);
        require(shouldBePoolLength == expectedLength);

        // getSupportedLiquidityPool
        address shouldBeFirstPoolCreated = CollarEngine(engine).getSupportedLiquidityPool(0);
        console.log(" shouldBeFirstPoolCreated", shouldBeFirstPoolCreated);
        require(shouldBeFirstPoolCreated == firstPool);

        address shouldBeLastPoolCreated =
            CollarEngine(engine).getSupportedLiquidityPool(shouldBePoolLength - 1);
        console.log(" shouldBeLastPoolCreated", shouldBeLastPoolCreated);
        require(shouldBeLastPoolCreated == lastPool);
    }

    function _addLiquidityToPools(address[numOfPools] memory pools, uint amountToAdd) internal {
        // setup pool liquidity // assume provider has enough funds

        // add liquidity to each pool
        for (uint i = 0; i < pools.length; i++) {
            address cashAssetToUse = CollarPool(pools[i]).cashAsset();
            IERC20(cashAssetToUse).forceApprove(pools[i], amountToAdd * 5);
            CollarPool(pools[i]).addLiquidityToSlot(11_100, amountToAdd);
            CollarPool(pools[i]).addLiquidityToSlot(11_200, amountToAdd);
            CollarPool(pools[i]).addLiquidityToSlot(11_500, amountToAdd);
            CollarPool(pools[i]).addLiquidityToSlot(12_000, amountToAdd);
        }
    }

    function run() external {
        require(chainId == block.chainid, "chainId does not match the chainId in config");
        (address deployer, address user1, address user2, address liquidityProvider) = setup();
        vm.startBroadcast(deployer);
        _deployandSetupEngine();
        // create main WETH pools
        address[numOfPools] memory createdPools = _createPools();
        vm.stopBroadcast();

        console.log("\n");
        console.log("Verifying deployment : ");
        _verifyVaultManagerCreation(user1, user2);
        _verifyPoolCreation(numOfPools, createdPools[0], createdPools[numOfPools - 1]);

        /**
         * @dev in order for this part to work provider address needs to be funded with casdh assets through
         * tenderly previously
         */
        require(liquidityProvider != address(0), "liquidity provider address not set");
        require(liquidityProvider.balance > 1000, "liquidity provider address not funded");
        uint amountToAdd = 100_000e6;
        uint lpBalance = IERC20(CollarPool(createdPools[0]).cashAsset()).balanceOf(liquidityProvider);
        require(lpBalance >= amountToAdd * 4, "liquidity provider does not have enough funds");
        vm.startBroadcast(liquidityProvider);
        _addLiquidityToPools(createdPools, amountToAdd);
        vm.stopBroadcast();
    }
}
