#!/bin/bash

# Usage:
# - use this if some contracts ended up not verified after broadcast
# - ensure etherscan API and env vars are properly defined in foundry.toml and .env
# - can be run any number of times, verified contracts will be skipped by forge

# the broadcast file to use from the run that needs re-verification
BROADCAST_FILE="broadcast/deploy-protocol.s.sol/8453/dry-run/run-latest.json"
# the chain id
CHAIN_ID="8453"
RPC_VAR="OPBASE_MAINNET_RPC"
# a single command for verification. RPC is used to guess deploy args, --watch is waiting until finished.
FORGE_BASE_CMD="forge verify-contract -c $CHAIN_ID --verifier etherscan --watch --guess-constructor-args -r \$$RPC_VAR"

echo "# Verification commands to execute (paste into terminal)"
# extract any contracts deployed (CREATE type transactions) and print verification commands for them
jq -r ".transactions[] | select(.transactionType == \"CREATE\") | \"$FORGE_BASE_CMD \(.contractAddress) \(.contractName)\"" "$BROADCAST_FILE"
