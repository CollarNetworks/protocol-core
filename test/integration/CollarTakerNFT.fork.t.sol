// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "./utils/DeploymentLoader.sol";

contract CollarTakerNFTForkTest is Test, DeploymentLoader {
    address cashAsset = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8; // USDC
    address collateralAsset = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1; // WETH

    function setUp() public override {
        super.setUp();
    }

    function testOpenAndSettlePosition() public {
        DeploymentHelper.AssetPairContracts memory pair =
            getPairByAssets(address(cashAsset), address(collateralAsset));

        uint putLockedCash = 1000e6;
        uint offerId = createProviderOffer(pair, 12_000, 100_000e6);

        (uint takerId, uint providerId) = openPairedPosition(pair, user, putLockedCash, offerId);

        assertGt(takerId, 0, "Taker ID should be greater than 0");
        assertGt(providerId, 0, "Provider ID should be greater than 0");

        // Advance time to position expiration
        vm.warp(block.timestamp + pair.durations[0]);

        settlePairedPosition(pair, user, takerId);

        uint withdrawnAmount = withdrawFromSettled(pair, user, takerId);
        assertGt(withdrawnAmount, 0, "Withdrawn amount should be greater than 0");
    }

    function createProviderOffer(
        DeploymentHelper.AssetPairContracts memory pair,
        uint callStrikeDeviation,
        uint amount
    ) internal returns (uint offerId) {
        vm.startPrank(provider);
        pair.cashAsset.approve(address(pair.providerNFT), amount);
        offerId = pair.providerNFT.createOffer(callStrikeDeviation, amount, pair.ltvs[0], pair.durations[0]);
        vm.stopPrank();
    }

    function openPairedPosition(
        DeploymentHelper.AssetPairContracts memory pair,
        address user,
        uint putLockedCash,
        uint offerId
    ) internal returns (uint takerId, uint providerId) {
        vm.startPrank(user);
        pair.cashAsset.approve(address(pair.takerNFT), putLockedCash);
        (takerId, providerId) = pair.takerNFT.openPairedPosition(putLockedCash, pair.providerNFT, offerId);
        vm.stopPrank();
    }

    function settlePairedPosition(DeploymentHelper.AssetPairContracts memory pair, address user, uint takerId)
        internal
    {
        vm.prank(user);
        pair.takerNFT.settlePairedPosition(takerId);
    }

    function withdrawFromSettled(DeploymentHelper.AssetPairContracts memory pair, address user, uint takerId)
        internal
        returns (uint withdrawnAmount)
    {
        vm.prank(user);
        withdrawnAmount = pair.takerNFT.withdrawFromSettled(takerId, user);
    }
}
