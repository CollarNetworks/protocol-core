// SPDX-License-Identifier: GPL 2.0
pragma solidity 0.8.22;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IConfigHub {
    event UnderlyingSupportSet(address indexed underlying, bool indexed enabled);
    event CashAssetSupportSet(address indexed cashAsset, bool indexed enabled);
    event LTVRangeSet(uint indexed minLTV, uint indexed maxLTV);
    event CollarDurationRangeSet(uint indexed minDuration, uint indexed maxDuration);
    event ContractCanOpenSet(
        IERC20 indexed assetA, IERC20 indexed assetB, address indexed contractAddress, bool enabled
    );
    event PauseGuardianSet(address sender, bool enabled);
    event ProtocolFeeParamsUpdated(
        uint prevFeeAPR, uint newFeeAPR, address prevRecipient, address newRecipient
    );
}
