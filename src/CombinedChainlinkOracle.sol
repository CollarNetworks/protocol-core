// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Strings } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

import { BaseTakerOracle, ITakerOracle } from "./base/BaseTakerOracle.sol";

/**
 * TODO: docs
 *
 * Reference implementation:
 * https://github.com/euler-xyz/euler-price-oracle/blob/0572b45f6096f42f290b7cf7df584226815bfa52/src/adapter/CrossAdapter.sol
 */
contract CombinedOracle is BaseTakerOracle {
    string public constant VERSION = "0.2.0";

    ITakerOracle public immutable oracle_1;
    ITakerOracle public immutable oracle_2;
    bool public immutable invert_1;
    bool public immutable invert_2;

    constructor(
        address _baseToken,
        address _quoteToken,
        address _oracle_1,
        bool _invert_1,
        address _oracle_2,
        bool _invert_2
    ) BaseTakerOracle(_baseToken, _quoteToken, address(0)) {
        oracle_1 = ITakerOracle(_oracle_1);
        oracle_2 = ITakerOracle(_oracle_2);
        invert_1 = _invert_1;
        invert_2 = _invert_2;

        // check that all assets match: base, cross, and quote
        // assume 1 not inverted and invert if needed
        (address base, address cross_1) = (oracle_1.baseToken(), oracle_1.quoteToken());
        if (invert_1) (base, cross_1) = (cross_1, base);

        // assume 2 not inverted and invert if needed
        (address cross_2, address quote) = (oracle_2.baseToken(), oracle_2.quoteToken());
        if (invert_2) (quote, cross_2) = (cross_2, quote);

        // check all match passed in tokens and implied cross token
        require(base == baseToken, "CombinedChainlinkOracle: base argument mismatch");
        require(quote == quoteToken, "CombinedChainlinkOracle: quote argument mismatch");
        require(cross_1 == cross_2, "CombinedChainlinkOracle: cross token mismatch");
    }

    /// @notice Current price of a unit of base tokens (i.e. 10**baseToken.decimals()) in quote tokens.
    function currentPrice() external view override returns (uint) {
        // going from oracle 1 to 2
        uint price1 = invert_1 ? oracle_1.inversePrice() : oracle_1.currentPrice();
        uint divisor1 = invert_1 ? oracle_1.baseUnitAmount() : oracle_1.quoteUnitAmount();
        uint price2 = invert_2 ? oracle_2.inversePrice() : oracle_2.currentPrice();
        // 1: ETH/USD_18, 2: inv USDC/USD_18.
        // p1=3000e18, d1=1e18, p2=1e6 -> 3000e18 * 1e6 / 1e18 -> 3000e6
        return price1 * price2 / divisor1;
    }

    /// @notice Current price of a unit of quote tokens (i.e. 10**quoteToken.decimals()) in base tokens.
    function inversePrice() external view returns (uint) {
        // going from oracle 2 to 1, the inverts are flipped
        uint price2 = invert_2 ? oracle_2.currentPrice() : oracle_2.inversePrice();
        uint divisor2 = invert_2 ? oracle_2.quoteUnitAmount() : oracle_2.baseUnitAmount();
        uint price1 = invert_1 ? oracle_1.currentPrice() : oracle_1.inversePrice();
        // 1: ETH/USD_18, 2: inv USDC/USD_18.
        // p2=1e18, d2=1e18, p1=(1/3000)e18 -> 1e18 * (1/3000)e18 / 1e18 -> (1/3000)e18
        return price2 * price1 / divisor2;
    }
}
