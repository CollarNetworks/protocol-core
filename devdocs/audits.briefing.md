## 2024 Jan Scope:

```
------------------------------------------------------------------------------------------
File                                        blank        comment           code
------------------------------------------------------------------------------------------
src/LoansNFT.sol                              108            380            364
src/EscrowSupplierNFT.sol                      75            230            270
src/CollarTakerNFT.sol                         57            152            196
src/Rolls.sol                                  54            205            196
src/CollarProviderNFT.sol                      48            153            188
src/ConfigHub.sol                              25             73             79
src/CombinedOracle.sol                         14             40             56
src/ChainlinkOracle.sol                        14             50             55
src/SwapperUniV3.sol                            9             53             43
src/base/BaseManaged.sol                       17             36             43
src/base/BaseTakerOracle.sol                   14             57             34
src/base/BaseNFT.sol                            8             13             24
------------------------------------------------------------------------------------------
SUM:                                          443           1442           1548
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
Arbitrum only initially. OP stack rollups (Optimism, Base) in the future.

## Other Documentation
- Solidity files comments contain the most up to date documentation 
- Some diagrams for high level overview: [diagrams.md](diagrams.md) 
- General protocol / mechanism docs (outdated): https://docs.collarprotocol.xyz/

## Known Issues
- Providers offers do not limit execution price (only strike percentages), nor have deadlines, and are expected to be actively managed.
- No refund of protocol fee for position cancellations / rolls. Fee APR and roll frequency are assumed to be low, and rolls are assumed to be beneficial enough to users to be worth it. Accepted as low risk economic issue.
- Because oracle prices undergo multiple conversions (feeds, tokens units), asset and price feed combinations w.r.t to decimals and price ranges (e.g., low price tokens) are assumed to be checked to allow sufficient precision.
- In case of congestion, calls for `openPairedPosition` (`openLoan` that uses it), and rolls `executeRoll` can be executed at higher price than the user intended (if price is lower, `openLoan` and `executeRoll` have slippage protection, and `openPairedPosition` has better upside for the caller). This is accepted as low likelihood, and low impact: loss is small since short congestion will result in small price change vs. original intent, and long downtime may fail the oracle sequencer uptime check.
- Issues and considerations explained in the Solidity comments and audit report.
 
## Commonly Noted Non-issues (unless we're wrong, and they are)
- If deploying on a chain which can re-org, theoretically a re-org can allow an offer to be substituted by another. We see such a scenario as an extremely unlikely coincidence of implausibilities.
- Offer parameters that should be validated on position creation are not checked on offer creation. It is neither necessary nor sufficient to do (since config can change), and would add complexity for no benefit. Expected to be checked on FE for UX.
- In a block that has exactly the expiration timestamp, multiple actions are valid (settle, close, roll). If block is viewed as "containing" the timestamp, the logic seems consistent. Main reason for allowing is that each of those actions is safe to perform in that block, and state contention is not an impact.

## Prior Audits
- [Cantina solo review Oct-2024 report](../audits/2024-oct-cantinacode-solo-1.pdf)
- Cantina contest (findings to be made available after contest is finished)
- [Spearbit review Jan-2024 report](../audits/report-spearbit-collar-protocol-1226.pdf)

## Non obvious parameter ranges
- `minDuration` is at least 1 month.
- `maxLTV` is reasonably far from 99.99% 

## Testing and POC
- Install run tests excluding fork tests: `forge install && forge build && forge test --nmc Fork`
- POC: modify tests in `test/unit` for local testing, and `test/integration` for fork tests (require defining RPC in `.env`, see `.env.example`)
