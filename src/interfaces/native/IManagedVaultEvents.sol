// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

interface IManagedVaultEvents {
    event ManagerChanged(address newManager);
    event SubscriptionPeriodOpen();
    event SubscriptionPeriodClosed();
    event VaultCancelled();
    event DepositedAsset(address user, uint256 amount);
    event NewDepositor(address user, uint256 amount);
    event WithdrewAsset(address user, uint256 amount);
    event RemovedDepositor(address user, uint256 amount);
    event LentAsset(address user, uint256 amount);
    event NewLender(address user, uint256 amount);
    event WithdrewLoan(address user, uint256 amount);
    event RemovedLender(address user, uint256 amount);
    event ManagerWithdrew(uint256 amount);
    event AssetsHedged(uint256 callStrike, string maturity, uint256 fill, uint256 coverFill);
    event LoansDistributed();
}
