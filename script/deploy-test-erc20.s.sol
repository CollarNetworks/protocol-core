// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import { CollarEngine } from "../src/implementations/CollarEngine.sol";
import { ProviderPositionNFT } from "../src/ProviderPositionNFT.sol";
import { CollarTakerNFT } from "../src/CollarTakerNFT.sol";
import { Loans } from "../src/Loans.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IUniswapV3Factory } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import { CollarOwnedERC20 } from "../src//utils/CollarOwnedERC20.sol";

contract DeployArbitrumSepoliaProtocol is Script {
    using SafeERC20 for IERC20;

    uint constant chainId = 421_614; // Arbitrum Sepolia
    address constant uniswapV3FactoryAddress = 0x248AB79Bbb9bC29bB72f7Cd42F17e054Fc40188e; // Arbitrum Sepolia UniswapV3Factory

    uint24 constant POOL_FEE = 3000;

    function setUp() public { }

    function run() external {
        require(block.chainid == chainId, "Wrong chain");

        uint deployerPrivateKey = vm.envUint("PRIVKEY_DEV_DEPLOYER");
        address deployer = vm.addr(deployerPrivateKey);
        address liquidityProvider = vm.addr(vm.envUint("LIQUIDITY_PROVIDER_KEY"));

        vm.startBroadcast(deployerPrivateKey);

        address collateralAsset = address(new CollarOwnedERC20(deployer, "Collateral Asset", "COLL"));
        address cashAsset = address(new CollarOwnedERC20(deployer, "Cash Asset", "CASH"));
        console.log("Collateral asset address:", collateralAsset);
        console.log("Cash asset address:", cashAsset);
        CollarOwnedERC20(collateralAsset).mint(liquidityProvider, 1_000_000e18);
        CollarOwnedERC20(cashAsset).mint(liquidityProvider, 1_000_000e18);
        // check total supply
        console.log("cashAsset total supply:", CollarOwnedERC20(cashAsset).totalSupply());
        console.log("collateralAsset total supply:", CollarOwnedERC20(collateralAsset).totalSupply());
        // Debug: Check if tokens exist
        console.log("collateralAsset code size:", address(collateralAsset).code.length);
        console.log("cashAsset code size:", address(cashAsset).code.length);

        IUniswapV3Factory factory = IUniswapV3Factory(uniswapV3FactoryAddress);
        // check factory owner
        console.log("Factory owner:", factory.owner());
        // check fee tier is enabled
        console.logInt(factory.feeAmountTickSpacing(POOL_FEE));
        // Debug: Check if pool already exists
        address existingPool = factory.getPool(collateralAsset, cashAsset, POOL_FEE);
        console.log("Existing pool address:", existingPool);

        // Create Uniswap V3 pool
        address pool = factory.createPool(cashAsset, collateralAsset, POOL_FEE);
        console.log("pool address:", pool);
        // Mint tokens for liquidity provider

        vm.stopBroadcast();
    }
}
