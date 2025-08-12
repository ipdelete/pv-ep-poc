#!/usr/bin/env bash

# Helper script to toggle Private DNS Zone integration feature flag

SCRIPT_FILE="setup.sh"

if [ ! -f "$SCRIPT_FILE" ]; then
    echo "ERROR: $SCRIPT_FILE not found in current directory"
    exit 1
fi

# Check current state
current_state=$(grep "ENABLE_PRIVATE_DNS=" $SCRIPT_FILE | sed 's/.*ENABLE_PRIVATE_DNS="\([^"]*\)".*/\1/')

echo "Current Private DNS integration state: $current_state"

if [ "$current_state" = "true" ]; then
    # Change to false
    sed -i 's/ENABLE_PRIVATE_DNS="true"/ENABLE_PRIVATE_DNS="false"/' $SCRIPT_FILE
    echo "✅ Private DNS integration DISABLED"
    echo "   Private endpoints will be created without DNS zone integration"
elif [ "$current_state" = "false" ]; then
    # Change to true
    sed -i 's/ENABLE_PRIVATE_DNS="false"/ENABLE_PRIVATE_DNS="true"/' $SCRIPT_FILE
    echo "✅ Private DNS integration ENABLED"
    echo "   Private endpoints will be created with automatic DNS zone integration"
else
    echo "ERROR: Could not determine current state of ENABLE_PRIVATE_DNS"
    exit 1
fi

echo ""
echo "Updated state: $(grep "ENABLE_PRIVATE_DNS=" $SCRIPT_FILE | sed 's/.*ENABLE_PRIVATE_DNS="\([^"]*\)".*/\1/')"
