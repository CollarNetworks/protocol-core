// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TestERC20 is ERC20 {
    // reentrancy attacker
    address public attacker;

    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) { }

    function mint(address to, uint amount) external {
        _mint(to, amount);
    }

    function setAttacker(address _attacker) public {
        attacker = _attacker;
    }

    function _update(address from, address to, uint value) internal override {
        _maybeAttack();
        super._update(from, to, value);
    }

    function _maybeAttack() internal {
        if (attacker != address(0)) {
            (bool success, bytes memory data) = attacker.call(""); // call attacker fallback
            // bubble up the revert reason for tests
            if (!success) {
                assembly {
                    revert(add(data, 0x20), mload(data))
                }
            }
        }
    }
}
