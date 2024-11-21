// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract CollarOwnedERC20 is ERC20, Ownable {
    uint8 private DECIMALS;

    constructor(address _initialOwner, string memory name_, string memory symbol_, uint8 _decimals)
        ERC20(name_, symbol_)
        Ownable(_initialOwner)
    {
        DECIMALS = _decimals;
    }

    function decimals() public view override returns (uint8) {
        return DECIMALS;
    }

    function mint(address to, uint amount) public onlyOwner {
        _mint(to, amount);
    }
}
