#!/bin/bash

# Script to run the storage access test on the VM
# This script executes test-storage-access.sh on the VM using az vm run-command

# Configuration
RESOURCE_GROUP="rg-stgdemo-poc-eastus2-01"
VM_NAME="vm-stgdemo-poc-eastus2-01"
TEST_SCRIPT="test-storage-access.sh"

echo "======================================================="
echo "Azure Storage Test Runner"
echo "======================================================="
echo ""
echo "📋 Configuration:"
echo "   Resource Group: $RESOURCE_GROUP"
echo "   VM Name: $VM_NAME"
echo "   Test Script: $TEST_SCRIPT"
echo ""

# Check if test script exists
if [ ! -f "$TEST_SCRIPT" ]; then
    echo "❌ ERROR: Test script '$TEST_SCRIPT' not found in current directory"
    echo "Please ensure the test-storage-access.sh script is in the same directory"
    exit 1
fi

echo "✅ Test script found: $TEST_SCRIPT"
echo ""

# Check if Azure CLI is available
if ! command -v az &> /dev/null; then
    echo "❌ ERROR: Azure CLI not found"
    echo "Please install Azure CLI: https://docs.microsoft.com/cli/azure/install-azure-cli"
    exit 1
fi

echo "✅ Azure CLI found"
echo ""

# Check if logged in to Azure
echo "🔐 Checking Azure authentication..."
ACCOUNT_INFO=$(az account show 2>/dev/null)
if [ $? -ne 0 ]; then
    echo "❌ ERROR: Not logged in to Azure"
    echo "Please run: az login"
    exit 1
fi

SUBSCRIPTION_NAME=$(echo "$ACCOUNT_INFO" | grep -o '"name": "[^"]*' | cut -d'"' -f4)
echo "✅ Logged in to Azure subscription: $SUBSCRIPTION_NAME"
echo ""

# Check if VM exists and is running
echo "🖥️  Checking VM status..."
VM_STATUS=$(az vm get-instance-view \
    --resource-group "$RESOURCE_GROUP" \
    --name "$VM_NAME" \
    --query "instanceView.statuses[?code=='PowerState/running']" \
    --output tsv 2>/dev/null)

if [ -z "$VM_STATUS" ]; then
    echo "❌ ERROR: VM '$VM_NAME' is not running or not found"
    echo "Please ensure the VM is running in resource group '$RESOURCE_GROUP'"
    exit 1
fi

echo "✅ VM is running and accessible"
echo ""

# Execute the test script on the VM
echo "🚀 Executing storage access test on VM..."
echo "   This may take a few moments..."
echo ""
echo "======================================================="
echo "VM TEST OUTPUT:"
echo "======================================================="

# Run the test script on the VM
az vm run-command invoke \
    --resource-group "$RESOURCE_GROUP" \
    --name "$VM_NAME" \
    --command-id RunShellScript \
    --scripts "$(cat $TEST_SCRIPT)" \
    --query "value[0].message" \
    --output tsv

# Check the exit code
if [ $? -eq 0 ]; then
    echo ""
    echo "======================================================="
    echo "✅ Test execution completed successfully!"
    echo "======================================================="
else
    echo ""
    echo "======================================================="
    echo "❌ Test execution failed!"
    echo "======================================================="
    exit 1
fi

echo ""
echo "📊 Test Summary:"
echo "   - VM: $VM_NAME"
echo "   - Resource Group: $RESOURCE_GROUP"
echo "   - Test Script: $TEST_SCRIPT"
echo "   - Status: ✅ COMPLETED"
echo ""
echo "💡 Tips:"
echo "   - Rerun this script anytime to test storage access"
echo "   - Check Azure Portal for detailed VM logs if needed"
echo "   - Modify test-storage-access.sh to add more tests"
echo ""
