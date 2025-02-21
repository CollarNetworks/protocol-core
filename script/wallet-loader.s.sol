// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Script.sol";

library WalletLoader {
    function loadWalletsFromEnv(VmSafe vm) internal {
        vm.rememberKey(vm.envUint("PRIVKEY_DEV_DEPLOYER"));
        vm.rememberKey(vm.envUint("PRIVKEY_MAIN_DEPLOYER"));
    }
}
