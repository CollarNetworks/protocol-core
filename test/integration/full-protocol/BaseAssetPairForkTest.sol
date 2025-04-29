// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { ConfigHub } from "../../../src/ConfigHub.sol";
import { BaseDeployer } from "../../../script/libraries/BaseDeployer.sol";
import { ILoansNFT } from "../../../src/interfaces/ILoansNFT.sol";
import { IRolls } from "../../../src/interfaces/IRolls.sol";
import { ICollarTakerNFT } from "../../../src/interfaces/ICollarTakerNFT.sol";
import { ICollarProviderNFT } from "../../../src/interfaces/ICollarProviderNFT.sol";

abstract contract BaseAssetPairForkTest is Test {
    // constants for all pairs
    uint constant BIPS_BASE = 10_000;

    // escrow related constants
    uint constant interestAPR = 500; // 5% APR
    uint constant gracePeriod = 7 days;
    uint constant lateFeeAPR = 5000; // 50% APR

    // users
    address owner;
    address user;
    address provider;
    address escrowSupplier;

    // deployment
    ConfigHub public configHub;
    BaseDeployer.AssetPairContracts[] public deployedPairs;
    BaseDeployer.AssetPairContracts internal pair;

    // config params
    uint protocolFeeAPR;
    address protocolFeeRecipient;

    // pair params
    uint expectedOraclePrice;
    uint expectedNumPairs;

    // values to be set by pair
    address cashAsset;
    address underlying;
    string oracleDescription;

    uint expectedPairIndex;
    uint offerAmount;
    uint underlyingAmount;
    uint minLoanAmount;
    int rollFee;
    int rollDeltaFactor;
    uint bigCashAmount;
    uint bigUnderlyingAmount;

    // Swap amounts
    uint swapStepCashAmount;

    // Pool fee tier
    uint24 swapPoolFeeTier;

    uint slippage;
    uint callstrikeToUse;
    uint duration;
    uint ltv;

    function setUp() public virtual {
        user = makeAddr("user");
        provider = makeAddr("provider");
        escrowSupplier = makeAddr("escrowSupplier");

        // sets pair selection inputs and expected validation outputs
        _setTestValues();

        // set the deployment
        (ConfigHub hub, BaseDeployer.AssetPairContracts[] memory pairs) = getDeployedContracts();
        configHub = hub;
        for (uint i = 0; i < pairs.length; i++) {
            deployedPairs.push(pairs[i]);
        }

        // sets the pair based on the params
        _setPair();

        // tests use these specific values
        duration = 5 minutes;
        ltv = 9000;

        // override config values from deployment to ensure test params are allowed
        _updateConfigValues();

        fundWallets();
    }

    // abstract

    // @dev this should do the various setup steps, depending on the type of deployment
    // for example: fresh (deploy everything), fresh export-load, existing loaded, incremental from
    // existing, etc..
    function getDeployedContracts()
        internal
        virtual
        returns (ConfigHub hub, BaseDeployer.AssetPairContracts[] memory pairs);

    // setup

    function _updateConfigValues() private {
        vm.startPrank(owner);

        // override duration being too short
        configHub.setCollarDurationRange(duration, configHub.maxDuration());

        vm.stopPrank();
    }

    function _setPair() private {
        uint pairIndex;
        (pair, pairIndex) = getPairByAssets(address(cashAsset), address(underlying));

        // pair internal validations are done elsewhere
        // but we should check that assets match so that these checks are relevant
        assertEq(address(pair.underlying), underlying);
        assertEq(address(pair.cashAsset), cashAsset);
        // ensure we're testing all deployed pairs
        assertEq(pairIndex, expectedPairIndex);
        assertEq(deployedPairs.length, expectedNumPairs);
    }

    function getPairByAssets(address _cashAsset, address _underlying)
        internal
        view
        returns (BaseDeployer.AssetPairContracts memory _pair, uint index)
    {
        bool found = false;
        for (uint i = 0; i < deployedPairs.length; i++) {
            if (
                address(deployedPairs[i].cashAsset) == _cashAsset
                    && address(deployedPairs[i].underlying) == _underlying
            ) {
                require(!found, "getPairByAssets: found twice");
                found = true;
                (_pair, index) = (deployedPairs[i], i);
            }
        }
        require(found, "getPairByAssets: not found");
    }

    // abstract

    function _setTestValues() internal virtual;

    // utility

    function createProviderOffer(uint callStrikePercent, uint amount) internal returns (uint offerId) {
        vm.startPrank(provider);
        pair.cashAsset.approve(address(pair.providerNFT), amount);
        offerId = pair.providerNFT.createOffer(callStrikePercent, amount, ltv, duration, 0);
        vm.stopPrank();
    }

    function openLoan(uint offerId) internal returns (uint loanId, uint providerId, uint loanAmount) {
        vm.startPrank(user);
        pair.underlying.approve(address(pair.loansContract), underlyingAmount);
        (loanId, providerId, loanAmount) = pair.loansContract.openLoan(
            underlyingAmount,
            minLoanAmount,
            ILoansNFT.SwapParams(0, address(pair.loansContract.defaultSwapper()), ""),
            ILoansNFT.ProviderOffer(pair.providerNFT, offerId)
        );
        vm.stopPrank();
    }

    function closeLoan(uint loanId, uint minUnderlyingOut) internal returns (uint underlyingOut) {
        vm.startPrank(user);
        ILoansNFT.Loan memory loan = pair.loansContract.getLoan(loanId);
        // approve repayment amount in cash asset to loans contract
        pair.cashAsset.approve(address(pair.loansContract), loan.loanAmount);
        underlyingOut = pair.loansContract.closeLoan(
            loanId, ILoansNFT.SwapParams(minUnderlyingOut, address(pair.loansContract.defaultSwapper()), "")
        );
        vm.stopPrank();
    }

    function createRollOffer(uint loanId, uint providerId) internal returns (uint rollOfferId) {
        vm.startPrank(provider);
        pair.cashAsset.approve(address(pair.rollsContract), type(uint).max);
        pair.providerNFT.approve(address(pair.rollsContract), providerId);
        uint currentPrice = pair.takerNFT.currentOraclePrice();
        uint takerId = loanId;
        rollOfferId = pair.rollsContract.createOffer(
            takerId,
            rollFee,
            rollDeltaFactor,
            currentPrice * 90 / 100, // minPrice 90% of current
            currentPrice * 110 / 100, // maxPrice 110% of current
            0,
            block.timestamp + 1 hours
        );
        vm.stopPrank();
    }

    function rollLoan(uint loanId, uint rollOfferId, int minToUser)
        internal
        returns (uint newLoanId, uint newLoanAmount, int transferAmount)
    {
        vm.startPrank(user);
        pair.cashAsset.approve(address(pair.loansContract), type(uint).max);
        (newLoanId, newLoanAmount, transferAmount) = pair.loansContract.rollLoan(
            loanId, ILoansNFT.RollOffer(pair.rollsContract, rollOfferId), minToUser, 0, 0
        );
        vm.stopPrank();
    }

    function createEscrowOffer() internal returns (uint offerId) {
        vm.startPrank(escrowSupplier);
        pair.underlying.approve(address(pair.escrowNFT), underlyingAmount);
        offerId = pair.escrowNFT.createOffer(
            underlyingAmount,
            duration,
            interestAPR,
            gracePeriod,
            lateFeeAPR,
            0 // minEscrow
        );
        vm.stopPrank();
    }

    function openEscrowLoan(uint _minLoanAmount, uint providerOfferId, uint escrowOfferId, uint escrowFee)
        internal
        returns (uint loanId, uint providerId, uint loanAmount)
    {
        vm.startPrank(user);
        // Approve underlying amount plus escrow fee
        pair.underlying.approve(address(pair.loansContract), underlyingAmount + escrowFee);

        (loanId, providerId, loanAmount) = pair.loansContract.openEscrowLoan(
            underlyingAmount,
            _minLoanAmount,
            ILoansNFT.SwapParams(0, address(pair.loansContract.defaultSwapper()), ""),
            ILoansNFT.ProviderOffer(pair.providerNFT, providerOfferId),
            ILoansNFT.EscrowOffer(pair.escrowNFT, escrowOfferId),
            escrowFee
        );
        vm.stopPrank();
    }

    function createEscrowOffers() internal returns (uint offerId, uint escrowOfferId) {
        uint providerBalanceBefore = pair.cashAsset.balanceOf(provider);
        offerId = createProviderOffer(callstrikeToUse, offerAmount);
        assertEq(pair.cashAsset.balanceOf(provider), providerBalanceBefore - offerAmount);

        // Create escrow offer
        escrowOfferId = createEscrowOffer();
    }

    function executeEscrowLoan(uint offerId, uint escrowOfferId)
        internal
        returns (uint loanId, uint providerId, uint loanAmount)
    {
        (uint expectedEscrowFee,,) = pair.escrowNFT.upfrontFees(escrowOfferId, underlyingAmount);

        // Open escrow loan using base function
        (loanId, providerId, loanAmount) =
            openEscrowLoan(minLoanAmount, offerId, escrowOfferId, expectedEscrowFee);
    }

    function verifyEscrowLoan(
        uint loanId,
        uint loanAmount,
        uint escrowOfferId,
        uint feeRecipientBalanceBefore,
        uint escrowSupplierUnderlyingBefore,
        uint expectedProtocolFee
    ) internal view {
        (uint expectedEscrowFee,,) = pair.escrowNFT.upfrontFees(escrowOfferId, underlyingAmount);

        uint userUnderlyingBefore = pair.underlying.balanceOf(user) + underlyingAmount + expectedEscrowFee;

        checkLoanAmount(loanAmount);

        // Verify protocol fee
        assertEq(
            pair.cashAsset.balanceOf(protocolFeeRecipient) - feeRecipientBalanceBefore, expectedProtocolFee
        );

        // Verify loan state
        ILoansNFT.Loan memory loan = pair.loansContract.getLoan(loanId);
        assertTrue(loan.usesEscrow);
        assertEq(address(loan.escrowNFT), address(pair.escrowNFT));
        assertGt(loan.escrowId, 0);

        // Verify balances
        assertEq(pair.underlying.balanceOf(user), userUnderlyingBefore - underlyingAmount - expectedEscrowFee);
        assertEq(escrowSupplierUnderlyingBefore - pair.underlying.balanceOf(escrowSupplier), underlyingAmount);
    }

    function checkLoanAmount(uint actualLoanAmount) internal view {
        uint oraclePrice = pair.takerNFT.currentOraclePrice();
        uint expectedCashFromSwap = pair.oracle.convertToQuoteAmount(underlyingAmount, oraclePrice);
        // Calculate minimum expected loan amount (expectedCash * LTV)
        // Apply slippage tolerance for swaps and rounding
        uint minExpectedLoan = expectedCashFromSwap * ltv * (BIPS_BASE - slippage) / (BIPS_BASE * BIPS_BASE);

        // Check actual loan amount is at least the minimum expected
        assertGe(actualLoanAmount, minExpectedLoan);
    }

    function fundWallets() public {
        deal(address(cashAsset), user, bigCashAmount);
        deal(address(cashAsset), provider, bigCashAmount);
        deal(address(underlying), user, bigUnderlyingAmount);
        deal(address(underlying), provider, bigUnderlyingAmount);
        deal(address(underlying), escrowSupplier, bigUnderlyingAmount);
    }

    function getProviderProtocolFeeByLoanAmount(uint loanAmount) internal view returns (uint protocolFee) {
        // Calculate protocol fee based on post-swap provider locked amount
        uint swapOut = loanAmount * BIPS_BASE / ltv;
        uint initProviderLocked = swapOut * (callstrikeToUse - BIPS_BASE) / BIPS_BASE;
        (protocolFee,) = pair.providerNFT.protocolFee(initProviderLocked, duration, callstrikeToUse);
        assertGt(protocolFee, 0);
    }

    function closeAndCheckLoan(
        uint loanId,
        uint loanAmount,
        uint totalAmountToSwap,
        uint currentPrice,
        uint escrowRefund
    ) internal returns (uint underlyingOut) {
        // Track balances before closing
        uint userCashBefore = pair.cashAsset.balanceOf(user);
        uint userUnderlyingBefore = pair.underlying.balanceOf(user);
        // Convert cash amount to expected underlying amount using oracle's conversion
        uint expectedFromSwap = pair.oracle.convertToBaseAmount(totalAmountToSwap, currentPrice);

        uint minUnderlyingOut = (expectedFromSwap * (BIPS_BASE - slippage) / BIPS_BASE);
        underlyingOut = closeLoan(loanId, minUnderlyingOut);

        assertApproxEqAbs(
            underlyingOut, expectedFromSwap + escrowRefund, expectedFromSwap * slippage / BIPS_BASE
        );
        // Verify balance changes
        assertEq(userCashBefore - pair.cashAsset.balanceOf(user), loanAmount);
        assertEq(pair.underlying.balanceOf(user) - userUnderlyingBefore, underlyingOut);
    }

    // addresses of all loans contracts expected to be using the escrow for a particular underlying
    function expectedApprovedLoansForEscrow(IERC20 _underlying)
        internal
        view
        returns (address[] memory expectedLoans)
    {
        // define a array that's too long, and truncate after the loop (otherwise need to do two ugly loops)
        expectedLoans = new address[](deployedPairs.length);
        uint nPairsForUnderlying;
        for (uint i = 0; i < deployedPairs.length; i++) {
            if (deployedPairs[i].underlying == _underlying) {
                expectedLoans[nPairsForUnderlying] = address(deployedPairs[i].loansContract);
                nPairsForUnderlying++;
            }
        }
        // truncate the memory array to the right length
        assembly {
            mstore(expectedLoans, nPairsForUnderlying)
        }
    }

    // tests

    function test_validatePairDeployment() public view {
        // configHub
        assertEq(configHub.VERSION(), "0.3.0");
        assertEq(configHub.owner(), owner);
        assertEq(uint(configHub.protocolFeeAPR()), protocolFeeAPR);
        assertEq(configHub.feeRecipient(), protocolFeeRecipient);

        // oracle
        assertEq(address(pair.oracle.baseToken()), address(pair.underlying));
        assertEq(address(pair.oracle.quoteToken()), address(pair.cashAsset));
        assertEq(pair.oracle.description(), oracleDescription);

        // taker
        assertEq(pair.takerNFT.VERSION(), "0.3.0");
        assertEq(address(pair.takerNFT.configHubOwner()), owner);
        assertEq(address(pair.takerNFT.configHub()), address(configHub));
        assertEq(address(pair.takerNFT.underlying()), address(pair.underlying));
        assertEq(address(pair.takerNFT.cashAsset()), address(pair.cashAsset));
        assertEq(address(pair.takerNFT.oracle()), address(pair.oracle));

        // provider
        assertEq(pair.providerNFT.VERSION(), "0.3.0");
        assertEq(address(pair.providerNFT.configHubOwner()), owner);
        assertEq(address(pair.providerNFT.configHub()), address(configHub));
        assertEq(address(pair.providerNFT.underlying()), address(pair.underlying));
        assertEq(address(pair.providerNFT.cashAsset()), address(pair.cashAsset));
        assertEq(address(pair.providerNFT.taker()), address(pair.takerNFT));

        // rolls
        assertEq(pair.rollsContract.VERSION(), "0.3.0");
        assertEq(address(pair.rollsContract.takerNFT()), address(pair.takerNFT));
        assertEq(address(pair.rollsContract.cashAsset()), address(pair.cashAsset));

        // loans
        assertEq(pair.loansContract.VERSION(), "0.3.0");
        assertEq(address(pair.loansContract.configHubOwner()), owner);
        assertEq(address(pair.loansContract.configHub()), address(configHub));
        assertEq(address(pair.loansContract.takerNFT()), address(pair.takerNFT));
        assertEq(address(pair.loansContract.underlying()), address(pair.underlying));
        assertEq(address(pair.loansContract.cashAsset()), address(pair.cashAsset));
        assertEq(address(pair.loansContract.defaultSwapper()), address(pair.swapperUniV3));
        assertTrue(pair.loansContract.isAllowedSwapper(address(pair.swapperUniV3)));
        // all swappers
        address[] memory oneSwapper = new address[](1);
        oneSwapper[0] = address(pair.swapperUniV3);
        assertEq(pair.loansContract.allAllowedSwappers(), oneSwapper);

        // escrow
        assertEq(pair.escrowNFT.VERSION(), "0.3.0");
        assertEq(address(pair.escrowNFT.configHubOwner()), owner);
        assertEq(address(pair.escrowNFT.configHub()), address(configHub));
        assertEq(address(pair.escrowNFT.asset()), address(pair.underlying));

        // pair auth
        assertTrue(
            configHub.canOpenPair(address(pair.underlying), address(pair.cashAsset), address(pair.takerNFT))
        );
        assertTrue(
            configHub.canOpenPair(
                address(pair.underlying), address(pair.cashAsset), address(pair.providerNFT)
            )
        );
        assertTrue(
            configHub.canOpenPair(
                address(pair.underlying), address(pair.cashAsset), address(pair.loansContract)
            )
        );
        assertTrue(
            configHub.canOpenPair(
                address(pair.underlying), address(pair.cashAsset), address(pair.rollsContract)
            )
        );
        assertTrue(
            configHub.canOpenPair(
                address(pair.underlying), address(pair.escrowNFT), address(pair.loansContract)
            )
        );

        // all pair auth

        // underlying x cash -> pair
        address[] memory pairAuthed = new address[](4);
        pairAuthed[0] = address(pair.takerNFT);
        pairAuthed[1] = address(pair.providerNFT);
        pairAuthed[2] = address(pair.loansContract);
        pairAuthed[3] = address(pair.rollsContract);
        assertEq(configHub.allCanOpenPair(address(pair.underlying), address(pair.cashAsset)), pairAuthed);

        // underlying x escrow -> loans
        // multiple loans contracts can be using the same escrow
        address[] memory loansToEscrow = expectedApprovedLoansForEscrow(pair.underlying);
        assertEq(configHub.allCanOpenPair(address(pair.underlying), address(pair.escrowNFT)), loansToEscrow);

        // single asset auth
        assertTrue(configHub.canOpenSingle(address(pair.underlying), address(pair.escrowNFT)));

        // all single auth for underlying
        address[] memory escrowAuthed = new address[](1);
        escrowAuthed[0] = address(pair.escrowNFT);
        assertEq(configHub.allCanOpenPair(address(pair.underlying), configHub.ANY_ASSET()), escrowAuthed);
    }

    function testAssetsSanity() public {
        IERC20 asset1 = IERC20(cashAsset);
        IERC20 asset2 = IERC20(underlying);
        // 0 transfer works
        asset1.transfer(user, 0);
        asset2.transfer(user, 0);
        // 0 approval works
        asset1.approve(user, 0);
        asset2.approve(user, 0);

        // get some tokens
        deal(address(asset1), address(this), 10);
        deal(address(asset2), address(this), 10);
        // balance sanity
        uint balanceBefore = asset1.balanceOf(address(this));
        asset1.transfer(user, 1);
        assertEq(asset1.balanceOf(address(this)), balanceBefore - 1);
        balanceBefore = asset2.balanceOf(address(this));
        asset2.transfer(user, 1);
        assertEq(asset2.balanceOf(address(this)), balanceBefore - 1);

        // no transfer "max"
        vm.expectRevert();
        asset1.transfer(user, type(uint).max);
        vm.expectRevert();
        asset1.transfer(user, type(uint128).max);
        vm.expectRevert();
        asset2.transfer(user, type(uint).max);
        vm.expectRevert();
        asset2.transfer(user, type(uint128).max);
    }

    function testOraclePrice() public view {
        uint oraclePrice = pair.oracle.currentPrice();
        (uint a, uint b) = (oraclePrice, expectedOraclePrice);
        uint absDiffRatio = a > b ? (a - b) * BIPS_BASE / b : (b - a) * BIPS_BASE / a;
        // if bigger price is less than 2x the smaller price, we're still in the same range
        // otherwise, either the expected price needs to be updated (hopefully up), or the
        // oracle is misconfigured
        assertLt(absDiffRatio, BIPS_BASE, "prices differ by more than 2x");

        assertEq(oraclePrice, pair.takerNFT.currentOraclePrice());
    }

    function testOpenAndCloseLoan() public {
        uint providerBalanceBefore = pair.cashAsset.balanceOf(provider);
        uint offerId = createProviderOffer(callstrikeToUse, offerAmount);
        assertEq(pair.cashAsset.balanceOf(provider), providerBalanceBefore - offerAmount);
        uint feeRecipientBalanceBefore = pair.cashAsset.balanceOf(protocolFeeRecipient);

        (uint loanId,, uint loanAmount) = openLoan(offerId);
        // Verify fee taken and sent to recipient
        uint expectedFee = getProviderProtocolFeeByLoanAmount(loanAmount);
        assertEq(pair.cashAsset.balanceOf(protocolFeeRecipient) - feeRecipientBalanceBefore, expectedFee);
        checkLoanAmount(loanAmount);
        skip(duration);
        ICollarTakerNFT.TakerPosition memory position = pair.takerNFT.getPosition(loanId);
        uint currentPrice = pair.oracle.currentPrice();
        (uint takerWithdrawal,) = pair.takerNFT.previewSettlement(position, currentPrice);

        closeAndCheckLoan(loanId, loanAmount, loanAmount + takerWithdrawal, currentPrice, 0);
    }

    function testOpenEscrowLoan() public {
        uint escrowSupplierUnderlyingBefore = pair.underlying.balanceOf(escrowSupplier);
        (uint offerId, uint escrowOfferId) = createEscrowOffers();
        uint feeRecipientBalanceBefore = pair.cashAsset.balanceOf(protocolFeeRecipient);
        (uint loanId,, uint loanAmount) = executeEscrowLoan(offerId, escrowOfferId);
        uint expectedProtocolFee = getProviderProtocolFeeByLoanAmount(loanAmount);
        verifyEscrowLoan(
            loanId,
            loanAmount,
            escrowOfferId,
            feeRecipientBalanceBefore,
            escrowSupplierUnderlyingBefore,
            expectedProtocolFee
        );
    }

    function testOpenAndCloseEscrowLoan() public {
        //  create provider and escrow offers
        (uint offerId, uint escrowOfferId) = createEscrowOffers();
        (uint loanId,, uint loanAmount) = executeEscrowLoan(offerId, escrowOfferId);
        ILoansNFT.Loan memory loanBefore = pair.loansContract.getLoan(loanId);

        uint escrowSupplierBefore = pair.underlying.balanceOf(escrowSupplier);
        uint userBefore = pair.underlying.balanceOf(user);
        (, uint interestFeeHeld, uint lateFeeHeld) =
            pair.escrowNFT.upfrontFees(escrowOfferId, underlyingAmount);

        // Skip to expiry
        skip(duration);

        ICollarTakerNFT.TakerPosition memory position = pair.takerNFT.getPosition(loanId);
        uint currentPrice = pair.oracle.currentPrice();
        (uint takerWithdrawal,) = pair.takerNFT.previewSettlement(position, currentPrice);

        uint underlyingOut =
            closeAndCheckLoan(loanId, loanAmount, loanAmount + takerWithdrawal, currentPrice, lateFeeHeld);

        // Check escrow position's withdrawable amount (underlying + interest)
        uint withdrawable = pair.escrowNFT.getEscrow(loanBefore.escrowId).withdrawable;
        assertEq(withdrawable, underlyingAmount + interestFeeHeld);

        // Execute withdrawal and verify balance change
        vm.startPrank(escrowSupplier);
        pair.escrowNFT.withdrawReleased(loanBefore.escrowId);
        vm.stopPrank();

        assertEq(
            pair.underlying.balanceOf(escrowSupplier) - escrowSupplierBefore,
            underlyingAmount + interestFeeHeld
        );
        assertEq(pair.underlying.balanceOf(user) - userBefore, underlyingOut);
    }

    // stack too deep
    struct MemoryVars {
        uint loanId;
        uint providerId;
        address escrowSupplier2;
        uint escrowSupplier1Before;
        uint userUnderlyingBeforeRoll;
        uint escrowSupplier2Before;
        ILoansNFT.Loan loan;
        uint escrowWithdrawal;
        uint toLoans;
    }

    function testRollEscrowLoanBetweenSuppliers() public {
        // Create first provider and escrow offers
        (uint offerId1, uint escrowOfferId1) = createEscrowOffers();
        (uint escrowFees1,,) = pair.escrowNFT.upfrontFees(escrowOfferId1, underlyingAmount);

        uint userUnderlyingBefore = pair.underlying.balanceOf(user);

        MemoryVars memory mem;
        (mem.loanId, mem.providerId,) = executeEscrowLoan(offerId1, escrowOfferId1);

        // User has paid underlyingAmount + escrowFees1 at this point
        assertEq(userUnderlyingBefore - pair.underlying.balanceOf(user), underlyingAmount + escrowFees1);

        mem.escrowSupplier1Before = pair.underlying.balanceOf(escrowSupplier);

        // Create second escrow supplier
        mem.escrowSupplier2 = makeAddr("escrowSupplier2");
        deal(address(underlying), mem.escrowSupplier2, bigUnderlyingAmount);

        // Skip half the duration to test partial fees
        skip(duration / 2);

        // Get exact refund amount from contract
        mem.loan = pair.loansContract.getLoan(mem.loanId);
        (mem.escrowWithdrawal, mem.toLoans,) = pair.escrowNFT.previewRelease(mem.loan.escrowId, 0);

        // Create second escrow supplier's offer
        vm.startPrank(mem.escrowSupplier2);
        pair.underlying.approve(address(pair.escrowNFT), underlyingAmount);
        uint escrowOfferId2 = pair.escrowNFT.createOffer(
            underlyingAmount,
            duration,
            interestAPR,
            gracePeriod,
            lateFeeAPR,
            0 // minEscrow
        );
        vm.stopPrank();

        // Create roll offer using existing provider position
        uint rollOfferId = createRollOffer(mem.loanId, mem.providerId);
        (uint newEscrowFees,,) = pair.escrowNFT.upfrontFees(escrowOfferId2, underlyingAmount);
        mem.userUnderlyingBeforeRoll = pair.underlying.balanceOf(user);

        vm.startPrank(user);
        int toTaker = pair.rollsContract.previewRoll(rollOfferId, pair.takerNFT.currentOraclePrice()).toTaker;
        // make sure preview roll fee is within 10% of actual roll fee
        assertApproxEqAbs(-toTaker, rollFee, uint(rollFee) * 1000 / 10_000);
        if (toTaker < 0) {
            pair.cashAsset.approve(address(pair.loansContract), uint(-toTaker));
        }
        pair.underlying.approve(address(pair.loansContract), newEscrowFees);
        (uint newLoanId, uint newLoanAmount,) = pair.loansContract.rollLoan(
            mem.loanId,
            ILoansNFT.RollOffer(pair.rollsContract, rollOfferId),
            -1000e6,
            escrowOfferId2,
            newEscrowFees
        );
        vm.stopPrank();

        // Execute withdrawal for first supplier
        vm.startPrank(escrowSupplier);
        pair.escrowNFT.withdrawReleased(mem.loan.escrowId);
        vm.stopPrank();

        // Verify first supplier got partial fees using exact toLoans amount
        // we use Ge because of rounding (seeing 1 wei difference 237823439879 != 237823439878)
        assertGe(pair.underlying.balanceOf(escrowSupplier) - mem.escrowSupplier1Before, mem.escrowWithdrawal);

        // Verify user paid new escrow fee and got refund from old escrow
        assertEq(mem.userUnderlyingBeforeRoll - pair.underlying.balanceOf(user) + mem.toLoans, newEscrowFees);

        // Skip to end of new loan term
        skip(duration);

        // Track second supplier balance before closing
        mem.escrowSupplier2Before = pair.underlying.balanceOf(mem.escrowSupplier2);
        uint newEscrowId = pair.loansContract.getLoan(newLoanId).escrowId;

        uint currentPrice = pair.oracle.currentPrice();
        (uint takerWithdrawal,) =
            pair.takerNFT.previewSettlement(pair.takerNFT.getPosition(newLoanId), currentPrice);
        (uint escrowRefund,,,) = pair.escrowNFT.feesRefunds(newEscrowId);

        closeAndCheckLoan(
            newLoanId, newLoanAmount, newLoanAmount + takerWithdrawal, currentPrice, escrowRefund
        );

        // Execute withdrawal for second supplier
        vm.startPrank(mem.escrowSupplier2);
        pair.escrowNFT.withdrawReleased(newEscrowId);
        vm.stopPrank();

        // Verify second supplier got full amount - refund
        assertEq(
            pair.underlying.balanceOf(mem.escrowSupplier2) - mem.escrowSupplier2Before,
            underlyingAmount + newEscrowFees - escrowRefund
        );
    }

    function testRollLoan() public {
        uint offerId = createProviderOffer(callstrikeToUse, offerAmount);
        (uint loanId, uint providerId, uint initialLoanAmount) = openLoan(offerId);

        uint rollOfferId = createRollOffer(loanId, providerId);

        // Calculate and verify protocol fee based on new position's provider locked amount
        uint newPositionPrice = pair.takerNFT.currentOraclePrice();
        IRolls.PreviewResults memory expectedResults =
            pair.rollsContract.previewRoll(rollOfferId, newPositionPrice);
        assertGt(expectedResults.protocolFee, 0);
        assertGt(expectedResults.toProvider, 0);

        uint providerBalanceBefore = pair.cashAsset.balanceOf(provider);
        uint feeRecipientBalanceBefore = pair.cashAsset.balanceOf(protocolFeeRecipient);
        (uint newLoanId, uint newLoanAmount, int transferAmount) = rollLoan(
            loanId,
            rollOfferId,
            -1000e6 // Allow up to 1000 tokens to be paid by the user
        );

        // Verify fee taken and sent to recipient
        assertEq(
            pair.cashAsset.balanceOf(protocolFeeRecipient) - feeRecipientBalanceBefore,
            expectedResults.protocolFee
        );
        assertEq(int(pair.cashAsset.balanceOf(provider) - providerBalanceBefore), expectedResults.toProvider);
        assertGt(newLoanId, loanId);
        assertGe(int(newLoanAmount), int(initialLoanAmount) + transferAmount);
    }

    function testFullLoanLifecycle() public {
        uint feeRecipientBalanceBefore = pair.cashAsset.balanceOf(protocolFeeRecipient);

        uint offerId = createProviderOffer(callstrikeToUse, offerAmount);

        (uint loanId, uint providerId, uint initialLoanAmount) = openLoan(offerId);
        uint initialFee = getProviderProtocolFeeByLoanAmount(initialLoanAmount);
        // Verify fee taken and sent to recipient
        assertEq(pair.cashAsset.balanceOf(protocolFeeRecipient) - feeRecipientBalanceBefore, initialFee);

        // Advance time
        skip(duration - 20);

        uint recipientBalanceAfterOpenLoan = pair.cashAsset.balanceOf(protocolFeeRecipient);
        uint rollOfferId = createRollOffer(loanId, providerId);

        // Calculate roll protocol fee
        IRolls.PreviewResults memory expectedResults =
            pair.rollsContract.previewRoll(rollOfferId, pair.takerNFT.currentOraclePrice());
        assertGt(expectedResults.protocolFee, 0);
        (uint newLoanId, uint newLoanAmount, int transferAmount) = rollLoan(loanId, rollOfferId, -1000e6);

        assertEq(
            pair.cashAsset.balanceOf(protocolFeeRecipient) - recipientBalanceAfterOpenLoan,
            expectedResults.protocolFee
        );

        // Advance time again
        skip(duration);

        ICollarTakerNFT.TakerPosition memory position = pair.takerNFT.getPosition(newLoanId);
        uint currentPrice = pair.oracle.currentPrice();
        (uint takerWithdrawal,) = pair.takerNFT.previewSettlement(position, currentPrice);

        closeAndCheckLoan(newLoanId, newLoanAmount, newLoanAmount + takerWithdrawal, currentPrice, 0);
        assertGt(initialLoanAmount, 0);
        assertGe(int(newLoanAmount), int(initialLoanAmount) + transferAmount);

        // Verify total protocol fees collected
        assertEq(
            pair.cashAsset.balanceOf(protocolFeeRecipient) - feeRecipientBalanceBefore,
            initialFee + expectedResults.protocolFee
        );
    }

    function testCloseEscrowLoanAfterGracePeriod() public {
        //  create provider and escrow offers
        (uint offerId, uint escrowOfferId) = createEscrowOffers();
        (uint loanId,, uint loanAmount) = executeEscrowLoan(offerId, escrowOfferId);

        ILoansNFT.Loan memory loan = pair.loansContract.getLoan(loanId);
        uint escrowSupplierBefore = pair.underlying.balanceOf(escrowSupplier);
        uint userBefore = pair.underlying.balanceOf(user);
        (, uint interestFeeHeld, uint lateFeeHeld) =
            pair.escrowNFT.upfrontFees(escrowOfferId, underlyingAmount);

        // Skip past expiry
        skip(duration);
        uint expiryPrice = pair.oracle.currentPrice();
        // Get expiry price from oracle
        ICollarTakerNFT.TakerPosition memory position = pair.takerNFT.getPosition(loanId);
        (uint takerWithdrawal,) = pair.takerNFT.previewSettlement(position, expiryPrice);
        // bot settles the position
        pair.takerNFT.settlePairedPosition(loanId);

        // skip past grace period
        skip(gracePeriod + 1);

        uint totalAmountToSwap = loanAmount + takerWithdrawal;
        uint underlyingOut = closeAndCheckLoan(loanId, loanAmount, totalAmountToSwap, expiryPrice, 0);

        // Check escrow position's withdrawable (underlying + interest + late fee)
        uint withdrawable = pair.escrowNFT.getEscrow(loan.escrowId).withdrawable;
        // interest and late fee goes to escrow owner
        assertEq(withdrawable, underlyingAmount + interestFeeHeld + lateFeeHeld);

        // Execute withdrawal and verify balance
        vm.startPrank(escrowSupplier);
        pair.escrowNFT.withdrawReleased(loan.escrowId);
        vm.stopPrank();

        assertEq(
            pair.underlying.balanceOf(escrowSupplier) - escrowSupplierBefore,
            underlyingAmount + interestFeeHeld + lateFeeHeld
        );
        assertEq(pair.underlying.balanceOf(user) - userBefore, underlyingOut);
    }

    function testSeizeEscrowAndUnwrapLoan() public {
        //  create provider and escrow offers
        (uint offerId, uint escrowOfferId) = createEscrowOffers();
        (uint loanId,,) = executeEscrowLoan(offerId, escrowOfferId);

        ILoansNFT.Loan memory loan = pair.loansContract.getLoan(loanId);
        uint escrowSupplierBefore = pair.underlying.balanceOf(escrowSupplier);
        uint userBeforeUnderlying = pair.underlying.balanceOf(user);
        uint userBeforeCash = pair.cashAsset.balanceOf(user);
        (, uint interestFeeHeld, uint lateFeeHeld) =
            pair.escrowNFT.upfrontFees(escrowOfferId, underlyingAmount);

        // Skip past expiry
        skip(duration);
        uint expiryPrice = pair.oracle.currentPrice();
        // Get expiry price from oracle
        ICollarTakerNFT.TakerPosition memory position = pair.takerNFT.getPosition(loanId);
        (uint takerWithdrawal,) = pair.takerNFT.previewSettlement(position, expiryPrice);
        // bot settles the position
        pair.takerNFT.settlePairedPosition(loanId);

        // skip past grace period
        skip(gracePeriod + 1);

        // seize and withdraw from supplier
        vm.startPrank(escrowSupplier);
        pair.escrowNFT.seizeEscrow(loan.escrowId);
        assertEq(
            pair.underlying.balanceOf(escrowSupplier) - escrowSupplierBefore,
            underlyingAmount + interestFeeHeld + lateFeeHeld
        );

        // cancel and withdraw from user
        vm.startPrank(user);
        pair.loansContract.unwrapAndCancelLoan(loanId);
        pair.takerNFT.withdrawFromSettled(loanId);
        assertEq(pair.underlying.balanceOf(user) - userBeforeUnderlying, 0);
        assertEq(pair.cashAsset.balanceOf(user) - userBeforeCash, takerWithdrawal);
    }

    function testCloseEscrowLoanWithPartialLateFees() public {
        //  create provider and escrow offers
        (uint offerId, uint escrowOfferId) = createEscrowOffers();
        (uint loanId,, uint loanAmount) = executeEscrowLoan(offerId, escrowOfferId);

        ILoansNFT.Loan memory loanBefore = pair.loansContract.getLoan(loanId);
        uint escrowSupplierBefore = pair.underlying.balanceOf(escrowSupplier);
        uint userBefore = pair.underlying.balanceOf(user);
        (, uint interestFeeHeld, uint lateFeeHeld) =
            pair.escrowNFT.upfrontFees(escrowOfferId, underlyingAmount);

        // Skip past expiry but only halfway through grace period
        skip(duration);
        uint expiryPrice = pair.oracle.currentPrice();

        // bot settles the position
        pair.takerNFT.settlePairedPosition(loanId);

        skip(gracePeriod / 2);

        // Calculate expected late fee refund
        (,, uint lateFeeRefund,) = pair.escrowNFT.feesRefunds(loanBefore.escrowId);
        assertGt(lateFeeHeld, 0);
        assertEq(lateFeeRefund, lateFeeHeld / 2);
        ICollarTakerNFT.TakerPosition memory position = pair.takerNFT.getPosition(loanId);
        uint takerWithdrawal = position.withdrawable;

        uint underlyingOut =
            closeAndCheckLoan(loanId, loanAmount, loanAmount + takerWithdrawal, expiryPrice, lateFeeHeld);

        // Check escrow position's withdrawable (underlying + interest + partial late fee)
        uint withdrawable = pair.escrowNFT.getEscrow(loanBefore.escrowId).withdrawable;
        uint expectedWithdrawal = underlyingAmount + interestFeeHeld + lateFeeHeld - lateFeeRefund;
        assertEq(withdrawable, expectedWithdrawal);

        // Execute withdrawal and verify balance
        vm.startPrank(escrowSupplier);
        pair.escrowNFT.withdrawReleased(loanBefore.escrowId);
        vm.stopPrank();

        assertEq(pair.underlying.balanceOf(escrowSupplier) - escrowSupplierBefore, expectedWithdrawal);
        assertEq(pair.underlying.balanceOf(user) - userBefore, underlyingOut);
    }
}
