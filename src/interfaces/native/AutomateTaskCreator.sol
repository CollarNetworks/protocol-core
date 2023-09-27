//SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./AutomateReady.sol";
import "@oz-v4.9.3/token/ERC20/utils/SafeERC20.sol";

/**
 * @dev Inherit this contract to allow your smart contract
 * to be a task creator and create tasks.
 */
contract AutomateTaskCreator is AutomateReady {
    using SafeERC20 for IERC20;

    address public immutable fundsOwner;
    ITaskTreasuryUpgradable public immutable taskTreasury;

    constructor(address _automate, address _fundsOwner) AutomateReady(_automate, address(this)) {
        fundsOwner = _fundsOwner;
        taskTreasury = automate.taskTreasury();
    }

    /**
     * @dev
     * Withdraw funds from this contract's Gelato balance to fundsOwner.
     */
    function withdrawFunds(uint256 _amount, address _token) external {
        require(msg.sender == fundsOwner, "Only funds owner can withdraw funds");

        taskTreasury.withdrawFunds(payable(fundsOwner), _token, _amount);
    }

    function _depositFunds(uint256 _amount, address _token) internal {
        uint256 ethValue = _token == ETH ? _amount : 0;
        taskTreasury.depositFunds{value: ethValue}(address(this), _token, _amount);
    }

    function _createTask(
        address _execAddress,
        bytes memory _execDataOrSelector,
        ModuleData memory _moduleData,
        address _feeToken
    ) internal returns (bytes32) {
        return automate.createTask(_execAddress, _execDataOrSelector, _moduleData, _feeToken);
    }

    function _cancelTask(bytes32 _taskId) internal {
        automate.cancelTask(_taskId);
    }

    function _resolverModuleArg(address _resolverAddress, bytes memory _resolverData)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encode(_resolverAddress, _resolverData);
    }

    function _timeModuleArg(uint256 _startTime, uint256 _interval) internal pure returns (bytes memory) {
        return abi.encode(uint128(_startTime), uint128(_interval));
    }

    function _proxyModuleArg() internal pure returns (bytes memory) {
        return bytes("");
    }

    function _singleExecModuleArg() internal pure returns (bytes memory) {
        return bytes("");
    }
}

// interface ITaskTreasuryUpgradable {
//     function depositFunds(
//         address receiver,
//         address token,
//         uint256 amount
//     ) external payable;

//     function withdrawFunds(
//         address payable receiver,
//         address token,
//         uint256 amount
//     ) external;
// }

// interface IGelato {

//     enum Module {
//         RESOLVER,
//         TIME,
//         PROXY,
//         SINGLE_EXEC
//     }

//     struct ModuleData {
//         Module[] modules;
//         bytes[] args;
//     }

//     function createTask(
//         address execAddress,
//         bytes calldata execDataOrSelector,
//         ModuleData calldata moduleData,
//         address feeToken
//     ) external returns (bytes32 taskId);

//     function cancelTask(bytes32 taskId) external;

//     function getFeeDetails() external view returns (uint256, address);

//     function gelato() external view returns (address payable);

//     function taskTreasury() external view returns (ITaskTreasuryUpgradable);
// }
