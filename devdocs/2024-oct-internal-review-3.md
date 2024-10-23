# Issues

### General
- [x] #med/#low price ignoring decimals is confusing, error prone, violates "least astonishment", and is insufficiently documented outside of oracle:
  - While not too impactful if used only internally, price is expected as input argument for some methods, and is returned as output from others. This will certainly cause constant UX and integration difficulties, waste team's time, and undermine trust. It may also lead to user and integration mistakes, which may cause loss of funds, or loss of time, or reputational damage.  
  - Mitigaion: 
    - calculate prices for underlying's decimals instead of the BASE_TOKEN_AMOUNT, or set BASE_TOKEN_AMOUNT according to decimals. 
    - Refactor BASE_TOKEN_AMOUNT from oracle (possibly into taker), and expose "quote" methods that would convert between asset amounts in the oracle or taker (for use within Loans)
    - ~~Consider refactoring preview views (taker, rolls, etc) expecting prices to instead query them internally.~~  
- [x] #med/#low overall gas usage is high impacting composability (ability to batch several operations), and user gas costs with the highest call being at 1.7M gas. Some easy things can be done to reduce while minimally impacting safety / readability / usability
  - Examples with `forge clean && forge test --isolate --nmc "Fork" --gas-report --nmt revert | grep "rollLoan\|openLoan\|openEscrowLoan\|closeLoan\|executeRoll\|createOffer\|openPairedPosition\|startEscrow\|switchEscrow" | grep -v test`:
    - Loans before: roll 1.760M, openEscrowLoan 1.513M, openLoan 1.085K, close 599K
    - Loans after : roll 979M, openEscrowLoan 812K, openLoan 593K, close 461K
    - Rolls before: execute 1.022M, create 382K
    - Rolls after : execute 545K, create 250K
    - Taker before: open 755K
    - Taker after : open 354K
    - Escrow before: start 404K, switch 469K
    - Escrow after : start 229K, switch 276K
  - Composability risk: a contract that needs to batch many actions may have issues fitting all of them into a single tx in an Arbitrum block (although it is up to 32M gas, average usage is between 1M-3M, https://arbiscan.io/blocks?ps=100&p=1)
  - mitigations:
    - [x] remove usage of ERC721Enumerable (since its added functionality is unused): rollLoan to 1.471M, openLoan 871K.
    - [x] remove fields that aren't needed / can be calculated from other fields (call-price, put-price, callLockedCash). E.g., DRY fields (don't copy from offer to position, just store offerId)
    - [x] ~~reuse fields where it makes sense: principal & withdrawable~~ not impactful
    - [x] pack fields in storage (time u32, bips uint16, nft-id u64 due to batching). Use packed only for storage, but use full size for internal and external interfaces everywhere else (StoredPos / MemPos).
    - [x] reduce nft approvals and transfers in cancel
    - [x] ~~check if removing forceApprove helps~~ not too impactful
    - [x] pack confighub values to reduce cold sloads during opens
    - [x] ~~try solady ERC721~~ not enough difference suprisingly (between 1K-10K gas difference at most)
    - [x] post deployment: keep non-zero erc20 and NFT balances in contracts (to avoid 0-non-zero-0 transfer chains) 
- [ ] #low erc20 tokens are trusted to be simple, but still contracts that hold balances may be safer with balance checks on transfers: taker open, create offers (2). Example compv3 uint max transfer which may not be obvious when whitelisting an asset.
  - mitigation: doc expected erc20 behaviors + consider balance checks
  - checklist for tokens (to add as docs), https://github.com/d-xo/weird-erc20:
    - no hooks or reentracy vectors
    - balance changes only due to transfers. E.g., no rebasing / internal shares
    - balance changes always and exactly with transfer arguments. E.g, no FoT, no max(uint) args (cUSDCv3)
    - approval of 0 works
    - transfer of 0 works
- [ ] #low document for each contract what post-deployment setup is needed (in that contract and others)
- [ ] #low incorrect email + missing security contact
- [x] #low remove all unused interface methods
- [x] #low refactor all simple math (min / max / etc) with OZ library
- [x] #note copyright header
- [x] #note unused imports in a few places
- [x] #note several notes and nits from lightchaser https://gist.github.com/ChaseTheLight01/a66ec6b0599e1760f8512c42ec5f96ea
- [x] #note memory structs should be preferred to storage when access is read-only (even though gas is slightly higher) for clarity

