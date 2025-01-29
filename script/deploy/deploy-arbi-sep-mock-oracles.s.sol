// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import { CollarTakerNFT } from "../../src/CollarTakerNFT.sol";
import { TWAPMockChainlinkFeed } from "../../test/utils/TWAPMockChainlinkFeed.sol";
import { FixedMockChainlinkFeed } from "../../test/utils/FixedMockChainlinkFeed.sol";
import { WalletLoader } from "../wallet-loader.s.sol";
import { BaseTakerOracle } from "../libraries/BaseDeployer.sol";

import {
    ArbitrumSepoliaDeployer as deployLib,
    BaseDeployer,
    Const
} from "../libraries/ArbitrumSepoliaDeployer.sol";

contract DeployNewMocksForTakers is Script {
    address wethUSDCTakerAddress = 0x86F729a0C910890385666b77db4aFdA6daC2dA16;
    address wbtcUSDCTakerAddress = 0x898695c9955bc82e210C3bF231903fE004dAFeD5;

    function run() external {
        require(block.chainid == Const.ArbiSep_chainId, "chainId does not match the chainId in config");

        // Load deployer wallet
        (address deployerAcc,,,) = WalletLoader.loadWalletsFromEnv(vm);

        vm.startBroadcast(deployerAcc);

        // deploy direct oracles
        BaseTakerOracle oracletETH_USD = deployLib.deployMockOracleETHUSD();
        BaseTakerOracle oracletWBTC_USD = deployLib.deployMockOracleBTCUSD();
        BaseTakerOracle oracletUSDC_USD = deployLib.deployMockOracleUSDCUSD();

        // deploy combined oracles
        BaseTakerOracle wethUSDCoracle = BaseDeployer.deployCombinedOracle(
            deployLib.tWETH,
            deployLib.tUSDC,
            oracletETH_USD,
            oracletUSDC_USD,
            true,
            "Comb(CL(TWAPMock(ETH / USD))|inv(CL(FixedMock(USDC / USD))))"
        );
        BaseTakerOracle wbtcUSDCoracle = BaseDeployer.deployCombinedOracle(
            deployLib.tWBTC,
            deployLib.tUSDC,
            oracletWBTC_USD,
            oracletUSDC_USD,
            true,
            "Comb(CL(TWAPMock(BTC / USD))|inv(CL(FixedMock(USDC / USD))))"
        );

        // switch WETH taker oracle
        CollarTakerNFT wethTaker = CollarTakerNFT(wethUSDCTakerAddress);
        wethTaker.setOracle(wethUSDCoracle);
        address newOracle = address(wethTaker.oracle());
        console.log("new oracle address for taker %s : %s ", wethUSDCTakerAddress, newOracle);

        // switch WBTC taker oracle
        CollarTakerNFT wbtcTaker = CollarTakerNFT(wbtcUSDCTakerAddress);
        wbtcTaker.setOracle(wbtcUSDCoracle);
        newOracle = address(wbtcTaker.oracle());
        console.log("new oracle address for taker : ", wbtcUSDCTakerAddress, newOracle);

        vm.stopBroadcast();

        console.log("\new oracles set successfully");
    }
}
