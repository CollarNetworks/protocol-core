# Disclaimers

- This is just an initial state of my understanding and observations.
- This is not an exhaustive list, but more of a "first" pass.
- The "severities" are approximate, and are there to convey my recommendation for relative importance and order of triaging.
- Some fix recommendations can depend / be obviated by implementing other recommendations, so should be ordered / triaged correctly.

# Specific Issues

> Grouped by: change-sets, contracts, somewhat odered by priority / severity

### Depends on VaultManager refactor

- [ ] **Vault manager per user vs. single BorrowPositions contract**
  - [ ] #med `createVaultManager` allowing one manager per sender:
    - vault-manager is Ownable, so this limitation prevents users from being able to interact with protocol if they transfer their vault.
    - this also allows a user to at the same time own multiple managers by creating and transferring, so if one-manager-per-user is an important assumption, it can be violated.
    - [ ] #med (engine) `createVaultManager` allowing only one manager per sender limits composability since cannot be used by other protocols in a flexible way
    - [ ] #high (vault) `user` and `owner` being initially the same, but `user` being immutable and used for auth, while `owner` is transferrable is problematic and confusing.
    - [ ] #high (vault) if ownership is transferred, user is still the expected sender for sensitive functions
    - Update: there's shouldn't mapping, use ownable, remove `user`  in vault. FE solution - use events (and later subgraph).
  - [ ] #low vault addresses are create1 so are known in advance and can be taken by anyone depending on transaction order. should use sender as create2 salt to avoid frontrunning risks (incorrectly predicting users' vault)
    - update: fix to create2
  - [ ] #low `uuid` is not necessarily unique, and is misleading name (since not universally unique). uuid will only unique if there's one factory and it continues restricting one per user, but both are not necessarily true from vault's POV (coupling)
    - fix: to be unique can use its own contract address instead of user address
    - even better: to not depend on id uniqueness in general if used accross several contracts, and instead per contract sequential ids can be used direclty (position / vault index)
  - [ ] #note `openVault` accepts a lot of parameters code/design smell
  - [ ] #low (pool) position doesn't store the opening vault-manager, and `finalizePosition` doesn't check the closing and opening manager is the same. position should store and check the "owner" vault?
  - [ ] #issue ERC6909TokenSupply / ERC6909 is the library audited / secure?

### Depends on LiquidityPool refactors

- [ ] **5 providers per position limitation:**
  - [ ] #high `addLiquidityToSlot` can bump out anyone's liquidity and immediately remove it using `withdrawLiquidityFromSlot`
    - can do it while frontrunning an openVault to
    - 1. take the trade if it's good
    - 2. DoS - prevent any trade from happening (by "removing" liquidity from the slot)
    - can backrun all liquidity provisions to remove DoS the whole protocol
    - fix: no eviction / limit logic, instead allow user to pass list of specific providers to use (to avoid DoS) or empty list to use in order
    - [ ]  `_getSmallestProvider`
      - [ ] #low `_getSmallestProvider` should not check return `address(0)`  if `_isSlotFull` since that provider will raise error. the check is also redundant since condition cannot be trigerred (callers are checking too)
      - [ ] #low for empty slot, `address(0)` will be returned
      - [ ] #note if `type(uint).max` is actually provided, `address(0)` will be returned
      - fix: should revert on empty slot, should start `smallestAmount` at first index.
      - better: remove the need for this entirely
- [ ] **Slots design:**
  - [ ] #med #design if provider is open to multiple slots, they must lock max liquidity in each slot - either capital inefficient or inflexible. instead of slots with locked liquidity allow provider to specify accepted ranges, and let users pick providers.
    - update: user would always choose the highest anyway
    - update: but removing slots and ticks still makes sense since it would make contracts simpler and more flexible. provider positions would be flat IDs with whatever params (no ticks no slots)
  - [ ] #note `tickScaleFactor` needs more documentation and explanation for why it's needed and why it has no decimals
    - it seems to be "abstraction leakage" or how internal "ranges" are translated to external prices / deviations.
    - [ ] #low (design) providers cannot control their "slippage" (must actively manage liquidity with price changes, and are exposed to oracle risk) accepting trades at any asset price from the vault. maybe worth to store acceptable price ranges per provider for opening positions?
  - [ ] #issue ERC6909TokenSupply / ERC6909 is the library audited / secure?
  - [ ] TickCalculations fixes:
    - [ ] #low "slot/tick" and `tickScaleFactor` should be internal to pool contract instead of being a library in the vault. this creates unnecessary coupling and complexity (another lib, noise in the vault calculations). vault knows about external prices, but should ask pool about the pools internal "slots / ticks"
    - [ ] #issue `priceToTick` and `bpsToTick` using unsafe casting + unused. should be removed?
    - [ ] #low there is no real need to use `uint24`, and pool uses full uint anyway

