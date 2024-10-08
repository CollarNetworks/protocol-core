// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/*
This is not a test-util, but rather a possible replacement swapper.

Compared to a highly constrained swapper like SwapperUniV3, this swapper is more flexible,
since can work with any router / any interface. But it has more surface area,
and delegates more complexity to the front-end (because it needs to construct the swap payload),
as well requires more trust from users - due to having to approve a hard-to-inspect payload

pros:
    - more flexibility after audits / deployment, can use any router (uni, 1inch, etc..)
    - less code
    - any stuck tokens can be drained

cons:
    - much more attack surface area
    - reentrancy needs to be either prevented or be proven to be non-issue (no inconsistent state)
    - more complicated front-end: construct payload, and show user what they are signing
    - more trust to users - can call malicious contracts
    - more trust of users to front-end - FE crafts the more complex payload
    - more testing for surface area / correctness for actual usage (fork tests for integrations)
    - any approval mistakenly granted to this swapper will be drained
*/
contract SwapperArbitraryCall {
    using SafeERC20 for IERC20;

    string public constant VERSION = "0.0.0"; // expected interface

    struct ArbitraryCall {
        address to;
        bytes data;
    }

    // ----- Mutative ----- //

    function swap(IERC20 assetIn, IERC20 assetOut, uint amountIn, uint minAmountOut, bytes calldata extraData)
        external
        returns (uint amountOut)
    {
        assetIn.safeTransferFrom(msg.sender, address(this), amountIn);

        uint balanceBefore = assetOut.balanceOf(address(this));

        ArbitraryCall memory swapCall = abi.decode(extraData, (ArbitraryCall));
        // approve
        assetIn.forceApprove(swapCall.to, amountIn);
        // call
        (bool success, bytes memory ret) = swapCall.to.call(swapCall.data);
        // bubble up the revert reason
        if (!success) {
            assembly {
                revert(add(ret, 0x20), mload(ret))
            }
        }

        // Calculate the actual amount received
        amountOut = assetOut.balanceOf(address(this)) - balanceBefore;

        // check amount is as expected by caller
        require(amountOut >= minAmountOut, "slippage exceeded");

        assetOut.safeTransfer(msg.sender, amountOut);
    }
}
