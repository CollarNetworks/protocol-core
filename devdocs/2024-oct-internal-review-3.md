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
    - [ ] pack fields in storage (time u32, bips uint16, nft-id u64 due to batching). Use packed only for storage, but use full size for internal and external interfaces everywhere else (StoredPos / MemPos).
    - [ ] pack confighub values to reduce cold sloads during opens
    - [ ] post deployment: keep non-zero erc20 balances in contracts (to avoid 0-non-zero-0 transfer chains)
- [ ] #low erc20 tokens are trusted to be simple, but still contracts that hold balances may be safer with balance checks on transfers: taker open, create offers (2). Example compv3 uint max transfer which may not be obvious when whitelisting an asset.
  - mitigation: doc expected erc20 behaviors + consider balance checks
- [x] #low remove all unused interface methods
- [ ] #low document for each contract what post-deployment setup is needed (in that contract and others)
- [ ] #low incorrect email + missing security contact
- [x] #low refactor all simple math (min / max / etc) with OZ library
- [x] #note copyright header
- [x] #note unused imports in a few places
- [x] #note several notes and nits from lightchaser https://gist.github.com/ChaseTheLight01/a66ec6b0599e1760f8512c42ec5f96ea
- [x] #note memory structs should be preferred to storage when access is read-only (even though gas is slightly higher) for clarity

###  Provider
- [ ] #med min take amount to prevent dusting / composability issues / griefing via fee issues / griefing via 0 user locked pos, may be non-negligible in case of low decimals + low gas fees
- [x] #low "ShortProviderNFT" is bad name, confusing and inaccurate. Should be "CollarProviderNFT"
- [x] #low naming: collateralAsset should be "underlying", since collateral is ambiguous and is actually cash. Should be just address since not used as erc20.
- [ ] #low max allowed protocol fee APR in provider offer
- [ ] #low rethink whether `cancelAndWithdraw` flow is not needed since taker is trusted anyway with settlement, so just settle call can be used (with 0 delta) and expiry check should be removed on provider side.
  - pros of separate flows: ensures ownership of NFT and concent, ensures expiry invariant
  - cons of separate flows:
    - added complexity by having different before / after expiry flows
    - redundant checks in taker and maker
    - cannot cancel with delta if needed
    - more gas by having to approve and transfer provider NFT
- [x] #note no good reason for recipient in withdrawal method
- [x] #note "unexpected takerId" check is redundant since checked value is returned from call invocation

### Taker
- [x] #low putLocked / callLocked are bad names since aren't correct, should be takerLocker / providerLocked
- [x] #low naming: collateralAsset should be "underlying", since collateral is ambiguous and is actually cash. Should be just address since not used as erc20.
- [x] #low expiration should be calculated and checked vs. provider position because is key parameter (to reduce coupling)
- [x] #low not all oracle views are checked in _setOracle, use interface instead of contract, check all used views
- [ ] #note Docs are incomplete
- [x] #note timestamp casting is not necessarily safe (if duration is not checked by provider)
- [x] #note previewSettlement arg position struct is awkward, should expect id
- [x] #note 0 put range check unneeded in calculateProviderLocked
- [x] #note naming: deviation -> percent
- [x] #note no good reason for recipient in withdrawal method
- [x] #note cei can be better in settle

###  Escrow
- [ ] #low min take amount to prevent dusting / composability issues

###  Loans
- [ ] #low swap-twap check should use twap value from before the swap, since swap is influencing the twap (reducing price)
- [ ] #low MAX_SWAP_TWAP_DEVIATION_BIPS is too low, and is a DoS risk => raise to 50%, since only for opens and is only a sanity check
- [x] #low check canOpen for self and dependencies contracts
- [ ] #low deadline for all offer specifying txs to prevent abuse of stale txs with current*. This is only relevant for congested networks though so not sure makes sense for arbi.
- [x] #note naming: setKeeperApproved and keeperApproved
- [x] #note naming: open instead of create

### Base admin
- [ ] #low rescuing nfts is not handled: use another arg / function to rescue nfts 
- [ ] #low ownable2step has error prone transfer method (since `transferOwnership` is overridden but functionality is different). override to `nominateOwner`
- [ ] #note docs for BaseEmergencyAdmin and BaseNFT + why they need config hub
- [x] #note naming: EmergencyAdmin is role and not attribute. BaseHubControlled?

###  ConfigHub:
- [ ] #low isSupportedCash/Collateral redundant because canOpen is sufficient and the methods are always used together + assets are immutable in all using contracts. increases potential for config issues, gas, and admin dos.
- [ ] #low ownable2step has error prone transfer method (since `transferOwnership` is overridden but functionality is different), override to `nominateOwner`
- [ ] #low pause guardians should be a mapping / set to avoid having to share pauser pkey between team members / owner multi-sig signers and bot
- [ ] #note docs are incomplete
- [x] #note naming: BIPS / percent in LTV
- [ ] #note MAX_CONFIGURABLE_DURATION 5 years seems excessive?

### Rolls
- [ ] #low taker has insufficent protection: needs deadline for congestion / stale transactions, max roll fee for direct fee control (since fee adjusts with price)
- [ ] #note "active" state variable can be replaced by checking if contract owns provider NFT
- [ ] #note provider deadline protection may be excessive, since can cancel stale offers, and has price limits, and requires approvals
- [x] #note create offer balance and allowance checks seem redundant since for spoofing can easily be passed by providing positive amount, and for mistake prevention only helps with temporary issues. Consider removing to reduce complexity.
- [x] #note naming: `rollFee*` stutter
- [x] #note execute checks order can be more intuitive: access control move to top, rearrange other checks
- [x] #note doc that `uint(-..)` reverts for int.min
- [x] #note docs why canOpen is not used
- [x] #note offer min max price check too strict, can be equal
- [x] #note `_abs` can be replaced with OZ lib usage

## Remaining from previous review:
- [ ] #low (design) providers cannot control their "slippage" (must actively manage liquidity with price changes, and are exposed to oracle risk) accepting trades at any oracle price from the taker contract. maybe worth to store acceptable price ranges per provider for opening positions?
- [ ] #low Oracle decimals and amounts: 1e18 is used as base token amount, which is confusing if collateral token has lower decimals. e.g., 1e18 USDC is 1 trillion, so price for USDC base token is for 1 trillion units
- [x] #note missing interface docs + redirects in implementations


## Known design issues (for audits)
- no refund of protocol fee for cancellations, e.g., in case of rolls. fee APR and roll frequency are assumed to be low, and rolls are assumed to be beneficial enough to users to be worth it. accepted as low risk economic issue.
- loanNFT owner is pushed any collateral leftovers during foreclosure instead of pulling (so can be a contract that will not forward it to actual user, e.g., an NFT trading contract). accepted severity low: low likelihood, medium impact.
- loans currentProviderNFT, currentEscrowNFT, and currentRolls are assumed to change infrequently, so a stale transaction in which an offer for a different contract was intended by user is expected to be unlikely: arbitrum is unlikely to keep pending stale transactions, admin is trusted not to abuse, offer is assumed to not coincide with another existing offer in case of mistake, and various slippage parameters are assumed to be sufficient to prevent malicious scenarios. accepted risk up to low severity.
- because oracle uses 1e18 as token amount, underlying asset tokens with more than 18 decimals and/or very low prices may have low precision prices  
