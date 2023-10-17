# Collar Protocol Vault

The vault is the abstraction (and currently, the implementation) of the collar. It is created when a user wishes to collar their asset, selects liquidity constraints, and then supplies the necessary liquidity to the engine. The engine itself creates the vault contract.

The vault allows the user to withdraw (up to the specified LTV) their loan. The vault vault allows the user and/or marketmaker to withdraw their collateral/cash when the vault matures.