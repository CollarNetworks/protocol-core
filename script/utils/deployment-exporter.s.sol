// DeploymentUtils.sol
pragma solidity 0.8.22;

import "forge-std/Script.sol";
import { ProviderPositionNFT } from "../../src/ProviderPositionNFT.sol";
import { CollarTakerNFT } from "../../src/CollarTakerNFT.sol";
import { Loans } from "../../src/Loans.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Rolls } from "../../src/Rolls.sol";
import { BaseDeployment } from "../base.s.sol";

contract DeploymentUtils is Script {
    function exportDeployment(
        string memory name,
        address configHub,
        address router,
        BaseDeployment.AssetPairContracts[] memory assetPairs
    ) public {
        string memory json = constructJson(configHub, router, assetPairs);
        writeJsonToFile(name, json);
    }

    function constructJson(
        address configHub,
        address router,
        BaseDeployment.AssetPairContracts[] memory assetPairs
    ) public pure returns (string memory) {
        string memory json = "{";

        json = string(abi.encodePacked(json, '"configHub": "', vm.toString(configHub), '",'));
        json = string(abi.encodePacked(json, '"router": "', vm.toString(router), '",'));

        for (uint i = 0; i < assetPairs.length; i++) {
            BaseDeployment.AssetPairContracts memory pair = assetPairs[i];
            string memory pairName = string(
                abi.encodePacked(
                    vm.toString(address(pair.collateralAsset)), "_", vm.toString(address(pair.cashAsset))
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
                abi.encodePacked(
                    json, '"', pairName, '_cashAsset": "', vm.toString(address(pair.cashAsset)), '",'
                )
            );

            json = string(
                abi.encodePacked(
                    json,
                    '"',
                    pairName,
                    '_collateralAsset": "',
                    vm.toString(address(pair.collateralAsset)),
                    '",'
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
        }

        // Remove the trailing comma and close the JSON object
        json = string(abi.encodePacked(substring(json, 0, bytes(json).length - 1), "}"));

        return json;
    }

    function writeJsonToFile(string memory name, string memory json) internal {
        string memory chainOutputFolder = _getExportPath();
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

    function substring(string memory str, uint startIndex, uint endIndex)
        public
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

    function getConfigHub() public view returns (address) {
        string memory json =
            vm.readFile(string(abi.encodePacked(_getExportPath(), "collar_protocol_deployment-latest.json")));

        return _parseAddress(bytes(json), ".configHub");
    }

    function getRouter() public view returns (address) {
        string memory json =
            vm.readFile(string(abi.encodePacked(_getExportPath(), "collar_protocol_deployment-latest.json")));
        return _parseAddress(bytes(json), ".router");
    }

    function getAll() public view returns (BaseDeployment.AssetPairContracts[] memory) {
        string memory json =
            vm.readFile(string(abi.encodePacked(_getExportPath(), "collar_protocol_deployment-latest.json")));
        bytes memory parsedJson = bytes(json);
        string[] memory allKeys = vm.parseJsonKeys(json, ".");
        // Count valid asset pairs
        uint pairCount = 0;
        for (uint i = 0; i < allKeys.length; i++) {
            if (
                bytes(allKeys[i]).length > 9 // exclude non asset pair keys
                    && compareStrings(
                        substring(allKeys[i], bytes(allKeys[i]).length - 9, bytes(allKeys[i]).length), "_takerNFT"
                    )
            ) {
                pairCount++; // get amount of asset pairs to create array
            }
        }

        BaseDeployment.AssetPairContracts[] memory result = new BaseDeployment.AssetPairContracts[](pairCount); // create array with correct size
        uint resultIndex = 0;

        for (uint i = 0; i < allKeys.length; i++) {
            if (
                bytes(allKeys[i]).length > 9 // exclude non asset pair keys
                    && compareStrings(
                        substring(allKeys[i], bytes(allKeys[i]).length - 9, bytes(allKeys[i]).length), "_takerNFT"
                    )
            ) {
                // for each unique takerNFT key (every asset pair), get the base key and create the asset pair using all other key suffixes
                string memory baseKey = substring(allKeys[i], 0, bytes(allKeys[i]).length - 9);

                result[resultIndex] = BaseDeployment.AssetPairContracts({
                    takerNFT: CollarTakerNFT(
                        _parseAddress(parsedJson, string(abi.encodePacked(".", baseKey, "_takerNFT")))
                    ),
                    providerNFT: ProviderPositionNFT(
                        _parseAddress(parsedJson, string(abi.encodePacked(".", baseKey, "_providerNFT")))
                    ),
                    loansContract: Loans(
                        _parseAddress(parsedJson, string(abi.encodePacked(".", baseKey, "_loansContract")))
                    ),
                    rollsContract: Rolls(
                        _parseAddress(parsedJson, string(abi.encodePacked(".", baseKey, "_rollsContract")))
                    ),
                    cashAsset: IERC20(
                        _parseAddress(parsedJson, string(abi.encodePacked(".", baseKey, "_cashAsset")))
                    ),
                    collateralAsset: IERC20(
                        _parseAddress(parsedJson, string(abi.encodePacked(".", baseKey, "_collateralAsset")))
                    ),
                    durations: _parseUintArray(parsedJson, string(abi.encodePacked(".", baseKey, "_durations"))),
                    ltvs: _parseUintArray(parsedJson, string(abi.encodePacked(".", baseKey, "_ltvs")))
                });
                resultIndex++;
            }
        }

        return result;
    }

    function getByAssetPair(address cashAsset, address collateralAsset)
        public
        view
        returns (BaseDeployment.AssetPairContracts memory)
    {
        BaseDeployment.AssetPairContracts[] memory allPairs = getAll();
        for (uint i = 0; i < allPairs.length; i++) {
            if (
                address(allPairs[i].cashAsset) == cashAsset
                    && address(allPairs[i].collateralAsset) == collateralAsset
            ) {
                return allPairs[i];
            }
        }
        revert("Asset pair not found");
    }

    function _getExportPath() public view returns (string memory) {
        string memory root = vm.projectRoot();
        return string(abi.encodePacked(root, "/script/output/", vm.toString(block.chainid), "/"));
    }

    function compareStrings(string memory a, string memory b) public pure returns (bool) {
        return (keccak256(abi.encodePacked((a))) == keccak256(abi.encodePacked((b))));
    }

    function _parseAddress(bytes memory json, string memory key) internal pure returns (address) {
        return address(uint160(uint(vm.parseJsonUint(string(json), key))));
    }

    function _parseUintArray(bytes memory json, string memory key) internal pure returns (uint[] memory) {
        bytes memory arrayData = vm.parseJson(string(json), key);
        uint[] memory result = abi.decode(arrayData, (uint[]));
        return result;
    }
}
