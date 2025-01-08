// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import { CollarTakerNFT } from "../../src/CollarTakerNFT.sol";
import { TWAPMockChainlinkFeed } from "../../test/utils/TWAPMockChainlinkFeed.sol";
import { FixedMockChainlinkFeed } from "../../test/utils/FixedMockChainlinkFeed.sol";
import { WalletLoader } from "../wallet-loader.s.sol";
import { ArbitrumSepoliaDeployer } from "../ArbitrumSepoliaDeployer.sol";
import { BaseTakerOracle } from "../BaseDeployer.sol";

contract DeployNewMocksForTakers is Script, ArbitrumSepoliaDeployer {
    address wethUSDCTakerAddress = 0x86F729a0C910890385666b77db4aFdA6daC2dA16;
    address wbtcUSDCTakerAddress = 0x898695c9955bc82e210C3bF231903fE004dAFeD5;

    function run() external {
        require(chainId == block.chainid, "chainId does not match the chainId in config");

        // Load deployer wallet
        (address deployer,,,) = WalletLoader.loadWalletsFromEnv(vm);

        vm.startBroadcast(deployer);

        // reconfigure mock feeds
        _configureFeeds();

        // deploy direct oracles
        BaseTakerOracle oracletETH_USD =
            deployChainlinkOracle(tWETH, VIRTUAL_ASSET, _getFeed("TWAPMock(ETH / USD)"), sequencerFeed);
        BaseTakerOracle oracletWBTC_USD =
            deployChainlinkOracle(tWBTC, VIRTUAL_ASSET, _getFeed("TWAPMock(BTC / USD)"), sequencerFeed);
        BaseTakerOracle oracletUSDC_USD =
            deployChainlinkOracle(tUSDC, VIRTUAL_ASSET, _getFeed("FixedMock(USDC / USD)"), sequencerFeed);

        BaseTakerOracle wethUSDCoracle = deployCombinedOracle(
            tWETH,
            tUSDC,
            oracletETH_USD,
            oracletUSDC_USD,
            true,
            "Comb(CL(TWAPMock(ETH / USD))|inv(CL(FixedMock(USDC / USD))))"
        );
        BaseTakerOracle wbtcUSDCoracle = deployCombinedOracle(
            tWBTC,
            tUSDC,
            oracletWBTC_USD,
            oracletUSDC_USD,
            true,
            "Comb(CL(TWAPMock(BTC / USD))|inv(CL(FixedMock(USDC / USD))))"
        );

        CollarTakerNFT wethTaker = CollarTakerNFT(wethUSDCTakerAddress);
        wethTaker.setOracle(wethUSDCoracle);

        address newOracle = address(wethTaker.oracle());
        console.log("new oracle address for taker %s : %s ", wethUSDCTakerAddress, newOracle);
        CollarTakerNFT wbtcTaker = CollarTakerNFT(wbtcUSDCTakerAddress);
        wbtcTaker.setOracle(wbtcUSDCoracle);

        newOracle = address(wbtcTaker.oracle());
        console.log("new oracle address for taker : ", wbtcUSDCTakerAddress, newOracle);

        vm.stopBroadcast();

        console.log("\new oracles set successfully");
    }
}
