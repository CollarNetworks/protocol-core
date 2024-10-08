// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract CollarOwnedERC20 is ERC20, Ownable {
    constructor(address _initialOwner, string memory name_, string memory symbol_)
        ERC20(name_, symbol_)
        Ownable(_initialOwner)
    { }

    function mint(address to, uint amount) public onlyOwner {
        _mint(to, amount);
    }
}
