// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

import {TransferHelper} from "@uni-v3-periphery/libraries/TransferHelper.sol";
import {AggregatorV3Interface} from "@chainlink-v0.8/interfaces/AggregatorV3Interface.sol";
import {SafeERC20, IERC20} from "@oz-v4.9.3/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@oz-v4.9.3/security/ReentrancyGuard.sol";
import {IWETH} from "./interfaces/external/IWETH.sol";
import {ICollarEngineEvents} from "./interfaces/native/ICollarEngineEvents.sol";
import {ICollarEngine} from "./interfaces/native/ICollarEngine.sol";
import {CollarVault} from "./CollarVault.sol";
import {ISwapRouter} from "@uni-v3-periphery/interfaces/ISwapRouter.sol";
import {ICollarEngineGetters} from "./interfaces/native/ICollarEngineGetters.sol";
import {Ownable} from "@oz-v4.9.3/access/Ownable.sol";

// import "interfaces/ICollarKeeperManager.sol";
// import "./CollarKeeperManager.sol";

/// @title Collar Protocol Engine
/// @author Collar Networks, Inc.
/// @notice The engine handles RFQ and launches vaults
/// @dev Developers can send calls directly to the engine if they desire
/// @custom:security-contact hello@collarprotocolentAsset.xyz
contract CollarEngine is ReentrancyGuard, ICollarEngineEvents, ICollarEngine, ICollarEngineGetters {
    /// @dev SafeERC20 prevents other contracts from doing anything malicious when we call transferFrom
    using SafeERC20 for IERC20;

    /// @notice Takes in the required addresses upon deployment
    /// @dev This should be later replaced by an addressbook contract
    constructor(
        uint256 _feeRatePct,
        address _feeWallet,
        address _marketmaker,
        address _lendAsset,
        address _dexRouter,
        address _oracle,
        address _weth
    ) {
        require(
            _weth != address(0) && _oracle != address(0) && _dexRouter != address(0) && _lendAsset != address(0)
                && _marketmaker != address(0) && _feeWallet != address(0) && _feeRatePct != 0,
            "error - no zero addresses"
        );

        marketmaker = _marketmaker;
        lendAsset = _lendAsset;
        feeRatePct = _feeRatePct;
        feeWallet = payable(_feeWallet);
        dexRouter = ISwapRouter(_dexRouter);
        priceFeed = AggregatorV3Interface(_oracle);
        WETH9 = _weth;
    }

    /// @notice Retrieves the client's pricing details
    /// @return a tuple of length 12
    function getMyPrice() external view returns (Pricing) {
        require(isCustomer[msg.sender], "error - no pricings req'd for customer");
        return pricings[msg.sender];
    }

    /// @notice Makes fetch external without upsetting the compiler
    function getOraclePrice() public view override returns (uint256) {
        (, int256 price,,,) = priceFeed.latestRoundData();
        return uint256(price) * 1e10; //make sure
    }

    /// @notice Allows the admin to update where the initial delta hedge is executed
    /// @param _newDexRouter is the address of the new dex the admin wants to point the buying/selling flow to
    /// @dev this functionality needs to be improved in v2 to allow for various dexes, ideally we extrapolate this into its own contract
    function updateDexRouter(address _newDexRouter) external onlyOwner {
        require(_newDexRouter != address(0));
        dexRouter = ISwapRouter(_newDexRouter);
    }

    /**
     * @notice This kicks off the pricing request, and is called by the client. We've currently implemented an LTV cap of 90%.
     * The RFQ flow is managed by updating state from 0 -> 1 -> 2 depending on how far along in the process the client is with the marketmaker.
     * This ensures consent is given and assets flow in a way that is consistent with that consent.
     * @param _qty The quantity of the asset that the user wants to borrow against. This determines the amount of collateral the user will receive.
     * @param _ltvPct The loan-to-value (LTV) ratio expresses the amount of collateral required as a percentage of the total amount of assets
     *                borrowed. For example, if the user wants to borrow 90 DAI and the LTV is 90%, they would need to provide 100 DAI worth of ETH as
     *                collateralentAsset. The LTV can range from 0% to 90%, and the function will fail if the requested LTV is higher than 90%.
     *                A higher LTV means that the user can borrow more assets with less collateral but at the cost of limiting their potential upside, assuming they don't rollentAsset.
     * @param _maturityTimestamp The UNIX timestamp at which the trade matures. The UNIX timestamp is the number of seconds that have elapsed since January 1, 1970.
     * @param _notes Additional notes or comments that the user wants to include with the pricing request.
     */

    function requestPrice(uint256 _qty, uint256 _ltvPct, uint256 _maturityTimestamp, string memory _notes) external {
        require(_ltvPct <= 90, "error - current max ltv is 90%");

        pricings[msg.sender] = Pricing(
            rfqid,
            lendAsset,
            marketmaker,
            msg.sender,
            PxState.REQD,
            "Prepaid",
            "ETH",
            _maturityTimestamp,
            _qty,
            _ltvPct,
            _ltvPct + feeRatePct,
            0,
            _notes
        );

        isCustomer[msg.sender] = true;
        rfqid++;
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
        require(
            pricings[_client].state == PxState.PXD || pricings[_client].state == PxState.ACKD, "error - can only pull PXD or ACKD pricings"
        );
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

    // function setKeeperManager(address _newKeeperManager) external onlyAdmin {
    //     keeperManager = _newKeeperManager;
    // }

    /// @notice This function executes the trade the client has requested, gotten a price for, 
    /// and requested to trade. It is called by the marketmaker and implies final consent
    /// @param _client the address of the counterparty for the marketmaker
    function executeTrade(address _client) external onlyMarketMaker nonReentrant returns (address) {
        //take lendasset from marketmakerr
        IERC20 lentAsset = IERC20(lendAsset);
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
        lentAsset.safeTransferFrom(msg.sender, address(vault), collat);

        //move rest of sale proceeds to vault
        lentAsset.safeTransfer(address(vault), (100 - p.putstrikePct) * fill * p.qty / 1e2 / 1e18);

        //pay fee to feewallet
        lentAsset.safeTransfer(feeWallet, feeRatePct * p.qty * fill / 1e2 / 1e18);

        //send loan to client
        lentAsset.safeTransfer(p.client, (p.putstrikePct - feeRatePct) * p.qty * fill / 1e2 / 1e18);

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

    /// @notice This function allows the admin to lower the fee rate of the protocol or increase it.
    function updateFeeRatePct(uint256 _newFeeRatePct) external onlyOwner {
        // i.e. "3"
        feeRatePct = _newFeeRatePct;
    }

    /// @notice This allows the marketmaker to refund the client and call off the trade if the price has moved significantly
    function rejectOrder(address _client, string calldata _reason) external onlyOwnerOrMarketMaker() {
        require(pricings[_client].state == PxState.DONE, "error - can only ioi pricings with state PXD");
        pricings[_client].state = PxState.REJ;
        pricings[_client].notes = _reason;
        uint256 amtToSend = clientEscrow[_client];
        clientEscrow[_client] = 0;

        //this is the most secure way to transfer value
        _client.call{value: amtToSend}("");
    }

    /// @notice This function aggregates all the recordkeeping for the broader contract into one 
    /// to abstract this portion out from the main execute trade function
    function incrementVaults(address _client, address _marketmaker) internal returns (uint256, uint256) {
        uint256 currIdUser = nextUserVaultId[_client];
        uint256 nextIdUser = currIdUser + 1;
        uint256 currIdmm = nextMarketmakerVaultId[_marketmaker];
        uint256 nextIdmm = currIdmm + 1;
        nextUserVaultId[_client] = nextIdUser;
        nextMarketmakerVaultId[_marketmaker] = nextIdmm;
        return (currIdUser, currIdmm);
    }

    /// @notice This function integrates with the relevant Uniswap v3 pool to sell ETH at the market price 
    /// to conduct the initial delta-hedge, an accommodation for marketmakers.
    /// @param amountIn amount of ETH to sell
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

        return dexRouter.exactInputSingle(params);
    }
}