// SPDX-License-Identifier: GPL-2.0
pragma solidity 0.8.22;

import { OracleLibrary, IUniswapV3Pool } from "@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol";
import { IUniswapV3Factory } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import { IPeripheryImmutableState } from
    "@uniswap/v3-periphery/contracts/interfaces/IPeripheryImmutableState.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { IChainlinkFeedLike } from "../../src/interfaces/IChainlinkFeedLike.sol";

contract MockChainlinkFeed is IChainlinkFeedLike {
    string public constant VERSION = "0.1.0";
    uint32 public constant TWAP_WINDOW = 1800; // 30 minutes

    address public immutable baseToken;
    address public immutable quoteToken;
    uint24 public immutable feeTier;
    IUniswapV3Pool public immutable pool;
    uint8 private immutable _decimals;
    string private _description;
    uint private immutable virtualQuoteDecimals;

    constructor(
        address _baseToken,
        address _quoteToken,
        uint24 _feeTier,
        address _uniV3SwapRouter,
        uint8 feedDecimals,
        string memory feedDescription,
        uint _virtualQuoteDecimals
    ) {
        baseToken = _baseToken;
        quoteToken = _quoteToken;
        feeTier = _feeTier;
        _decimals = feedDecimals;
        _description = feedDescription;
        virtualQuoteDecimals = _virtualQuoteDecimals;

        // Get pool from factory
        address uniV3Factory = IPeripheryImmutableState(_uniV3SwapRouter).factory();
        pool = IUniswapV3Pool(IUniswapV3Factory(uniV3Factory).getPool(_baseToken, _quoteToken, _feeTier));
        require(address(pool) != address(0), "Pool does not exist");
    }

    function decimals() external view returns (uint8) {
        return _decimals;
    }

    function description() external view returns (string memory) {
        return _description;
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int answer, uint startedAt, uint updatedAt, uint80 answeredInRound)
    {
        // Set up time window for TWAP
        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = TWAP_WINDOW;
        secondsAgos[1] = 0;

        // Get TWAP tick
        (int56[] memory tickCumulatives,) = pool.observe(secondsAgos);
        int56 tickCumulativesDelta = tickCumulatives[1] - tickCumulatives[0];
        int24 tick = int24(tickCumulativesDelta / int56(uint56(TWAP_WINDOW)));
        if (tickCumulativesDelta < 0 && (tickCumulativesDelta % int56(uint56(TWAP_WINDOW)) != 0)) tick--;

        // Get base token decimals for quote calculation
        uint baseAmount = 10 ** IERC20Metadata(baseToken).decimals();

        // Get price quote in USDC decimals
        uint priceInQuoteDecimals =
            OracleLibrary.getQuoteAtTick(tick, uint128(baseAmount), baseToken, quoteToken);

        // Convert to virtual decimals (e.g., from USDC to USD)
        uint quoteDecimals = IERC20Metadata(quoteToken).decimals();
        uint priceInVirtualDecimals = priceInQuoteDecimals * 10 ** (virtualQuoteDecimals - quoteDecimals);

        // Convert to Chainlink feed decimals
        if (_decimals != virtualQuoteDecimals) {
            uint scalingFactor = 10 ** (virtualQuoteDecimals - _decimals);
            answer = int(priceInVirtualDecimals / scalingFactor);
        } else {
            answer = int(priceInVirtualDecimals);
        }

        // Set other Chainlink feed fields
        roundId = uint80(block.number);
        startedAt = block.timestamp - TWAP_WINDOW;
        updatedAt = block.timestamp;
        answeredInRound = roundId;

        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }
}
