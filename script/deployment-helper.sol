// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import { ConfigHub } from "../src/ConfigHub.sol";
import { CollarProviderNFT } from "../src/CollarProviderNFT.sol";
import { CollarTakerNFT } from "../src/CollarTakerNFT.sol";
import { LoansNFT } from "../src/LoansNFT.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Rolls } from "../src/Rolls.sol";
import { EscrowSupplierNFT } from "../src/EscrowSupplierNFT.sol";
import { OracleUniV3TWAP } from "../src/OracleUniV3TWAP.sol";
import { SwapperUniV3 } from "../src/SwapperUniV3.sol";

library DeploymentHelper {
    struct AssetPairContracts {
        CollarProviderNFT providerNFT;
        CollarTakerNFT takerNFT;
        LoansNFT loansContract;
        Rolls rollsContract;
        IERC20 cashAsset;
        IERC20 underlying;
        OracleUniV3TWAP oracle;
        SwapperUniV3 swapperUniV3;
        EscrowSupplierNFT escrowNFT;
        uint24 oracleFeeTier;
        uint24 swapFeeTier;
        uint[] durations;
        uint[] ltvs;
    }

    struct PairConfig {
        string name;
        IERC20 cashAsset;
        IERC20 underlying;
        uint[] durations;
        uint[] ltvs;
        uint24 oracleFeeTier;
        uint24 swapFeeTier;
        uint32 twapWindow;
        address swapRouter;
        address sequencerUptimeFeed;
    }

    function deployConfigHub(address owner) internal returns (ConfigHub) {
        return new ConfigHub(owner);
    }

    function deployContractPair(ConfigHub configHub, PairConfig memory pairConfig, address owner)
        internal
        returns (AssetPairContracts memory contracts)
    {
        OracleUniV3TWAP oracle = new OracleUniV3TWAP(
            address(pairConfig.underlying),
            address(pairConfig.cashAsset),
            pairConfig.oracleFeeTier,
            pairConfig.twapWindow,
            pairConfig.swapRouter,
            pairConfig.sequencerUptimeFeed
        );

        CollarTakerNFT takerNFT = new CollarTakerNFT(
            owner,
            configHub,
            pairConfig.cashAsset,
            pairConfig.underlying,
            oracle,
            string(abi.encodePacked("Taker ", pairConfig.name)),
            string(abi.encodePacked("T", pairConfig.name))
        );
        CollarProviderNFT providerNFT = new CollarProviderNFT(
            owner,
            configHub,
            pairConfig.cashAsset,
            pairConfig.underlying,
            address(takerNFT),
            string(abi.encodePacked("Provider ", pairConfig.name)),
            string(abi.encodePacked("P", pairConfig.name))
        );
        LoansNFT loansContract = new LoansNFT(
            owner,
            takerNFT,
            string(abi.encodePacked("Loans ", pairConfig.name)),
            string(abi.encodePacked("L", pairConfig.name))
        );
        Rolls rollsContract = new Rolls(owner, takerNFT);
        SwapperUniV3 swapperUniV3 = new SwapperUniV3(pairConfig.swapRouter, pairConfig.swapFeeTier);
        EscrowSupplierNFT escrowNFT = new EscrowSupplierNFT(
            owner,
            configHub,
            pairConfig.underlying,
            string(abi.encodePacked("Escrow ", pairConfig.name)),
            string(abi.encodePacked("E", pairConfig.name))
        );
        contracts = AssetPairContracts({
            providerNFT: providerNFT,
            takerNFT: takerNFT,
            loansContract: loansContract,
            rollsContract: rollsContract,
            cashAsset: pairConfig.cashAsset,
            underlying: pairConfig.underlying,
            oracle: oracle,
            swapperUniV3: swapperUniV3,
            oracleFeeTier: pairConfig.oracleFeeTier,
            swapFeeTier: pairConfig.swapFeeTier,
            durations: pairConfig.durations,
            ltvs: pairConfig.ltvs,
            escrowNFT: escrowNFT
        });
    }
}
