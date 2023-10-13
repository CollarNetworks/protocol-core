# Smart Contract Interactions

The smart contracts in the system are the following:

1) Collar Engine
2) Vaults
3) Liquidity Pools
4) Liquidity Pool Manager
5) VaultLens
6) Dex Aggregator - Likely 1inch

- **Collar Engine** creates **vaults** when users supply their own liquidity, contingent on there being enough liquidity available at chosen profit cap %

- This liquidity is supplied by market makers via the **Liquidity Pool Manager**

- The **Liquidity Pool Manager** handles creation of the **Liquidity Pools** themselves and is also the contract that handles view-queries about them (similar to the Uni router)

- Users, but particularly market makers, can use the **VaultLens** to get detailed, computed information about vaults and their assets.

- Upon creating a vault, and sometimes later, some of the users' collateral will get auto-swapped to cash via the **Dex Aggregator**