(copied from https://gist.github.com/philbugcatcher/d9abe138d63f1f462aa51e2af2e1ba0a)

# Collar Protocol Fix Review

**Conducted by:** Phil (philbugcatcher)  
**Date:** January 14th, 2025  
**Review Commit Hash:** `897a702d8967ac9a5f32b6c1969723f929900d6d`  
**Fixed Commit Hash:** `d3677887a684e051f959438b7bbc8d2ef114590b`

# Summary
**Findings Count**
| Severity          | Count | Fixed | Acknowledged |
|-------------------|-------|-------|--------------|
| Critical risk     | 0     | 0     | 0            |
| High risk         | 0     | 0     | 0            |
| Medium risk       | 0     | 0     | 0            |
| Low risk          | 2     | 0     | 2            |
| Informational     | 2     | 0     | 2            |
| Gas Optimizations | 3     | 0     | 3            |
| **Total**         | **7** | **0** | **7**        |

# Table of contents
- [Issues](#issues)
  - [[L-1] `Rolls::createOffer()` slippage protection does not protect from reference price slippage on the creation of the offer](#l-1-rollscreateoffer-slippage-protection-does-not-protect-from-reference-price-slippage-on-the-creation-of-the-offer)
  - [[L-2] `EscrowSupplierNFT.sol` will not properly escrow the borrower's underlying if the price of the underlying is above the call strike price when the loan is closed](#l-2-escrowsuppliernftsol-will-not-properly-escrow-the-borrowers-underlying-if-the-price-of-the-underlying-is-above-the-call-strike-price-when-the-loan-is-closed)
  - [[I-1] `CollarProviderNFT.sol` is not required to have the same `ConfigHub.sol` as its `CollarTakerNFT.sol` counterpart](#i-1-collarprovidernftsol-is-not-required-to-have-the-same-confighub-as-its-collartakernftsol-counterpart)
  - [[I-2] `EscrowSupplierNFT.sol` is not required to have the same `ConfigHub.sol` as its `LoansNFT.sol` counterpart](#i-2-escrowsuppliernftsol-is-not-required-to-have-the-same-confighubsol-as-its-loansnftsol-counterpart)
    <br>

- [Optimization](#optimization)
  - [[G-1] Checking `canOpenPair()` for the taker and provider in `LoansNFT` and `CollarProviderNFT` is not necessary](#g-1-checking-canopenpair-for-the-taker-and-provider-in-loansnft-and-collarprovidernft-is-not-necessary)
  - [[G-2] Escrow cleaning on `LoansNFT::_openLoan()` is unnecessary, and only adds to the gas consumption](#g-2-escrow-cleaning-on-loansnft_openloan-is-unnecessary-and-only-adds-to-the-gas-consumption)
  - [[G-3] `CollarProviderNFT.sol` could use one less storage slot (reducing reading and writing to storage) by using the `CollarTakerNFT.sol`'s `takerId`](#g-3-collarprovidernftsol-could-use-one-less-storage-slot-reducing-reading-and-writing-to-storage-by-using-the-collartakernftsols-takerid)
    <br>

- [Documentation](#documentation)
  - [Outdated comment on `LoansNFT::keeperApprovedFor()`](#outdated-comment-on-loansnftkeeperapprovedfor)
  - [Comment on `LoansNFT::onlyNFTOwner()` mentions taker ID instead of loan ID](#comment-on-loansnftonlynftowner-mentions-taker-id-instead-of-loan-id)
  - [`LoansNFT::_openLoan()` comments references a wrong/ outdated function name](#loansnft_openloan-comments-references-a-wrong-outdated-function-name)
  - [Outdated comments on `LoansNFT::closeLoan()`](#outdated-comments-on-loansnftcloseloan)
  - [Outdated/ wrong comments on `EscrowSupplierNFT::endEscrow()`](#outdated-wrong-comments-on-escrowsuppliernftendescrow)
  - [`Rolls::createOffer()`'s NatSpec doesn't mention that the provider must approve the NFT to the contract](#rollscreateoffers-natspec-doesnt-mention-that-the-provider-must-approve-the-nft-to-the-contract)
  - [`LoansNFT::_loanAmountAfterRoll()` references an outdated function name](#loansnft_loanamountafterroll-references-an-outdated-function-name)
  - [Outdated comments on `EscrowSupplierNFT::switchEscrow()`](#outdated-comments-on-escrowsuppliernftswitchescrow)
    <br>
    <br>


## Issues
<br>

### [L-1] `Rolls::createOffer()` slippage protection does not protect from reference price slippage on the creation of the offer
#### Summary
`Rolls::createOffer()` has slippage parameters for the provider. However, it does not protect against the slippage of the reference price on the creation of the offer.
<br>

#### Description
When the rolls offer is created, the contract fetches the oracle price for the asset, and ties the user-provided `feeAmount` to that specific price (`feeReferencePrice`). This price will be used to adjust the fee effectively charged to the taker, according to the `feeDeltaFactorBIPS` provided.
<br>

This means that if the reference price shifts between the moment the user sends the transaction and the moment the transaction is included in the blockchain, the offer will be tied to a different reference price than the one the provider used to assemble their offer.
<br>

#### Recommendation
Allow the provider to inform their reference price directly instead of fetching from the oracle, or implement reference price slippage (e.g. `minReferencePrice` and `maxReferencePrice`).
<br>

#### Status: acknowledged
**Protocol comment:**
> Added documentation in [d367788](https://github.com/CollarNetworks/protocol-core/pull/114/commits/d3677887a684e051f959438b7bbc8d2ef114590b). Taking a user specified reference price is possibly a more useful interface, and we'll document this to be considered for a future change. Simplicity and reduction of surface area are the advantages of the current approach. The impact is limited since "slippage" is limited due to the market price oracle usage, and if the reference price doesn't suit the provider, they can cancel (and possibly redo the offer).
<br>
<br>

### [L-2] `EscrowSupplierNFT.sol` will not properly escrow the borrower's underlying if the price of the underlying is above the call strike price when the loan is closed
#### Description
The `EscrowSupplierNFT.sol` contract is supposed to hold the borrower's funds for the duration of the loan, returning to the borrower when the loan ends. This is necessary so that the borrower sells "the supplier's tokens" instead of their own.
<br>

However, if the price of the underlying is above the call strike price when the loan is closed, the borrower will receive less underlying than they escrowed initially. Effectively, this means that the borrower sold their own underlying.
<br>

#### Recommendation
Close loans with escrow based on the `quantity of underlying tokens`, instead of the `quantity of cashAsset tokens`
<br>

#### Status: acknowledged
**Protocol comment:**
> Added documentation in [d367788](https://github.com/CollarNetworks/protocol-core/pull/114/commits/d3677887a684e051f959438b7bbc8d2ef114590b). This is [already documented](https://github.com/CollarNetworks/protocol-core/blob/897a702d8967ac9a5f32b6c1969723f929900d6d/src/LoansNFT.sol#L184-L185), but the recommendation makes sense, even though repaying more than loaned initially is likely to have its own tax implications for the borrower. In a future version, it's possible that custom repayment amounts (instead of the full loanAmount) will be added, allowing users to take a fuller advantage of the escrow.
<br>
<br>

### [I-1] `CollarProviderNFT.sol` is not required to have the same `ConfigHub.sol` as its `CollarTakerNFT.sol` counterpart
#### Description
This can cause inconsistencies, such as a different paused state across contracts, or different settings, such as allowed duration or LTV intervals.
<br>

#### Recommendation
Set the `ConfigHub` in the constructor (similarly to `LoansNFT.sol` and `Rolls.sol`), either with a low level call or importing the taker interface.
<br>

#### Status: acknowledged
**Protocol comment:**
> This is a fair point, but it's a complex tradeoff space. Allowing per-contract settings contract makes migrations easier by avoiding migration complexity (due to the need for a single common settings contract). For example, if a new ProviderNFT implementation requires a new config value, or a breaking interface change in config interface compared to what older ProviderNFTs need, it makes sense to allow newer contract to use newer ConfigHub. Another example is making it possible to control pause guardians lists with higher granularity.
<br>
<br>

### [I-2] `EscrowSupplierNFT.sol` is not required to have the same `ConfigHub.sol` as its `LoansNFT.sol` counterpart
#### Description
This can cause inconsistencies, such as a different paused state across contracts, or different settings, such as allowed duration or LTV intervals.

One example of this inconsistency would be if the admin pauses the `ConfigHub.sol` associated with `LoansNFT.sol`, but not with `EscrowSupplierNFT.sol`, the escrow owner would be able to seize the escrow.
<br>

#### Recommendation
Check whether the `EscrowSupplierNFT.sol` contract shares the same `ConfigHub` on `LoansNFT::_conditionalOpenEscrow()`:
```diff
    function _conditionalOpenEscrow(bool usesEscrow, uint escrowed, EscrowOffer memory offer, uint fees)
        internal
        returns (EscrowSupplierNFT escrowNFT, uint escrowId)
    {
        if (usesEscrow) {
            escrowNFT = offer.escrowNFT;
+           // check if escrowNFT uses the same ConfigHub
+           require(address(configHub) == address(escrowNFT.configHub()));
```
<br>

#### Status: acknowledged
**Protocol comment:**
> This is a fair point, but it's a complex tradeoff space. Allowing per-contract settings contract makes migrations easier by avoiding migration complexity (due to the need for a single common settings contract). For example, if a new ProviderNFT implementation requires a new config value, or a breaking interface change in config interface compared to what older ProviderNFTs need, it makes sense to allow newer contract to use newer ConfigHub. Another example is making it possible to control pause guardians lists with higher granularity.
<br>
<br>

## Optimization
<br>

### [G-1] Checking `canOpenPair()` for the taker and provider in `LoansNFT` and `CollarProviderNFT` is not necessary
The `LoansNFT.sol` and `CollarProviderNFT.sol` contracts define a single, immutable, non-upgradeable `CollarTakerNFT.sol` contract upon deployment. The `CollarTakerNFT.sol` contract already requires that itself and the `CollarProviderNFT.sol` counterpart it is interacting with can open a paired position upon `CollarTakerNFT::openPairedPosition()`:
```solidity
    function openPairedPosition(uint takerLocked, CollarProviderNFT providerNFT, uint offerId)
        external
        whenNotPaused
        returns (uint takerId, uint providerId)
    {
        // check asset & self allowed
@>      require(configHub.canOpenPair(underlying, cashAsset, address(this)), "taker: unsupported taker");
        // check assets & provider allowed
@>      require(
            configHub.canOpenPair(underlying, cashAsset, address(providerNFT)), "taker: unsupported provider"
        );
        // check assets match
        require(providerNFT.underlying() == underlying, "taker: underlying mismatch");
        require(providerNFT.cashAsset() == cashAsset, "taker: cashAsset mismatch");
        // check this is the right taker (in case multiple are allowed). ProviderNFT checks too.
@>      require(providerNFT.taker() == address(this), "taker: taker mismatch");
```
<br>

Therefore, it is not necessary to check this on all of these 3 contracts.
<br>

The rationale is similar to this comment on `EscrowSupplierNFT`:
```solidity
        // @dev loans is not checked since is directly authed in this contract via setLoansAllowed
```
<br>

#### Status: acknowledged
**Protocol comment:**
> These input validation and close-only mode checks make sense in each contract, since otherwise assumptions about implementation details of the others need to be made, creating unnecessary coupling and surface area. Also, as noted in I-1 and I-2, the ConfigHubs controlling each side can be different contracts.
<br>
<br>

### [G-2] Escrow cleaning on `LoansNFT::_openLoan()` is unnecessary, and only adds to the gas consumption
The function `_openLoan()` is only called internally by the external functions `openLoan()` and `openEscrowLoan()`. As of the current implementation, it is not possible for the `_openLoan()` function to be called with `usesEscrow == false && escrowFees != 0`.
<br>

This is because the `usesEscrow` parameter is defined by the contract (i.e. not user input) on the external functions `openLoan()` and `openEscrowLoan()`, and will always be, respectively, false and true.
<br>

In the case of the `openLoan()`, the contract also defines `escrowFees == 0`, not allowing user input. This means the only path to `usesEscrow == false` also sets `escrowFees == 0`.
<br>

#### Status: acknowledged
**Protocol comment:**
> Agree that it does not impact calculation and is only there for readability. This is already [documented there](https://github.com/CollarNetworks/protocol-core/blob/897a702d8967ac9a5f32b6c1969723f929900d6d/src/LoansNFT.sol#L415), this should ideally be optimized away by the compiler, but in case it does not the gas impact is negilgible.
<br>
<br>

### [G-3] `CollarProviderNFT.sol` could use one less storage slot (reducing reading and writing to storage) by using the `CollarTakerNFT.sol`'s `takerId`
This would reduce storage read and write on `CollarProviderNFT.sol`. There is no risk of ID collision, as each `CollarProviderNFT.sol` contract only has one immutable `CollarTakerNFT.sol` counterpart.
<br>

Additionally, it would be simpler to have the same NFT ID for each side of the collar position.
<br>

#### Status: acknowledged
**Protocol comment:**
> This is a good possible optimization and simplification, as well as possibly better UX, and we'll consider this for a future version. While the storage impact would remain similar (takerId is part of the first slot of the struct), the SSTORE for the nextTokenId increment can be saved (roughly 7k gas).
<br>
<br>

## Documentation
<br>

### Outdated comment on `LoansNFT::keeperApprovedFor()`
```diff
+   // borrowers that allow a keeper for loan closing for specific loans
-   // callers (users or escrow owners) that allow a keeper for loan closing for specific loans
```

#### Status: Fixed in [d367788](https://github.com/CollarNetworks/protocol-core/pull/114/commits/d3677887a684e051f959438b7bbc8d2ef114590b)

<br>
<br>

### Comment on `LoansNFT::onlyNFTOwner()` mentions taker ID instead of loan ID
```diff
    modifier onlyNFTOwner(uint loanId) {
+       /// @dev will also revert on non-existent (unminted / burned) loan ID
-       /// @dev will also revert on non-existent (unminted / burned) taker ID
```

#### Status: Fixed in [d367788](https://github.com/CollarNetworks/protocol-core/pull/114/commits/d3677887a684e051f959438b7bbc8d2ef114590b)

<br>
<br>

### `LoansNFT::_openLoan()` comments references a wrong/ outdated function name
```diff
+       // taker NFT and provider NFT canOpen is checked in _swapAndMintCollar
-       // taker NFT and provider NFT canOpen is checked in _swapAndMintPaired
```

#### Status: Fixed in [d367788](https://github.com/CollarNetworks/protocol-core/pull/114/commits/d3677887a684e051f959438b7bbc8d2ef114590b)

<br>
<br>

### Outdated comments on `LoansNFT::closeLoan()`
Late fees are not handled by this function anymore:
```diff
     * @notice Closes an existing loan, repaying the borrowed amount and returning underlying.
     * If escrow was used, releases it by returning the swapped underlying in exchange for the
+    * user's underlying, returning leftover fees if any.
-    * user's underlying, handling any late fees.
     * The amount of underlying returned may be smaller or larger than originally deposited,
     * depending on the position's settlement result, escrow late fees, and the final swap.
```

```diff
+       // release escrow if it was used, returning leftover fees if any.
-       // release escrow if it was used, paying any late fees if needed.
```

#### Status: Fixed in [d367788](https://github.com/CollarNetworks/protocol-core/pull/114/commits/d3677887a684e051f959438b7bbc8d2ef114590b)

<br>
<br>

### Outdated/ wrong comments on `EscrowSupplierNFT::endEscrow()`
```diff
    /**
     * @notice Ends an escrow. Returns any refund beyond what's owed back to loans.
     * @dev Can only be called by the Loans contract that started the escrow
     * @param escrowId The ID of the escrow to end
+    * @param repaid The amount repaid which should be equal to or less than the original escrow amount.
-    * @param repaid The amount repaid which should be equal to the original escrow amount.
     * @return toLoans Amount to be returned to loans (refund deducing shortfalls)
     */
```
<br>

```diff
+       // transfer in the repaid assets
-       // transfer in the repaid assets in: original supplier's assets, plus any late fee
        asset.safeTransferFrom(msg.sender, address(this), repaid);
```

#### Status: Fixed in [d367788](https://github.com/CollarNetworks/protocol-core/pull/114/commits/d3677887a684e051f959438b7bbc8d2ef114590b)

<br>
<br>

### `Rolls::createOffer()`'s NatSpec doesn't mention that the provider must approve the NFT to the contract
--

#### Status: Fixed in [d367788](https://github.com/CollarNetworks/protocol-core/pull/114/commits/d3677887a684e051f959438b7bbc8d2ef114590b)

<br>
<br>

### `LoansNFT::_loanAmountAfterRoll()` references an outdated function name
```diff
+       // The transfer subtracted the fee (see Rolls _previewRoll), so it needs
-       // The transfer subtracted the fee (see Rolls _previewTransferAmounts), so it needs
```

#### Status: Fixed in [d367788](https://github.com/CollarNetworks/protocol-core/pull/114/commits/d3677887a684e051f959438b7bbc8d2ef114590b)

<br>
<br>

### Outdated comments on `EscrowSupplierNFT::switchEscrow()`
This comment refers to the previous version, that charged late fees upon the end of the escrow, and not relevant now that the late fees are prepaid:
```diff
-       // do not allow expired escrow to be switched since 0 fromLoans is used for _endEscrow
```
<br>

This comment does not address late fees:
```diff
+       Escrow fees are accounted separately by transferring the full N's fees
+       (held until release), and refunding O's fees held.
-       Interest is accounted separately by transferring the full N's interest fee
-       (held until release), and refunding O's interest held.
```

#### Status: Fixed in [d367788](https://github.com/CollarNetworks/protocol-core/pull/114/commits/d3677887a684e051f959438b7bbc8d2ef114590b)
