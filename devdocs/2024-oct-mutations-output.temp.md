# Remove after full triage (during / after testing review).

### Notes
- Below output was filtered for false positives, and "as expected" mutants. 
- Some issues were either addressed during initial triage (in comments, code, or test changes), but most were not. The addressed ones were appended with "fixed".
- Some issues were investigated and explained in the output.
- Related mutations are grouped together, unrelated have have separating line-spaces

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

### Updated stats (after filtering):
> Format: "uncaught number (percent)" of revert / comment / tweak
```
LoansNFT:           0 (-) /   0 (-)   /  20  (5.8)  
CollarTakerNFT:     0 (-) /   2 (3.2) /   9  (4.6)
Rolls:              0 (-) /   0 (-)   /   9  (3.9)  
EscrowSupplierNFT:  0 (-) /   0 (-)   /   8  (2.7)  
SwapperUniV3:       0 (-) /   0 (-)   /   6 (15.7)  
ShortProviderNFT:   0 (-) /   0 (-)   /   3  (1.7)  
OracleUniV3TWAP:    0 (-) /   0 (-)   /   3  (4.2)  
ConfigHub:          0 (-) /   2 (7.2) /   2  (2.2)  
BaseEmergencyAdmin: 0 (-) /   0 (-)   /   0    (-)  
BaseNFT:            0 (-) /   0 (-)   /   0    (-)
```

### Filtered and partially processed output:

