#!/bin/bash

# Check arguments
if [ "$#" -ne 3 ]; then
  echo "Usage: $0 <chain_id> <contract_address> <local_contract_path>"
  return 1 2>/dev/null
fi

CHAIN_ID=$1
CONTRACT_ADDRESS=$2
CONTRACT_NAME=$(basename "$3" .sol)
LOCAL_CONTRACT_PATH="$3"

# Temp files
TEMP_DIR=$(mktemp -d)
ETHERSCAN_FLAT="${TEMP_DIR}/${CONTRACT_NAME}-${CONTRACT_ADDRESS}-etherscan.sol"
LOCAL_FLAT="${TEMP_DIR}/${CONTRACT_NAME}-${CONTRACT_ADDRESS}-local.sol"
DIFF_OUTPUT="${TEMP_DIR}/${CONTRACT_NAME}-${CONTRACT_ADDRESS}-diff.txt"

# Get the local and verified code
forge flatten "$LOCAL_CONTRACT_PATH" > "$LOCAL_FLAT"
cast source --flatten "$CONTRACT_ADDRESS" -c "$CHAIN_ID" > "$ETHERSCAN_FLAT"

# Generate diff
diff -u "$LOCAL_FLAT" "$ETHERSCAN_FLAT" > "$DIFF_OUTPUT"
DIFF_EXIT_CODE=$?

echo "Temp files:"
echo "  Local flattened: $LOCAL_FLAT ($(wc -l < "$LOCAL_FLAT") lines)"
echo "  Etherscan flattened: $ETHERSCAN_FLAT ($(wc -l < "$ETHERSCAN_FLAT") lines)"
echo "  Diff: $DIFF_OUTPUT ($(wc -l < "$DIFF_OUTPUT") lines)"

# Report results
if [ $DIFF_EXIT_CODE -eq 0 ]; then
  echo "✅ No difference between local and etherscan"
elif [ $DIFF_EXIT_CODE -eq 1 ]; then
  echo "⚠️ Found differences between local and etherscan:"
  cat "$DIFF_OUTPUT"
else
  echo "❌ Error comparing files (diff exit code: $DIFF_EXIT_CODE)"
fi
