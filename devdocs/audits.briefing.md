## 2025 Apr Scope:

```
------------------------------------------------------------------------------------------
File                                        blank        comment           code
------------------------------------------------------------------------------------------
src/LoansNFT.sol                              108            380            372
src/EscrowSupplierNFT.sol                      72            227            262
src/CollarTakerNFT.sol                         57            175            217
src/CollarProviderNFT.sol                      55            176            199
src/Rolls.sol                                  55            211            195
src/ConfigHub.sol                              22             64             75
src/CombinedOracle.sol                         14             40             56
src/ChainlinkOracle.sol                        14             50             55
src/SwapperUniV3.sol                            9             53             43
src/base/BaseTakerOracle.sol                   14             57             34
src/base/BaseManaged.sol                       14             22             25
src/base/BaseNFT.sol                            7              9             16
------------------------------------------------------------------------------------------
SUM:                                          441           1464           1549
------------------------------------------------------------------------------------------
```

## ERC-20 assumptions / integration checklist: 
- No hooks or reentrancy vectors
- Balance changes only due to transfers. E.g., no rebasing / internal shares
- Balance changes always and exactly with transfer arguments. E.g, no FoT, no max(uint) args overrides like cUSDCv3
- Approval of 0 amount works
- Transfers of 0 amount works
- (for checklist use: check changes to https://github.com/d-xo/weird-erc20)

## Deployment Destinations
Base, possibly Eth L1 later.

## Other Documentation
- Solidity files comments contain the most up to date documentation 
- Some diagrams for high level overview: [diagrams.md](diagrams.md) 
- General protocol / mechanism docs (outdated!): https://docs.collarprotocol.xyz/

## Known Issues
- Providers offers do not limit execution price (only strike percentages), nor have deadlines, and are expected to be actively managed.
- No refund of protocol fee for position cancellations / rolls. Fee APR and roll frequency are assumed to be low, and rolls are assumed to be beneficial enough to users to be worth it. Accepted as low risk economic issue.
- Protocol fee (charged from provider offer, on top of provider position) can be high relative to provider position's size, especially for smaller callStrikePercent.  
- Because oracle prices undergo multiple conversions (feeds, tokens units), asset and price feed combinations w.r.t to decimals and price ranges (e.g., low price tokens) are assumed to be checked to allow sufficient precision.
- In case of congestion, calls for `openPairedPosition` (`openLoan` that uses it), and rolls `executeRoll` can be executed at higher price than the user intended (if price is lower, `openLoan` and `executeRoll` have slippage protection, and `openPairedPosition` has better upside for the caller). This is accepted as low likelihood, and low impact: loss is small since short congestion will result in small price change vs. original intent, and long downtime may fail the oracle sequencer uptime check.
- If an oracle becomes malicious, there isn't a way to "unset" it. ConfigHub can prevent opening new positions for that pair, but existing positions will remain vulnerable.
- If a collar position is settled via `settleAsCancelled` (due an oracle malfunction, or no one calling regular settle for one week), the Loan using that position will still be possible to close, but the amount of underlying returned may not correspond well to current price (because the collar position will be settled at its opening price). The loan can also be cancelled if desired.    
- Any tokens accidentally sent to any of the contracts cannot be rescued.
- Issues and considerations explained in the Solidity comments and audit reports.
 
## Commonly Noted Non-issues (unless we're wrong, and they are)
- If deploying on a chain which can re-org, theoretically a re-org can allow an offer to be substituted by another. We see such a scenario as an extremely unlikely coincidence of implausibilities.
- Offer parameters that should be validated on position creation are not checked on offer creation. It is neither necessary nor sufficient to do (since config can change), and would add complexity for no benefit. Expected to be checked on FE for UX.
- In a block that has exactly the expiration timestamp, multiple actions are valid (settle, close, roll). If block is viewed as "containing" the timestamp, the logic seems consistent. Main reason for allowing is that each of those actions is safe to perform in that block, and state contention is not an impact.

## Prior Audits
- [Cantina solo review Oct-2024 report](../audits/2024-oct-cantinacode-solo-1.pdf)
- [Cantina contest](../audits/2024-dec-cantina-competition.pdf)
- [Spearbit review Jan-2024 report](../audits/report-spearbit-collar-protocol-1226.pdf)

## Non obvious parameter ranges
- `minDuration` is at least 1 month.
- `maxLTV` is reasonably far from 99.99% 

## ConfigHub's owner privileges (for BaseManaged contracts)
- Can update the values set in ConfigHub and replace the ConfigHub contract that's being used. This includes what internal contracts are allowed to open positions, LTV range, durations range, protocol fee parameters.
- Can update the loansNFT allowed swappers.

## Testing and POC
- Install run tests excluding fork tests: `forge install && forge build && forge test --nmc Fork`
- POC: modify tests in `test/unit` for local testing, and `test/integration` for fork tests (require defining RPC in `.env`, see `.env.example`)
