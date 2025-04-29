#!/bin/bash

# Usage:
# - use this to generate a Markdown table of explorer links and names

# the broadcast file to use
BROADCAST_FILE="broadcast/deploy-protocol.s.sol/8453/dry-run/run-latest.json"
EXPLORER_BASE_URL="https://basescan.org/address/"

#BROADCAST_FILE="broadcast/deploy-protocol.s.sol/84532/dry-run/run-latest.json"
#EXPLORER_BASE_URL="https://sepolia.basescan.org/address/"

echo "# Deployed contracts"

## simple lines
# jq -r ".transactions[] | select(.transactionType == \"CREATE\") | \"$EXPLORER_BASE_URL\(.contractAddress) \(.contractName)\"" "$BROADCAST_FILE"

# markdown table
echo ""
echo "| Link | Name |"
echo "|----------|---------|"
jq -r ".transactions[] | select(.transactionType == \"CREATE\") | \"| ${EXPLORER_BASE_URL}\(.contractAddress) | \(.contractName) |\"" "$BROADCAST_FILE"