### Independent

- [ ] **Swapping fixes:**
  - [ ] #critical vault's `openVault` swap price (and so the price used for accounting) is at full user control (can sandwich themselves) so user can choose any price they like:
    - can be exploited by using low price - put the provider at a loss from the start
    - should use TWAP price when opening
  - [ ] #low `_swap` should do explicit balance check to avoid trusting the external implementation for the return value to match balance update

- [x] **Fix TWAP usage & logic:**
  - [x] #med `getHistoricalAssetPriceViaTWAP` passes `expiresAt` as twapStart, but should be expiresAt - twapLength, or variable `getTWAP` should expect `twapEnd` instead
  - [x] #high in `getTWAP` `twapLength` is added twice (and `twapStartTimestamp` is outside of the twap window). Both incorrect price (15 minutes in past), and incorrect window is used.
  - [x] #low `factory.getPool` can be used instead of custom `_getPoolForTokenPair`


- [x] **Remove non-TWAP price usage**
  - [x] #med `getCurrentAssetPrice` is not used, but is not safe for pretty much anything onchain - should be removed:
  - [x] #med (oracle lib) `twapLength` 0 should not be allowed and slot0 (instaneous price) should not be used
    - should be removed, and instead use short twap around the right time
    - #low also `twapStartTimestamp` is ignored for `twapLength` 0, and will provide current price even the `twapStartTimestamp` is some specific time

- [ ] **Pool logic fixes:**
  - [ ] `openPosition`
    - [ ] #high amount subtracted from provider is too little. providers can withdraw some "locked" liquidity - thus stealing from other providers.
    - [ ] #med amount reserved and minted not equal (minted < provided), should sum up provider liquidity.
    - [ ] #med `positions[uuid]` if can be theoretically called multiple times, overwritten without being checked. while opening a uuid "should" be called with only once, this tightly couples logic of factory + vault-manager + pool. should just check and revert
  - [ ] #med redeem is callable before `finalizePosition` when `withdrawable` is 0, and will burn tokens while withdrawing 0 (losing funds). should check position was finalized (should add flag?)
  - [ ] `finalizePosition`
    - [ ] #med a lof of unsafe casting both ways - if sums is negative for `withdrawable`, `totalLiquidity`, `redeemableLiquidity`. also turning `uints` to `ints`.
      - should split into two cases: positive update and negative update for uuid and and total, and then update
    - [ ] #med depends on uuid being unique again and vault not being able to call twice (there's no flag for "finalized" for position), since overwrites `positions[uuid].withdrawable` and doesn't reduce `principal`
    - [ ] #low `vaultManager` is both argument and sender. it should not be possible to call for non-sender vault manager, since it will cause the vault to not be finalizable. remove argument?

- [ ] **Dependency management:**
  - [ ] #med https://github.com/CollarNetworks/uni-v3-periphery-solc-v0.8 copy is a strange approach - unaudited and  should not be used. Instead do something like https://github.com/euler-xyz/euler-price-oracle/blob/master/src/adapter/uniswap/UniswapV3Oracle.sol by importing SDK packages

- [ ] **Global / Recurring:**
  - [ ] #med use SafeERC20's transfer and approve methods
  - [ ] #med decimals:
    - Oracle lib `getQuoteAtTick` assumes `baseToken` is 1e18 decimals
  - [x] #low Requires vs. Errors:
    - I prefer "requires" due to readability, brevity, easier logic, more informative messages. A lot of auditors prefer it. It's very common in large high quality codebases (even on L1) to stick to requires. Why bloat with 4 lines instead of 1, create and and import TrickyToNameAndAnnoyingToReadError, and have to think in double-negatives?

