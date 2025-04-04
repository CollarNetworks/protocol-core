# Changelog

Notable changes to contracts.

# Unreleased (0.3.0)

BaseManaged:
  - No direct ownership, instead has `onlyConfigHubOwner` modifier.
  - `rescueTokens` removed. 
  - All pausing removed.
CollarTakerNFT, LoansNFT, EscrowSupplierNFT, CollarProviderNFT:
  - Inheriting from updated BaseManaged (not ownable, not pausable).
  - Different constructor interface. 
  - Using `onlyConfigHubOwner` for admin methods.
LoansNFT:
  - removed the admin method for setting keeper, users can choose a keeper when approving
CollarTakerNFT:
  - `setOracle` is removed, and `settleAsCancelled` (for oracle failure) is added 
CollarProviderNFT:
  - `protocolFee` charges fee on full notional amount (cash value of loan input), and expects `callStrikePercent` argument.
EscrowSupplierNFT:
  - remove `loansCanOpen` and admin setter, and use canOpenPair on configHub for this auth instead
Rolls:
  - Update to use the updated protocolFee interface.
  - Not inheriting from BaseManaged.
  - Add `previewOffer` view 
ConfigHub
  - remove pause guardians
  - make canOpenPair interface more loose to allow removing supplier's `loansCanOpen`    

# 0.2.0 (All contracts)

First version deployed to Base mainnet. 
