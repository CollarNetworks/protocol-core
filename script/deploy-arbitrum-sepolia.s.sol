// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import { ConfigHub } from "../src/ConfigHub.sol";
import { ProviderPositionNFT } from "../src/ProviderPositionNFT.sol";
import { OracleUniV3TWAP } from "../src/OracleUniV3TWAP.sol";
import { CollarTakerNFT } from "../src/CollarTakerNFT.sol";
import { Loans } from "../src/Loans.sol";
import { Rolls } from "../src/Rolls.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IUniswapV3Factory } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import { IV3SwapRouter } from "@uniswap/swap-router-contracts/contracts/interfaces/IV3SwapRouter.sol";
import { CollarOwnedERC20 } from "../test/utils/CollarOwnedERC20.sol";

contract DeployArbitrumSepoliaProtocol is Script {
    using SafeERC20 for IERC20;

    address deployer;
    uint constant chainId = 421_614; // Arbitrum Sepolia
    address constant uniswapV3FactoryAddress = 0x248AB79Bbb9bC29bB72f7Cd42F17e054Fc40188e; // Arbitrum Sepolia UniswapV3Factory
    uint24 constant FEE_TIER = 3000;
    uint32 constant TWAP_WINDOW = 15 minutes;

    IV3SwapRouter constant SWAP_ROUTER = IV3SwapRouter(0x101F443B4d1b059569D643917553c771E1b9663E);

    struct AssetPair {
        string collateralSymbol;
        string cashSymbol;
        address collateralAsset;
        address cashAsset;
    }

    AssetPair[] public assetPairs;

    struct DeployedContracts {
        ProviderPositionNFT providerNFT;
        OracleUniV3TWAP oracle;
        CollarTakerNFT takerNFT;
        Loans loansContract;
        Rolls rollsContract;
    }

    mapping(string => mapping(string => DeployedContracts)) public deployedContractPairs;

    ConfigHub public configHub;

    function run() external {
        require(block.chainid == chainId, "Wrong chain");

        uint deployerPrivateKey = vm.envUint("PRIVKEY_DEV_DEPLOYER");
        deployer = vm.addr(deployerPrivateKey);
        vm.startBroadcast(deployerPrivateKey);

        configHub = ConfigHub(0x67741B209d0A97972B7b95fA5DA55E70C14607BA);
        configHub.setUniV3Router(address(SWAP_ROUTER));

        initializeAssetPairs();

        for (uint i = 0; i < assetPairs.length; i++) {
            DeployedContracts memory contracts = deployContracts(configHub, deployer, assetPairs[i]);
            deployedContractPairs[assetPairs[i].collateralSymbol][assetPairs[i].cashSymbol] = contracts;

            console.log(
                "Deployed contracts for pair:", assetPairs[i].collateralSymbol, "/", assetPairs[i].cashSymbol
            );
            console.log("ProviderNFT deployed at:", address(contracts.providerNFT));
            console.log("TakerNFT deployed at:", address(contracts.takerNFT));
            console.log("Oracle deployed at:", address(contracts.oracle));
            console.log("Loans contract deployed at:", address(contracts.loansContract));
            console.log("Rolls contract deployed at:", address(contracts.rollsContract));

            _verifyDeployment(configHub, contracts, assetPairs[i]);
        }

        vm.stopBroadcast();
    }

    function initializeAssetPairs() internal {
        assetPairs.push(
            AssetPair(
                "wETH",
                "USDC",
                0x09Ba2a40950e9DA7db4d21578C3A8F322F94E5c7,
                0x871421373190Cfd686BF8738a544e30441C5B865
            )
        );
        assetPairs.push(
            AssetPair(
                "wETH",
                "USDT",
                0x09Ba2a40950e9DA7db4d21578C3A8F322F94E5c7,
                0x0D1a19ad75DDF5057958a46D81437BCC5927d399
            )
        );
        assetPairs.push(
            AssetPair(
                "wBTC",
                "USDC",
                0x30eB946e0fdc00d84D28a0e898B207eacA6e21f6,
                0x871421373190Cfd686BF8738a544e30441C5B865
            )
        );
        assetPairs.push(
            AssetPair(
                "wBTC",
                "USDT",
                0x30eB946e0fdc00d84D28a0e898B207eacA6e21f6,
                0x0D1a19ad75DDF5057958a46D81437BCC5927d399
            )
        );
    }

    function deployContracts(ConfigHub _configHub, address _deployer, AssetPair memory assetPair)
        internal
        returns (DeployedContracts memory)
    {
        require(
            assetPair.collateralAsset != address(0) && assetPair.cashAsset != address(0),
            "Invalid asset addresses"
        );

        // Add support for assets in the configHub
        _configHub.setCollateralAssetSupport(assetPair.collateralAsset, true);
        _configHub.setCashAssetSupport(assetPair.cashAsset, true);

        // Deploy contract pair
        OracleUniV3TWAP oracle = new OracleUniV3TWAP(
            assetPair.collateralAsset, assetPair.cashAsset, FEE_TIER, TWAP_WINDOW, address(SWAP_ROUTER)
        );

        CollarTakerNFT takerNFT = new CollarTakerNFT(
            _deployer,
            _configHub,
            IERC20(assetPair.cashAsset),
            IERC20(assetPair.collateralAsset),
            oracle,
            string(abi.encodePacked("Taker ", assetPair.collateralSymbol, "/", assetPair.cashSymbol)),
            string(abi.encodePacked("T", assetPair.collateralSymbol, "/", assetPair.cashSymbol))
        );

        ProviderPositionNFT providerNFT = new ProviderPositionNFT(
            _deployer,
            _configHub,
            IERC20(assetPair.cashAsset),
            IERC20(assetPair.collateralAsset),
            address(takerNFT),
            string(abi.encodePacked("Provider ", assetPair.collateralSymbol, "/", assetPair.cashSymbol)),
            string(abi.encodePacked("P", assetPair.collateralSymbol, "/", assetPair.cashSymbol))
        );

        Loans loansContract = new Loans(_deployer, takerNFT);
        Rolls rollsContract = new Rolls(_deployer, takerNFT);
        loansContract.setKeeper(_deployer);
        loansContract.setRollsContract(rollsContract);
        _configHub.setCollarTakerContractAuth(address(takerNFT), true);
        _configHub.setProviderContractAuth(address(providerNFT), true);

        return DeployedContracts({
            providerNFT: providerNFT,
            oracle: oracle,
            takerNFT: takerNFT,
            loansContract: loansContract,
            rollsContract: rollsContract
        });
    }

    function _verifyDeployment(
        ConfigHub _configHub,
        DeployedContracts memory contracts,
        AssetPair memory assetPair
    ) internal view {
        require(_configHub.isCollarTakerNFT(address(contracts.takerNFT)), "TakerNFT not authorized");
        require(_configHub.isProviderNFT(address(contracts.providerNFT)), "ProviderNFT not authorized");
        require(_configHub.isSupportedCashAsset(assetPair.cashAsset), "Cash asset not supported");
        require(
            _configHub.isSupportedCollateralAsset(assetPair.collateralAsset), "Collateral asset not supported"
        );

        console.log(
            "Deployment verified successfully for pair:",
            assetPair.collateralSymbol,
            "/",
            assetPair.cashSymbol
        );
    }
}
