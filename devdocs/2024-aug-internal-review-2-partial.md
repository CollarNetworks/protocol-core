# Issues

### Loans
- [x] #med Swapper contract refactor so that swapping (stateless) can be updated without migration
  - create / close should take additional arguments: `.., address swapper, bytes calldata swapperData)`
- [x] #med uniswap fee can be 100 too
  - mitigation: check fee is supported by checking vs. `factory.feeAmountTickSpacing()` instead of specific values
- [ ] #low no close path for loans in case are left hanging (in case of migration or if settled and withdrawn directly:
  - mitigation: add `cancelLoan` that can be triggered by anyone for a loan that was active, but who's NFT (takerId) was burned (so was cancelled or withdrawn outside of the loans contract)
  - should emit LoanCancelled event

### Provider
- [ ] #med if taker is disallowed in config, provider positions cannot be settled / cancelled:
  - this makes it impossible to allow close-only mode (for phasing out old contracts) without also allowing users / providers to open new positions.
  - mitigation: should only check self is allowed on open, rename flags to signify "open" allowed?
  - test: cancel/settle should be possible even if both taker and provider is disabled in configHub (but not paused)
- [ ] #low store takerId in position struct. Otherwise can't look up to which taker position a provider position is paired with (must use subgraph) - so is both bad for composability and UI
- [ ] #note provider should check itself is allowed on open for completeness (only taker checks it now)

### Taker
- [ ] #note contract and natspec docs missing

### Remaining from previous review:
- [ ] #low (design) providers cannot control their "slippage" (must actively manage liquidity with price changes, and are exposed to oracle risk) accepting trades at any oracle price from the taker contract. maybe worth to store acceptable price ranges per provider for opening positions?
- [ ] #low Oracle decimals and amounts: 1e18 is used as base token amount, which is confusing if collateral token has lower decimals. e.g., 1e18 USDC is 1 trillion, so price for USDC base token is for 1 trillion units
- [ ] #note missing interface docs + redirects in implementations