###  Provider
- [x] #med min take amount to prevent dusting / composability issues / griefing via protocol fee issues / griefing via 0 user locked pos, may be non-negligible in case of low decimals + low gas fees
- [x] #low ~~rethink whether `cancelAndWithdraw` flow is not needed since taker is trusted anyway with settlement, so just settle call can be used (with 0 delta) and expiry check should be removed on provider side.~~ withdrawal in "settlement vis cancel" case becomes problematic
- [x] #low "ShortProviderNFT" is bad name, confusing and inaccurate. Should be "CollarProviderNFT"
- [x] #low naming: collateralAsset should be "underlying", since collateral is ambiguous and is actually cash. Should be just address since not used as erc20.
- [x] #low settle position doesn't check that position exists (relies on taker)
- [x] #note no good reason for recipient in withdrawal method
- [x] #note "unexpected takerId" check is redundant since checked value is returned from call invocation

###  Escrow
- [x] #med min take amount to prevent dusting / composability issues
- [x] #low switchEscrow should ensure not expired because is using 0 fromLoans
- [x] #low close-only problematic for escrow, because loansAllowed is checked (in modifier) in endEscrow
- [x] #note naming: lateFee view should be `owedTo` because is used for total owed mainly
- [x] #note naming: gracePeriod should be maxGracePeriod
- [x] #note switchEscrow order of params (fee and loanId) is reverse from startEscrow, which is error prone
- [x] #note no need to return the struct from start / switch escrow
- [x] #note document why cancelling escrow loans immediately does not allow griefing escrow suppliers

###  Loans
- [x] #med `escrowGracePeriodEnd` can overestimate grace period because uses historical price for both settlement and conversion. Should use current price for conversion.
- [x] #med `escrowGracePeriodEnd` can overestimate grace period because doesn't check if position is settled already, so may estimate cash incorrectly. Should only estimate for settled to reduce complexity.
- [x] #low escrow fee should be explicitly specified by user
- [x] ~~#low no open param for deadline / price increase (up) in case of congestion / sequencer outage~~ added to known issues
- [x] #low expected offer contract address for all offer-specifying methods (open, roll) to prevent abuse of stale / in-flight / delayed txs with current* (rolls, provider, escrow) being updated to new contracts.
- [x] #low swap-twap check should use twap value from before the swap, since swap is influencing the twap (reducing price)
- [x] #low MAX_SWAP_TWAP_DEVIATION_BIPS is too low, and is a DoS risk => raise to 50%, since only for opens and is only a sanity check. Consider removing completely since benefit is unclear, but adds complexity and dos vectors and scenarios (e.g., volatility)
- [x] #low check canOpen for self and dependencies contracts
- [x] #note document why no slippage check is done on what escrow releases on close
- [x] #note foreclose loan validity check should be first for clearer revert
- [x] #note naming: setKeeperApproved and keeperApproved
- [x] #note naming: open instead of create

### Taker
- [x] #low ~~no open param for deadline / price range in case of congestion / sequencer outage~~ added to known
- [x] #low putLocked / callLocked are bad names since aren't correct, should be takerLocker / providerLocked
- [x] #low naming: collateralAsset should be "underlying", since collateral is ambiguous and is actually cash. Should be just address since not used as erc20.
- [x] #low expiration should be calculated and checked vs. provider position because is key parameter (to reduce coupling)
- [x] #low not all oracle views are checked in _setOracle, use interface instead of contract, check all used views
- [ ] #note docs are mostly missing
- [x] #note add `historicalOraclePrice` view so that Loans can use that instead of oracle directly
- [x] #note timestamp casting is not necessarily safe (if duration is not checked by provider)
- [x] #note previewSettlement arg position struct is awkward, should expect id
- [x] #note 0 put range check unneeded in calculateProviderLocked
- [x] #note naming: deviation -> percent
- [x] #note no good reason for recipient in withdrawal method
- [x] #note cei can be better in settle

