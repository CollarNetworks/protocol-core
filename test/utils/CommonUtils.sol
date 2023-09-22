// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";

abstract contract AddressBook is Test {
    address owner = makeAddr("owner");
    address admin = makeAddr("owner");
    address averageJoe = makeAddr("joe");
    address marketMakerMike = makeAddr("mike");
    address feeWallet = makeAddr("fee");
    address usdc = makeAddr("usdc");
    address testDex = makeAddr("dex");
    address ethUSDOracle = makeAddr("oracle");
    address weth = makeAddr("weth");
}

abstract contract DefaultConstants {
    uint256 constant DEFAULT_RFQID = 0;
    uint256 constant DEFAULT_RAKE = 3;
    uint256 constant DEFAULT_QTY = 0.1 ether;
    uint256 constant DEFAULT_PUT_STRIKE_PCT = 88;
    uint256 constant DEFAULT_CALL_STRIKE_PCT = 110;
    uint256 constant DEFAULT_MATURITY_TIMESTAMP = 1682192947;
    uint256 constant DEFAULT_LTV = 85;
}
