// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {ICollarVaultEvents} from "./ICollarVaultEvents.sol";
import {ISwapRouter} from "@uni-v3-periphery/interfaces/ISwapRouter.sol";
import {AggregatorV3Interface} from "@chainlink-v0.8/interfaces/AggregatorV3Interface.sol";

abstract contract ICollarVault is ICollarVaultEvents {
    uint256 qty;

    uint256 lent;
    address lendAsset;

    uint256 putstrikePct;
    uint256 callstrikePct;
    
    address marketmaker;
    address payable client;
    
    uint256 maturityTimestamp;
    uint256 rollcount;

    //economic amts
    uint256 fill;
    uint256 mmCollateral;
    uint256 proceeds;
    uint256 feePaid;

    uint256 rollputpct;
    uint256 rollcallpct;
    uint256 rollltvpct;
    uint256 rollmatstamp;
    uint256 cashposted;

    address feeWallet;
    uint256 rollFeeRate;
    address WETH9;

    address /*immutable*/ engine;
    address /*immutable*/ admin;
    uint256 /*immutable*/ rfqid;

    //settlement preferences/status
    bool rollPref = true;
    bool settled = false;
    bool repaid = false;
    bool deetsPostedA = false;
    bool deetsPostedB = false;
    uint256 loanRepayBalance; // where money goes when you repay
    uint256 settlePref = 0; // 0 netshare 1 cash 2 physical
    uint256 postedPhysicalCollat = 0;
    uint256 finalPrice;

    //rolldetails
    uint256 rollstate = 0; // 0 new 1 reqd 2 pxd 3 done 4 execd

    ISwapRouter /*immutable*/ dexRouter;
    AggregatorV3Interface /*immutable*/ internal priceFeed;

    function matureVault() external virtual;

    /// @notice Only allows the engine to call certain functions
    modifier onlyEngine() {
        require(msg.sender == engine, "error - can only be called by the engine");
        _;
    }

        /// @notice Ensures matured contracts can no longer be edited, request rolls, or change settlement type
    modifier whileLive() {
        require(block.timestamp < maturityTimestamp, "error - this has matured");
        _;
    }

    modifier onceMatured() {
        require(block.timestamp >= maturityTimestamp, "error - this vault is still live");
        _;
    }

    /// @notice Currently 2 days is our minimum notice time that must be given prior to expiry to request a roll price
    modifier isRollable() {
        require(maturityTimestamp - block.timestamp >= 2 days, "error - cant roll within 2 days of expiry");
        _;
    }

    //admins can roll within a week of maturity, only if rolling is enabled on contract
    modifier isEligibleRoller() {
        require(
            msg.sender == client || (rollPref && msg.sender == admin && maturityTimestamp - block.timestamp <= 1 weeks),
            "error - you are not an eligible roller at this time"
        );
        _;
    }

    /// @notice Modifiers that limit who is allowed to do what at certain phases of the RFQ and Execution process
    modifier onlyMarketMaker() {
        require(msg.sender == marketmaker, "error - this function can only be called by the marketmaker");
        _;
    }

    modifier onlyClient() {
        require(msg.sender == client, "error - this function can only be called by the client");
        _;
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, "error - this function can only be called by the admin");
        _;
    }
}


