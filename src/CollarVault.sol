// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {SafeERC20, IERC20} from "@oz-v4.9.3/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@oz-v4.9.3/security/ReentrancyGuard.sol";
import {ISwapRouter} from "@uni-v3-periphery/interfaces/ISwapRouter.sol";
import {AggregatorV3Interface} from "@chainlink-v0.8/interfaces/AggregatorV3Interface.sol";
import {ICollarVaultEvents} from "./interfaces/ICollarVaultEvents.sol";
import {ICollarEngine} from "./interfaces/ICollarEngine.sol";
import {IWETH9 as IWETH} from "@uni-v3-periphery/interfaces/external/IWETH9.sol";
import {TransferHelper} from "@uni-v3-periphery/libraries/TransferHelper.sol";
import {ICollarVault} from "./interfaces/ICollarVault.sol";

/// @title Collar Protocol Engine
/// @author Collar Networks, Inc.
/// @notice The vault handles RFQ and execution of rolls for existing vaults
/// @custom:security-contact hello@collarprotocol.xyz

contract CollarVault is ReentrancyGuard, ICollarVault {
    using SafeERC20 for IERC20;

    /// @notice fills are 4 digits // inputted as 13000101 = 1300.0101 actual - need to keep as 8 digits
    constructor(
        address _admin,
        uint256 _rfqid,
        uint256 _qty,
        address _lendAsset,
        uint256 _putStrikePct,
        uint256 _callStrikePct,
        uint256 _maturityTimestamp,
        address _dexRouter,
        address _priceFeed
    ) {
        admin = _admin;
        rfqid = _rfqid;
        qty = _qty;
        lendAsset = _lendAsset;
        putstrikePct = _putStrikePct;
        callstrikePct = _callStrikePct;
        maturityTimestamp = _maturityTimestamp;
        engine = msg.sender;
        dexRouter = ISwapRouter(_dexRouter);
        priceFeed = AggregatorV3Interface(_priceFeed);
    }

    /// @notice Retrieves the oracle price
    function getOraclePrice() public view returns (uint256) {
        (, int256 price,,,) = priceFeed.latestRoundData();
        uint256 p = uint256(price) * 1e10; //make sure
        return (p);
    }

    function checkMatured() external view returns (bool) {
        return block.timestamp >= maturityTimestamp;
    }

    function getRepaymentAmount() external view returns (uint256) {
        return putstrikePct * qty / 1e2;
    }

    /// @notice Used by the UI to retrieve information about the vault
    function getVaultDetails()
        external
        view
        returns (uint256, uint256, address, uint256, uint256, uint256, uint256, uint256, uint256, address, uint256, uint256)
    {
        return
            (qty, lent, lendAsset, putstrikePct, callstrikePct, maturityTimestamp, fill, mmCollateral, proceeds, engine, rfqid, rollcount);
    }

    /// @notice Allows clients to update settlement preferences
    function setSettleType(uint256 _newSettlePref) external onlyClient {
        require(!settled, "error - vault has already been settled");
        require(_newSettlePref <= 2 && _newSettlePref != settlePref, "error - settle change instruction invalid");
        settlePref = _newSettlePref;
    }

    /// @notice Retrieves the roll details for the UI
    function getRollDetails() external view returns (bool, uint256, uint256, uint256, uint256) {
        return (rollPref, rollstate, rollputpct, rollcallpct, rollmatstamp); //rollcollat
    }

    /// @notice Allows clients to update roll preferences
    function setRollPref(bool _newRollPref) external onlyClient whileLive {
        rollPref = _newRollPref;
    }

    /// @notice Allows the client to request a roll price
    //putstrike req is done as % of new fill/oracle px
    function requestRollPrice(uint256 _rollltvpct, uint256 _rollMaturityTimestamp) external isEligibleRoller isRollable whileLive {
        rollstate = 1;
        rollltvpct = _rollltvpct;
        rollputpct = _rollltvpct + rollFeeRate;
        require(rollputpct <= 90, "error - cant do ltv higher than 87%");
        rollmatstamp = _rollMaturityTimestamp;
    }

    function pullRollRequest() external isEligibleRoller isRollable whileLive {
        require(rollstate >= 1, "error - you can't pull a roll you haven't yet requested");
        resetRoll();
    }

    function giveRollOrder() external isEligibleRoller isRollable whileLive {
        rollstate = 3;
    }

    function showRollPrice(uint256 _rollcallpct) external onlyMarketMaker isRollable whileLive {
        require(rollstate == 1 || rollstate == 2, "error - client has not requested a roll");
        require(_rollcallpct >= 100, "error - roll call strike is too low");
        rollstate = 2;
        rollcallpct = _rollcallpct;
    }

    function rejectRoll() external onlyMarketMaker isRollable whileLive {
        require(rollstate >= 1, "error - client has not requested a roll");
        resetRoll();
    }

    function changeMarketmaker(address _newMM) external onlyAdmin nonReentrant {
        require(_newMM != admin && _newMM != marketmaker, "error - must be a new, non-admin marketmaker");
        resetRoll();
        marketmaker = _newMM;
        //should only be called in states of marketmaker blowup/abandonment
    }

    //see if call higher or lower, if lower, mm withdraws, if higher, they post
    //see if ltv higher or lower, if lower, client posts, if higher, withdraw
    function executeRoll() external onlyMarketMaker isRollable whileLive nonReentrant {
        require(true, "error - people have enough collateral");
        require(rollstate == 3, "error - client order has not yet been given (need state 3)");
        IERC20 lentERC20 = IERC20(lendAsset);
        uint256 newpx = getOraclePrice() / 1e12;
        uint256 rollfee = qty * rollFeeRate * newpx / 1e2 / 1e18;
        //figure out how much client made based on oracle px
        uint256 mmportion;
        uint256 clientportion;
        uint256 callstrike = callstrikePct * fill / 1e2;
        uint256 putstrike = putstrikePct * fill / 1e2;
        if (newpx >= callstrike) {
            //above
            clientportion = proceeds + mmCollateral;
        } else if (newpx <= callstrike && newpx >= putstrike) {
            //btwn
            mmportion = (callstrike - newpx) * qty / 1e18;
            clientportion = (newpx - putstrike) * qty / 1e18;
        } else {
            // below
            mmportion = proceeds + mmCollateral;
        }
        //calc collateral required for the new trade
        uint256 newmmcollat = qty * (rollcallpct - 100) * newpx / 1e2 / 1e18;
        uint256 newclientcollat = qty * (100 - rollltvpct) * newpx / 1e2 / 1e18; //using ltv ensures fee is paid
        //true up mm collat

        if (newmmcollat >= mmportion) {
            lentERC20.safeTransferFrom(msg.sender, address(this), newmmcollat - mmportion);
        } else {
            lentERC20.safeTransfer(msg.sender, mmportion - newmmcollat);
        }
        //true up client collat (may be cash or phys)

        if (newclientcollat >= clientportion) {
            //if theres a shortfall, sell/seize collat to cover shortfall
            if (settlePref == 1) {
                //cash
                require(cashposted >= newclientcollat - clientportion, "error - insufficient cash collateral posted");
                cashposted -= newclientcollat - clientportion;
            } else {
                //netsh or phys
                //sells physical eth posted to cover
                require(true, "error - add a quote px here?"); //https://docs.uniswap.org/contracts/v3/reference/periphery/lens/QuoterV2#quoteexactinputsingle
                postedPhysicalCollat -= swapExactInputSingle(newclientcollat - clientportion);
            }
        } else {
            // lent += clientportion-newclientcollat-rollfee; // or just write to .85?
            lentERC20.safeTransfer(client, clientportion - newclientcollat);
            //give client excess collat
        }
        //payout protocol fee
        feePaid += rollfee;
        lentERC20.safeTransfer(feeWallet, rollfee);

        //update all the terms of the vault to the rolled terms
        lent = rollltvpct * newpx * qty / 1e18 / 1e2;
        proceeds = (100 - rollputpct) * newpx * qty / 1e18 / 1e2;
        mmCollateral = newmmcollat;
        maturityTimestamp = rollmatstamp;
        callstrikePct = rollcallpct;
        putstrikePct = rollputpct;
        fill = newpx;
        rollcount += 1;
        rollstate = 4; // 0 new 1 reqd 2 pxd 3 done 4 execd
        rollputpct = 0;
        rollcallpct = 0;
        rollltvpct = 0;
        rollmatstamp = 0;
    }

    function postTradeDetailsA(uint256 _lent, uint256 _fill, uint256 _collat, uint256 _proceeds, address _weth) external onlyEngine {
        require(!deetsPostedA, "error - deets already posted"); //only once
        deetsPostedA = true;
        lent = _lent;
        fill = _fill;
        mmCollateral = _collat;
        proceeds = _proceeds;
        WETH9 = _weth;
    }

    function postTradeDetailsB(uint256 _fee, address _feeWallet, uint256 _rollFeeRate, address _marketmaker, address _client)
        external
        onlyEngine
    {
        require(!deetsPostedB, "error - deets already posted"); //only once
        deetsPostedB = true;
        feePaid = _fee;
        feeWallet = _feeWallet;
        rollFeeRate = _rollFeeRate;
        marketmaker = _marketmaker;
        client = payable(_client);
    }

    function repayLoan() external onlyClient whileLive nonReentrant {
        uint256 amtToRepay = fill * putstrikePct * qty / 1e2 / 1e18;
        IERC20(lendAsset).safeTransferFrom(msg.sender, address(this), amtToRepay);
        loanRepayBalance = amtToRepay;
        repaid = true;
    }

    function postCash(uint256 _stableAmt) external onlyClient whileLive nonReentrant {
        IERC20(lendAsset).safeTransferFrom(msg.sender, address(this), _stableAmt);
        cashposted += _stableAmt;
    }

    function reclaimCash(uint256 _stableAmt) external onlyClient {
        require(_stableAmt <= cashposted, "error - you don't have that much cash in the contract to reclaim");
        cashposted -= _stableAmt;
        IERC20(lendAsset).safeTransfer(msg.sender, _stableAmt);
    }

    function postPhysical() external payable onlyClient whileLive {
        postedPhysicalCollat += msg.value;
    }

    function reclaimPhysical(uint256 amtWei) external onlyClient {
        require(amtWei <= postedPhysicalCollat, "error - you can only withdraw up to the posted collateral");
        postedPhysicalCollat -= amtWei;
        msg.sender.call{value: amtWei}; // proper way to transmit value
    }

    function matureVault() external override onceMatured nonReentrant {
        // anyone can call, protocol/keepers/mm/client will do it
        require(!settled, "error - vault has already been settled");
        settled = true;
        finalPrice = getOraclePrice() / 1e12;
        //figure out how much each person gets
        uint256 mmGets;
        uint256 clientGets;
        IERC20 lentERC20 = IERC20(lendAsset);
        if (finalPrice <= putstrikePct * fill / 1e2) {
            mmGets = (proceeds + mmCollateral) * qty / 1e18;
            clientGets = 0;
        } else if (finalPrice >= callstrikePct * fill / 1e2) {
            mmGets = 0;
            clientGets = (proceeds + mmCollateral) * qty / 1e18;
        } else {
            mmGets = ((callstrikePct * fill / 1e2) - finalPrice) * qty / 1e18;
            clientGets = (finalPrice - (putstrikePct * fill / 1e2)) * qty / 1e18;
        }
        //figure out if you're trading full delta or not (cash vs phys)

        if (repaid) {
            clientGets += putstrikePct * fill * qty / 1e2;
        }
        if ((settlePref == 0 || settlePref == 2) && clientGets > 0) {
            lentERC20.safeApprove(address(dexRouter), clientGets + mmGets);
            uint256 ethProceeds = swapExactInputSingleFlipped(clientGets); //returns "amounts?"
            IWETH(WETH9).withdraw(ethProceeds);
            client.call{value: ethProceeds}("");
        } else {
            lentERC20.safeTransfer(client, clientGets); // pay cash
        }
        //payout marketmaker
        lentERC20.safeTransfer(marketmaker, mmGets); // if it's usdc 6dp
    }

    function swapExactInputSingle(uint256 amountIn) internal returns (uint256 amountOut) {
        IWETH(WETH9).deposit{value: amountIn}();
        // Approve the router to spend DAI.
        TransferHelper.safeApprove(WETH9, address(dexRouter), amountIn);
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: WETH9,
            tokenOut: lendAsset,
            // pool fee 0.3%
            fee: 3000,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: amountIn,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });
        amountOut = dexRouter.exactInputSingle(params);
        return (amountOut);
    }

    function swapExactInputSingleFlipped(uint256 amountIn) internal returns (uint256 amountOut) {
        TransferHelper.safeApprove(lendAsset, address(dexRouter), amountIn);
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: lendAsset,
            tokenOut: WETH9,
            fee: 3000, // pool fee 0.3%
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: amountIn,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });
        amountOut = dexRouter.exactInputSingle(params);
        return (amountOut);
    }

    /// @notice Allows the contract to reset the roll details for the trade
    function resetRoll() internal whileLive {
        IERC20 lendAsset = IERC20(lendAsset);
        rollstate = 0;
        rollcallpct = 0;
        rollputpct = 0;
        rollmatstamp = 0;
        lendAsset.safeTransfer(client, cashposted);
    }
}