```
Mutating contract CollarTakerNFT


[CR] Line 130: 'require(block.timestamp >= position.expiration, "not expired")' ==> '//require(block.timestamp >= position.expiration, "not expired")' --> UNCAUGHT
- unspecific errors (shadowed by provider)
[CR] Line 131: 'require(!position.settled, "already settled")' ==> '//require(!position.settled, "already settled")' --> UNCAUGHT

[AOR] Line 68: 'uint putRange = BIPS_BASE - putStrikeDeviation' ==> 'uint putRange = BIPS_BASE % putStrikeDeviation' --> UNCAUGHT
[AOR] Line 69: 'uint callRange = callStrikeDeviation - BIPS_BASE' ==> 'uint callRange = callStrikeDeviation % BIPS_BASE' --> UNCAUGHT
[AOR] Line 296: 'uint lpPart = startPrice - endPrice' ==> 'uint lpPart = startPrice % endPrice' --> UNCAUGHT
[AOR] Line 297: 'uint putRange = startPrice - putPrice' ==> 'uint putRange = startPrice % putPrice' --> UNCAUGHT
[AOR] Line 303: 'uint userPart = endPrice - startPrice' ==> 'uint userPart = endPrice % startPrice' --> UNCAUGHT
[AOR] Line 304: 'uint callRange = callPrice - startPrice' ==> 'uint callRange = callPrice % startPrice' --> UNCAUGHT

[ROR] Line 226: 'putStrikePrice < twapPrice' ==> 'putStrikePrice  <=  twapPrice' --> UNCAUGHT
[ROR] Line 226: 'putStrikePrice < twapPrice' ==> 'putStrikePrice  !=  twapPrice' --> UNCAUGHT
[ROR] Line 226: 'callStrikePrice > twapPrice' ==> 'callStrikePrice  !=  twapPrice' --> UNCAUGHT

Done mutating CollarTakerNFT.
Revert mutants: 0 uncaught of 58 (0.0%)
Comment mutants: 2 uncaught of 62 (3.225806451612903%)
Tweak mutants: 27 uncaught of 192 (14.0625%)



Mutating contract ShortProviderNFT

[ROR] Line 142: 'callStrikeDeviation >= MIN_CALL_STRIKE_BIPS' ==> 'callStrikeDeviation  >  MIN_CALL_STRIKE_BIPS' --> UNCAUGHT
[ROR] Line 143: 'callStrikeDeviation <= MAX_CALL_STRIKE_BIPS' ==> 'callStrikeDeviation  <  MAX_CALL_STRIKE_BIPS' --> UNCAUGHT
[ROR] Line 144: 'putStrikeDeviation <= MAX_PUT_STRIKE_BIPS' ==> 'putStrikeDeviation  <  MAX_PUT_STRIKE_BIPS' --> UNCAUGHT

Done mutating ShortProviderNFT.
Revert mutants: 0 uncaught of 57 (0.0%)
Comment mutants: 0 uncaught of 60 (0.0%)
Tweak mutants: 12 uncaught of 169 (7.100591715976331%)



Mutating contract SwapperUniV3

[AOR] Line 93: 'amountOut = assetOut.balanceOf(address(this)) - balanceBefore' ==> 'amountOut = assetOut.balanceOf(address(this)) + balanceBefore' --> UNCAUGHT
[MVIE] Line 70: 'uint balanceBefore = ' ==> 'uint balanceBefore ' --> UNCAUGHT

[ROR] Line 37: '_feeTier == 100' ==> '_feeTier  <=  100' --> UNCAUGHT
[ROR] Line 37: '_feeTier == 500' ==> '_feeTier  <=  500' --> UNCAUGHT
[ROR] Line 37: '_feeTier == 3000' ==> '_feeTier  >=  3000' --> UNCAUGHT
[ROR] Line 37: '_feeTier == 10_000' ==> '_feeTier  >=  10_000' --> UNCAUGHT

Done mutating SwapperUniV3.
Revert mutants: 0 uncaught of 7 (0.0%)
Comment mutants: 1 uncaught of 10 (10.0%)
Tweak mutants: 6 uncaught of 38 (15.789473684210526%)



Mutating contract LoansNFT

[AOR] Line 554: 'amountOut = assetOut.balanceOf(address(this)) - balanceBefore' ==> 'amountOut = assetOut.balanceOf(address(this)) + balanceBefore' --> UNCAUGHT

[AOR] Line 831: 'uint swapPrice = cashFromSwap * takerNFT.oracle().BASE_TOKEN_AMOUNT() / collateralAmount' ==> 'uint swapPrice = cashFromSwap + takerNFT.oracle().BASE_TOKEN_AMOUNT() / collateralAmount' --> UNCAUGHT
[AOR] Line 831: 'uint swapPrice = cashFromSwap * takerNFT.oracle().BASE_TOKEN_AMOUNT() / collateralAmount' ==> 'uint swapPrice = cashFromSwap - takerNFT.oracle().BASE_TOKEN_AMOUNT() / collateralAmount' --> UNCAUGHT

[AOR] Line 833: 'uint deviation = diff * BIPS_BASE / twapPrice' ==> 'uint deviation = diff + BIPS_BASE / twapPrice' --> UNCAUGHT
[AOR] Line 833: 'uint deviation = diff * BIPS_BASE / twapPrice' ==> 'uint deviation = diff - BIPS_BASE / twapPrice' --> UNCAUGHT
[AOR] Line 833: 'uint deviation = diff * BIPS_BASE / twapPrice' ==> 'uint deviation = diff * BIPS_BASE * twapPrice' --> UNCAUGHT

[MIA] Line 432: 'setDefault' ==> 'true' --> UNCAUGHT. no true/false call. fixed.

[MIA] Line 832: 'swapPrice > twapPrice' ==> 'false' --> UNCAUGHT

[MVIE] Line 537: 'uint balanceBefore = ' ==> 'uint balanceBefore ' --> UNCAUGHT

[MVIE] Line 621: 'uint initialBalance = ' ==> 'uint initialBalance ' --> UNCAUGHT

[ROR] Line 463: 'loanAmount >= minLoanAmount' ==> 'loanAmount  >  minLoanAmount' --> UNCAUGHT

[ROR] Line 557: 'amountOut == amountOutSwapper' ==> 'amountOut  <=  amountOutSwapper' --> UNCAUGHT

[ROR] Line 772: 'block.timestamp <= _expiration(loanId)' ==> 'block.timestamp  <  _expiration(loanId)' --> UNCAUGHT

[ROR] Line 832: 'swapPrice > twapPrice' ==> 'swapPrice  ==  twapPrice' --> UNCAUGHT

[ROR] Line 850: 'repayment <= initialLoanAmount' ==> 'repayment  <  initialLoanAmount' --> UNCAUGHT

[SBR] Line 124: 'Loan storage loan = loans[loanId]' ==> 'Loan memory loan = loans[loanId]' --> UNCAUGHT
[SBR] Line 331: 'Loan storage loan = loans[loanId]' ==> 'Loan memory loan = loans[loanId]' --> UNCAUGHT
[SBR] Line 727: 'Loan storage loan = loans[loanId]' ==> 'Loan memory loan = loans[loanId]' --> UNCAUGHT
[SBR] Line 759: 'Loan storage loan = loans[loanId]' ==> 'Loan memory loan = loans[loanId]' --> UNCAUGHT
[SBR] Line 860: 'Loan storage loan = loans[loanId]' ==> 'Loan memory loan = loans[loanId]' --> UNCAUGHT

Done mutating LoansNFT.
Revert mutants: 0 uncaught of 114 (0.0%)
Comment mutants: 4 uncaught of 116 (3.4482758620689653%)
Tweak mutants: 58 uncaught of 342 (16.95906432748538%)



Mutating contract ConfigHub

[CR] Line 76: 'emit CollateralAssetSupportSet(collateralAsset, enabled)' ==> '//emit CollateralAssetSupportSet(collateralAsset, enabled)' --> UNCAUGHT
[CR] Line 83: 'emit CashAssetSupportSet(cashAsset, enabled)' ==> '//emit CashAssetSupportSet(cashAsset, enabled)' --> UNCAUGHT

[ROR] Line 66: 'max <= MAX_CONFIGURABLE_DURATION' ==> 'max  <  MAX_CONFIGURABLE_DURATION' --> UNCAUGHT
[ROR] Line 96: '_apr <= BIPS_BASE' ==> '_apr  <  BIPS_BASE' --> UNCAUGHT

Done mutating ConfigHub.
Revert mutants: 0 uncaught of 27 (0.0%)
Comment mutants: 2 uncaught of 28 (7.142857142857143%)
Tweak mutants: 7 uncaught of 87 (8.045977011494253%)



Mutating contract Rolls
[AOR] Line 376: 'uint withdrawn = cashAsset.balanceOf(address(this)) - balanceBefore' ==> 'uint withdrawn = cashAsset.balanceOf(address(this)) + balanceBefore' --> UNCAUGHT

[LIR] Line 65: 'uint public nextRollId = 1' ==> 'uint public nextRollId = 0' --> UNCAUGHT

[MIA] Line 191: 'minToProvider < 0' ==> 'true' --> UNCAUGHT. fixed

[MVIE] Line 374: 'uint balanceBefore = ' ==> 'uint balanceBefore ' --> UNCAUGHT

[ROR] Line 182: 'minPrice < maxPrice' ==> 'minPrice  <=  maxPrice' --> UNCAUGHT. fixed

[ROR] Line 183: '_abs(rollFeeDeltaFactorBIPS) <= BIPS_BASE' ==> '_abs(rollFeeDeltaFactorBIPS)  <  BIPS_BASE' --> UNCAUGHT

[ROR] Line 184: 'block.timestamp <= deadline' ==> 'block.timestamp  <  deadline' --> UNCAUGHT

[ROR] Line 272: 'block.timestamp <= offer.deadline' ==> 'block.timestamp  <  offer.deadline' --> UNCAUGHT

[ROR] Line 289: 'toProvider >= offer.minToProvider' ==> 'toProvider  >  offer.minToProvider' --> UNCAUGHT

Done mutating Rolls.
Revert mutants: 0 uncaught of 57 (0.0%)
Comment mutants: 0 uncaught of 55 (0.0%)
Tweak mutants: 31 uncaught of 226 (13.716814159292035%)



Mutating contract EscrowSupplierNFT

[AOR] Line 231: 'uint toRemove = previousAmount - newAmount' ==> 'uint toRemove = previousAmount + newAmount' --> UNCAUGHT. fixed

[AOR] Line 232: 'offers[offerId].available -= toRemove' ==> 'offers[offerId].available %= toRemove' --> UNCAUGHT
[ASOR] Line 232: 'offers[offerId].available -= toRemove' ==> 'offers[offerId].available ^= toRemove' --> UNCAUGHT
[ASOR] Line 232: 'offers[offerId].available -= toRemove' ==> 'offers[offerId].available <<= toRemove' --> UNCAUGHT
[ASOR] Line 232: 'offers[offerId].available -= toRemove' ==> 'offers[offerId].available >>= toRemove' --> UNCAUGHT
[ASOR] Line 232: 'offers[offerId].available -= toRemove' ==> 'offers[offerId].available %= toRemove' --> UNCAUGHT

[MVIE] Line 479: 'uint lateFee = ' ==> 'uint lateFee ' --> UNCAUGHT
	lateFee view is tested, but is not enforced (min with available)

[ROR] Line 381: 'block.timestamp > escrow.expiration + escrow.gracePeriod' ==> 'block.timestamp  !=  escrow.expiration + escrow.gracePeriod' --> UNCAUGHT. fixed

Done mutating EscrowSupplierNFT.
Revert mutants: 0 uncaught of 79 (0.0%)
Comment mutants: 0 uncaught of 85 (0.0%)
Tweak mutants: 30 uncaught of 290 (10.344827586206897%)



Mutating contract OracleUniV3TWAP

[ROR] Line 119: 'tickCumulativesDelta < 0' ==> 'tickCumulativesDelta  <=  0' --> UNCAUGHT
[ROR] Line 119: 'tickCumulativesDelta < 0' ==> 'tickCumulativesDelta  !=  0' --> UNCAUGHT
[ROR] Line 119: 'tickCumulativesDelta % int56(uint56(twapWindow)) != 0' ==> 'tickCumulativesDelta % int56(uint56(twapWindow))  <  0' --> UNCAUGHT

Done mutating OracleUniV3TWAP.
Revert mutants: 0 uncaught of 12 (0.0%)
Comment mutants: 0 uncaught of 19 (0.0%)
Tweak mutants: 8 uncaught of 70 (11.428571428571429%)



Mutating contract BaseEmergencyAdmin
Done mutating BaseEmergencyAdmin.
Revert mutants: 0 uncaught of 12 (0.0%)
Comment mutants: 0 uncaught of 12 (0.0%)
Tweak mutants: 1 uncaught of 18 (5.555555555555555%)



Mutating contract BaseNFT
Done mutating BaseNFT.
Revert mutants: 0 uncaught of 1 (0.0%)
Comment mutants: 0 uncaught of 5 (0.0%)
Tweak mutants: 0 uncaught of 3 (0.0%)
```
