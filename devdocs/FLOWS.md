# Collar Protocol - User & System Flows

Basically, what actions can the end user, the market maker, and the system administrators do and what does that look like?

## Users
- View what they could get for a vault, including how much liquidity is available and at what maximum profit cap they can get it at, and for which underlying tokens
- Open a fault with some underlying collateral, and take out a loan against their collatera
- Be able to pay back their loan
- Be able to withdraw assets (if applicable) when a vault matures

## Market Makers
- Be able to supply liquidity to liquidity pools at various rates (in terms of maximum profit cap to users)
- Be able to see all their liquidity in one place
- Be able to see how much of their liquidity is locked in vaults, and how much is free
- Be able to withdraw liquidity from matured vaults easily, or have them auto-sent back into the liquidity pools
- Be able to pre-mark liquidity that is currently in use to be allocated to a different profit cap % than it currently is
- Be able to see what undelrying collateral their liquidity is backing up

## Admins
- Be able to pause the system in case of castastrophic failure
- Be able to upgrade the system to add features
- Should (eventually) NOT be able to take sole custody of user funds
- Should be able to adjust system paramters, within reason