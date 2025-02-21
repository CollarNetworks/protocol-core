// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

// constants that are used in scripts
library Const {
    address internal constant VIRTUAL_ASSET = address(type(uint160).max); // 0xff..ff

    // ----- Arbitrum -----
    uint internal constant ArbiMain_chainId = 42_161;
    uint internal constant ArbiSep_chainId = 421_614;

    // accounts
    address internal constant ArbiMain_owner = 0x064136F596D464650d599EF3B61c4f585f5fd438; // multisig
    address internal constant ArbiMain_deployerAcc = 0x82269A25cfAceEDB88771A096e416E2Af646B3e2; // main-deployer
    address internal constant ArbiMain_feeRecipient = 0x1980fB2f1e18E0CEc2219e3eda333b05fd92dA0d; // collarprotocol.eth
    address internal constant ArbiSep_owner = 0xCAB1dF186C386C2537d65484B3328383469cEbD8;
    address internal constant ArbiSep_deployerAcc = 0xCAB1dF186C386C2537d65484B3328383469cEbD8;
    address internal constant ArbiSep_feeRecipient = 0xCAB1dF186C386C2537d65484B3328383469cEbD8;

    // uniswap
    address internal constant ArbiMain_UniRouter = 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;
    address internal constant ArbiSep_UniRouter = 0x101F443B4d1b059569D643917553c771E1b9663E;
    address internal constant ArbiSep_UniFactory = 0x248AB79Bbb9bC29bB72f7Cd42F17e054Fc40188e;
    address internal constant ArbiSep_UniPosMan = 0x6b2937Bde17889EDCf8fbD8dE31C3C2a70Bc4d65;

    // CL feeds
    address internal constant ArbiMain_SeqFeed = 0xFdB631F5EE196F0ed6FAa767959853A9F217697D;
    address internal constant ArbiMain_CLFeedETH_USD = 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612;
    address internal constant ArbiMain_CLFeedWBTC_USD = 0xd0C7101eACbB49F3deCcCc166d238410D6D46d57;
    address internal constant ArbiMain_CLFeedUSDC_USD = 0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3;
    address internal constant ArbiMain_CLFeedUSDT_USD = 0x3f3f5dF88dC9F13eac63DF89EC16ef6e7E25DdE7;
    // Note: CL feeds and some Sepolia assets are not used in scripts, but are used in tests
    // so are not defined here to reduce clutter.

    // assets
    address internal constant ArbiMain_USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    address internal constant ArbiMain_USDT = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;
    address internal constant ArbiMain_WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address internal constant ArbiMain_WBTC = 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f;
    // CollarOwnedERC20 deployed on 12/11/2024
    address internal constant ArbiSep_tUSDC = 0x69fC9D4d59843C6E55f00b5F66b263C963214C53;
    address internal constant ArbiSep_tWETH = 0xF17eb654885Afece15039a9Aa26F91063cC693E0;
    address internal constant ArbiSep_tWBTC = 0x19d87c960265C229D4b1429DF6F0C7d18F0611F3;

    // artifacts
    string internal constant ArbiMain_artifactsName = "arbitrum_mainnet_collar_protocol_deployment";
    string internal constant ArbiSep_artifactsName = "arbitrum_sepolia_collar_protocol_deployment";

    // ----- Base -----
    uint internal constant OPBaseMain_chainId = 8453;
    uint internal constant OPBaseSep_chainId = 84_532;

    // accounts
    address internal constant OPBaseMain_owner = 0x064136F596D464650d599EF3B61c4f585f5fd438; // multisig
    address internal constant OPBaseMain_deployerAcc = 0x82269A25cfAceEDB88771A096e416E2Af646B3e2; // main-deployer
    address internal constant OPBaseMain_feeRecipient = 0x1980fB2f1e18E0CEc2219e3eda333b05fd92dA0d; // collarprotocol.eth
    address internal constant OPBaseSep_owner = 0x63cEcA915a23C3878b7c1a393F7676B4387C013f; // base sep safe multisig
    address internal constant OPBaseSep_deployerAcc = 0xCAB1dF186C386C2537d65484B3328383469cEbD8;
    address internal constant OPBaseSep_feeRecipient = 0xCAB1dF186C386C2537d65484B3328383469cEbD8;

    // uniswap
    // https://docs.uniswap.org/contracts/v3/reference/deployments/base-deployments
    address internal constant OPBaseMain_UniRouter = 0x2626664c2603336E57B271c5C0b26F421741e481;
    address internal constant OPBaseSep_UniRouter = 0x94cC0AaC535CCDB3C01d6787D6413C739ae12bc4;
    address internal constant OPBaseSep_UniFactory = 0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24;
    address internal constant OPBaseSep_UniPosMan = 0x27F971cb582BF9E50F397e4d29a5C7A34f11faA2;

    // CL feeds
    // https://docs.chain.link/data-feeds/l2-sequencer-feeds#overview
    address internal constant OPBaseMain_SeqFeed = 0xBCF85224fc0756B9Fa45aA7892530B47e10b6433;
    // https://docs.chain.link/data-feeds/price-feeds/addresses?network=base&page=1
    address internal constant OPBaseMain_CLFeedETH_USD = 0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70; // 0.15%, 1200, 8
    address internal constant OPBaseMain_CLFeedUSDC_USD = 0x7e860098F58bBFC8648a4311b374B1D669a2bc6B; // 0.3%, 86400, 8
    address internal constant OPBaseMain_CLFeedCBBTC_USD = 0x07DA0E54543a844a80ABE69c8A12F22B3aA59f9D; // 0.3%, 1200, 8
    address internal constant OPBaseSep_CLFeedETH_USD = 0x4aDC67696bA383F43DD60A9e78F2C97Fbbfc7cb1; // 0.15%, 1200, 8
    address internal constant OPBaseSep_CLFeedUSDC_USD = 0xd30e2101a97dcbAeBCBC04F14C3f624E67A35165; // 0.1%, 86400, 8

    // assets
    // https://app.uniswap.org/explore/pools/base/
    address internal constant OPBaseMain_USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address internal constant OPBaseMain_WETH = 0x4200000000000000000000000000000000000006;
    address internal constant OPBaseMain_cbBTC = 0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf;
    address internal constant OPBaseSep_USDC = 0xf7464321dE37BdE4C03AAeeF6b1e7b71379A9a64;
    address internal constant OPBaseSep_WETH = 0x4200000000000000000000000000000000000006;
    // CollarOwnedERC20 deployed on 11/02/2025
    address internal constant OPBaseSep_tUSDC = 0x17F5E1f30871D487612331d674765F610324a532;
    address internal constant OPBaseSep_tWETH = 0xA703Bb2faf4A977E9867DcbfC4c141c0a50F3Aec;
    address internal constant OPBaseSep_tWBTC = 0x25361aD7C93F46e71434940d705815bD38BB0fa3;

    // artifacts
    string internal constant OPBaseMain_artifactsName = "opbase_mainnet_collar_protocol_deployment";
    string internal constant OPBaseSep_artifactsName = "opbase_sepolia_collar_protocol_deployment";
}
