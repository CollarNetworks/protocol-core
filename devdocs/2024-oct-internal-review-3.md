# Issues


### General
  - [ ] #med overall gas usage is high impacting composability (ability to batch several operations), and user gas costs. Some easy things can be done to reduce while minimally impacting safety / readability / usability
    - Examples with `forge test -vvv --isolate --nmc Fork --gas-report --nmt revert`:
      - Loans: roll 1.461M, openEscrow 1.224M, open 867K, close 557K
      - Rolls: execute 893K, create 365K
      - Taker: open 609K
      - Escrow: start 327K, switch 388K
    - mitigations:
      - [x] remove usage of ERC721Enumerable (since its added functionality is unused)
      - [ ] remove fields that aren't needed / can be calculated from other fields (call-price, put-price, callLockedCash)
      - [ ] reuse fields where it makes sense: principal & withdrawable
      - [ ] pack fields in storage (time u32, bips uint16, nft-id u32 / u64). Use packed only for storage, but use full size for internal and external interfaces everywhere else (StoredPos / MemPos).
      - [ ] post deployment: keep non-zero erc20 balances in contracts (to avoid 0-non-zero-0 transfer chains)
  - [ ] #low erc20 tokens are trusted to be simple, but still contracts that hold balances may be safer with balance checks on transfers: taker open, create offers (2). Example compv3 uint max transfer which may not be obvious when whitelisting an asset.
    - mitigation: doc expected erc20 behaviors + consider balance checks
  - [ ] #low rescuing nfts is not handled: accept optional tokenId to know to transfer NFTs
  - [ ] #low ownable2step has error prone transfer method (since `transferOwnership` is overridden but functionality is different), override to `nominateOwner`
  - [ ] #low remove all unused interface methods
  - [ ] #low document for each contract what post-deployment setup is needed (in that contract and others)
  - [x] #low refactor all simple math (min / max / etc) with OZ library
  - [x] #note unused imports in a few places
  - [x] #note several notes and nits from lightchaser https://gist.github.com/ChaseTheLight01/a66ec6b0599e1760f8512c42ec5f96ea

### Rolls
  - [ ] #note naming: `rollFee*` stutter
  - [ ] #note execute checks order can be more intuitive: access control move to top, rearrange other checks
  - [x] #note doc that `uint(-..)` reverts for int.min

### Taker
  - [ ] #note Docs are incomplete
  - [x] #note previewSettlement arg position struct is awkward, should expect id
  - [ ] #note naming: deviation -> percent
  - [ ] #note no good reason for recipient in withdrawal method

###  Provider
  - [ ] #note no good reason for recipient in withdrawal method

###  Loans
  - [ ] #low swap-twap check should use twap value from before the swap, since swap is influencing the twap (reducing price)
  - [ ] #low MAX_SWAP_TWAP_DEVIATION_BIPS is too low, and is a DoS risk => raise to 50%, since only for opens and is only a sanity check
  - [x] #low check canOpen for self and dependencies contracts
  - [ ] #note naming: setKeeperAllowed should be setAllowsClosingKeeper
  - [x] #note naming: open instead of create

###  ConfigHub:
  - [ ] #note docs are incomplete
  - [ ] #note naming: BIPS / percent in LTV

### Remaining from previous review:
- [ ] #low (design) providers cannot control their "slippage" (must actively manage liquidity with price changes, and are exposed to oracle risk) accepting trades at any oracle price from the taker contract. maybe worth to store acceptable price ranges per provider for opening positions?
- [ ] #low Oracle decimals and amounts: 1e18 is used as base token amount, which is confusing if collateral token has lower decimals. e.g., 1e18 USDC is 1 trillion, so price for USDC base token is for 1 trillion units
- [ ] #note missing interface docs + redirects in implementations
