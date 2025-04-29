// SPDX-License-Identifier: GPL 2.0
pragma solidity 0.8.22;

interface IConfigHub {
    event LTVRangeSet(uint indexed minLTV, uint indexed maxLTV);
    event CollarDurationRangeSet(uint indexed minDuration, uint indexed maxDuration);
    event ContractCanOpenSet(
        address indexed assetA, address indexed assetB, address indexed contractAddress, bool enabled
    );
    event ProtocolFeeParamsUpdated(
        uint prevFeeAPR, uint newFeeAPR, address prevRecipient, address newRecipient
    );
}
