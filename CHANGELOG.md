# Changelog

Notable changes to contracts.

# Unreleased (0.3.0)

- BaseManaged:
  - No direct ownership, instead has `onlyConfigHubOwner` modifier.
  - All pausing removed.
- CollarTakerNFT, LoansNFT, EscrowSupplierNFT, CollarProviderNFT:
  - Inheriting from updated BaseManaged (not ownable, not pausable).
  - Different constructor interface. 
  - Using `onlyConfigHubOwner` for admin methods.
- CollarProviderNFT:
  - `protocolFee` charges fee on full notional amount (cash value of loan input), and expects `callStrikePercent` argument.
- Rolls:
  - Update to use the updated protocolFee interface.
  - Not inheriting from BaseManaged. 

# 0.2.0 (All contracts)

First version deployed to Base mainnet. 
