// SPDX-License-Identifier: GPL 2.0
pragma solidity 0.8.22;

/**
 * @title ITakerOracle
 * @notice Interface for oracle contracts used by CollarTakerNFT
 * @dev Contracts implementing this interface are expected to provide prices for a specific
 * base/quote token pair. Prices are expressed as the amount of quote tokens per "unit" of base token.
 */
interface ITakerOracle {
    function baseToken() external view returns (address);

    function quoteToken() external view returns (address);

    function baseUnitAmount() external view returns (uint);

    /// @notice Current price.
    /// @return Amount of quoteToken for a "unit" of baseToken (i.e. 10**baseToken.decimals())
    function currentPrice() external view returns (uint);

    /**
     * @notice Returns the price at the specified timestamp if available, otherwise returns the
     * current price.
     * @param timestamp The timestamp to get the price for
     * @return price The price at the specified timestamp, or the current price if historical data
     * is not available. Amount of quoteToken for a "unit" of baseToken (i.e. 10**baseToken.decimals())
     * @return historical Whether the returned price is historical (true) or the current fallback price (false)
     */
    function pastPriceWithFallback(uint32 timestamp) external view returns (uint price, bool historical);

    /**
     * @notice Calculates the amount of quote tokens equivalent to the amount of base tokens at a given price
     * @param quoteTokenAmount The amount of quote tokens
     * @param atPrice The price to use for the conversion as returned by the same contract
     * @return The equivalent amount of base tokens
     */
    function convertToBaseAmount(uint quoteTokenAmount, uint atPrice) external view returns (uint);

    /**
     * @notice Calculates the amount of base tokens equivalent to the amount of quote tokens at a given price
     * @param baseTokenAmount The amount of base tokens
     * @param atPrice The price to use for the conversion as returned by the same contract
     * @return The equivalent amount of quote tokens
     */
    function convertToQuoteAmount(uint baseTokenAmount, uint atPrice) external view returns (uint);
}
