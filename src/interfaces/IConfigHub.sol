// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity 0.8.22;

interface IConfigHub {
    event CollateralAssetSupportSet(address indexed collateralAsset, bool indexed enabled);
    event CashAssetSupportSet(address indexed cashAsset, bool indexed enabled);
    event LTVRangeSet(uint indexed minLTV, uint indexed maxLTV);
    event CollarDurationRangeSet(uint indexed minDuration, uint indexed maxDuration);
    event ContractCanOpenSet(address indexed contractAddress, bool indexed enabled);
    event PauseGuardianSet(address prevGaurdian, address newGuardian);
    event ProtocolFeeParamsUpdated(
        uint prevFeeAPR, uint newFeeAPR, address prevRecipient, address newRecipient
    );
}
