// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

import "forge-std/console.sol";
import { ICollarVaultState } from "../../src/interfaces/ICollarVaultState.sol";

abstract contract PrintVaultStatsUtility {

    function printVaultStats(bytes calldata encodedVaultaData, string calldata context) external view {

        ICollarVaultState.Vault memory vault = abi.decode(encodedVaultaData, (ICollarVaultState.Vault));

        console.log("---", context, "---");
        console.log("");
        console.log(" BASIC INFO ");
        console.log("Active:                    ", vault.active);
        console.log("Opened At:                 ", vault.openedAt);
        console.log("Expires At:                ", vault.expiresAt);
        console.log("Duration:                  ", vault.duration);
        console.log("LTV:                       ", vault.ltv);
        console.log("");
        console.log(" ASSET SPECIFIC INFO ");
        console.log("Collateral Asset:          ", vault.collateralAsset);
        console.log("Cash Asset:                ", vault.cashAsset);
        console.log("Collateral Amount:         ", vault.collateralAmount);
        console.log("Cash Amount:               ", vault.cashAmount);
        console.log("Initial Collateral Price:  ", vault.initialCollateralPrice);
        console.log("");
        console.log(" LIQUIDITY POOL INFO ");
        console.log("Liquidity Pool:            ", vault.liquidityPool);
        console.log("Locked Pool Cash:          ", vault.lockedPoolCash);
        console.log("Put Strike Tick:           ", vault.putStrikeTick);
        console.log("Call Strike Tick:          ", vault.callStrikeTick);
        console.log("Put Strike Price:          ", vault.putStrikePrice);
        console.log("Call Strike Price:         ", vault.callStrikePrice);
        console.log("");
        console.log(" VAULT SPECIFIC INFO ");
        console.log("Loan Balance:              ", vault.loanBalance);
        console.log("Locked Vault Cash:         ", vault.lockedVaultCash);
        console.log("");


    }

}