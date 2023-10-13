// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

abstract contract IPayable {
    receive() external payable {}
    fallback() external payable {}
}
