// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import { ConfigHub } from "../src/ConfigHub.sol";
import { ProviderPositionNFT } from "../src/ProviderPositionNFT.sol";
import { CollarTakerNFT } from "../src/CollarTakerNFT.sol";
import { Loans } from "../src/Loans.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Rolls } from "../src/Rolls.sol";
import { OracleUniV3TWAP } from "../src/OracleUniV3TWAP.sol";
import { SwapperUniV3 } from "../src/SwapperUniV3.sol";

contract DeploymentHelper {
    struct AssetPairContracts {
        ProviderPositionNFT providerNFT;
        CollarTakerNFT takerNFT;
        Loans loansContract;
        Rolls rollsContract;
        IERC20 cashAsset;
        IERC20 collateralAsset;
        OracleUniV3TWAP oracle;
        SwapperUniV3 swapperUniV3;
        uint24 oracleFeeTier;
        uint24 swapFeeTier;
        uint[] durations;
        uint[] ltvs;
    }

    struct PairConfig {
        string name;
        IERC20 cashAsset;
        IERC20 collateralAsset;
        uint[] durations;
        uint[] ltvs;
        uint24 oracleFeeTier;
        uint24 swapFeeTier;
        uint32 twapWindow;
        address swapRouter;
    }

    function deployConfigHub(address owner) public returns (ConfigHub) {
        return new ConfigHub(owner);
    }

    function deployContractPair(ConfigHub configHub, PairConfig memory pairConfig, address owner)
        public
        returns (AssetPairContracts memory contracts)
    {
        OracleUniV3TWAP oracle = new OracleUniV3TWAP(
            address(pairConfig.collateralAsset),
            address(pairConfig.cashAsset),
            pairConfig.oracleFeeTier,
            pairConfig.twapWindow,
            pairConfig.swapRouter
        );

        CollarTakerNFT takerNFT = new CollarTakerNFT(
            owner,
            configHub,
            pairConfig.cashAsset,
            pairConfig.collateralAsset,
            oracle,
            string(abi.encodePacked("Taker ", pairConfig.name)),
            string(abi.encodePacked("T", pairConfig.name))
        );
        ProviderPositionNFT providerNFT = new ProviderPositionNFT(
            owner,
            configHub,
            pairConfig.cashAsset,
            pairConfig.collateralAsset,
            address(takerNFT),
            string(abi.encodePacked("Provider ", pairConfig.name)),
            string(abi.encodePacked("P", pairConfig.name))
        );
        Loans loansContract = new Loans(owner, takerNFT);
        Rolls rollsContract = new Rolls(owner, takerNFT);
        SwapperUniV3 swapperUniV3 = new SwapperUniV3(pairConfig.swapRouter, pairConfig.swapFeeTier);

        contracts = AssetPairContracts({
            providerNFT: providerNFT,
            takerNFT: takerNFT,
            loansContract: loansContract,
            rollsContract: rollsContract,
            cashAsset: pairConfig.cashAsset,
            collateralAsset: pairConfig.collateralAsset,
            oracle: oracle,
            swapperUniV3: swapperUniV3,
            oracleFeeTier: pairConfig.oracleFeeTier,
            swapFeeTier: pairConfig.swapFeeTier,
            durations: pairConfig.durations,
            ltvs: pairConfig.ltvs
        });
    }
}
