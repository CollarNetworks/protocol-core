## 2024 Oct Scope:

```
---------------------------------------------------------------------------------------
File                                     blank        comment           code
---------------------------------------------------------------------------------------
src/LoansNFT.sol                           116            396            361
src/EscrowSupplierNFT.sol                   77            247            251
src/CollarTakerNFT.sol                      58            152            201
src/Rolls.sol                               56            192            194
src/CollarProviderNFT.sol                   48            137            189
src/OracleUniV3TWAP.sol                     24            142             85
src/ConfigHub.sol                           23             68             71
src/SwapperUniV3.sol                        10             46             44
src/base/BaseManaged.sol                    17             38             41
src/base/BaseNFT.sol                         6             12             18
---------------------------------------------------------------------------------------
SUM:                                       435           1430           1455
---------------------------------------------------------------------------------------
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
- Solidity files have the most up to date docs
- Some diagrams for high level overview: [diagrams.md](diagrams.md) 
- General protocol / mechanism docs: https://docs.collarprotocol.xyz/

## Known Design Issues
- Providers offers do not limit execution price (only strike prices), so are expected to actively manage for large price changes.
- No refund of protocol fee for position cancellations / rolls. Fee APR and roll frequency are assumed to be low, and rolls are assumed to be beneficial enough to users to be worth it. Accepted as low risk economic issue.
- During escrow loan foreclosure, any remaining underlying is pushed to the borrower (loan NFT ID owner) instead of being stored to be pulled. So it can be sent to a contract that will not credit it to actual user. Accepted as low: low likelihood, medium impact, user mistake due to being foreclosed.
- Because oracle uses the unlderying's decimals for base unit amount, underlying asset tokens with few decimals and/or very low prices in cashAsset token may have low precision prices. As a unrealistic example, GUSD (2 decimals on mainnet) as underlying, and WBTC as cash, would result in 4 decimals of price. Asset combinations w.r.t to decimals and price ranges are assumed to be checked to allow sufficient precision.
- In case of congestion, "stale" `openPairedPosition` (and `openLoan` that uses it) and rolls `executeRoll` can be executed at higher price than the user intended (if price is lower, `openLoan` and `executeRoll` have slippage protection, and `openPairedPosition` has better upside for the caller). This is accepted because of combination of: 1) sequencer uptime check in oracle, 2) low likelihood: Arbitrum not having a public mempool, and low impact: loss is small since short congestion will result in small price change vs. original intent. Dealing with it using a deadline / maxPrice parameter would unnecessarily bloat the interfaces without significant safety benefit. 

## Potentially interesting leads:
- Arbitrum timeboost implications
- Reentrancy via swapper (assuming using more advanced multi-hop swaps / aggregators etc)
- Misconfigurations that don't break
- Mechanism and economic issues (incentives)
- Any implications of "Known Issues" / design decisions we may be overlooking / underestimating  
