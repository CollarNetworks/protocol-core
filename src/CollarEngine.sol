// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {TransferHelper} from "@uni-v3-periphery/libraries/TransferHelper.sol";
import "@chainlink-v0.8/interfaces/AggregatorV3Interface.sol";
import "@oz-v4.9.3/token/ERC20/utils/SafeERC20.sol";
import "@oz-v4.9.3/security/ReentrancyGuard.sol";
import "./interfaces/external/IWETH.sol";
import "./interfaces/native/ICollarEngineEvents.sol";
// import "interfaces/ICollarKeeperManager.sol";
import "./CollarVault.sol";
// import "./CollarKeeperManager.sol";

/// @title Collar Protocol Engine
/// @author Collar Networks, Inc.
/// @notice The engine handles RFQ and launches vaults
/// @dev Developers can send calls directly to the engine if they desire
/// @custom:security-contact hello@collarprotocol.xyz
/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocol.xyz>
 * 
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

contract CollarEngine is ReentrancyGuard, ICollarEngineEvents {
    /// @dev SafeERC20 prevents other contracts from doing anything malicious when we call transferFrom
    using SafeERC20 for IERC20;

    /// @dev Passed in during deployment
    ISwapRouter dexRouter;
    // address keeperManager;
    AggregatorV3Interface internal priceFeed;
    address admin;
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

    /// @notice Takes in the required addresses upon deployment
    /// @dev This should be later replaced by an addressbook contract
    constructor(uint256 _feeRatePct, address _feeWallet, address _marketmaker, address _lendAsset, address _dexRouter, address _oracle, address _weth) {
        require(
            _weth != address(0) && _oracle != address(0) && _dexRouter != address(0) && _lendAsset != address(0) && _marketmaker != address(0)
                && _feeWallet != address(0) && _feeRatePct != 0,
            "error - no zero addresses"
        );
        admin = msg.sender;
        marketmaker = _marketmaker;
        lendAsset = _lendAsset;
        feeRatePct = _feeRatePct;
        feeWallet = payable(_feeWallet);
        // IERC20(lendAsset).approve(_dexRouter, 2**256-1);
        dexRouter = ISwapRouter(_dexRouter);
        priceFeed = AggregatorV3Interface(_oracle);
        WETH9 = _weth;
    }

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

    /// @notice this modifier limits function calls to the admin i.e. the deployer of this contract
    modifier onlyAdmin() {
        require(msg.sender == admin, "error - only callable by admin");
        _;
    }
    /// @notice this modifier limits calls to the specified marketmaker i.e. the deployer of this contract

    modifier onlyMarketMaker() {
        require(msg.sender == marketmaker, "error - only callable by whitelisted marketmaker");
        _;
    }

    /// @dev this is required by the solidity  compiler
    receive() external payable {}

    /// @notice getter functions for various variables, vaults, pricings, etc.
    function getAdmin() external view returns (address) {
        return admin;
    }

    function getDexRouter() external view returns (address) {
        return address(dexRouter);
    }

    function getMarketmaker() external view returns (address) {
        return marketmaker;
    }

    function getFeerate() external view returns (uint256) {
        return feeRatePct;
    }

    function getFeewallet() external view returns (address) {
        return feeWallet;
    }

    function getPricingByClient(address client) external view returns (Pricing memory) {
        return pricings[client];
    }

    function getStateByClient(address client) external view returns (PxState) {
        return pricings[client].state;
    }

    function getLendAsset() external view returns (address) {
        return lendAsset;
    }

    function getLastTradeVault(address client) external view returns (address) {
        return userVaults[client][nextUserVaultId[client] - 1];
    }

    function getLastTradeVaultMarketmaker(address _marketmaker) external view returns (address) {
        return marketmakerVaults[_marketmaker][nextMarketmakerVaultId[marketmaker] - 1];
    }

    function getClientEscrow(address client) external view returns (uint256) {
        return clientEscrow[client];
    }

    function getNextUserVaultId(address _client) external view returns (uint256) {
        return nextUserVaultId[_client];
    }

    function getNextMarketmakerVaultId(address _marketmaker) external view returns (uint256) {
        return nextMarketmakerVaultId[_marketmaker];
    }

    function getClientVaultById(address _client, uint256 _id) external view returns (address) {
        return userVaults[_client][_id];
    }

    function getMarketmakerVaultById(address _marketmaker, uint256 _id) external view returns (address) {
        return marketmakerVaults[_marketmaker][_id];
    }

    /// @notice Used by the UI to display latest vaults for clients
    function getLastThreeClientVaults(address _client) external view returns (address[3] memory) {
        require(_client != address(0), "error - no zero inputs");
        address[3] memory out;
        uint256 next = nextUserVaultId[_client];
        if (next < 3) {
            next = 3;
        }
        for (uint256 i = next - 3; i < next; i++) {
            out[i] = userVaults[_client][i];
        }
        return (out);
    }

    /// @notice Used by the UI to display latest vaults for marketmakers
    function getLastThreeMarketmakerVaults(address _marketmaker) external view returns (address[3] memory) {
        address[3] memory out;
        uint256 next = nextMarketmakerVaultId[_marketmaker];
        if (next < 3) {
            next = 3;
        }
        for (uint256 i = next - 3; i < next; i++) {
            out[i] = marketmakerVaults[_marketmaker][i];
        }
        return (out);
    }

    function getCurrRfqid() external view returns (uint256) {
        return rfqid;
    }

    /// @notice Retrieves the client's pricing details
    /// @return a tuple of length 12
    function getMyPrice()
        external
        view
        returns (uint256, address, address, PxState, string memory, string memory, uint256, uint256, uint256, uint256, uint256, string memory)
    {
        require(isCustomer[msg.sender], "error - no pricings req'd for customer");
        Pricing memory p = pricings[msg.sender];
        return (
            p.rfqid, p.lendAsset, p.marketmaker, p.state, p.structure, p.underlier, p.maturityTimestamp, p.qty, p.ltv, p.putstrikePct, p.callstrikePct, p.notes
        );
    }

    /// @notice Retrieves the oracle price
    function fetchOraclePrice() internal view returns (uint256) {
        (, int256 price,,,) = priceFeed.latestRoundData();
        uint256 p = uint256(price) * 1e10; //make sure
        return (p);
    }

    /// @notice Makes fetch external without upsetting the compiler
    function getOraclePrice() external view returns (uint256) {
        return fetchOraclePrice();
    }

    /// @notice Allows the admin to update where the initial delta hedge is executed
    /// @param _newDexRouter is the address of the new dex the admin wants to point the buying/selling flow to
    /// @dev this functionality needs to be improved in v2 to allow for various dexes, ideally we extrapolate this into its own contract
    function updateDexRouter(address _newDexRouter) external onlyAdmin {
        require(_newDexRouter != address(0));
        dexRouter = ISwapRouter(_newDexRouter);
    }
    /**
     * @notice This kicks off the pricing request, and is called by the client. We've currently implemented an LTV cap of 90%.
     * The RFQ flow is managed by updating state from 0 -> 1 -> 2 depending on how far along in the process the client is with the marketmaker.
     * This ensures consent is given and assets flow in a way that is consistent with that consent.
     *
     * @param _qty The quantity of the asset that the user wants to borrow against. This determines the amount of collateral the user will receive.
     *
     * @param _ltvPct The loan-to-value (LTV) ratio expresses the amount of collateral required as a percentage of the total amount of assets
     *                borrowed. For example, if the user wants to borrow 90 DAI and the LTV is 90%, they would need to provide 100 DAI worth of ETH as
     *                collateral. The LTV can range from 0% to 90%, and the function will fail if the requested LTV is higher than 90%.
     *                A higher LTV means that the user can borrow more assets with less collateral but at the cost of limiting their potential upside, assuming they don't roll.
     *
     * @param _maturityTimestamp The UNIX timestamp at which the trade matures. The UNIX timestamp is the number of seconds that have elapsed since January 1, 1970.
     *
     * @param _notes Additional notes or comments that the user wants to include with the pricing request.
     */

    function requestPrice(uint256 _qty, uint256 _ltvPct, uint256 _maturityTimestamp, string memory _notes) external {
        require(_ltvPct <= 90, "error - current max ltv is 90%");
        uint256 r = rfqid;
        rfqid++;
        pricings[msg.sender] =
            Pricing(r, lendAsset, marketmaker, msg.sender, PxState.REQD, "Prepaid", "ETH", _maturityTimestamp, _qty, _ltvPct, _ltvPct + feeRatePct, 0, _notes);
        isCustomer[msg.sender] = true;
        //maybe also test for tax/delta here
    }

    /// @notice This allows marketmakers to acknowledge clients as they arrive, and is currently limited to a single marketmaker.
    function ackPrice(address _client) external onlyMarketMaker {
        require(pricings[_client].state == PxState.REQD, "error - can only ack req'd pricings");
        pricings[_client].state = PxState.ACKD;
    }

    /// @notice This functions allows marketmakers to show a price on-chain in a verifiable way
    function showPrice(address _client, uint256 _callStrikePct) external onlyMarketMaker {
        // to add delta pct potentially
        //to add multiple decimal places...
        require(msg.sender == pricings[_client].marketmaker && msg.sender == marketmaker, "error - must be marketmaker");
        require(_callStrikePct > 100, "error - must be above 100");
        require(pricings[_client].state == PxState.ACKD, "error - must ack pricing");
        pricings[_client].callstrikePct = _callStrikePct;
        pricings[_client].state = PxState.PXD;
    }

    /// @notice This functions allows marketmakers to pull a price they've shown and not allow the client to trade.
    function pullPrice(address _client) external onlyMarketMaker {
        require(pricings[_client].state == PxState.PXD || pricings[_client].state == PxState.ACKD, "error - can only pull PXD or ACKD pricings");
        pricings[_client].state = PxState.OFF;
    }

    /// @notice This allows the client to say "done" and increments the client's balance by the amount of ETH sent to the contract.
    function clientGiveOrder() external payable {
        // assumes mkt swaps for now
        require(pricings[msg.sender].state == PxState.PXD, "error - must be in state PXD");
        pricings[msg.sender].qty = msg.value;
        pricings[msg.sender].state = PxState.DONE;
        clientEscrow[msg.sender] = clientEscrow[msg.sender] + msg.value;
    }

    /// @notice This allows the client to revoke their consent to trade
    function clientPullOrder() external {
        require(pricings[msg.sender].state == PxState.DONE || pricings[msg.sender].state == PxState.PXD, "error - must be state DONE");
        uint256 toPay = clientEscrow[msg.sender];
        clientEscrow[msg.sender] = 0;
        pricings[msg.sender].state = PxState.NEW; //reverts to pxd state
        // bool success;(success,) =
        msg.sender.call{value: toPay}("");
        // require(success == true, "error - failed to withdraw");
    }

    /// @notice This function integrates with the relevant Uniswap v3 pool to sell ETH at the market price to conduct the initial delta-hedge, an accommodation for marketmakers.
    function swapExactInputSingle(uint256 amountIn) internal returns (uint256 amountOut) {
        IWETH(WETH9).deposit{value: amountIn}();
        // Approve the router to spend DAI.
        SafeERC20.safeApprove(IERC20(WETH9), address(dexRouter), amountIn);
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: WETH9,
            tokenOut: lendAsset,
            fee: 3000, // pool fee 0.3%
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: amountIn,
            amountOutMinimum: 0, //can be limit orders
            sqrtPriceLimitX96: 0
        });
        amountOut = dexRouter.exactInputSingle(params);
        return (amountOut);
    }

    // function setKeeperManager(address _newKeeperManager) external onlyAdmin {
    //     keeperManager = _newKeeperManager;
    // }
    /// @notice This function executes the trade the client has requested, gotten a price for, and requested to trade. It is called by the marketmaker and implies final consent
    function executeTrade(address _client) external onlyMarketMaker nonReentrant returns (address) {
        //take lendasset from marketmakerr
        IERC20 l = IERC20(lendAsset);
        Pricing memory p = pricings[_client];
        // translates back to a dollar fill
        uint256 fill = swapExactInputSingle(p.qty) * 1e18 / p.qty;
        //prevents underflow
        uint256 collat = (p.callstrikePct - 100) * p.qty * fill / 1e2 / 1e18 + 1;
        //make the new vault
        CollarVault vault = new CollarVault(
            admin,
            p.rfqid,
            p.qty,
            p.lendAsset,
            p.putstrikePct,
            p.callstrikePct,
            p.maturityTimestamp,
            address(dexRouter),
            address(priceFeed)
        );

        //add the vaults to tracking system, increment trackers
        (uint256 currIdUser, uint256 currIdmm) = incrementVaults(p.client, p.marketmaker);
        userVaults[p.client][currIdUser] = address(vault);
        marketmakerVaults[msg.sender][currIdmm] = address(vault);

        //write down the client balance to zero since you're paying them out
        clientEscrow[_client] = 0;
        //move mm collateral to the vault
        l.safeTransferFrom(msg.sender, address(vault), collat);
        //move rest of sale proceeds to vault
        l.safeTransfer(address(vault), (100 - p.putstrikePct) * fill * p.qty / 1e2 / 1e18);
        //pay fee to feewallet
        l.safeTransfer(feeWallet, feeRatePct * p.qty * fill / 1e2 / 1e18);
        //send loan to client
        l.safeTransfer(p.client, (p.putstrikePct - feeRatePct) * p.qty * fill / 1e2 / 1e18);

        vault.postTradeDetailsA(
            (p.putstrikePct - feeRatePct) * p.qty * fill / 1e2 / 1e18, //loanAmt
            fill, //fill
            collat, // mmCollat
            (100 - p.putstrikePct) * fill * p.qty / 1e2 / 1e18,
            WETH9
        );
        vault.postTradeDetailsB(
            feeRatePct * p.qty * fill / 1e2 / 1e18, // fee
            feeWallet,
            feeRatePct,
            p.marketmaker,
            p.client
        );

        //launch keeper with gelato
        // ICollarKeeperManager(keeperManager).launchMaturityKeeper(address(vault), p.maturityTimestamp);

        //resets the price state to NEW
        pricings[_client].state = PxState.NEW;

        return (address(vault));
    }

    /// @notice This function aggregates all the recordkeeping for the broader contract into one to abstract this portion out from the main execute trade function
    function incrementVaults(address _client, address _marketmaker) internal returns (uint256, uint256) {
        uint256 currIdUser = nextUserVaultId[_client];
        uint256 nextIdUser = currIdUser + 1;
        uint256 currIdmm = nextMarketmakerVaultId[_marketmaker];
        uint256 nextIdmm = currIdmm + 1;
        nextUserVaultId[_client] = nextIdUser;
        nextMarketmakerVaultId[_marketmaker] = nextIdmm;
        return (currIdUser, currIdmm);
    }

    /// @notice This function allows the admin to lower the fee rate of the protocol or increase it.
    function updateFeeRatePct(uint256 _newFeeRatePct) external onlyAdmin {
        // i.e. "3"
        feeRatePct = _newFeeRatePct;
    }

    /// @notice This allows the marketmaker to refund the client and call off the trade if the price has moved significantly
    function rejectOrder(address _client, string calldata _reason) external {
        require(msg.sender == marketmaker || msg.sender == admin, "error - can only be done by the marketmaker or the admin");
        require(pricings[_client].state == PxState.DONE, "error - can only ioi pricings with state PXD");
        pricings[_client].state = PxState.REJ;
        pricings[_client].notes = _reason;
        uint256 amtToSend = clientEscrow[_client];
        clientEscrow[_client] = 0;
        //this is the most secure way to transfer value
        _client.call{value: amtToSend}("");
    }
}
