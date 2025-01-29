// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import { Strings } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { ConfigHub } from "../src/ConfigHub.sol";
import { CollarProviderNFT } from "../src/CollarProviderNFT.sol";
import { CollarTakerNFT } from "../src/CollarTakerNFT.sol";
import { LoansNFT } from "../src/LoansNFT.sol";
import { Rolls } from "../src/Rolls.sol";
import { EscrowSupplierNFT } from "../src/EscrowSupplierNFT.sol";
import { ChainlinkOracle, BaseTakerOracle } from "../src/ChainlinkOracle.sol";
import { SwapperUniV3 } from "../src/SwapperUniV3.sol";
import { CombinedOracle } from "../src/CombinedOracle.sol";

library BaseDeployer {
    struct AssetPairContracts {
        CollarProviderNFT providerNFT;
        CollarTakerNFT takerNFT;
        LoansNFT loansContract;
        Rolls rollsContract;
        IERC20 cashAsset;
        IERC20 underlying;
        BaseTakerOracle oracle;
        SwapperUniV3 swapperUniV3;
        EscrowSupplierNFT escrowNFT;
        uint24 swapFeeTier;
    }

    struct ChainlinkFeed {
        address feedAddress;
        string description;
        uint heartbeat;
        uint decimals; // unused (quried onchain), defined for context
        uint deviationBIPS; // unused, defined for context
    }

    struct PairConfig {
        string name;
        IERC20 underlying;
        IERC20 cashAsset;
        BaseTakerOracle oracle;
        uint24 swapFeeTier;
        address swapRouter;
        address existingEscrowNFT; // New field for existing escrow contract
    }

    struct HubParams {
        uint minLTV;
        uint maxLTV;
        uint minDuration;
        uint maxDuration;
        address feeRecipient;
        uint feeAPR;
        address[] pauseGuardians;
    }

    struct DeploymentResult {
        ConfigHub configHub;
        AssetPairContracts[] assetPairContracts;
    }

    function deployConfigHub(address owner) internal returns (ConfigHub) {
        return new ConfigHub(owner);
    }

    function deployEscrowNFT(
        address owner,
        ConfigHub configHub,
        IERC20 underlying,
        string memory underlyingSymbol
    ) internal returns (EscrowSupplierNFT) {
        return new EscrowSupplierNFT(
            owner,
            configHub,
            underlying,
            string(abi.encodePacked("Escrow ", underlyingSymbol)),
            string(abi.encodePacked("E", underlyingSymbol))
        );
    }

    function deployChainlinkOracle(
        address base,
        address quote,
        ChainlinkFeed memory chainlinkFeed,
        address sequencerUptimeFeed
    ) internal returns (BaseTakerOracle oracle) {
        oracle = new ChainlinkOracle(
            base,
            quote,
            chainlinkFeed.feedAddress,
            chainlinkFeed.description,
            chainlinkFeed.heartbeat + 60, // a bit higher than heartbeat
            sequencerUptimeFeed
        );
    }

    function deployCombinedOracle(
        address base,
        address quote,
        BaseTakerOracle oracle1,
        BaseTakerOracle oracle2,
        bool invert2,
        string memory expectedDescription
    ) internal returns (BaseTakerOracle oracle) {
        oracle = new CombinedOracle(
            base,
            quote,
            address(oracle1),
            false, // this is false for all needed cases
            address(oracle2),
            invert2,
            expectedDescription
        );
    }

    function deployContractPair(address owner, ConfigHub configHub, PairConfig memory pairConfig)
        internal
        returns (AssetPairContracts memory contracts)
    {
        CollarTakerNFT takerNFT = new CollarTakerNFT(
            owner,
            configHub,
            pairConfig.cashAsset,
            pairConfig.underlying,
            pairConfig.oracle,
            string.concat("Taker ", pairConfig.name),
            string.concat("T", pairConfig.name)
        );
        CollarProviderNFT providerNFT = new CollarProviderNFT(
            owner,
            configHub,
            pairConfig.cashAsset,
            pairConfig.underlying,
            address(takerNFT),
            string.concat("Provider ", pairConfig.name),
            string.concat("P", pairConfig.name)
        );
        LoansNFT loansContract = new LoansNFT(
            owner, takerNFT, string.concat("Loans ", pairConfig.name), string.concat("L", pairConfig.name)
        );
        Rolls rollsContract = new Rolls(owner, takerNFT);
        SwapperUniV3 swapperUniV3 = new SwapperUniV3(pairConfig.swapRouter, pairConfig.swapFeeTier);
        // Use existing escrow if provided, otherwise create new
        EscrowSupplierNFT escrowNFT;
        if (pairConfig.existingEscrowNFT != address(0)) {
            escrowNFT = EscrowSupplierNFT(pairConfig.existingEscrowNFT);
        } else {
            escrowNFT = deployEscrowNFT(
                owner,
                configHub,
                pairConfig.underlying,
                IERC20Metadata(address(pairConfig.underlying)).symbol()
            );
        }
        contracts = AssetPairContracts({
            providerNFT: providerNFT,
            takerNFT: takerNFT,
            loansContract: loansContract,
            rollsContract: rollsContract,
            cashAsset: pairConfig.cashAsset,
            underlying: pairConfig.underlying,
            oracle: pairConfig.oracle,
            swapperUniV3: swapperUniV3,
            swapFeeTier: pairConfig.swapFeeTier,
            escrowNFT: escrowNFT
        });
    }

    function setupContractPair(ConfigHub hub, AssetPairContracts memory pair) internal {
        hub.setCanOpenPair(pair.underlying, pair.cashAsset, address(pair.takerNFT), true);
        hub.setCanOpenPair(pair.underlying, pair.cashAsset, address(pair.providerNFT), true);
        hub.setCanOpenPair(pair.underlying, pair.cashAsset, address(pair.loansContract), true);
        hub.setCanOpenPair(pair.underlying, pair.cashAsset, address(pair.rollsContract), true);
        hub.setCanOpenPair(pair.underlying, hub.ANY_ASSET(), address(pair.escrowNFT), true);

        pair.loansContract.setSwapperAllowed(address(pair.swapperUniV3), true, true);

        pair.escrowNFT.setLoansCanOpen(address(pair.loansContract), true);
    }

    function setupConfigHub(ConfigHub configHub, HubParams memory hubParams) internal {
        configHub.setLTVRange(hubParams.minLTV, hubParams.maxLTV);
        configHub.setCollarDurationRange(hubParams.minDuration, hubParams.maxDuration);
        configHub.setProtocolFeeParams(hubParams.feeAPR, hubParams.feeRecipient);
        for (uint i; i < hubParams.pauseGuardians.length; ++i) {
            configHub.setPauseGuardian(hubParams.pauseGuardians[i], true);
        }
    }

    // @dev this only nominates, and ownership must be accepted by the new owner
    function nominateNewOwnerAll(address owner, DeploymentResult memory result) internal {
        result.configHub.transferOwnership(owner);

        for (uint i = 0; i < result.assetPairContracts.length; i++) {
            nominateNewOwnerPair(owner, result.assetPairContracts[i]);
        }
    }

    function nominateNewOwnerPair(address owner, AssetPairContracts memory pair) internal {
        pair.takerNFT.transferOwnership(owner);
        pair.providerNFT.transferOwnership(owner);
        pair.loansContract.transferOwnership(owner);
        pair.rollsContract.transferOwnership(owner);
        pair.escrowNFT.transferOwnership(owner);
    }

    function acceptOwnershipAsSender(address acceptingOwner, DeploymentResult memory result) internal {
        // we can't ensure sender is acceptingOwner by checking here because:
        // - if this is run in a script msg.sender will be the scripts's sender
        // - if it's run from a test it will be whoever is being pranked, or the test contract
        // - if ran from within a contract, will be the contract address
        // In any case, the acceptance will not work if sender is incorrect.
        result.configHub.acceptOwnership();
        for (uint i = 0; i < result.assetPairContracts.length; i++) {
            BaseDeployer.AssetPairContracts memory pair = result.assetPairContracts[i];
            pair.takerNFT.acceptOwnership();
            pair.providerNFT.acceptOwnership();
            pair.loansContract.acceptOwnership();
            pair.rollsContract.acceptOwnership();
            // check because we may have already accepted previously (for another pair)
            if (pair.escrowNFT.owner() != acceptingOwner) pair.escrowNFT.acceptOwnership();
        }
    }
}