### Base admin
- [ ] #low rescuing nfts is not handled: use another arg / function to rescue nfts 
- [ ] #low ownable2step has error prone transfer method (since `transferOwnership` is overridden but functionality is different). override to `nominateOwner`
- [ ] #note docs for BaseEmergencyAdmin and BaseNFT + why they need config hub
- [x] #note naming: EmergencyAdmin is role and not attribute. BaseHubControlled?

###  ConfigHub:
- [x] #low max allowed protocol fee APR
- [x] #low isSupportedCash/Collateral redundant because canOpen is sufficient and the methods are always used together. Increases potential for config issues, gas, and admin dos. Instead can use nested mappings to store both assets and canOpen together.
- [ ] #low ownable2step has error prone transfer method (since `transferOwnership` is overridden but functionality is different), override to `nominateOwner`
- [ ] #low pause guardians should be a mapping / set to avoid having to share pauser pkey between team members / owner multi-sig signers and bot
- [x] #note canOpen is not pair / asset specific, so can allow cross asset misuse
- [ ] #note docs are incomplete
- [x] #note naming: BIPS / percent in LTV
- [ ] #note MAX_CONFIGURABLE_DURATION 5 years seems excessive?

### Rolls
- [x] #low ~~executeRoll has insufficient protection: needs deadline for congestion / stale transactions, max roll fee for direct fee control (since fee adjusts with price)~~ added to known
- [x] #note ~~provider deadline protection may be excessive, since can cancel stale offers, and has price limits, and requires approvals~~ better to leave as is
- [x] #note "active" state variable can be replaced by checking if contract owns provider NFT. Ack, won't fix.
- [x] #note create offer balance and allowance checks seem redundant since for spoofing can easily be passed by providing positive amount, and for mistake prevention only helps with temporary issues. Consider removing to reduce complexity.
- [x] #note naming: `rollFee*` stutter
- [x] #note execute checks order can be more intuitive: access control move to top, rearrange other checks
- [x] #note doc that `uint(-..)` reverts for int.min
- [x] #note docs why canOpen is not used
- [x] #note offer min max price check too strict, can be equal
- [x] #note `_abs` can be replaced with OZ lib usage

### Oracle
- [x] #med sequencer liveness oracle should prevent usage of bad prices ( https://docs.chain.link/data-feeds/l2-sequencer-feeds )
- [x] #low need more comprehensive warning, mitigation, and monitoring docs for TWAP issues
- [ ] #note ITakerOracle interface needs docs
- [ ] #note contract itself needs more docs
- [x] #note use high level try/catch since it's more readable in this case

## Remaining from previous review:
- [ ] #low (design) providers cannot limit offer execution price, and must manage offers with price changes. Are also exposed to oracle risk accepting trades at any oracle price from the taker contract. maybe store and check min-price / range?
- [x] #note missing interface docs + redirects in implementations

## Known design issues (for audits)
- no refund of protocol fee for cancellations, e.g., in case of rolls. fee APR and roll frequency are assumed to be low, and rolls are assumed to be beneficial enough to users to be worth it. accepted as low risk economic issue.
- loanNFT owner is pushed any collateral leftovers during foreclosure instead of pulling (so can be a contract that will not forward it to actual user, e.g., an NFT trading contract). accepted severity low: low likelihood, medium impact.
- because oracle uses the unlderying's decimals for base unit amount, underlying asset tokens with few decimals and/or very low prices in their "cash" token may have low precision prices. For example GUSD (2 decimals) as underlying, and WBTC as cash (doesn't make much sense), will result in just 4 decimals of price. Therefore, asset (underlying) tokens with sufficient decimals and price ranges should be used.
- in case of congestion / sequencer outage, "stale" openPairedPosition (and openLoan that uses it) and rolls executeRoll can be executed at higher price than the user intended (if price is lower, openLoan and executeRoll have slippage protection, and openPairedPosition has better upside). This is accepted because of combination of: 1) low likelihood (Arbitrum) and low impact ("loss" is small / intended), 2) because user can revoke asset permissions via force inclusion in some cases, 3) planned sequencer liveness check. Dealing with it using a deadline / maxPrice parameter would unnecessarily bloat the interfaces without significant safety benefit since parameter is likely be be unused if added.
