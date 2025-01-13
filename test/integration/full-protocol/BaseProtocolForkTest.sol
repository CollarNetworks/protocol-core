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

            // oracle
            assertEq(address(pair.oracle.baseToken()), address(pair.underlying));
            assertEq(address(pair.oracle.quoteToken()), address(pair.cashAsset));

            // taker
            assertEq(address(pair.takerNFT.owner()), owner);
            assertEq(address(pair.takerNFT.configHub()), address(configHub));
            assertEq(address(pair.takerNFT.underlying()), address(pair.underlying));
            assertEq(address(pair.takerNFT.cashAsset()), address(pair.cashAsset));
            assertEq(address(pair.takerNFT.oracle()), address(pair.oracle));

            // provider
            assertEq(address(pair.providerNFT.owner()), owner);
            assertEq(address(pair.providerNFT.configHub()), address(configHub));
            assertEq(address(pair.providerNFT.underlying()), address(pair.underlying));
            assertEq(address(pair.providerNFT.cashAsset()), address(pair.cashAsset));
            assertEq(address(pair.providerNFT.taker()), address(pair.takerNFT));

            // rolls
            assertEq(address(pair.rollsContract.owner()), owner);
            assertEq(address(pair.rollsContract.configHub()), address(configHub));
            assertEq(address(pair.rollsContract.takerNFT()), address(pair.takerNFT));
            assertEq(address(pair.rollsContract.cashAsset()), address(pair.cashAsset));

            // loans
            assertEq(address(pair.loansContract.owner()), owner);
            assertEq(address(pair.loansContract.configHub()), address(configHub));
            assertEq(address(pair.loansContract.takerNFT()), address(pair.takerNFT));
            assertEq(address(pair.loansContract.underlying()), address(pair.underlying));
            assertEq(address(pair.loansContract.cashAsset()), address(pair.cashAsset));
            assertEq(address(pair.loansContract.defaultSwapper()), address(pair.swapperUniV3));
            assertTrue(pair.loansContract.isAllowedSwapper(address(pair.swapperUniV3)));

            // escrow
            assertEq(address(pair.escrowNFT.owner()), owner);
            assertEq(address(pair.escrowNFT.configHub()), address(configHub));
            assertTrue(pair.escrowNFT.loansCanOpen(address(pair.loansContract)));
            assertEq(address(pair.escrowNFT.asset()), address(pair.underlying));

            // pair auth
            assertTrue(configHub.canOpenPair(pair.underlying, pair.cashAsset, address(pair.takerNFT)));
            assertTrue(configHub.canOpenPair(pair.underlying, pair.cashAsset, address(pair.providerNFT)));
            assertTrue(configHub.canOpenPair(pair.underlying, pair.cashAsset, address(pair.loansContract)));
            assertTrue(configHub.canOpenPair(pair.underlying, pair.cashAsset, address(pair.rollsContract)));

            // all pair auth
            address[] memory pairAuthed = new address[](4);
            pairAuthed[0] = address(pair.takerNFT);
            pairAuthed[1] = address(pair.providerNFT);
            pairAuthed[2] = address(pair.loansContract);
            pairAuthed[3] = address(pair.rollsContract);
            assertEq(configHub.allCanOpenPair(pair.underlying, pair.cashAsset), pairAuthed);

            // single asset auth
            assertTrue(configHub.canOpenSingle(pair.underlying, address(pair.escrowNFT)));

            // all single auth for underlying
            address[] memory escrowAuthed = new address[](1);
            escrowAuthed[0] = address(pair.escrowNFT);
            assertEq(configHub.allCanOpenPair(pair.underlying, configHub.ANY_ASSET()), escrowAuthed);
        }
    }
}
