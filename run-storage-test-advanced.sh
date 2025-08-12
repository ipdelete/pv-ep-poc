#!/bin/bash

# Advanced script to run storage access tests on Azure VM
# Supports custom parameters and multiple test options

# Default configuration
DEFAULT_RESOURCE_GROUP="rg-stgdemo-poc-eastus2-01"
DEFAULT_VM_NAME="vm-stgdemo-poc-eastus2-01"
DEFAULT_TEST_SCRIPT="test-storage-access.sh"

# Function to display usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -g, --resource-group RG_NAME   Resource group name (default: $DEFAULT_RESOURCE_GROUP)"
    echo "  -v, --vm-name VM_NAME          Virtual machine name (default: $DEFAULT_VM_NAME)"
    echo "  -s, --script SCRIPT_NAME       Test script name (default: $DEFAULT_TEST_SCRIPT)"
    echo "  -q, --quiet                    Quiet mode - minimal output"
    echo "  -h, --help                     Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                             # Run with default settings"
    echo "  $0 -g my-rg -v my-vm          # Use custom resource group and VM"
    echo "  $0 --quiet                    # Run in quiet mode"
    echo ""
}

# Initialize variables with defaults
RESOURCE_GROUP="$DEFAULT_RESOURCE_GROUP"
VM_NAME="$DEFAULT_VM_NAME"
TEST_SCRIPT="$DEFAULT_TEST_SCRIPT"
QUIET_MODE=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -g|--resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        -v|--vm-name)
            VM_NAME="$2"
            shift 2
            ;;
        -s|--script)
            TEST_SCRIPT="$2"
            shift 2
            ;;
        -q|--quiet)
            QUIET_MODE=true
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            echo "❌ ERROR: Unknown option $1"
            show_usage
            exit 1
            ;;
    esac
done

# Function for conditional echo (respects quiet mode)
log() {
    if [ "$QUIET_MODE" = false ]; then
        echo "$@"
    fi
}

# Function for important messages (always shown)
important() {
    echo "$@"
}

# Main execution starts here
if [ "$QUIET_MODE" = false ]; then
    log "======================================================="
    log "Azure Storage Test Runner (Advanced)"
    log "======================================================="
    log ""
    log "📋 Configuration:"
    log "   Resource Group: $RESOURCE_GROUP"
    log "   VM Name: $VM_NAME"
    log "   Test Script: $TEST_SCRIPT"
    log "   Quiet Mode: $QUIET_MODE"
    log ""
fi

# Check if test script exists
if [ ! -f "$TEST_SCRIPT" ]; then
    important "❌ ERROR: Test script '$TEST_SCRIPT' not found in current directory"
    important "Please ensure the test script is in the same directory as this runner script"
    exit 1
fi

log "✅ Test script found: $TEST_SCRIPT"

# Check if Azure CLI is available
if ! command -v az &> /dev/null; then
    important "❌ ERROR: Azure CLI not found"
    important "Please install Azure CLI: https://docs.microsoft.com/cli/azure/install-azure-cli"
    exit 1
fi

log "✅ Azure CLI found"

# Check if logged in to Azure
log "🔐 Checking Azure authentication..."
ACCOUNT_INFO=$(az account show 2>/dev/null)
if [ $? -ne 0 ]; then
    important "❌ ERROR: Not logged in to Azure"
    important "Please run: az login"
    exit 1
fi

SUBSCRIPTION_NAME=$(echo "$ACCOUNT_INFO" | grep -o '"name": "[^"]*' | cut -d'"' -f4)
log "✅ Logged in to Azure subscription: $SUBSCRIPTION_NAME"

# Check if VM exists and is running
log "🖥️  Checking VM status..."
VM_STATUS=$(az vm get-instance-view \
    --resource-group "$RESOURCE_GROUP" \
    --name "$VM_NAME" \
    --query "instanceView.statuses[?code=='PowerState/running']" \
    --output tsv 2>/dev/null)

if [ -z "$VM_STATUS" ]; then
    important "❌ ERROR: VM '$VM_NAME' is not running or not found in resource group '$RESOURCE_GROUP'"
    important "Please ensure the VM is running and accessible"
    exit 1
fi

log "✅ VM is running and accessible"
log ""

# Get VM details for logging
if [ "$QUIET_MODE" = false ]; then
    VM_INFO=$(az vm show --resource-group "$RESOURCE_GROUP" --name "$VM_NAME" --query "{Location:location, Size:hardwareProfile.vmSize, PrivateIP:privateIps[0]}" --output tsv 2>/dev/null)
    if [ $? -eq 0 ]; then
        log "📊 VM Details:"
        echo "$VM_INFO" | while IFS=$'\t' read -r location size privateip; do
            log "   Location: $location"
            log "   Size: $size"
            log "   Private IP: $privateip"
        done
        log ""
    fi
fi

# Execute the test script on the VM
important "🚀 Executing storage access test on VM..."
if [ "$QUIET_MODE" = false ]; then
    log "   This may take a few moments..."
    log ""
    log "======================================================="
    log "VM TEST OUTPUT:"
    log "======================================================="
fi

# Record start time
START_TIME=$(date +%s)

# Run the test script on the VM
TEST_OUTPUT=$(az vm run-command invoke \
    --resource-group "$RESOURCE_GROUP" \
    --name "$VM_NAME" \
    --command-id RunShellScript \
    --scripts "$(cat $TEST_SCRIPT)" \
    --query "value[0].message" \
    --output tsv 2>&1)

EXIT_CODE=$?
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

# Display the output
if [ "$QUIET_MODE" = false ]; then
    echo "$TEST_OUTPUT"
    echo ""
    log "======================================================="
fi

# Check the exit code and provide summary
if [ $EXIT_CODE -eq 0 ]; then
    important "✅ Test execution completed successfully! (Duration: ${DURATION}s)"
    if [ "$QUIET_MODE" = false ]; then
        log "======================================================="
        log ""
        log "📊 Test Summary:"
        log "   - VM: $VM_NAME"
        log "   - Resource Group: $RESOURCE_GROUP"
        log "   - Test Script: $TEST_SCRIPT"
        log "   - Duration: ${DURATION} seconds"
        log "   - Status: ✅ COMPLETED"
        log ""
        log "💡 Tips:"
        log "   - Rerun this script anytime: $0"
        log "   - Use --quiet for automated scripts: $0 --quiet"
        log "   - Check Azure Portal for detailed VM logs if needed"
        log "   - Modify $TEST_SCRIPT to add more tests"
        log ""
    fi
else
    important "❌ Test execution failed! (Duration: ${DURATION}s)"
    if [ "$QUIET_MODE" = true ]; then
        important "Error output:"
        echo "$TEST_OUTPUT"
    fi
    exit 1
fi
