# Collar Protocol Architechture

## Contracts - Overview

### Engine
The engine is the heart of the system. It is responsible for the following:
    
 - creating new vaults
 - managing liquidity
 - system-wide access control
 - upgrade mechanics for vaults (should we want this)


### Vaults
 - vaults are idempotent with collars
 - a user can have many vaults; a vault can only have one user
 - a vault can have many market makers - depending on how the composition of the liquidity pool pulled from
 - vaults are created by the engine by the end-user
 - vaults are supplied with liquidity from market makers via liquidity pools and from users directly
 - vaults have only two possible states: active and inactive
 - vaults will NOT user ERC4626
 - vaults WILL be ERC721
 - vaults will initially have a fixed LTV and put-strike %
 - vaults will have a fixed duration
 - vaults can be "rolled", but really what is happening underneath is just closing and reopening with different parameters, assuming sufficient liquidity

### Liquidity Pools
 - liquidity pools will be fairly simple to start with
 - simply a smart contract that holds and tracks the cash balances of each market maker and bins them into buckets based on their risk profile, which they can adjust
 - this is similar in concept to uniswap liquidity ticks, but not as complicated
 - also similar to uniswap, we'll have "view/helper" contracts that add utility with calculating liquidity, moving liquidity, etc - think "router"

 ## MVP Implementation
 - an engine that handles auth and creates the vaults
 - a liquidity pool manager that creates new liquidity pools for tokens and proxies calls to the liquidity pools
 - vaults that are created on-demand with liquidity from the liquidity pools when users send in their assets

## Steps to MVP
 - [x] list out desired user and market maker flows
 - [x] list out desired admin and system management flows
 - [x] list out every single interaction between system smart contracts
 - [ ] create interfaces for each smart contract
    - [ ] Engine
    - [ ] Vault
    - [x] Liquidity Pools
    - [x] Liquidity Pool Manager
    - [ ] Lens
 - [ ] create implementations for each smart contract
    - [ ] Engine
    - [ ] Vault
    - [ ] Liquidity Pools
    - [ ] Liquidity Pool Manager
    - [ ] Lens
 - [ ] create test suites for each contract and for flows