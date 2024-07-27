# Collar Protocol v1

Note: These docs are likely outdated.
TODO: Update these docs.

## Overview

TODO: update

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

TODO: update
