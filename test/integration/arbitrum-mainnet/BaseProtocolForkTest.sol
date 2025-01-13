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
    // deployment checks
    uint forkId;
    bool forkSet;

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
        if (!forkSet) {
            console.log("Setting up fork and deploying contracts");
            setupNewFork();
            setupDeployer();
            // Deploy contracts
            vm.startPrank(owner);
            BaseDeployer.DeploymentResult memory result = deployer.deployAndSetupFullProtocol(owner);
            DeploymentArtifactsLib.exportDeployment(
                vm, deploymentName(), address(result.configHub), result.assetPairContracts
            );
            vm.stopPrank();
            forkSet = true;
        } else {
            console.log("Fork already set, selecting fork");
            vm.selectFork(forkId);
        }
        (ConfigHub hub, BaseDeployer.AssetPairContracts[] memory pairs) = loadDeployment();
        configHub = hub;
        for (uint i = 0; i < pairs.length; i++) {
            deployedPairs.push(pairs[i]);
        }
        require(address(configHub) != address(0), "ConfigHub not deployed");
        require(deployedPairs.length > 0, "No pairs deployed");
    }

    function setupNewFork() internal virtual {
        // this test suite needs to run independently so we load a fork here
        // if we are in development we want to fix the block to reduce the time it takes to run the tests
        if (vm.envBool("FIX_BLOCK_ARBITRUM_MAINNET")) {
            forkId = vm.createSelectFork(
                vm.envString("ARBITRUM_MAINNET_RPC"), vm.envUint("BLOCK_NUMBER_ARBITRUM_MAINNET")
            );
        } else {
            forkId = vm.createSelectFork(vm.envString("ARBITRUM_MAINNET_RPC"));
        }
    }

    function setupDeployer() internal virtual {
        deployer = new ArbitrumMainnetDeployer();
    }

    function deploymentName() internal pure returns (string memory) {
        return "collar_protocol_fork_deployment";
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
}
