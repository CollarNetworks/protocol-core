// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import {Test} from "@forge-std/Test.sol";
import {ERC20, ERC20Permit} from "@oz-v4.9.3/token/ERC20/extensions/ERC20Permit.sol";

/// @title TestERC20
/// @dev Extension of ERC20Permit that allows free minting
/// @dev The address is automatically labelled with the name of the token via forge-std
contract TestERC20 is ERC20Permit, Test {
    uint8 internal decimals_;

    constructor(string memory _name, string memory _symbol, uint8 _decimals) ERC20(_name, _symbol) ERC20Permit(_name) {
        _decimals = _decimals;
        vm.label(address(this), _name);
    }

    function decimals() public view override returns (uint8) {
        return decimals_;
    }

    function mint(uint256 amount) external {
        _mint(msg.sender, amount);
    }

    function mintTo(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
