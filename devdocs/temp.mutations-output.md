# Remove after triage

### Mutators reference [from source](https://github.com/crytic/slither/tree/3befc968bcda024b9952aeff8b3a17fd427426de/slither/tools/mutator/mutators): 
- aor - arithmetic op replacement
- asor - assign op rep
- bor - bitwise
- cr - comment rep
- fhr - func header
- lir - literal int
- lor - logical op
- mia - "if" around statement
- mvie - variable init using expression
- mviv - variable init using value
- mwa - while around statement
- ror - relational op
- rr - revert rep
- sbr - solidity expression rep
- uor - unary op

### Unfiltered output:

> `... slither-mutate src/ --test-cmd 'forge test --nmc Fork'`

```
Mutating contract CollarTakerNFT
[AOR] Line 89: 'uint putRange = BIPS_BASE - putStrikePercent' ==> 'uint putRange = BIPS_BASE % putStrikePercent' --> UNCAUGHT
[AOR] Line 90: 'uint callRange = callStrikePercent - BIPS_BASE' ==> 'uint callRange = callStrikePercent % BIPS_BASE' --> UNCAUGHT
[AOR] Line 319: 'uint providerGainRange = startPrice - endPrice' ==> 'uint providerGainRange = startPrice % endPrice' --> UNCAUGHT
[AOR] Line 320: 'uint putRange = startPrice - putStrikePrice' ==> 'uint putRange = startPrice % putStrikePrice' --> UNCAUGHT
[AOR] Line 327: 'uint takerGainRange = endPrice - startPrice' ==> 'uint takerGainRange = endPrice % startPrice' --> UNCAUGHT
[AOR] Line 328: 'uint callRange = callStrikePrice - startPrice' ==> 'uint callRange = callStrikePrice % startPrice' --> UNCAUGHT
[FHR] Line 83: 'function calculateProviderLocked(uint takerLocked, uint putStrikePercent, uint callStrikePercent)
        public
        pure
        returns (uint)
    ' ==> 'function calculateProviderLocked(uint takerLocked, uint putStrikePercent, uint callStrikePercent)
        public
        view
        returns (uint)
    ' --> UNCAUGHT
[FHR] Line 109: 'function previewSettlement(TakerPosition memory position, uint endPrice)
        external
        pure
        returns (uint takerBalance, int providerDelta)
    ' ==> 'function previewSettlement(TakerPosition memory position, uint endPrice)
        external
        view
        returns (uint takerBalance, int providerDelta)
    ' --> UNCAUGHT
[FHR] Line 265: 'function _setOracle(ITakerOracle _oracle) internal ' ==> 'function _setOracle(ITakerOracle _oracle) private ' --> UNCAUGHT
[FHR] Line 292: 'function _strikePrices(uint putStrikePercent, uint callStrikePercent, uint startPrice)
        internal
        pure
        returns (uint putStrikePrice, uint callStrikePrice)
    ' ==> 'function _strikePrices(uint putStrikePercent, uint callStrikePercent, uint startPrice)
        private
        pure
        returns (uint putStrikePrice, uint callStrikePrice)
    ' --> UNCAUGHT
[FHR] Line 301: 'function _settlementCalculations(TakerPosition memory position, uint endPrice)
        internal
        pure
        returns (uint takerBalance, int providerDelta)
    ' ==> 'function _settlementCalculations(TakerPosition memory position, uint endPrice)
        private
        pure
        returns (uint takerBalance, int providerDelta)
    ' --> UNCAUGHT
[MIA] Line 201: 'providerDelta > 0' ==> 'true' --> UNCAUGHT
[ROR] Line 131: 'providerNFT.underlying() == underlying' ==> 'providerNFT.underlying()  <=  underlying' --> UNCAUGHT
[ROR] Line 132: 'providerNFT.cashAsset() == cashAsset' ==> 'providerNFT.cashAsset()  >=  cashAsset' --> UNCAUGHT
[ROR] Line 135: 'offer.duration != 0' ==> 'offer.duration  >  0' --> UNCAUGHT
[ROR] Line 144: 'putStrikePrice < startPrice' ==> 'putStrikePrice  <=  startPrice' --> UNCAUGHT
[ROR] Line 144: 'putStrikePrice < startPrice' ==> 'putStrikePrice  !=  startPrice' --> UNCAUGHT
[ROR] Line 144: 'callStrikePrice > startPrice' ==> 'callStrikePrice  !=  startPrice' --> UNCAUGHT
[ROR] Line 154: 'expiration == providerNFT.expiration(providerId)' ==> 'expiration  >=  providerNFT.expiration(providerId)' --> UNCAUGHT
[ROR] Line 201: 'providerDelta > 0' ==> 'providerDelta  >=  0' --> UNCAUGHT
[ROR] Line 201: 'providerDelta > 0' ==> 'providerDelta  !=  0' --> UNCAUGHT
[ROR] Line 275: '_oracle.currentPrice() != 0' ==> '_oracle.currentPrice()  >  0' --> UNCAUGHT
[ROR] Line 277: 'price != 0' ==> 'price  >  0' --> UNCAUGHT
[ROR] Line 282: '_oracle.convertToBaseAmount(price, price) != 0' ==> '_oracle.convertToBaseAmount(price, price)  >  0' --> UNCAUGHT
[ROR] Line 316: 'endPrice < startPrice' ==> 'endPrice  <=  startPrice' --> UNCAUGHT
[SBR] Line 15: 'uint internal constant BIPS_BASE = 10_000' ==> 'uint internal immutable BIPS_BASE = 10_000' --> UNCAUGHT
[SBR] Line 52: 'TakerPositionStored memory stored = positions[takerId]' ==> 'TakerPositionStored storage stored = positions[takerId]' --> UNCAUGHT
[SBR] Line 77: 'TakerPositionStored storage stored = positions[takerId]' ==> 'TakerPositionStored memory stored = positions[takerId]' --> UNCAUGHT
[SBR] Line 159: 'positions[takerId] = TakerPositionStored({
            providerNFT: providerNFT,
            providerId: SafeCast.toUint64(providerId),
            settled: false, // unset until settlement
            startPrice: startPrice,
            takerLocked: takerLocked,
            withdrawable: 0 // unset until settlement
         })' ==> 'positions[takerId] = TakerPositionStored({
            providerNFT: providerNFT,
            providerId: SafeCast.toUint32(providerId),
            settled: false, // unset until settlement
            startPrice: startPrice,
            takerLocked: takerLocked,
            withdrawable: 0 // unset until settlement
         })' --> UNCAUGHT
[SBR] Line 276: '(uint price,) = _oracle.pastPriceWithFallback(uint32(block.timestamp))' ==> '(uint price,) = _oracle.pastPriceWithFallback(uint16(block.timestamp))' --> UNCAUGHT
Done mutating CollarTakerNFT.
Revert mutants: 0 uncaught of 59 (0.0%)
Comment mutants: 0 uncaught of 59 (0.0%)
Tweak mutants: 30 uncaught of 232 (12.931034482758621%)

Mutating contract SwapperUniV3
[CR] Line 61: 'extraData' ==> '//extraData' --> UNCAUGHT
[ROR] Line 32: '_feeTier == 100' ==> '_feeTier  <=  100' --> UNCAUGHT
[ROR] Line 32: '_feeTier == 500' ==> '_feeTier  <=  500' --> UNCAUGHT
[ROR] Line 32: '_feeTier == 3000' ==> '_feeTier  >=  3000' --> UNCAUGHT
[ROR] Line 32: '_feeTier == 10_000' ==> '_feeTier  >=  10_000' --> UNCAUGHT
Done mutating SwapperUniV3.
Revert mutants: 0 uncaught of 7 (0.0%)
Comment mutants: 1 uncaught of 10 (10.0%)
Tweak mutants: 4 uncaught of 38 (10.526315789473685%)

Mutating contract CollarProviderNFT
[MIA] Line 194: 'newAmount < previousAmount' ==> 'true' --> UNCAUGHT
[ROR] Line 159: 'callStrikePercent >= MIN_CALL_STRIKE_BIPS' ==> 'callStrikePercent  >  MIN_CALL_STRIKE_BIPS' --> UNCAUGHT
[ROR] Line 160: 'callStrikePercent <= MAX_CALL_STRIKE_BIPS' ==> 'callStrikePercent  <  MAX_CALL_STRIKE_BIPS' --> UNCAUGHT
[ROR] Line 161: 'putStrikePercent <= MAX_PUT_STRIKE_BIPS' ==> 'putStrikePercent  <  MAX_PUT_STRIKE_BIPS' --> UNCAUGHT
[ROR] Line 189: 'newAmount > previousAmount' ==> 'newAmount  >=  previousAmount' --> UNCAUGHT
[ROR] Line 194: 'newAmount < previousAmount' ==> 'newAmount  <=  previousAmount' --> UNCAUGHT
[ROR] Line 194: 'newAmount < previousAmount' ==> 'newAmount  !=  previousAmount' --> UNCAUGHT
[ROR] Line 266: 'fee != 0' ==> 'fee  >  0' --> UNCAUGHT
[ROR] Line 289: 'position.expiration != 0' ==> 'position.expiration  >  0' --> UNCAUGHT
[ROR] Line 297: 'cashDelta > 0' ==> 'cashDelta  >=  0' --> UNCAUGHT
[ROR] Line 324: 'position.expiration != 0' ==> 'position.expiration  >  0' --> UNCAUGHT
[SBR] Line 43: 'uint public constant MIN_CALL_STRIKE_BIPS = BIPS_BASE + 1' ==> 'uint public immutable MIN_CALL_STRIKE_BIPS = BIPS_BASE + 1' --> UNCAUGHT
[SBR] Line 44: 'uint public constant MAX_CALL_STRIKE_BIPS = 10 * BIPS_BASE' ==> 'uint public immutable MAX_CALL_STRIKE_BIPS = 10 * BIPS_BASE' --> UNCAUGHT
[SBR] Line 45: 'uint public constant MAX_PUT_STRIKE_BIPS = BIPS_BASE - 1' ==> 'uint public immutable MAX_PUT_STRIKE_BIPS = BIPS_BASE - 1' --> UNCAUGHT
[SBR] Line 93: 'ProviderPositionStored memory stored = positions[positionId]' ==> 'ProviderPositionStored storage stored = positions[positionId]' --> UNCAUGHT
[SBR] Line 116: 'LiquidityOfferStored memory stored = liquidityOffers[offerId]' ==> 'LiquidityOfferStored storage stored = liquidityOffers[offerId]' --> UNCAUGHT
[SBR] Line 164: 'liquidityOffers[offerId] = LiquidityOfferStored({
            provider: msg.sender,
            putStrikePercent: SafeCast.toUint24(putStrikePercent),
            callStrikePercent: SafeCast.toUint24(callStrikePercent),
            duration: SafeCast.toUint32(duration),
            minLocked: minLocked,
            available: amount
        })' ==> 'liquidityOffers[offerId] = LiquidityOfferStored({
            provider: msg.sender,
            putStrikePercent: SafeCast.toUint24(putStrikePercent),
            callStrikePercent: SafeCast.toUint24(callStrikePercent),
            duration: SafeCast.toUint16(duration),
            minLocked: minLocked,
            available: amount
        })' --> UNCAUGHT
[SBR] Line 246: 'positions[positionId] = ProviderPositionStored({
            offerId: SafeCast.toUint64(offerId),
            takerId: SafeCast.toUint64(takerId),
            expiration: SafeCast.toUint32(block.timestamp + offer.duration),
            settled: false, // unset until settlement
            providerLocked: providerLocked,
            withdrawable: 0 // unset until settlement
         })' ==> 'positions[positionId] = ProviderPositionStored({
            offerId: SafeCast.toUint32(offerId),
            takerId: SafeCast.toUint32(takerId),
            expiration: SafeCast.toUint32(block.timestamp + offer.duration),
            settled: false, // unset until settlement
            providerLocked: providerLocked,
            withdrawable: 0 // unset until settlement
         })' --> UNCAUGHT
Done mutating CollarProviderNFT.
Revert mutants: 0 uncaught of 58 (0.0%)
Comment mutants: 0 uncaught of 59 (0.0%)
Tweak mutants: 18 uncaught of 219 (8.219178082191782%)

Mutating contract LoansNFT
[CR] Line 214: 'whenNotPaused' ==> '//whenNotPaused' --> UNCAUGHT
[CR] Line 286: 'whenNotPaused' ==> '//whenNotPaused' --> UNCAUGHT
[CR] Line 411: 'underlying.safeTransfer(borrower, toBorrower)' ==> '//underlying.safeTransfer(borrower, toBorrower)' --> UNCAUGHT
[CR] Line 477: 'escrowFee = usesEscrow ? escrowFee : 0' ==> '//escrowFee = usesEscrow ? escrowFee : 0' --> UNCAUGHT
[AOR] Line 738: 'uint leftOver = fromSwap - toEscrow' ==> 'uint leftOver = fromSwap % toEscrow' --> UNCAUGHT
[AOR] Line 748: 'underlyingOut = fromEscrow + leftOver' ==> 'underlyingOut = fromEscrow - leftOver' --> UNCAUGHT
[FHR] Line 462: 'function _openLoan(
        uint underlyingAmount,
        uint minLoanAmount,
        SwapParams calldata swapParams,
        ProviderOffer calldata providerOffer,
        bool usesEscrow,
        EscrowOffer memory escrowOffer,
        uint escrowFee
    ) internal returns (uint loanId, uint providerId, uint loanAmount) ' ==> 'function _openLoan(
        uint underlyingAmount,
        uint minLoanAmount,
        SwapParams calldata swapParams,
        ProviderOffer calldata providerOffer,
        bool usesEscrow,
        EscrowOffer memory escrowOffer,
        uint escrowFee
    ) private returns (uint loanId, uint providerId, uint loanAmount) ' --> UNCAUGHT
[FHR] Line 522: 'function _swapAndMintCollar(
        uint underlyingAmount,
        ProviderOffer calldata offer,
        SwapParams calldata swapParams
    ) internal returns (uint takerId, uint providerId, uint loanAmount) ' ==> 'function _swapAndMintCollar(
        uint underlyingAmount,
        ProviderOffer calldata offer,
        SwapParams calldata swapParams
    ) private returns (uint takerId, uint providerId, uint loanAmount) ' --> UNCAUGHT
[FHR] Line 568: 'function _swap(IERC20 assetIn, IERC20 assetOut, uint amountIn, SwapParams calldata swapParams)
        internal
        returns (uint amountOut)
    ' ==> 'function _swap(IERC20 assetIn, IERC20 assetOut, uint amountIn, SwapParams calldata swapParams)
        private
        returns (uint amountOut)
    ' --> UNCAUGHT
[FHR] Line 602: 'function _settleAndWithdrawTaker(uint loanId) internal returns (uint withdrawnAmount) ' ==> 'function _settleAndWithdrawTaker(uint loanId) private returns (uint withdrawnAmount) ' --> UNCAUGHT
[FHR] Line 616: 'function _executeRoll(uint loanId, RollOffer calldata rollOffer, int minToUser)
        internal
        returns (uint newTakerId, int toTaker, int rollFee)
    ' ==> 'function _executeRoll(uint loanId, RollOffer calldata rollOffer, int minToUser)
        private
        returns (uint newTakerId, int toTaker, int rollFee)
    ' --> UNCAUGHT
[FHR] Line 665: 'function _conditionalOpenEscrow(bool usesEscrow, uint escrowed, EscrowOffer memory offer, uint fee)
        internal
        returns (EscrowSupplierNFT escrowNFT, uint escrowId)
    ' ==> 'function _conditionalOpenEscrow(bool usesEscrow, uint escrowed, EscrowOffer memory offer, uint fee)
        private
        returns (EscrowSupplierNFT escrowNFT, uint escrowId)
    ' --> UNCAUGHT
[FHR] Line 691: 'function _conditionalSwitchEscrow(Loan memory prevLoan, uint offerId, uint newLoanId, uint newFee)
        internal
        returns (uint newEscrowId)
    ' ==> 'function _conditionalSwitchEscrow(Loan memory prevLoan, uint offerId, uint newLoanId, uint newFee)
        private
        returns (uint newEscrowId)
    ' --> UNCAUGHT
[FHR] Line 720: 'function _conditionalReleaseEscrow(Loan memory loan, uint fromSwap)
        internal
        returns (uint underlyingOut)
    ' ==> 'function _conditionalReleaseEscrow(Loan memory loan, uint fromSwap)
        private
        returns (uint underlyingOut)
    ' --> UNCAUGHT
[FHR] Line 728: 'function _releaseEscrow(EscrowSupplierNFT escrowNFT, uint escrowId, uint fromSwap)
        internal
        returns (uint underlyingOut)
    ' ==> 'function _releaseEscrow(EscrowSupplierNFT escrowNFT, uint escrowId, uint fromSwap)
        private
        returns (uint underlyingOut)
    ' --> UNCAUGHT
[FHR] Line 753: 'function _conditionalCheckAndCancelEscrow(uint loanId, address refundRecipient) internal ' ==> 'function _conditionalCheckAndCancelEscrow(uint loanId, address refundRecipient) private ' --> UNCAUGHT
[FHR] Line 799: 'function _isSenderOrKeeperFor(address authorizedSender) internal view returns (bool) ' ==> 'function _isSenderOrKeeperFor(address authorizedSender) private view returns (bool) ' --> UNCAUGHT
[FHR] Line 807: 'function _newLoanIdCheck(uint takerId) internal view returns (uint loanId) ' ==> 'function _newLoanIdCheck(uint takerId) private view returns (uint loanId) ' --> UNCAUGHT
[FHR] Line 818: 'function _takerId(uint loanId) internal pure returns (uint takerId) ' ==> 'function _takerId(uint loanId) internal view returns (uint takerId) ' --> UNCAUGHT
[FHR] Line 818: 'function _takerId(uint loanId) internal pure returns (uint takerId) ' ==> 'function _takerId(uint loanId) private pure returns (uint takerId) ' --> UNCAUGHT
[FHR] Line 823: 'function _expiration(uint loanId) internal view returns (uint expiration) ' ==> 'function _expiration(uint loanId) private view returns (uint expiration) ' --> UNCAUGHT
[FHR] Line 827: 'function _loanAmountAfterRoll(int fromRollsToUser, int rollFee, uint prevLoanAmount)
        internal
        pure
        returns (uint newLoanAmount)
    ' ==> 'function _loanAmountAfterRoll(int fromRollsToUser, int rollFee, uint prevLoanAmount)
        internal
        view
        returns (uint newLoanAmount)
    ' --> UNCAUGHT
[FHR] Line 827: 'function _loanAmountAfterRoll(int fromRollsToUser, int rollFee, uint prevLoanAmount)
        internal
        pure
        returns (uint newLoanAmount)
    ' ==> 'function _loanAmountAfterRoll(int fromRollsToUser, int rollFee, uint prevLoanAmount)
        private
        pure
        returns (uint newLoanAmount)
    ' --> UNCAUGHT
[FHR] Line 853: 'function _escrowValidations(uint loanId, EscrowSupplierNFT escrowNFT, uint escrowId) internal view ' ==> 'function _escrowValidations(uint loanId, EscrowSupplierNFT escrowNFT, uint escrowId) private view ' --> UNCAUGHT
[MIA] Line 607: '!settled' ==> 'true' --> UNCAUGHT
[MVIE] Line 144: 'EscrowOffer memory noEscrow = ' ==> 'EscrowOffer memory noEscrow ' --> UNCAUGHT
[MVIE] Line 738: 'uint leftOver = ' ==> 'uint leftOver ' --> UNCAUGHT
[ROR] Line 390: 'block.timestamp > gracePeriodEnd' ==> 'block.timestamp  !=  gracePeriodEnd' --> UNCAUGHT
[ROR] Line 449: 'bytes(ISwapper(swapper).VERSION()).length > 0' ==> 'bytes(ISwapper(swapper).VERSION()).length  !=  0' --> UNCAUGHT
[ROR] Line 493: 'loanAmount >= minLoanAmount' ==> 'loanAmount  >  minLoanAmount' --> UNCAUGHT
[ROR] Line 537: 'underlyingAmount != 0' ==> 'underlyingAmount  >  0' --> UNCAUGHT
[ROR] Line 597: 'amountOut == amountOutSwapper' ==> 'amountOut  <=  amountOutSwapper' --> UNCAUGHT
[ROR] Line 634: 'preview.toTaker < 0' ==> 'preview.toTaker  <=  0' --> UNCAUGHT
[ROR] Line 653: 'toTaker > 0' ==> 'toTaker  >=  0' --> UNCAUGHT
[ROR] Line 660: 'cashAsset.balanceOf(address(this)) == initialBalance' ==> 'cashAsset.balanceOf(address(this))  <=  initialBalance' --> UNCAUGHT
[ROR] Line 672: 'escrowNFT.asset() == underlying' ==> 'escrowNFT.asset()  <=  underlying' --> UNCAUGHT
[ROR] Line 779: 'block.timestamp <= _expiration(loanId)' ==> 'block.timestamp  <  _expiration(loanId)' --> UNCAUGHT
[ROR] Line 815: 'loans[loanId].underlyingAmount == 0' ==> 'loans[loanId].underlyingAmount  <=  0' --> UNCAUGHT
[ROR] Line 839: 'loanChange < 0' ==> 'loanChange  <=  0' --> UNCAUGHT
[ROR] Line 841: 'repayment <= prevLoanAmount' ==> 'repayment  <  prevLoanAmount' --> UNCAUGHT
[ROR] Line 859: 'escrow.loanId == loanId' ==> 'escrow.loanId  >=  loanId' --> UNCAUGHT
[SBR] Line 38: 'uint internal constant BIPS_BASE = 10_000' ==> 'uint internal immutable BIPS_BASE = 10_000' --> UNCAUGHT
[SBR] Line 83: 'LoanStored memory stored = loans[loanId]' ==> 'LoanStored storage stored = loans[loanId]' --> UNCAUGHT
[SBR] Line 316: 'loans[newLoanId] = LoanStored({
            underlyingAmount: prevLoan.underlyingAmount,
            loanAmount: newLoanAmount,
            usesEscrow: prevLoan.usesEscrow,
            escrowNFT: prevLoan.escrowNFT,
            escrowId: SafeCast.toUint64(newEscrowId)
        })' ==> 'loans[newLoanId] = LoanStored({
            underlyingAmount: prevLoan.underlyingAmount,
            loanAmount: newLoanAmount,
            usesEscrow: prevLoan.usesEscrow,
            escrowNFT: prevLoan.escrowNFT,
            escrowId: SafeCast.toUint32(newEscrowId)
        })' --> UNCAUGHT
[SBR] Line 504: 'loans[loanId] = LoanStored({
            underlyingAmount: underlyingAmount,
            loanAmount: loanAmount,
            usesEscrow: usesEscrow,
            escrowNFT: escrowNFT,
            escrowId: SafeCast.toUint64(escrowId)
        })' ==> 'loans[loanId] = LoanStored({
            underlyingAmount: underlyingAmount,
            loanAmount: loanAmount,
            usesEscrow: usesEscrow,
            escrowNFT: escrowNFT,
            escrowId: SafeCast.toUint32(escrowId)
        })' --> UNCAUGHT
Done mutating LoansNFT.
Revert mutants: 0 uncaught of 100 (0.0%)
Comment mutants: 4 uncaught of 100 (4.0%)
Tweak mutants: 41 uncaught of 294 (13.945578231292517%)

Mutating contract ConfigHub
[ROR] Line 84: 'max <= MAX_CONFIGURABLE_DURATION' ==> 'max  <  MAX_CONFIGURABLE_DURATION' --> UNCAUGHT
[ROR] Line 110: 'apr == 0' ==> 'apr  <=  0' --> UNCAUGHT
[SBR] Line 17: 'IERC20 public constant ANY_ASSET = IERC20(address(type(uint160).max))' ==> 'IERC20 public immutable ANY_ASSET = IERC20(address(type(uint160).max))' --> UNCAUGHT
[SBR] Line 20: 'uint public constant MAX_PROTOCOL_FEE_BIPS = BIPS_BASE / 100' ==> 'uint public immutable MAX_PROTOCOL_FEE_BIPS = BIPS_BASE / 100' --> UNCAUGHT
[SBR] Line 21: 'uint public constant MIN_CONFIGURABLE_LTV_BIPS = BIPS_BASE / 10' ==> 'uint public immutable MIN_CONFIGURABLE_LTV_BIPS = BIPS_BASE / 10' --> UNCAUGHT
[SBR] Line 22: 'uint public constant MAX_CONFIGURABLE_LTV_BIPS = BIPS_BASE - 1' ==> 'uint public immutable MAX_CONFIGURABLE_LTV_BIPS = BIPS_BASE - 1' --> UNCAUGHT
[SBR] Line 23: 'uint public constant MIN_CONFIGURABLE_DURATION = 300' ==> 'uint public immutable MIN_CONFIGURABLE_DURATION = 300' --> UNCAUGHT
[SBR] Line 24: 'uint public constant MAX_CONFIGURABLE_DURATION = 5 * 365 days' ==> 'uint public immutable MAX_CONFIGURABLE_DURATION = 5 * 365 days' --> UNCAUGHT
[SBR] Line 86: 'minDuration = SafeCast.toUint32(min)' ==> 'minDuration = SafeCast.toUint16(min)' --> UNCAUGHT
[SBR] Line 112: 'protocolFeeAPR = SafeCast.toUint16(apr)' ==> 'protocolFeeAPR = SafeCast.toUint8(apr)' --> UNCAUGHT
Done mutating ConfigHub.
Revert mutants: 0 uncaught of 26 (0.0%)
Comment mutants: 0 uncaught of 27 (0.0%)
Tweak mutants: 10 uncaught of 115 (8.695652173913043%)

Mutating contract Rolls
[FHR] Line 102: 'function calculateRollFee(RollOffer memory offer, uint price) public pure returns (int rollFee) ' ==> 'function calculateRollFee(RollOffer memory offer, uint price) public view returns (int rollFee) ' --> UNCAUGHT
[FHR] Line 286: 'function _executeRoll(RollOffer memory offer, PreviewResults memory preview)
        internal
        returns (uint newTakerId, uint newProviderId)
    ' ==> 'function _executeRoll(RollOffer memory offer, PreviewResults memory preview)
        private
        returns (uint newTakerId, uint newProviderId)
    ' --> UNCAUGHT
[FHR] Line 316: 'function _cancelPairedPositionAndWithdraw(uint takerId, ICollarTakerNFT.TakerPosition memory takerPos)
        internal
    ' ==> 'function _cancelPairedPositionAndWithdraw(uint takerId, ICollarTakerNFT.TakerPosition memory takerPos)
        private
    ' --> UNCAUGHT
[FHR] Line 330: 'function _openNewPairedPosition(PreviewResults memory preview)
        internal
        returns (uint newTakerId, uint newProviderId)
    ' ==> 'function _openNewPairedPosition(PreviewResults memory preview)
        private
        returns (uint newTakerId, uint newProviderId)
    ' --> UNCAUGHT
[FHR] Line 361: 'function _previewRoll(ICollarTakerNFT.TakerPosition memory takerPos, uint newPrice, int rollFee)
        internal
        view
        returns (PreviewResults memory)
    ' ==> 'function _previewRoll(ICollarTakerNFT.TakerPosition memory takerPos, uint newPrice, int rollFee)
        private
        view
        returns (PreviewResults memory)
    ' --> UNCAUGHT
[FHR] Line 418: 'function _newLockedAmounts(ICollarTakerNFT.TakerPosition memory takerPos, uint newPrice)
        internal
        view
        returns (uint newTakerLocked, uint newProviderLocked)
    ' ==> 'function _newLockedAmounts(ICollarTakerNFT.TakerPosition memory takerPos, uint newPrice)
        private
        view
        returns (uint newTakerLocked, uint newProviderLocked)
    ' --> UNCAUGHT
[LIR] Line 55: 'uint public nextRollId = 1' ==> 'uint public nextRollId = 0' --> UNCAUGHT
[MVIV] Line 55: 'uint public nextRollId = ' ==> 'uint public nextRollId ' --> UNCAUGHT
[ROR] Line 131: 'offer.feeReferencePrice != 0' ==> 'offer.feeReferencePrice  >  0' --> UNCAUGHT
[ROR] Line 170: 'takerPos.expiration != 0' ==> 'takerPos.expiration  >  0' --> UNCAUGHT
[ROR] Line 180: 'minPrice <= maxPrice' ==> 'minPrice  <  maxPrice' --> UNCAUGHT
[ROR] Line 181: 'SignedMath.abs(feeDeltaFactorBIPS) <= BIPS_BASE' ==> 'SignedMath.abs(feeDeltaFactorBIPS)  <  BIPS_BASE' --> UNCAUGHT
[ROR] Line 182: 'block.timestamp <= deadline' ==> 'block.timestamp  <  deadline' --> UNCAUGHT
[ROR] Line 262: 'block.timestamp <= offer.deadline' ==> 'block.timestamp  <  offer.deadline' --> UNCAUGHT
[ROR] Line 277: 'toProvider >= offer.minToProvider' ==> 'toProvider  >  offer.minToProvider' --> UNCAUGHT
[ROR] Line 300: 'toTaker < 0' ==> 'toTaker  <=  0' --> UNCAUGHT
[ROR] Line 302: 'toProvider < 0' ==> 'toProvider  <=  0' --> UNCAUGHT
[ROR] Line 308: 'toTaker > 0' ==> 'toTaker  >=  0' --> UNCAUGHT
[ROR] Line 309: 'toProvider > 0' ==> 'toProvider  >=  0' --> UNCAUGHT
[ROR] Line 327: 'withdrawn == expectedAmount' ==> 'withdrawn  >=  expectedAmount' --> UNCAUGHT
[SBR] Line 45: 'uint internal constant BIPS_BASE = 10_000' ==> 'uint internal immutable BIPS_BASE = 10_000' --> UNCAUGHT
[SBR] Line 73: 'RollOfferStored memory stored = rollOffers[rollId]' ==> 'RollOfferStored storage stored = rollOffers[rollId]' --> UNCAUGHT
[SBR] Line 189: 'rollOffers[rollId] = RollOfferStored({
            providerNFT: providerNFT,
            providerId: SafeCast.toUint64(providerId),
            deadline: SafeCast.toUint32(deadline),
            takerId: SafeCast.toUint64(takerId),
            feeDeltaFactorBIPS: SafeCast.toInt24(feeDeltaFactorBIPS),
            active: true,
            provider: msg.sender,
            feeAmount: feeAmount,
            feeReferencePrice: takerNFT.currentOraclePrice(), // the roll offer fees are for current price
            minPrice: minPrice,
            maxPrice: maxPrice,
            minToProvider: minToProvider
        })' ==> 'rollOffers[rollId] = RollOfferStored({
            providerNFT: providerNFT,
            providerId: SafeCast.toUint32(providerId),
            deadline: SafeCast.toUint32(deadline),
            takerId: SafeCast.toUint32(takerId),
            feeDeltaFactorBIPS: SafeCast.toInt24(feeDeltaFactorBIPS),
            active: true,
            provider: msg.sender,
            feeAmount: feeAmount,
            feeReferencePrice: takerNFT.currentOraclePrice(), // the roll offer fees are for current price
            minPrice: minPrice,
            maxPrice: maxPrice,
            minToProvider: minToProvider
        })' --> UNCAUGHT
Done mutating Rolls.
Revert mutants: 0 uncaught of 49 (0.0%)
Comment mutants: 0 uncaught of 50 (0.0%)
Tweak mutants: 23 uncaught of 210 (10.952380952380953%)

Mutating contract EscrowSupplierNFT
[FHR] Line 429: 'function _startEscrow(uint offerId, uint escrowed, uint fee, uint loanId)
        internal
        returns (uint escrowId)
    ' ==> 'function _startEscrow(uint offerId, uint escrowed, uint fee, uint loanId)
        private
        returns (uint escrowId)
    ' --> UNCAUGHT
[FHR] Line 476: 'function _endEscrow(uint escrowId, Escrow memory escrow, uint fromLoans)
        internal
        returns (uint toLoans)
    ' ==> 'function _endEscrow(uint escrowId, Escrow memory escrow, uint fromLoans)
        private
        returns (uint toLoans)
    ' --> UNCAUGHT
[FHR] Line 496: 'function _releaseCalculations(Escrow memory escrow, uint fromLoans)
        internal
        view
        returns (uint withdrawal, uint toLoans, uint interestRefund)
    ' ==> 'function _releaseCalculations(Escrow memory escrow, uint fromLoans)
        private
        view
        returns (uint withdrawal, uint toLoans, uint interestRefund)
    ' --> UNCAUGHT
[FHR] Line 540: 'function _lateFee(Escrow memory escrow) internal view returns (uint) ' ==> 'function _lateFee(Escrow memory escrow) private view returns (uint) ' --> UNCAUGHT
[FHR] Line 552: 'function _interestFeeRefund(Escrow memory escrow) internal view returns (uint refund) ' ==> 'function _interestFeeRefund(Escrow memory escrow) private view returns (uint refund) ' --> UNCAUGHT
[MIA] Line 246: 'newAmount < previousAmount' ==> 'true' --> UNCAUGHT
[MVIE] Line 505: 'uint lateFee = ' ==> 'uint lateFee ' --> UNCAUGHT
[ROR] Line 99: 'stored.expiration != 0' ==> 'stored.expiration  >  0' --> UNCAUGHT
[ROR] Line 144: 'escrow.escrowed != 0' ==> 'escrow.escrowed  >  0' --> UNCAUGHT
[ROR] Line 144: 'escrow.escrowed != 0' ==> 'escrow.escrowed  >=  0' --> UNCAUGHT
[ROR] Line 144: 'escrow.lateFeeAPR != 0' ==> 'escrow.lateFeeAPR  >  0' --> UNCAUGHT
[ROR] Line 211: 'maxGracePeriod >= MIN_GRACE_PERIOD' ==> 'maxGracePeriod  >  MIN_GRACE_PERIOD' --> UNCAUGHT
[ROR] Line 241: 'newAmount > previousAmount' ==> 'newAmount  >=  previousAmount' --> UNCAUGHT
[ROR] Line 246: 'newAmount < previousAmount' ==> 'newAmount  <=  previousAmount' --> UNCAUGHT
[ROR] Line 246: 'newAmount < previousAmount' ==> 'newAmount  !=  previousAmount' --> UNCAUGHT
[ROR] Line 402: 'block.timestamp > gracePeriodEnd' ==> 'block.timestamp  !=  gracePeriodEnd' --> UNCAUGHT
[SBR] Line 39: 'uint internal constant YEAR = 365 days' ==> 'uint internal immutable YEAR = 365 days' --> UNCAUGHT
[SBR] Line 41: 'uint public constant MAX_INTEREST_APR_BIPS = BIPS_BASE' ==> 'uint public immutable MAX_INTEREST_APR_BIPS = BIPS_BASE' --> UNCAUGHT
[SBR] Line 42: 'uint public constant MAX_LATE_FEE_APR_BIPS = BIPS_BASE * 12' ==> 'uint public immutable MAX_LATE_FEE_APR_BIPS = BIPS_BASE * 12' --> UNCAUGHT
[SBR] Line 43: 'uint public constant MIN_GRACE_PERIOD = 1 days' ==> 'uint public immutable MIN_GRACE_PERIOD = 1 days' --> UNCAUGHT
[SBR] Line 44: 'uint public constant MAX_GRACE_PERIOD = 30 days' ==> 'uint public immutable MAX_GRACE_PERIOD = 30 days' --> UNCAUGHT
[SBR] Line 82: 'OfferStored memory stored = offers[offerId]' ==> 'OfferStored storage stored = offers[offerId]' --> UNCAUGHT
[SBR] Line 96: 'EscrowStored memory stored = escrows[escrowId]' ==> 'EscrowStored storage stored = escrows[escrowId]' --> UNCAUGHT
[SBR] Line 250: 'asset.safeTransfer(msg.sender, toRemove)' ==> 'asset.safeTransfer(tx.origin, toRemove)' --> UNCAUGHT
[SBR] Line 456: 'escrows[escrowId] = EscrowStored({
            offerId: SafeCast.toUint64(offerId),
            loanId: SafeCast.toUint64(loanId),
            expiration: SafeCast.toUint32(block.timestamp + offer.duration),
            released: false, // unset until release
            loans: msg.sender,
            escrowed: escrowed,
            interestHeld: fee,
            withdrawable: 0 // unset until release
         })' ==> 'escrows[escrowId] = EscrowStored({
            offerId: SafeCast.toUint32(offerId),
            loanId: SafeCast.toUint32(loanId),
            expiration: SafeCast.toUint32(block.timestamp + offer.duration),
            released: false, // unset until release
            loans: msg.sender,
            escrowed: escrowed,
            interestHeld: fee,
            withdrawable: 0 // unset until release
         })' --> UNCAUGHT
Done mutating EscrowSupplierNFT.
Revert mutants: 0 uncaught of 78 (0.0%)
Comment mutants: 0 uncaught of 78 (0.0%)
Tweak mutants: 25 uncaught of 332 (7.530120481927711%)

Mutating contract OracleUniV3TWAP
[AOR] Line 114: 'return answer == 0 && block.timestamp - startedAt >= atLeast' ==> 'return answer == 0 && block.timestamp % startedAt >= atLeast' --> UNCAUGHT
[ROR] Line 84: 'baseUnitAmount <= type(uint128).max' ==> 'baseUnitAmount  <  type(uint128).max' --> UNCAUGHT
[ROR] Line 114: 'answer == 0' ==> 'answer  <=  0' --> UNCAUGHT
[ROR] Line 200: 'tickCumulativesDelta < 0' ==> 'tickCumulativesDelta  <=  0' --> UNCAUGHT
[ROR] Line 200: 'tickCumulativesDelta < 0' ==> 'tickCumulativesDelta  !=  0' --> UNCAUGHT
[ROR] Line 200: 'tickCumulativesDelta % int56(uint56(twapWindow)) != 0' ==> 'tickCumulativesDelta % int56(uint56(twapWindow))  <  0' --> UNCAUGHT
[SBR] Line 57: 'uint32 public constant MIN_TWAP_WINDOW = 300' ==> 'uint32 public immutable MIN_TWAP_WINDOW = 300' --> UNCAUGHT
[SBR] Line 57: 'uint32 public constant MIN_TWAP_WINDOW = 300' ==> 'uint16 public constant MIN_TWAP_WINDOW = 300' --> UNCAUGHT
[SBR] Line 84: 'require(baseUnitAmount <= type(uint128).max, "invalid decimals")' ==> 'require(baseUnitAmount <= type(uint64).max, "invalid decimals")' --> UNCAUGHT
[SBR] Line 201: 'return OracleLibrary.getQuoteAtTick(tick, uint128(baseUnitAmount), baseToken, quoteToken)' ==> 'return OracleLibrary.getQuoteAtTick(tick, uint64(baseUnitAmount), baseToken, quoteToken)' --> UNCAUGHT
[UOR] Line 200: 'tick--' ==> '--tick' --> UNCAUGHT
Done mutating OracleUniV3TWAP.
Revert mutants: 0 uncaught of 16 (0.0%)
Comment mutants: 0 uncaught of 26 (0.0%)
Tweak mutants: 11 uncaught of 104 (10.576923076923077%)

Mutating contract BaseManaged
[ROR] Line 72: 'bytes(_newConfigHub.VERSION()).length > 0' ==> 'bytes(_newConfigHub.VERSION()).length  !=  0' --> UNCAUGHT
Done mutating BaseManaged.
Revert mutants: 0 uncaught of 13 (0.0%)
Comment mutants: 0 uncaught of 13 (0.0%)
Tweak mutants: 1 uncaught of 21 (4.761904761904762%)

```
