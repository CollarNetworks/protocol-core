// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Script.sol";
import "forge-std/console.sol";

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

    function run() external {
        require(chainId == block.chainid, "chainId does not match the chainId in config");
        (address deployer, address user1, address user2, address liquidityProvider) = setup();
        vm.startBroadcast(deployer);
        _deployandSetupEngine();
        vm.stopBroadcast();
        console.log("\n");
        console.log("Verifying deployment : ");

        /**
         * @dev in order for this part to work provider address needs to be funded with casdh assets through
         * tenderly previously
         */
        require(liquidityProvider != address(0), "liquidity provider address not set");
        require(liquidityProvider.balance > 1000, "liquidity provider address not funded");
    }
}
