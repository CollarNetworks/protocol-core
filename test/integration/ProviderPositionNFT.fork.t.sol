// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "./utils/DeploymentLoader.sol";
import { ProviderPositionNFT } from "../../src/ProviderPositionNFT.sol";

contract ProviderPositionNFTForkTest is Test, DeploymentLoader {
    address cashAsset = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8; // USDC
    address collateralAsset = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1; // WETH

    function setUp() public override {
        super.setUp();
    }

    function testCreateOfferAndMintPosition() public {
        DeploymentHelper.AssetPairContracts memory pair =
            getPairByAssets(address(cashAsset), address(collateralAsset));

        uint offerId = createProviderOffer(pair, 12_000, 100_000e6);
        assertGt(offerId, 0, "Offer ID should be greater than 0");

        uint amount = 1000e6;
        uint takerId = 1; // Assume this taker ID exists
        (uint positionId, ProviderPositionNFT.ProviderPosition memory position) =
            mintFromOffer(pair, offerId, amount, takerId);

        assertGt(positionId, 0, "Position ID should be greater than 0");
        assertEq(position.takerId, takerId, "Position takerId should match");
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

    function mintFromOffer(
        DeploymentHelper.AssetPairContracts memory pair,
        uint offerId,
        uint amount,
        uint takerId
    ) internal returns (uint positionId, ProviderPositionNFT.ProviderPosition memory position) {
        vm.prank(address(pair.takerNFT));
        (positionId, position) = pair.providerNFT.mintFromOffer(offerId, amount, takerId);
    }
}
