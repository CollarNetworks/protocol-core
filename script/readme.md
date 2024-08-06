# Prerequisites
Before asking questions about `forge script`, please read the following:

https://book.getfoundry.sh/tutorials/solidity-scripting

# Deploying the Protocol

## Dev / Local

TODO

## Interfacing with the deployed contracts

TODO

### Mock Contracts
    
TODO

## Contract ABIs

To build a frontend that interacts with the smart contracts, you'll need the ABIs for each contract. You can grab them via `forge inspect`:

`> forge inspect CollarEngine abi` : outputs to console

`> forge inspect CollarEngine abi > ~/CollarFrontend/abis/CollarEngine.json` : outputs to file, use this in your frontend web3 lib

## Customizing deploy scripts

To tweak the deploy scripts or add new functionality, just copy and paste either smart contract in `script/dev.s.sol` - just don't forget to change the name of the smart contract for that script to something descriptive and unique.
