// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

interface ICollarVaultEvents {
    event SettlePrefChanged(string settlePref, string newSettlePref);
    event RollPrefChange(string rollPref, string newRollPref);
}
