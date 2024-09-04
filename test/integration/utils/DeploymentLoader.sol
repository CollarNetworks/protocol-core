// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import { DeploymentUtils } from "../../../script/utils/deployment-exporter.s.sol";
import { ConfigHub } from "../../../src/ConfigHub.sol";
import { DeploymentHelper } from "../../../script/deployment-helper.sol";

abstract contract DeploymentLoader is DeploymentUtils {
    ConfigHub public configHub;
    address public router;
    DeploymentHelper.AssetPairContracts[] public deployedPairs;
    address owner;
    address user;
    address user2;
    address provider;

    function setUp() public virtual {
        (ConfigHub hub, DeploymentHelper.AssetPairContracts[] memory pairs) = loadDeployment();
        configHub = hub;
        for (uint i = 0; i < pairs.length; i++) {
            deployedPairs.push(pairs[i]);
        }
        uint deployerPrivKey = vm.envUint("PRIVKEY_DEV_DEPLOYER");
        uint user1PrivKey = vm.envUint("PRIVKEY_DEV_TEST1");
        uint user2PrivKey = vm.envUint("PRIVKEY_DEV_TEST2");
        uint liquidityProviderPrivKey = vm.envUint("LIQUIDITY_PROVIDER_KEY");

        owner = vm.addr(deployerPrivKey);
        user = vm.addr(user1PrivKey);
        user2 = vm.addr(user2PrivKey);
        provider = vm.addr(liquidityProviderPrivKey);

        vm.label(owner, "Owner");
        vm.label(user, "User");
        vm.label(user2, "User 2");
        vm.label(provider, "Liquidity Provider");
    }

    function loadDeployment()
        internal
        view
        returns (ConfigHub, DeploymentHelper.AssetPairContracts[] memory)
    {
        (address configHubAddress, DeploymentHelper.AssetPairContracts[] memory pairs) = getAll();

        return (ConfigHub(configHubAddress), pairs);
    }

    function getPairByAssets(address cashAsset, address collateralAsset)
        internal
        view
        returns (DeploymentHelper.AssetPairContracts memory pair)
    {
        if (deployedPairs.length == 0) {
            for (uint i = 0; i < deployedPairs.length; i++) {
                if (
                    address(deployedPairs[i].cashAsset) == cashAsset
                        && address(deployedPairs[i].collateralAsset) == collateralAsset
                ) {
                    return deployedPairs[i];
                }
            }
        } else {
            (, pair) = getByAssetPair(cashAsset, collateralAsset);
        }
    }
}
