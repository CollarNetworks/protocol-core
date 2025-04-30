// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import { DeploymentArtifactsLib } from "../libraries/DeploymentArtifacts.sol";

import { BaseDeployer } from "../libraries/BaseDeployer.sol";
import { Const } from "../utils/Const.sol";
import { OPBaseMainnetDeployer } from "../libraries/OPBaseMainnetDeployer.sol";
import { OPBaseSepoliaDeployer } from "../libraries/OPBaseSepoliaDeployer.sol";
import { ArbitrumMainnetDeployer } from "../libraries/ArbitrumMainnetDeployer.sol";
import { ArbitrumSepoliaDeployer } from "../libraries/ArbitrumSepoliaDeployer.sol";

abstract contract DeployProtocolScript is Script {
    address public owner;
    string public defaultArtifactsName;

    // default run() as script
    function run() external {
        run("");
    }

    /// run() that can be used for tests, or for scripts by specifying `"" --sig 'run(string)'`
    /// @param artifactsName overrides the default artifacts name when used in tests
    function run(string memory artifactsName) public returns (BaseDeployer.DeploymentResult memory result) {
        setParams();

        // note: when in tests, this also has the effect of "pranking" msg.sender
        vm.startBroadcast(msg.sender);

        // deploy and nominate owner
        result = deployAndSetup();

        // artifact name if not given (should only be specified in tests)
        if (bytes(artifactsName).length == 0) {
            artifactsName = defaultArtifactsName;
        }
        // save the deployment artifacts
        DeploymentArtifactsLib.exportDeployment(vm, artifactsName, result);

        vm.stopBroadcast();
    }

    function setParams() internal virtual;
    function deployAndSetup() internal virtual returns (BaseDeployer.DeploymentResult memory);
}

contract DeployOPBaseMainnet is DeployProtocolScript {
    function setParams() internal override {
        owner = Const.OPBaseMain_owner;
        defaultArtifactsName = Const.OPBaseMain_artifactsName;
    }

    function deployAndSetup() internal override returns (BaseDeployer.DeploymentResult memory) {
        return OPBaseMainnetDeployer.deployAndSetupFullProtocol(msg.sender, owner);
    }
}

contract DeployOPBaseSepolia is DeployProtocolScript {
    function setParams() internal override {
        owner = Const.OPBaseSep_owner;
        defaultArtifactsName = Const.OPBaseSep_artifactsName;
    }

    function deployAndSetup() internal override returns (BaseDeployer.DeploymentResult memory) {
        return OPBaseSepoliaDeployer.deployAndSetupFullProtocol(msg.sender, owner);
    }
}

contract DeployArbitrumMainnet is DeployProtocolScript {
    function setParams() internal override {
        owner = Const.ArbiMain_owner;
        defaultArtifactsName = Const.ArbiMain_artifactsName;
    }

    function deployAndSetup() internal override returns (BaseDeployer.DeploymentResult memory) {
        return ArbitrumMainnetDeployer.deployAndSetupFullProtocol(msg.sender, owner);
    }
}

contract DeployArbitrumSepolia is DeployProtocolScript {
    function setParams() internal override {
        owner = Const.ArbiSep_owner;
        defaultArtifactsName = Const.ArbiSep_artifactsName;
    }

    function deployAndSetup() internal override returns (BaseDeployer.DeploymentResult memory) {
        return ArbitrumSepoliaDeployer.deployAndSetupFullProtocol(msg.sender, owner);
    }
}
