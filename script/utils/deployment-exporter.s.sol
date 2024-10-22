// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import { Vm } from "forge-std/Vm.sol";
import { CollarProviderNFT } from "../../src/CollarProviderNFT.sol";
import { CollarTakerNFT } from "../../src/CollarTakerNFT.sol";
import { LoansNFT } from "../../src/LoansNFT.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Rolls } from "../../src/Rolls.sol";
import { DeploymentHelper } from "../deployment-helper.sol";
import { OracleUniV3TWAP } from "../../src/OracleUniV3TWAP.sol";
import { SwapperUniV3 } from "../../src/SwapperUniV3.sol";

library DeploymentUtils {
    uint8 constant ADDRESS_LENGTH = 42; // 20 raw bytes * 2 hex chars per byte + 2 for 0x prefix

    function exportDeployment(
        Vm vm,
        string memory name,
        address configHub,
        address router,
        DeploymentHelper.AssetPairContracts[] memory assetPairs
    ) internal {
        string memory json = constructJson(vm, configHub, router, assetPairs);
        writeJsonToFile(vm, name, json);
    }

    function constructJson(
        Vm vm,
        address configHub,
        address router,
        DeploymentHelper.AssetPairContracts[] memory assetPairs
    ) internal pure returns (string memory) {
        string memory json = "{";

        json = string(abi.encodePacked(json, '"configHub": "', vm.toString(configHub), '",'));
        json = string(abi.encodePacked(json, '"router": "', vm.toString(router), '",'));

        for (uint i = 0; i < assetPairs.length; i++) {
            DeploymentHelper.AssetPairContracts memory pair = assetPairs[i];
            string memory pairName = string(
                abi.encodePacked(
                    vm.toString(address(pair.underlying)), "_", vm.toString(address(pair.cashAsset))
                )
            );

            json = string(
                abi.encodePacked(
                    json, '"', pairName, '_takerNFT": "', vm.toString(address(pair.takerNFT)), '",'
                )
            );
            json = string(
                abi.encodePacked(
                    json, '"', pairName, '_providerNFT": "', vm.toString(address(pair.providerNFT)), '",'
                )
            );
            json = string(
                abi.encodePacked(
                    json, '"', pairName, '_loansContract": "', vm.toString(address(pair.loansContract)), '",'
                )
            );
            json = string(
                abi.encodePacked(
                    json, '"', pairName, '_rollsContract": "', vm.toString(address(pair.rollsContract)), '",'
                )
            );

            json = string(
                abi.encodePacked(json, '"', pairName, '_oracle": "', vm.toString(address(pair.oracle)), '",')
            );

            json = string(
                abi.encodePacked(
                    json, '"', pairName, '_swapperUniV3": "', vm.toString(address(pair.swapperUniV3)), '",'
                )
            );

            json = string(
                abi.encodePacked(
                    json, '"', pairName, '_cashAsset": "', vm.toString(address(pair.cashAsset)), '",'
                )
            );

            json = string(
                abi.encodePacked(
                    json, '"', pairName, '_underlying": "', vm.toString(address(pair.underlying)), '",'
                )
            );

            // durations and ltvs to json
            json = string(abi.encodePacked(json, '"', pairName, '_durations": ['));
            for (uint j = 0; j < pair.durations.length; j++) {
                json = string(abi.encodePacked(json, vm.toString(pair.durations[j]), ","));
            }
            json = string(abi.encodePacked(substring(json, 0, bytes(json).length - 1), "],"));

            json = string(abi.encodePacked(json, '"', pairName, '_ltvs": ['));
            for (uint j = 0; j < pair.ltvs.length; j++) {
                json = string(abi.encodePacked(json, vm.toString(pair.ltvs[j]), ","));
            }
            json = string(abi.encodePacked(substring(json, 0, bytes(json).length - 1), "],"));
            json = string(
                abi.encodePacked(
                    json, '"', pairName, '_oracleFeeTier":', vm.toString(pair.oracleFeeTier), ","
                )
            );
            json = string(
                abi.encodePacked(json, '"', pairName, '_swapFeeTier":', vm.toString(pair.swapFeeTier), ",")
            );
        }

        // Remove the trailing comma and close the JSON object
        json = string(abi.encodePacked(substring(json, 0, bytes(json).length - 1), "}"));

        return json;
    }

    function writeJsonToFile(Vm vm, string memory name, string memory json) internal {
        string memory chainOutputFolder = _getExportPath(vm);
        bool exists = vm.isDir(chainOutputFolder);
        if (!exists) {
            vm.createDir(chainOutputFolder, true);
        }
        string memory timestamp = vm.toString(block.timestamp);
        string memory filename = string(abi.encodePacked(name, "-", timestamp, ".json"));
        string memory path = string(abi.encodePacked(chainOutputFolder, filename));
        vm.writeJson(json, path);
        string memory latestFilename = string(abi.encodePacked(name, "-latest.json"));
        string memory latestPath = string(abi.encodePacked(chainOutputFolder, latestFilename));
        vm.writeJson(json, latestPath);
    }

    function getConfigHub(Vm vm) internal view returns (address) {
        string memory json = vm.readFile(
            string(abi.encodePacked(_getExportPath(vm), "collar_protocol_deployment-latest.json"))
        );
        return _parseAddress(vm, bytes(json), ".configHub");
    }

    function getRouter(Vm vm) internal view returns (address) {
        string memory json = vm.readFile(
            string(abi.encodePacked(_getExportPath(vm), "collar_protocol_deployment-latest.json"))
        );
        return _parseAddress(vm, bytes(json), ".router");
    }

    function getAll(Vm vm, string memory filename)
        internal
        view
        returns (address, DeploymentHelper.AssetPairContracts[] memory)
    {
        string memory json =
            vm.readFile(string(abi.encodePacked(_getExportPath(vm), filename, "-latest.json")));
        bytes memory parsedJson = bytes(json);

        address configHubAddress = _parseAddress(vm, parsedJson, ".configHub");

        string[] memory allKeys = vm.parseJsonKeys(json, ".");

        // Count valid asset pairs
        uint pairCount = 0;
        for (uint i = 0; i < allKeys.length; i++) {
            // we check if the key is longer than two addresses,
            // since a pair key is formed by two addresses joined by an underscore
            if (
                bytes(allKeys[i]).length > (ADDRESS_LENGTH * 2)
                    && compareStrings(
                        substring(allKeys[i], bytes(allKeys[i]).length - 9, bytes(allKeys[i]).length), "_takerNFT"
                    )
            ) {
                pairCount++;
            }
        }

        DeploymentHelper.AssetPairContracts[] memory result =
            new DeploymentHelper.AssetPairContracts[](pairCount);
        uint resultIndex = 0;

        for (uint i = 0; i < allKeys.length; i++) {
            // we check if the key is longer than two addresses,
            // since a pair key is formed by two addresses joined by an underscore
            if (
                bytes(allKeys[i]).length > (ADDRESS_LENGTH * 2)
                    && compareStrings(
                        substring(allKeys[i], bytes(allKeys[i]).length - 9, bytes(allKeys[i]).length), "_takerNFT"
                    )
            ) {
                // for each unique takerNFT key (every asset pair), get the base key and create the asset pair
                // using all other key suffixes
                string memory baseKey = substring(allKeys[i], 0, bytes(allKeys[i]).length - 9);

                result[resultIndex] = DeploymentHelper.AssetPairContracts({
                    providerNFT: CollarProviderNFT(
                        _parseAddress(vm, parsedJson, string(abi.encodePacked(".", baseKey, "_providerNFT")))
                    ),
                    takerNFT: CollarTakerNFT(
                        _parseAddress(vm, parsedJson, string(abi.encodePacked(".", baseKey, "_takerNFT")))
                    ),
                    loansContract: LoansNFT(
                        _parseAddress(vm, parsedJson, string(abi.encodePacked(".", baseKey, "_loansContract")))
                    ),
                    rollsContract: Rolls(
                        _parseAddress(vm, parsedJson, string(abi.encodePacked(".", baseKey, "_rollsContract")))
                    ),
                    cashAsset: IERC20(
                        _parseAddress(vm, parsedJson, string(abi.encodePacked(".", baseKey, "_cashAsset")))
                    ),
                    underlying: IERC20(
                        _parseAddress(vm, parsedJson, string(abi.encodePacked(".", baseKey, "_underlying")))
                    ),
                    oracle: OracleUniV3TWAP(
                        _parseAddress(vm, parsedJson, string(abi.encodePacked(".", baseKey, "_oracle")))
                    ),
                    swapperUniV3: SwapperUniV3(
                        _parseAddress(vm, parsedJson, string(abi.encodePacked(".", baseKey, "_swapperUniV3")))
                    ),
                    durations: _parseUintArray(
                        vm, parsedJson, string(abi.encodePacked(".", baseKey, "_durations"))
                    ),
                    ltvs: _parseUintArray(vm, parsedJson, string(abi.encodePacked(".", baseKey, "_ltvs"))),
                    oracleFeeTier: uint24(
                        vm.parseJsonUint(json, string(abi.encodePacked(".", baseKey, "_oracleFeeTier")))
                    ),
                    swapFeeTier: uint24(
                        vm.parseJsonUint(json, string(abi.encodePacked(".", baseKey, "_swapFeeTier")))
                    )
                });
                resultIndex++;
            }
        }

        return (configHubAddress, result);
    }

    function getByAssetPair(Vm vm, string memory filename, address cashAsset, address underlying)
        internal
        view
        returns (address hub, DeploymentHelper.AssetPairContracts memory)
    {
        (address configHub, DeploymentHelper.AssetPairContracts[] memory allPairs) = getAll(vm, filename);
        for (uint i = 0; i < allPairs.length; i++) {
            if (address(allPairs[i].cashAsset) == cashAsset && address(allPairs[i].underlying) == underlying)
            {
                return (configHub, allPairs[i]);
            }
        }
        revert("Asset pair not found");
    }

    function _getExportPath(Vm vm) internal view returns (string memory) {
        string memory root = vm.projectRoot();
        return string(abi.encodePacked(root, "/script/output/", vm.toString(block.chainid), "/"));
    }

    function substring(string memory str, uint startIndex, uint endIndex)
        internal
        pure
        returns (string memory)
    {
        bytes memory strBytes = bytes(str);
        require(startIndex <= endIndex && endIndex <= strBytes.length, "Invalid substring indices");
        bytes memory result = new bytes(endIndex - startIndex);
        for (uint i = startIndex; i < endIndex; i++) {
            result[i - startIndex] = strBytes[i];
        }
        return string(result);
    }

    function compareStrings(string memory a, string memory b) internal pure returns (bool) {
        return (keccak256(abi.encodePacked((a))) == keccak256(abi.encodePacked((b))));
    }

    function _parseAddress(Vm vm, bytes memory json, string memory key) internal pure returns (address) {
        return address(uint160(uint(vm.parseJsonUint(string(json), key))));
    }

    function _parseUintArray(Vm vm, bytes memory json, string memory key)
        internal
        pure
        returns (uint[] memory)
    {
        bytes memory arrayData = vm.parseJson(string(json), key);
        uint[] memory result = abi.decode(arrayData, (uint[]));
        return result;
    }
}
