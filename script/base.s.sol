// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import { ConfigHub } from "../src/ConfigHub.sol";
import { ProviderPositionNFT } from "../src/ProviderPositionNFT.sol";
import { CollarTakerNFT } from "../src/CollarTakerNFT.sol";
import { Loans } from "../src/Loans.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Rolls } from "../src/Rolls.sol";
import { DeploymentUtils } from "./utils/deployment-exporter.s.sol";
import { OracleUniV3TWAP } from "../src/OracleUniV3TWAP.sol";

contract BaseDeployment is Script {
    address router;
    ConfigHub configHub;
    address deployerAddress;

    struct AssetPairContracts {
        ProviderPositionNFT providerNFT;
        CollarTakerNFT takerNFT;
        Loans loansContract;
        Rolls rollsContract;
        IERC20 cashAsset;
        IERC20 collateralAsset;
        OracleUniV3TWAP oracle;
        uint[] durations;
        uint[] ltvs;
    }

    uint[] callStrikeTicks = [11_100, 11_200, 11_500, 12_000];

    uint24 constant FEE_TIER = 3000;
    uint32 constant TWAP_WINDOW = 15 minutes;

    function setup()
        internal
        returns (address deployer, address user1, address user2, address liquidityProvider)
    {
        VmSafe.Wallet memory deployerWallet = vm.createWallet(vm.envUint("PRIVKEY_DEV_DEPLOYER"));
        VmSafe.Wallet memory user1Wallet = vm.createWallet(vm.envUint("PRIVKEY_DEV_TEST1"));
        VmSafe.Wallet memory user2Wallet = vm.createWallet(vm.envUint("PRIVKEY_DEV_TEST2"));
        VmSafe.Wallet memory liquidityProviderWallet = vm.createWallet(vm.envUint("LIQUIDITY_PROVIDER_KEY"));

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
}
