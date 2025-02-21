// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import { Strings } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

import { BaseTakerOracle, ITakerOracle } from "./base/BaseTakerOracle.sol";

/**
 * @title CombinedOracle
 * @custom:security-contact security@collarprotocol.xyz
 * @notice Combines two other oracles that use a common asset into one
 *
 * Key Assumptions:
 * - Assets and intermediate assets are chosen such that resulting precision is satisfactory
 * - Combined price deviations (in case of CL oracles are taken into account)
 * - The sequencer feed (on L2 networks) on the the leaf oracles is checked (not checked here).
 *
 * @dev reference implementation:
 * https://github.com/euler-xyz/euler-price-oracle/blob/0572b45f6096f42f290b7cf7df584226815bfa52/src/adapter/CrossAdapter.sol
 */
contract CombinedOracle is BaseTakerOracle {
    string public constant VERSION = "0.2.0";

    /// @notice first oracle to be combined (A -> B)
    ITakerOracle public immutable oracle_1;
    /// @notice second oracle to be combined (C -> D)
    ITakerOracle public immutable oracle_2;
    /// @notice whether the first oracle's direction is reversed in the path
    bool public immutable invert_1;
    /// @notice whether the second oracle's direction is reversed in the path
    bool public immutable invert_2;

    // internal caching of fixed amounts
    uint internal immutable base1Amount;
    uint internal immutable base2Amount;
    uint internal immutable quote1Amount;
    uint internal immutable quote2Amount;

    constructor(
        address _baseToken,
        address _quoteToken,
        address _oracle_1,
        bool _invert_1,
        address _oracle_2,
        bool _invert_2,
        string memory expectedDescription
    ) BaseTakerOracle(_baseToken, _quoteToken, address(0)) {
        oracle_1 = ITakerOracle(_oracle_1);
        oracle_2 = ITakerOracle(_oracle_2);
        invert_1 = _invert_1;
        invert_2 = _invert_2;

        // check that all assets match: base, cross, and quote
        // assume 1 not inverted and invert if needed. If inverted, A->B turns into B->A
        (address base, address cross_1) = (oracle_1.baseToken(), oracle_1.quoteToken());
        if (invert_1) (base, cross_1) = (cross_1, base);

        // assume 2 not inverted and invert if needed. If inverted, C->D turns into D->C
        (address cross_2, address quote) = (oracle_2.baseToken(), oracle_2.quoteToken());
        if (invert_2) (quote, cross_2) = (cross_2, quote);

        // check all match passed in tokens and implied cross token.
        // For example, if no inversion of was done for 1: A->B and 2: C->D
        // We expected that A == baseToken, D == quoteToken, and B == C
        require(base == baseToken, "CombinedOracle: base argument mismatch");
        require(quote == quoteToken, "CombinedOracle: quote argument mismatch");
        require(cross_1 == cross_2, "CombinedOracle: cross token mismatch");

        // cache amounts
        (base1Amount, quote1Amount) = (oracle_1.baseUnitAmount(), oracle_1.quoteUnitAmount());
        (base2Amount, quote2Amount) = (oracle_2.baseUnitAmount(), oracle_2.quoteUnitAmount());

        // check description as expected
        require(Strings.equal(description(), expectedDescription), "CombinedOracle: description mismatch");
    }

    /// @notice Current price of a unit of base tokens (i.e. 10**baseToken.decimals()) in quote tokens.
    /// For a path combination of (A->B, B->C), it quotes the price of A->C, of one unit of A in C units
    function currentPrice() external view override returns (uint) {
        // going from oracle 1 to 2
        uint price1 = invert_1 ? oracle_1.inversePrice() : oracle_1.currentPrice();
        uint divisor1 = invert_1 ? base1Amount : quote1Amount;
        uint price2 = invert_2 ? oracle_2.inversePrice() : oracle_2.currentPrice();
        // 1: ETH/USD_18, 2: inv USDC/USD_18. currentPrice() is for unit of ETH in USDC
        // p1=3000e18, d1=1e18, p2=1e6 -> 3000e18 * 1e6 / 1e18 -> 3000e6
        return price1 * price2 / divisor1;
    }

    /// @notice Current price of a unit of quote tokens (i.e. 10**quoteToken.decimals()) in base tokens.
    /// For a path combination of (A->B, B->C), it quotes the price of C->A, of one unit of C in A units
    function inversePrice() external view returns (uint) {
        // @dev the invert conditionals are flipped because of the reversed direction of trade
        // going from oracle 2 to 1
        uint price2 = invert_2 ? oracle_2.currentPrice() : oracle_2.inversePrice();
        uint divisor2 = invert_2 ? quote2Amount : base2Amount;
        uint price1 = invert_1 ? oracle_1.currentPrice() : oracle_1.inversePrice();
        // 1: ETH/USD_18, 2: inv USDC/USD_18. inversePrice() is for unit of USDC in ETH
        // p2=1e18, d2=1e18, p1=(1/3000)e18 -> 1e18 * (1/3000)e18 / 1e18 -> (1/3000)e18
        return price2 * price1 / divisor2;
    }

    /// @notice returns the description of the oracle for human readable config sanity checks.
    /// For O1, and O2, and invert 1 false, and invert 2 true, returns "Comb(O1|inv(O2))"
    function description() public view returns (string memory) {
        (bool inv1, bool inv2) = (invert_1, invert_2);
        string memory o1 = string.concat(inv1 ? "inv(" : "", oracle_1.description(), inv1 ? ")" : "");
        string memory o2 = string.concat(inv2 ? "inv(" : "", oracle_2.description(), inv2 ? ")" : "");
        return string.concat("Comb(", o1, "|", o2, ")");
    }
}
