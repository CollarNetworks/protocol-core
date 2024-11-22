// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import { ConfigHub } from "../src/ConfigHub.sol";
import { CollarProviderNFT } from "../src/CollarProviderNFT.sol";
import { CollarTakerNFT } from "../src/CollarTakerNFT.sol";
import { LoansNFT } from "../src/LoansNFT.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Rolls } from "../src/Rolls.sol";
import { EscrowSupplierNFT } from "../src/EscrowSupplierNFT.sol";
import { ChainlinkOracle, BaseTakerOracle } from "../src/ChainlinkOracle.sol";
import { SwapperUniV3 } from "../src/SwapperUniV3.sol";
import { CombinedOracle } from "../src/CombinedOracle.sol";

abstract contract BaseDeployer {
    address constant VIRTUAL_ASSET = address(type(uint160).max); // 0xff..ff

    uint immutable chainId;

    uint immutable minDuration;
    uint immutable maxDuration;
    uint immutable minLTV;
    uint immutable maxLTV;

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
        uint decimals;
        uint deviationBIPS;
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
    }

    struct DeploymentResult {
        ConfigHub configHub;
        AssetPairContracts[] assetPairContracts;
    }

    mapping(bytes32 description => ChainlinkFeed feedConfig) internal priceFeeds;

    function _configureFeed(ChainlinkFeed memory feedConfig) internal {
        priceFeeds[bytes32(bytes(feedConfig.description))] = feedConfig;
    }

    function _getFeed(string memory description) internal view returns (ChainlinkFeed memory) {
        return priceFeeds[bytes32(bytes(description))];
    }

    function deployAndSetupProtocol(address owner) internal returns (DeploymentResult memory result) {
        require(chainId == block.chainid, "chainId does not match the chainId in config");

        result.configHub = deployConfigHub(owner);

        setupConfigHub(
            result.configHub,
            HubParams({ minLTV: minLTV, maxLTV: maxLTV, minDuration: minDuration, maxDuration: maxDuration })
        );

        result.assetPairContracts = _createContractPairs(result.configHub, owner);

        for (uint i = 0; i < result.assetPairContracts.length; i++) {
            setupContractPair(result.configHub, result.assetPairContracts[i]);
        }
    }

    function _createContractPairs(ConfigHub configHub, address owner)
        internal
        virtual
        returns (AssetPairContracts[] memory assetPairContracts);

    function deployConfigHub(address owner) internal returns (ConfigHub) {
        return new ConfigHub(owner);
    }

    function deployEscrowNFT(
        ConfigHub configHub,
        address owner,
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
        bool invert2
    ) internal returns (BaseTakerOracle oracle) {
        oracle = new CombinedOracle(
            base,
            quote,
            address(oracle1),
            false, // this is false for all needed cases
            address(oracle2),
            invert2
        );
    }

    function deployContractPair(ConfigHub configHub, PairConfig memory pairConfig, address owner)
        internal
        returns (AssetPairContracts memory contracts)
    {
        CollarTakerNFT takerNFT = new CollarTakerNFT(
            owner,
            configHub,
            pairConfig.cashAsset,
            pairConfig.underlying,
            pairConfig.oracle,
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
        // Use existing escrow if provided, otherwise create new
        EscrowSupplierNFT escrowNFT;
        if (pairConfig.existingEscrowNFT != address(0)) {
            escrowNFT = EscrowSupplierNFT(pairConfig.existingEscrowNFT);
        } else {
            escrowNFT = deployEscrowNFT(
                configHub,
                owner,
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
        pair.loansContract.setSwapperAllowed(address(pair.swapperUniV3), true, true);
        hub.setCanOpenPair(pair.underlying, hub.ANY_ASSET(), address(pair.escrowNFT), true);
        pair.escrowNFT.setLoansCanOpen(address(pair.loansContract), true);
    }

    function setupConfigHub(ConfigHub configHub, HubParams memory hubParams) internal {
        configHub.setLTVRange(hubParams.minLTV, hubParams.maxLTV);
        configHub.setCollarDurationRange(hubParams.minDuration, hubParams.maxDuration);
    }
}
