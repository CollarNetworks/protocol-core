// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "forge-std/Test.sol";

import { DeploymentArtifactsLib } from "../../../script/utils/DeploymentArtifacts.sol";
import { ConfigHub } from "../../../src/ConfigHub.sol";
import { ArbitrumMainnetDeployer, BaseDeployer } from "../../../script/ArbitrumMainnetDeployer.sol";

abstract contract BaseProtocolForkTest is Test {
    ConfigHub public configHub;

    BaseDeployer deployer;
    BaseDeployer.AssetPairContracts[] public deployedPairs;
    address owner;
    address user;
    address user2;
    address provider;

    function setUp() public virtual {
        uint deployerPrivKey = vm.envUint("PRIVKEY_DEV_DEPLOYER");
        uint user1PrivKey = vm.envUint("PRIVKEY_DEV_TEST1");
        uint user2PrivKey = vm.envUint("PRIVKEY_DEV_TEST2");
        uint liquidityProviderPrivKey = vm.envUint("LIQUIDITY_PROVIDER_KEY");

        owner = vm.addr(deployerPrivKey);
        user = vm.addr(user1PrivKey);
        user2 = vm.addr(user2PrivKey);
        provider = vm.addr(liquidityProviderPrivKey);

        vm.label(provider, "Liquidity Provider");
        vm.label(owner, "Owner");
        vm.label(user, "User");
        vm.label(user2, "User 2");

        setupNewFork();

        vm.startPrank(owner);

        setupDeployer();

        BaseDeployer.DeploymentResult memory result = deployer.deployAndSetupFullProtocol(owner);

        acceptOwnership(owner, result);

        DeploymentArtifactsLib.exportDeployment(
            vm, deploymentName(), address(result.configHub), result.assetPairContracts
        );
        vm.stopPrank();

        (ConfigHub hub, BaseDeployer.AssetPairContracts[] memory pairs) = loadDeployment();
        configHub = hub;
        for (uint i = 0; i < pairs.length; i++) {
            deployedPairs.push(pairs[i]);
        }
        require(address(configHub) != address(0), "ConfigHub not deployed");
        require(deployedPairs.length > 0, "No pairs deployed");
    }

    // abstract

    function setupNewFork() internal virtual;

    function setupDeployer() internal virtual;

    function deploymentName() internal pure virtual returns (string memory);

    // internal

    function acceptOwnership(address _owner, BaseDeployer.DeploymentResult memory result) internal {
        result.configHub.acceptOwnership();
        for (uint i = 0; i < result.assetPairContracts.length; i++) {
            BaseDeployer.AssetPairContracts memory pair = result.assetPairContracts[i];
            pair.takerNFT.acceptOwnership();
            pair.providerNFT.acceptOwnership();
            pair.loansContract.acceptOwnership();
            pair.rollsContract.acceptOwnership();
            // check because we may have already accepted previously (for another pair)
            if (pair.escrowNFT.owner() != _owner) pair.escrowNFT.acceptOwnership();
        }
    }

    function loadDeployment() internal view returns (ConfigHub, BaseDeployer.AssetPairContracts[] memory) {
        (address configHubAddress, BaseDeployer.AssetPairContracts[] memory pairs) =
            DeploymentArtifactsLib.loadHubAndAllPairs(vm, deploymentName());

        return (ConfigHub(configHubAddress), pairs);
    }

    function getPairByAssets(address cashAsset, address underlying)
        internal
        view
        returns (BaseDeployer.AssetPairContracts memory pair, uint index)
    {
        bool found = false;
        for (uint i = 0; i < deployedPairs.length; i++) {
            if (
                address(deployedPairs[i].cashAsset) == cashAsset
                    && address(deployedPairs[i].underlying) == underlying
            ) {
                require(!found, "getPairByAssets: found twice");
                found = true;
                (pair, index) = (deployedPairs[i], i);
            }
        }
        require(found, "getPairByAssets: not found");
    }

    // tests for deployment

    function test_validateConfigHubDeployment() public view {
        assertEq(address(configHub) != address(0), true);
        assertEq(configHub.owner(), owner);
    }

    function test_validatePairDeployments() public view {
        for (uint i = 0; i < deployedPairs.length; i++) {
            BaseDeployer.AssetPairContracts memory pair = deployedPairs[i];

            assertEq(address(pair.providerNFT) != address(0), true);
            assertEq(address(pair.takerNFT) != address(0), true);
            assertEq(address(pair.loansContract) != address(0), true);
            assertEq(address(pair.rollsContract) != address(0), true);

            assertTrue(configHub.canOpenPair(pair.underlying, pair.cashAsset, address(pair.takerNFT)));
            assertTrue(configHub.canOpenPair(pair.underlying, pair.cashAsset, address(pair.providerNFT)));
            assertTrue(configHub.canOpenPair(pair.underlying, pair.cashAsset, address(pair.loansContract)));
            assertTrue(configHub.canOpenPair(pair.underlying, pair.cashAsset, address(pair.rollsContract)));

            address[] memory allAuthed = new address[](4);
            allAuthed[0] = address(pair.takerNFT);
            allAuthed[1] = address(pair.providerNFT);
            allAuthed[2] = address(pair.loansContract);
            allAuthed[3] = address(pair.rollsContract);
            assertEq(configHub.allCanOpenPair(pair.underlying, pair.cashAsset), allAuthed);

            assertEq(address(pair.rollsContract.takerNFT()) == address(pair.takerNFT), true);
        }
    }
}