- [ ] **Naming issues**:
  - [ ] engine
    - [ ] `univ3SwapRouter` should have correct name (`unitV3router` or smth) because is later used with specific UniV3 interface (in vault manager)
    - [ ] "engine" is a misleading name - there's no logic really, only vault factory and config.
  - [ ] vault:
    - [ ] "vault" for internal struct is bad name since typically refers to a specific type of separate contract, but here it isn't a contract, it's a "position" type thing. Can be named BorrowPositions or smth similar.
    - [ ] `vaultNonce` - "nonce" is not typically used this way, can be vaultIndex
  - [ ] pool
    - [ ] "slot" is an overloaded name (because of storage slots, `.slot`, and other various slots). Tick also already refers to a specific UniV3 things. So maybe "Range" / "offerRange" ?
    - [ ] `providers` should be `providersLiquidity` because it's a map

- [ ] **Vault lows and notes**:
  - [ ] #low encoding structs to bytes makes no sense vaultInfo, vaultInfoByNonce.
  - [ ] #note `VaultForABI` event??
  - [ ] #note `vaultTokenCashSupply` should use named mapping parameters
  - [ ] #note some views are used only in tests, should be removed or added only to test contract ( `Testable`): `isVaultExpired`, `vaultInfo`, `vaultInfoByNonce`
  - [x] #note `previewRedeem` else condition can be removed? finalized is checked by redeem already
  - [ ] `openVault`
    - [ ] #low safer (and more efficient) to initialize new Vault struct in memory, and than to write to storage. safer because won't forget fields.
    - [ ] #low approval not needed since is given again in `closeVault`. giving approval here (for delayed action) is not safe, error prone, and uncommon pattern (the pools accumulate approvals, not very "vault" like)
    - [ ] #low tokens are implicitely assumed to be all 1e18 decimals
    - [ ] #note `openVault` too long / complex, need to be refactored:
    - validation, calculation, storage, transfers & interactions. use memory vault, than write to storage vault
    - [ ] #note `cashAmount` in `AssetSpecifiers`  should be `minCashAmount`
    - [ ] #note document that ERC20 should not have callbacks (reentrancy in openVault)
    - [ ] #note `_validateLiquidityOpts` inconsistent use of `tickToBps`
    - [ ] #note `vaultsByUUID[uuid]` should be cached
  - [ ] `closeVault`
    - [ ] #low unsafe casting
    - [ ] #note too long / complex
    - [ ] #note comments don't match code (4 cases vs. 5)
    - [ ] #note 1e32 is too much (18 + 18 + 32 = 66, out of 78), leaves only 11 decimals for "units"
    - [ ] #note a single "bag" and less conditions can be used. the total bag is divided between user and pool according to price linearly within the (put < call) range because the pool liquidity is locked proportionally to price as well.
    - [ ] #note setting active false can be done before making external calls
  - [ ] #issue using ERC20 for vault position is weird since tokens for a UUID are only minted once. having multiple users use the vault is weird because only `user` can withdraw borrowed. why would user trade part of their ERC20 redeem tokens?
  - [ ] Perhaps should use NFTs for positions to allow transferring. But in that case, the whole vault should not be per user, but a general NFT.

- [ ] **Pool lows and notes**:
  - [ ] #low `initializedSlotIndices` doesn't appear to be needed, and is confusing / error-prone since removal of `initializedSlotIndices` will not reset provider mappings and set values in slots
  - [x] #low `moveLiquidityFromSlot` should be DRY with just `_withdraw + _add` (internal methods) but without the transfers. also no need for `LiquidityMoved` event
  - [ ] #low `openPosition` iterating the providers map indices and making changes to the map during the loop (calling `set`) is not a safe pattern. it should be ok in this case, but it depends on implementation, and is error prone and "feels wrong". fix: iterate keys
  - [x] #note `previewRedeem` / `redeem` using external calls (via `ERC6909TokenSupply` ) on itself, can use `balanceOf` directly
  - [ ] #note `_isSlotFull`  can be one line
  - [ ] #note `_unallocate` should check `contains`, otherwise will raise less clear error
  - [ ] #note `addLiquidityToSlot` can have just one if branch since allocates similarly in both branches
  - [ ] #note liquidity can be added at any slot: below 100% and way above 100%. some validation makes sense.

