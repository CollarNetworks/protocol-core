// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

// constants that are used in scripts
library Const {
    address internal constant VIRTUAL_ASSET = address(type(uint160).max); // 0xff..ff

    // ----- Arbitrum Mainnet -----
    uint internal constant ArbiMain_chainId = 42_161;

    // deployer
    // TODO: use a different account
    address internal constant ArbiMain_deployerAcc = 0x2229C86F931E76650e9C0a7fef259298Ee358713;

    // uniswap
    address internal constant ArbiMain_UniRouter = 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;

    // CL feeds
    address internal constant ArbiMain_SeqFeed = 0xFdB631F5EE196F0ed6FAa767959853A9F217697D;
    address internal constant ArbiMain_CLFeedETH_USD = 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612;
    address internal constant ArbiMain_CLFeedWBTC_USD = 0xd0C7101eACbB49F3deCcCc166d238410D6D46d57;
    address internal constant ArbiMain_CLFeedUSDC_USD = 0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3;
    address internal constant ArbiMain_CLFeedUSDT_USD = 0x3f3f5dF88dC9F13eac63DF89EC16ef6e7E25DdE7;

    // assets
    address internal constant ArbiMain_USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    address internal constant ArbiMain_USDT = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;
    address internal constant ArbiMain_WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address internal constant ArbiMain_WBTC = 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f;

    // artifacts
    string internal constant ArbiMain_artifactsKey = "arbitrum_mainnet_collar_protocol_deployment";

    // ----- Arbitrum Sepolia -----
    uint internal constant ArbiSep_chainId = 421_614;

    // deployer
    address internal constant ArbiSep_deployerAcc = 0x2229C86F931E76650e9C0a7fef259298Ee358713;

    // uniswap
    address internal constant ArbiSep_UniRouter = 0x101F443B4d1b059569D643917553c771E1b9663E;
    address internal constant ArbiSep_UniFactory = 0x248AB79Bbb9bC29bB72f7Cd42F17e054Fc40188e;
    address internal constant ArbiSep_UniPosMan = 0x6b2937Bde17889EDCf8fbD8dE31C3C2a70Bc4d65;

    // assets
    // CollarOwnedERC20 deployed on 12/11/2024
    address internal constant ArbiSep_tUSDC = 0x69fC9D4d59843C6E55f00b5F66b263C963214C53;
    address internal constant ArbiSep_tWETH = 0xF17eb654885Afece15039a9Aa26F91063cC693E0;
    address internal constant ArbiSep_tWBTC = 0x19d87c960265C229D4b1429DF6F0C7d18F0611F3;

    // Note: CL feeds and some Sepolia assets are not used in scripts, but are used in tests
    // so are not defined here to reduce clutter.

    // artifacts
    string internal constant ArbiSep_artifactsKey = "arbitrum_sepolia_collar_protocol_deployment";
}
