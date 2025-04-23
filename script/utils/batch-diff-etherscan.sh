#!/bin/bash

# chain ID is hardcoded
CHAIN_ID=8453 # base
# CHAIN_ID=84532 # base-sep

echo "=== Batch Contract Diff ==="
echo "Using Chain ID: $CHAIN_ID (change in script as needed)"
echo "1. Paste your contract table below (copied from raw or rendered markdown). ContractName assumed to be last column."
echo "2. After pasting, press Enter"
echo "3. Then press Ctrl+D to finish input :"
# Create a temporary file to store the pasted table
TEMP_FILE=$(mktemp)
cat > "$TEMP_FILE"

# Initialize counter for commands run
COMMANDS_RUN=0

# Process each line of the file
while IFS= read -r line; do
    # Only process lines that contain /address/
    if [[ "$line" == *"/address/"* ]]; then
        # Extract the address using regex
        if [[ "$line" =~ (0x[a-fA-F0-9]{40}) ]]; then
            # Extract the address using grep (works in both bash and zsh)
            ADDRESS=$(grep -o '0x[a-fA-F0-9]\{40\}' <<< "$line")

            # Extract the contract name based on format
            if [[ "$line" == *"|"* ]]; then
                # For pipe-delimited markdown format
                CONTRACT_NAME=$(echo "$line" | awk -F'|' '{print $(NF-1)}' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            else
                # For tab-delimited rendered format
                CONTRACT_NAME=$(echo "$line" | awk '{print $NF}' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            fi

            if [ -n "$ADDRESS" ] && [ -n "$CONTRACT_NAME" ]; then
                # Construct and execute the command
                COMMAND=". ./script/utils/diff-etherscan.sh $CHAIN_ID $ADDRESS src/$CONTRACT_NAME.sol"
                echo "Running: $COMMAND"
                eval "$COMMAND"
                echo "--------------------------------------"

                # Increment the counter
                ((COMMANDS_RUN++))
            fi
        fi
    fi
done < "$TEMP_FILE"

echo "Total commands run: $COMMANDS_RUN"

# Clean up the temporary file
rm -f "$TEMP_FILE"
