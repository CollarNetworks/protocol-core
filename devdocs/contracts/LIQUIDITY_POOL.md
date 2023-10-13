# Collar Protocol Liquiditiy Pool

The liquidity pool is the most critical upgrade from v0 --> v1 of Collar. It replaces the RFQ process, making it (from the user's perspective) "one-click" to open a vault. No back and forth needed.

This requires market makers to predisclose their preferences, aka, show their cards. This might be something we improve in V2 but it doesn't seem easy to do. Probably not impossible though.

Market makers predisclose these preferences by providing liquidity at specific ranges (ticks), very similar to how one does when one provides liquidity on Uniswap V3. Liquidity in a particular tick is represented by a proportional share of ownership of that tick, and liquidity is pulled proportionally from each market maker of a ticket that multiple market makers have supplied to.

We maintain a mapping of each market maker's supplied liquidity; to calculate how much of this is "locked" (in use in a vault), we compare their supplied liquidity in a tick to the sum total liquidity in a tick, and look at the proportional usage of this liquidity. Their locked amount is thus easily calculable.

Let us represent a simplified system with only two liquidity ticks: T1 and T2, and market makers MM-X and MM-Y. We will show the internal state of the liquidity pool at each step of market makers depositing, users creating vaults, and vaults maturing, along with market makers withdrawing liquidity when able to do so.

 1) MM-X deposits 100 USDC into T1
    
    ```
    T1: 100 USDC (100% MM-X)
    T2: 0 USDC

    MM-X: 100 USDC (100 USDC @ T1)
    MM-Y: 0 USDC
    ```
 2) MM-Y deposits 50 USDC into T1 & 100 USDC into T2
    
    ```
    T1: 150 USDC (66% MM-X, 33% MM-Y)
    T2: 100 USDC (100% MM-Y)

    MM-X: 100 USDC (100 USDC @ T1)
    MM-Y: 150 USDC (50 USDC @ T1, 100 USDC @ T2)
    ```

 3) MM-X deposits 100 USDC into T2
    
    ```
    T1: 150 USDC (66% MM-X, 33% MM-Y)
    T2: 250 USDC (50% MM-X, 50% MM-Y)

    MM-X: 200 USDC (100 USDC @ T1, 100 USDC @ T2)
    MM-Y: 150 USDC (50 USDC @ T1, 100 USDC @ T2)
    ```


Note that while we *do* track a mapping of market maker balances to the ticks they have their liquidity in, we do NOT populate the reverse mapping.

Let's go through a scenario starting from the end of step 3 where a user wishes to open a vault requiring 300 USDC of matching liquidity and selects the best cap-liquidity that he can - which means using all liquidity at T2 that he can and only then using liquidity @ tick T1.
    
    ```
    User opens vault for 300 USDC - accepts best possible cap rate:

    T1: 150 USDC --> 100 USDC (66% MM-X, 33% MM-Y)
    T2: 250 USDC --> 0 USDC

    MM-X: 66 USDC (66 USDC @ T1)
    MM-Y: 33 USDC (33 USDC @ T1)
    ```

Note that the the ratios for ownership in T1 remain unchanged - this makes it easy to calculate how much a market maker has locked in a partiuclar liquidity tick *without* requiring that we update the reverse mapping every time liquidity is withdrawn, locked, or unlocked in that particular tick.