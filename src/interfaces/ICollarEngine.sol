// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {ISwapRouter} from "@uni-v3-periphery/interfaces/ISwapRouter.sol";
import {IPayable} from "./IPayable.sol";
import {AggregatorV3Interface} from "@chainlink-v0.8/interfaces/AggregatorV3Interface.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

abstract contract ICollarEngine is IPayable, Ownable {
    /// @dev Passed in during deployment
    ISwapRouter dexRouter;

    // address keeperManager;
    AggregatorV3Interface internal priceFeed;
    address marketmaker;
    address payable feeWallet;
    uint256 feeRatePct;
    address lendAsset;
    address WETH9;
    /// @dev Tracks the number of quotes over time
    uint256 rfqid;

    /// @dev Vault, collateral, client, marketmaker, tracking system
    mapping(address => mapping(uint256 => address)) internal userVaults;
    mapping(address => mapping(uint256 => address)) internal marketmakerVaults;
    mapping(address => uint256) internal nextMarketmakerVaultId;
    mapping(address => uint256) internal nextUserVaultId;
    mapping(address => Pricing) internal pricings;
    mapping(address => bool) internal isCustomer;
    mapping(address => uint256) internal clientEscrow;
    mapping(address => uint256) internal mmCollateralBalances;

    /// @notice Various states a Pricing struct can be in
    /// @param NEW means the client has nothing currently priced
    /// @param REQD means the client has requested a price from a marketmaker
    /// @param ACKD means the client has been acknowledged by the marketmaker
    /// @param PXD means the client can now accept or reject the price
    /// @param OFF means the marketmaker has pulled the price due to market movement
    /// @param REJ means the client or marketmaker has rejected the pricing and a new pricing can be requested
    /// @param DONE means the client has said "DONE" and consented to a trade
    enum PxState {
        NEW,
        REQD,
        ACKD,
        PXD,
        OFF,
        REJ,
        DONE
    }

    /// @notice The Pricing struct contains all the relevant information for a client's request for quote
    /// @param rfqid is the unique identifier for this pricing
    /// @param lendAsset refers to the asset that will be lent, usually a stablecoin (i.e. USDC)
    /// @dev USDC has 6 decimal places which we have currently hardcoded for throughout the code. This will need to be improved in v2
    /// @param marketmaker refers to the asset that will be lent, usually a stablecoin (i.e. USDC)
    /// @param client specifies which client has requested the trade
    /// @param state refers to what state the pricing is in, via the above ENUM
    /// @param structure specifies in plain language what type of trade is occuring i.e. "Collar"
    /// @param underlier refers to the risk asset i.e. ETH the price of which is measured by the provided oracle
    /// @param maturityTimestamp tracks the duration of the trade, typically 1-6 months
    /// @dev the maturity is measured using block.timestamp which can be manipulated +- 12 seconds, we are looking to improve upon this over time
    /// @param qty is the amount of the underlying asset that the client wishes to hedge
    /// @dev this is hardcoded to 18dp for the moment but may need to be updated in the future
    /// @param ltv the loan-to-value ratio the client expects i.e. "87" with a "3" feeRatePct would lead to "90" putstrikePct
    /// @param putstrikePct this is the floor on the asset's value and the amount the client will need to repay at maturity
    /// @param callstrikePct this is the cap on the asset's value that is being agreed to
    /// @dev these strikes are tracked as 0dp percentages i.e. "87" or "110" in order to preserve mathematical accuracy
    /// @dev we should do a deeper dive on exact decimal place accuracy in the future using Mantissa's
    /// @param notes is an optional parameter that allows for notes to be recorded on the blockchain with the pricing for the marketmaker in a trustless way
    struct Pricing {
        uint256 rfqid;
        address lendAsset;
        address marketmaker;
        address client;
        PxState state;
        string structure;
        string underlier;
        uint256 maturityTimestamp;
        uint256 qty;
        uint256 ltv;
        uint256 putstrikePct;
        uint256 callstrikePct;
        string notes;
    }

    function getOraclePrice() external view virtual returns (uint256);
    // function setKeeperManager(address) external;

    /// @notice this modifier limits calls to the specified marketmaker i.e. the deployer of this contract

    modifier onlyMarketMaker() {
        require(msg.sender == marketmaker, "error - only callable by whitelisted marketmaker");
        _;
    }

    modifier onlyOwnerOrMarketMaker() {
        require(msg.sender == marketmaker || msg.sender == owner(), "error - only callable by whitelisted marketmaker or owner");
        _;
    }
}
