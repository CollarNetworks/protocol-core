// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

string constant weth9Artifact = "lib/common/weth/WETH9.json";

abstract contract DefaultConstants {
    uint256 constant DEFAULT_RFQID = 0;
    uint256 constant DEFAULT_RAKE = 3;
    uint256 constant DEFAULT_QTY = 0.1 ether;
    uint256 constant DEFAULT_PUT_STRIKE_PCT = 88;
    uint256 constant DEFAULT_CALL_STRIKE_PCT = 110;
    uint256 constant DEFAULT_MATURITY_TIMESTAMP = 1_682_192_947;
    uint256 constant DEFAULT_LTV = 85;
}
