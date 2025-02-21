// SPDX-License-Identifier: GPL-2.0
pragma solidity 0.8.22;

import { OracleLibrary, IUniswapV3Pool } from "@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol";
import { IUniswapV3Factory } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import { IPeripheryImmutableState } from
    "@uniswap/v3-periphery/contracts/interfaces/IPeripheryImmutableState.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { IChainlinkFeedLike } from "../../src/interfaces/IChainlinkFeedLike.sol";
import { OracleUniV3TWAP } from "./OracleUniV3TWAP.sol";

contract TWAPMockChainlinkFeed is OracleUniV3TWAP, IChainlinkFeedLike {
    uint8 public immutable decimals;
    string public _description;
    uint private immutable virtualQuoteDecimals;
    uint32 public constant TWAP_WINDOW = 300; // 5 minutes

    constructor(
        address _baseToken,
        address _quoteToken,
        uint24 _feeTier,
        address _uniV3SwapRouter,
        uint8 feedDecimals,
        string memory feedDescription,
        uint _virtualQuoteDecimals
    )
        OracleUniV3TWAP(
            _baseToken,
            _quoteToken,
            _feeTier,
            TWAP_WINDOW,
            _uniV3SwapRouter,
            address(0) // no sequencer feed needed for mock
        )
    {
        decimals = feedDecimals;
        _description = feedDescription;
        virtualQuoteDecimals = _virtualQuoteDecimals;
    }

    /// @notice returns the description of the mockfeed for human readable config sanity checks.
    /// If _description is ABC, return TWAPMock(ABC)
    function description()
        external
        view
        override(OracleUniV3TWAP, IChainlinkFeedLike)
        returns (string memory)
    {
        return string.concat("TWAPMock(", _description, ")");
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int answer, uint startedAt, uint updatedAt, uint80 answeredInRound)
    {
        uint priceQuoteDecimals = currentPrice();

        // Convert to virtual decimals (e.g., from USDC to USD)
        uint quoteDecimals = IERC20Metadata(quoteToken).decimals();
        uint priceInVirtualDecimals = priceQuoteDecimals * 10 ** (virtualQuoteDecimals - quoteDecimals);

        // Convert to Chainlink feed decimals
        uint scalingFactor = 10 ** (virtualQuoteDecimals - decimals);
        answer = int(priceInVirtualDecimals / scalingFactor);

        // Set other Chainlink feed fields
        roundId = uint80(block.number);
        startedAt = block.timestamp - TWAP_WINDOW;
        updatedAt = block.timestamp;
        answeredInRound = roundId;

        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }
}