- [ ] **Engine notes**:
  - [x] #note unused and unncesseary modifiers - unused or used once. Add noise and complexity: errors, indirection, modifier code.
  - [x] #note events in setters typically emitted in the end.
  - [ ] #note docs redirect for overrides can use `@inheritdoc` for clarity
  - [ ] #note no need for overrides if implementing interface (and can remove virtual in interface)
  - [x] #note remove the comment with values at the bottom of the file.

- [ ] **Global / Recurring notes**:
  - [ ] #note Floating pragma. Should be a fixed version.
  - [ ] #note console imports
  - [ ] #note magic numbers: 3000, 10_000, 15 minutes, 5 ( #med because is highly likely to be changed). Maybe bring back and use `Constants.sol` mixin?

- [ ] **ERC6909TokenSupply / ERC6909 lows:**
  - [ ] #low to/from 0 unhandled and don't update totalSupply
  - [ ] #low transferFrom no allowance check from msg.sender or if operator

- [x] **Already "done" (part of "review" branch)**
  - [x] Refactor of Interfaces vs. Abstract confusion
  - [x] Removal of event-only interfaces
  - [x] `uint` style
  - [x] Library function should be internal

# Design questions

- **Pausing, Upgradability, Recovery methods:**
  - If proxies are too complex, pausing + recovery methods are still good risk management.
- **Architecture**:
  - Some problems:
    - Having many contracts are a big headache.
    - Per user vaults don't make much sense, the asset contracts are the main risk, so one contract per asset-pair should be enough.
    - Per expiry pools / strike price "locked" liquidity splitting doesn't make much sense either - capital inefficient and inflexible. Allowing offering same liquidity deposit to be used for different possible parameters shouldn't be too hard within a single contract.
  - Proposal 1: split by asset-config (cash + collateral) to isolate SC risks. So for an asset config
    - One borrow-side contract (manages borrow positions) - what is now vault manager, but for all users.
    - One provider-side contract (manages liquidity positions) - what is now pools, but for all strikes and expiries.
  - Proposal 2: keep the liquidity pools for simplicity, but unify borrower side (also, for simplicity, and for allowing unwinds via NFTs).
  - Proposal 3 (recommended): for allowing simple unwinds (full and partial) from both sides - "paired NFTs":
    - BorrowPosition NFTs are paired 1:1 with LenderPosition NFTs.
    - When user opens a position, it's minted as multiple NFT ids (e.g, [3,4,5]) to the user, each matching lender NFTs [3,4,5] which are minted to each lender.
    - This way, each NFT on each side is transferrable, there's no share calculations, and position management is simplified for both sides. Redeems on each side accept an array of IDs and check ownership.
    - "Unwind" takes a pair of NFTs (owned by same owner at that point), burns them, and releasing the funds.
    - This way any lender can buy out their portion of user's position from the user or any user can buy out the lender portion from any lender.
    - Rolls: a RollEscrow contract is created, where the user can escrow their borrow positions during a roll request. If the lenders take it, the escrow takes the lender's side burns the old, releases funds, and creates a new position sending the new position NFTs to original user and lender. If the deal doesn't go through, the user can take back their original position.
- **Refactor things now vs. later. Why now?:**
  - make design simpler and safer
  - make code smaller shorter (cheaper, less liability)
  - try to suit future features better (unwinds / rolls)
  - remove deeper issues that stem from design
  - takes advantage of existing logic and flows, but reorganizes them differently
  - iterating on architecture makes sense now vs. later:
    - already much more clarity on needs and current limitations
    - much easier to refactor things early: less complexity, less testing changes, FE changes
    - before audits is better, otherwise audits are wasted
    - very hard to update architecture later - unlike web2, can't swap / update back-end (data and funds are hard to migrate safely) because of how exposed and risky it is.
