# Prerequisites
Before asking questions about `forge script`, please read the following:

https://book.getfoundry.sh/tutorials/solidity-scripting

# Deploying the Protocol

## Dev / Local

 First, start the anvil chain in a separate terminal window:
 
 `> anvil`

 Next, load private keys via .env file. (If you haven't copied `.env.example` yet and created your `.env`, do this now. The content in `.env.example` is exactly what you need for your dev environment, so no need to change anything)

 `> source .env`
 
 Then, run either of the following commands to deploy the protocol to the local chain.

 To deploy a completely empty protocol with only the engine, test tokens, and a single liquidity pool: 
 
`> forge script script/deploy-protocol.s.sol --fork-url http://localhost:8545 --broadcast --tc DeployEmptyProtocol --sender 0xa0Ee7A142d267C1f36714E4a8F75612F20a79720`

 To deploy a protocol preloaded with two test users and their vault managers already created: 
 
`> forge script script/deploy-protocol.s.sol --fork-url http://localhost:8545 --broadcast --tc DeployInitializedProtocol --sender 0xa0Ee7A142d267C1f36714E4a8F75612F20a79720`

 To deploy a protocol preloaded with two test users, their vault managers already created, and pools filled (recommended): 

 `> forge script script/fill-liquidity-pool-slots.s.sol --fork-url http://localhost:8545 --broadcast --tc FillLiquidityPoolSlots --sender 0xa0Ee7A142d267C1f36714E4a8F75612F20a79720`

## Interfacing with the deployed contracts

Once you deploy the protocol as specified above, scroll up a little bit in your console to see the output logs of the script. You should see something like this:

```
== Logs ==
  
 --- Dev Environment Deployed ---
  
 # Dev Deployer Address: 0xa0Ee7A142d267C1f36714E4a8F75612F20a79720
  
 # Dev Deployer Key:     0x2a871d0798f97d79848a013d4936a73bf4cc922c825d33c1cf7073dff6d409c6
  
 # Contract Addresses

   - Cash Test ERC20 - - - - -  0x067c804bb006836469379D4A2A69a81803bd1F45
   - Collateral Test ERC20 - -  0x45009DD3aBBE29Db54fc5D893CeAa98a624882DF
   - Mock Router:  - - - - - -  0xf56AA3aCedDf88Ab12E494d0B96DA3C09a5d264e
   - Mock Engine - - - - - - -  0xdBD296711eC8eF9Aacb623ee3F1C0922dce0D7b2
   - Collar Pool - - - - - - -  0xDFD787c807DEA8d7e53311b779BC0c6a4704D286
  
 # Test Users

   - User 1 Address: 0x23618e81E3f5cdF7f54C3d65f7FBc0aBf5B21E8f
   - User 1 Privkey: 0xdbda1821b80551c9d65939329250298aa3472ba22feea921c0cf5d620ea67b97
   - User 2 Address: 0x14dC79964da2C08b23698B3D3cc7Ca32193d9955
   - User 2 Privkey: 0x4bbbf85ce3377467afe5d46f804f221813b2bb87f24d81f60f1fcdbf7cbf4356
   - User 3 Address: 0x976EA74026E726554dB657fA54763abd0C3a0aa9
   - User 3 Privkey: 0x92db14e403b83dfe3df233f83dfa3a0d7096f21ca9b0d6d6b8d88b2b4ec1564e
  
 # Vault Managers

   - User 1 Vault Manager:  0x95bD8D42f30351685e96C62EDdc0d0613bf9a87A
   - User 2 Vault Manager:  0xef11D1c2aA48826D4c41e54ab82D1Ff5Ad8A64Ca
   ```

Import the private keys for the deployer and the test addresses into a dev wallet so that you can easily switch between them. Metamask should work fine. All of the default addresses here are among the 10 anvil default accounts and should be preloaded with plenty of ETH; users 1 and 2 are by default preloaded with 100k of each test token (cash and collateral), and you can easily get more by calling `TestToken.mint(address, amount)` on the deployed test token smart contracts.

### Mock Contracts
    
For this local/dev environment, we don't need to set up all of Uniswap, Chainlink oracles, etc. So we mock this functionality instead. Specifically, the following:

 - [TestERC20 tokens](../test/utils/TestERC20.sol) - standard ERC20 implementation, but with added function for easy & free minting. You can call `mint(address, amount` on these contracts to get free tokens for testing. By default this is what `cashTestToken` and `collateralTestToken` are in the two deploy scripts here.

 - [Mocked UniV3 Router](../test/utils//MockUniRouter.sol)  - extremely simple mock of the Uniswap V3 router implementing only the `exactInputSingle` method (which is what vaults currently use to swap from collateral to cash). It will always use the maximum allowable slippage, eg `amountOutMinimum` and the trade will always succeed for any value (assuming the router has enough tokens; it's preloaded with 1 million of each token in each of these scripts by default)

 - [Mock Engine](../test/utils/MockConfigHub.sol) - fully functional `CollarEngine`, but we add in two functions to set the current price of an asset (for opening vaults) and the historical price of an asset at some blocktime (for closing vaults). You can have a look at the [vault manager tests](../test/unit/CollarVaultManager.t.sol) to see more specifically how this can be used.

## Contract ABIs

To build a frontend that interacts with the smart contracts, you'll need the ABIs for each contract. You can grab them via `forge inspect`:

`> forge inspect CollarEngine abi` : outputs to console

`> forge inspect CollarEngine abi > ~/CollarFrontend/abis/CollarEngine.json` : outputs to file, use this in your frontend web3 lib

## Customizing deploy scripts

To tweak the deploy scripts or add new functionality, just copy and paste either smart contract in `script/dev.s.sol` - just don't forget to change the name of the smart contract for that script to something descriptive and unique.
