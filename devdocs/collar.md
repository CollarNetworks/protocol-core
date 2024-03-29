# Collar Protocol v1

Note: These docs are likely outdated.
TODO: Update these docs.

## Overview

Collar Protocol consists of three main components.

> The engine coordinates governance and sets system parameters.

> Vaults are the primary user-facing component of the protocol.

> Market makers provide liquidity via liquidity pools for vaults.


## The Collar

User provides collateral to the system and is issued a loan against the value of the collateral.
The user is protected against downside risk of the collateral's value (to a degree), but is similarly
limited in upside potential.

There are two primary parameters to each Collar: the callstrike and the putstrike.

##### CallStrike: The upside potential of the collar

The callstrike can be any percentage above 100%; this caps the upside potential of the collar
to the percentage value of the starting price of the collateral.

A value of 120% would mean that the user could close the vault with up to 20% profit on the value of the supplied collateral.

##### PutStrike: The downside protection of the collar

The putstrike can be any percentage below 100%; this limits the downside risk of the collar
to the percentage value of the starting price of the collateral.

A value of 80% would mean that the user could close the vault with up to a maximum of 20% loss on the value of the supplied collateral.

### Example Collar

Here's an example collar:

> User Bob creates a vault with 1 ETH (spot price $3000), 85% putstrike, 115% callstrike

> Upon vault creation, the 1 ETH is swapped for $3000 @ spot. $2550 of this is available to Bob immediately as a loan. The remaining $450 is locked in the vault until expiration of the vault - this amount is at risk should the price finalize below the starting price. 

> Simultaneously, $450 from a Collar Liquidity Pool (to match the 115% callstrike) is locked until expiration of the vault. This amount covers the upside potential and could be used to cover the user's gains, should the price finalize above the starting price.

## Smart Contracts

### Engine

The Engine is the core governance and system control smart contract of the Collar Protocol.

It is the canonical lookup hub for allowed assets, vault parameters, and liquidity pools.

It will direct system fees and (eventually) contain governance for the protocol.

### Vault

Because vaults are conceptual objects, they can't be their own smart contracts - a user can have many vaults.

Vaults are created, tracked, and managed via the `VaultManager` smart contract, which allows users to execute the following operations:

- Create a new vault (given a collateral asset, a cash asset, a putstrike, and a callstrike)
- Withdraw cash as a loan from an existing vault
- Finalize an existing vault

#### Vault Creation

When a user creates a new vault, the following occurs:

1) The user's collateral is swapped for cash at the current spot price (with allowed slippage parameters)

2) The cash from the above swap is divided into two portions: the loan amount and the locked amount.

3) The locked amount is used to mint a new ERC1155 token which represent's the user's Collar to the user.

#### Vault Finalization

1) The price of the collateral asset at time of vault closure is checked.

2) The conversion rate of the ERC1155 token is set based on the price of the collateral asset at time of vault closure. This will allow the user to redeem the ERC1155 token for more or less than the original locked amount, depending on the price of the collateral asset at time of vault closure.

3) The conversion rate of the ERC115 token created in the **liquidity pool** itself is also set in a similar fashion.

### Liquidity Pool

The engine keeps tracks of a set of canonical liquidity pool smart contracts, where market makers may deposit liquidity
to be used for vaults, and indicate at what callstrike and putstrike ranges their liquidity may be used for.

Liquidity pools are each their own deployed smart contract; one per collateral asset (this feature is wip), one per cash asset (USDC, DAI, etc), per putstrike value (80%, 85%, etc), per vault length (1 month, 3 months, etc).

Thus a theoretical set of liquidity pools may look like this:

| Address | Asset | PutStrike | Vault Length |
| --- | --- | ----------- | ----|
| 0x12345678... | USDC | 80% | 1 month |
| 0x12345678... | USDC | 80% | 3 months |
| 0x12345678... | USDC | 85% | 1 month |
| 0x12345678... | USDC | 85% | 3 months |
| 0x12345678... | DAI | 80% | 1 month |
| 0x12345678... | DAI | 80% | 3 months |
| 0x12345678... | DAI | 85% | 1 month |
| 0x12345678... | DAI | 85% | 3 months |

Vaults can only be created by matching a user's request with available liquidity from a pool. 
When this match occurs, liquidity is "locked" for the vault until the vault is finalized.

#### Locking Liquidity via ERC1155

When liquidity is locked in a pool, it is converted to a new ERC1155 token.
This token can be exchanged for the underlying (adjusted) liquidity at vault finalization, but
note that it will be worth a different amount than the original liquidity deposited, depending 
on the vault outcome. It might even be worth zero!