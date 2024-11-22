## 2024 Nov Scope:

```
--------------------------------------------------------------------------------
File                              blank        comment           code
--------------------------------------------------------------------------------
src/LoansNFT.sol                    118            414            371
src/EscrowSupplierNFT.sol            78            253            254
src/CollarTakerNFT.sol               57            142            197
src/Rolls.sol                        56            196            194
src/CollarProviderNFT.sol            48            145            190
src/ConfigHub.sol                    25             73             79
src/ChainlinkOracle.sol              13             46             52
src/CombinedOracle.sol               11             37             47
src/SwapperUniV3.sol                  9             51             43
src/base/BaseManaged.sol             17             38             41
src/base/BaseTakerOracle.sol         13             49             33
src/base/BaseNFT.sol                  7             13             23
--------------------------------------------------------------------------------
SUM:                                452           1457           1524
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
- General protocol / mechanism docs: https://docs.collarprotocol.xyz/

## Known Issues
- Providers offers do not limit execution price (only strike percentages), nor have deadlines, and are expected to be actively managed.
- No refund of protocol fee for position cancellations / rolls. Fee APR and roll frequency are assumed to be low, and rolls are assumed to be beneficial enough to users to be worth it. Accepted as low risk economic issue.
- During escrow loan foreclosure, any remaining underlying is sent to the borrower instead of being stored to be pulled. So it can be sent to a contract that will not credit it to actual user.
- Because oracle prices undergo multiple conversions (feeds, tokens units), asset and price feed combinations w.r.t to decimals and price ranges are assumed to be checked to allow sufficient precision.
- In case of congestion, calls for `openPairedPosition` (`openLoan` that uses it), and rolls `executeRoll` can be executed at higher price than the user intended (if price is lower, `openLoan` and `executeRoll` have slippage protection, and `openPairedPosition` has better upside for the caller). This is accepted as low likelihood, and low impact: loss is small since short congestion will result in small price change vs. original intent, and long downtime may fail the oracle sequencer uptime check.
- Issues and considerations explained in the Solidity comments and audit report.

## Prior Audits
- [Cantina solo review Oct-2024 report](../audits/2024-oct-cantinacode-solo-1.pdf)

## Non obvious parameter ranges
- `minDuration` is at least 1 month.

## Potentially useful topics that may be accepted for low / info findings, despite inherent OOS assumptions:
- Arbitrum timeboost implications.
- Reentrancy or concerns for using `SwapperArbitraryCall` with more advanced multi-hop swaps or dex aggregators instead of the currently in-scope swapper.
- Any implications of "Known Issues" or design decisions we may be overlooking or underestimating, including any mechanism and economic issues (incentives). 

## Testing and POC
- Install run tests excluding fork tests: `forge install && forge build && forge test --nmc Fork`
- POC: modify tests in `test/unit` for local testing, and `test/integration` for fork tests (require defining RPC in `.env`, see `.env.example`)
