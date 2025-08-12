#!/usr/bin/env bash

# Script to get the public endpoint URL of the storage account and perform nslookup
echo "============================================="
echo "Azure Storage Account Endpoint DNS Lookup"
echo "============================================="
echo ""

# Configuration (matching setup.sh variables)
SUBSCRIPTION_ID="423c1491-b453-40f2-b5c9-4718d66c87d5"
LOCATION="eastus2"
ENVIRONMENT="poc"
WORKLOAD="stgdemo"
INSTANCE="01"

# Derived names
RG_NAME="rg-${WORKLOAD}-${ENVIRONMENT}-${LOCATION}-${INSTANCE}"
STORAGE_NAME="${WORKLOAD}${ENVIRONMENT}${LOCATION}${INSTANCE}"

# Function to check if Azure CLI is installed and configured
check_prerequisites() {
    echo "🔍 Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        echo "❌ ERROR: Azure CLI is not installed"
        echo "💡 Please install Azure CLI: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        echo "❌ ERROR: Not logged in to Azure CLI"
        echo "💡 Please run 'az login' first"
        exit 1
    fi
    
    # Check if nslookup is available
    if ! command -v nslookup &> /dev/null; then
        echo "❌ ERROR: nslookup command not found"
        echo "💡 Please install bind-utils (RHEL/CentOS) or dnsutils (Ubuntu/Debian)"
        exit 1
    fi
    
    echo "✅ Prerequisites check passed"
}

# Function to set the correct subscription
set_subscription() {
    echo "🔧 Setting Azure subscription..."
    
    CURRENT_SUB=$(az account show --query id --output tsv)
    if [ "$CURRENT_SUB" != "$SUBSCRIPTION_ID" ]; then
        echo "📋 Switching to subscription: $SUBSCRIPTION_ID"
        az account set --subscription "$SUBSCRIPTION_ID"
        
        if [ $? -ne 0 ]; then
            echo "❌ ERROR: Failed to set subscription"
            exit 1
        fi
    else
        echo "✅ Already using correct subscription: $SUBSCRIPTION_ID"
    fi
}

# Function to get storage account information
get_storage_info() {
    echo "🏪 Getting storage account information..."
    echo "📝 Storage Account Name: $STORAGE_NAME"
    echo "📝 Resource Group: $RG_NAME"
    echo ""
    
    # Check if storage account exists
    STORAGE_EXISTS=$(az storage account show \
        --name "$STORAGE_NAME" \
        --resource-group "$RG_NAME" \
        --query "name" \
        --output tsv 2>/dev/null)
    
    if [ -z "$STORAGE_EXISTS" ]; then
        echo "❌ ERROR: Storage account '$STORAGE_NAME' not found in resource group '$RG_NAME'"
        echo "💡 Make sure the setup.sh script has been run successfully"
        exit 1
    fi
    
    echo "✅ Storage account found: $STORAGE_EXISTS"
}

# Function to get the public blob endpoint
get_public_endpoint() {
    echo "🌐 Retrieving public blob endpoint..."
    
    # Get the primary blob endpoint
    BLOB_ENDPOINT=$(az storage account show \
        --name "$STORAGE_NAME" \
        --resource-group "$RG_NAME" \
        --query "primaryEndpoints.blob" \
        --output tsv)
    
    if [ -z "$BLOB_ENDPOINT" ]; then
        echo "❌ ERROR: Failed to retrieve blob endpoint"
        exit 1
    fi
    
    # Extract hostname from URL (remove https:// and trailing /)
    BLOB_HOSTNAME=$(echo "$BLOB_ENDPOINT" | sed 's|https://||' | sed 's|/.*$||')
    
    echo "✅ Public blob endpoint: $BLOB_ENDPOINT"
    echo "✅ Hostname: $BLOB_HOSTNAME"
    
    return 0
}

# Function to perform nslookup
perform_nslookup() {
    echo ""
    echo "🔍 Performing DNS lookup on storage endpoint..."
    echo "=============================================="
    
    # Standard nslookup and capture output for parsing
    echo "📡 nslookup results for: $BLOB_HOSTNAME"
    echo "----------------------------------------------"
    NSLOOKUP_OUTPUT=$(nslookup "$BLOB_HOSTNAME" 2>/dev/null)
    echo "$NSLOOKUP_OUTPUT"
    
    # Check the exit code of nslookup
    if [ $? -eq 0 ]; then
        echo ""
        echo "✅ DNS lookup completed successfully"
    else
        echo ""
        echo "⚠️ DNS lookup completed with warnings/errors"
    fi
    
    echo ""
    echo "📊 Additional DNS information:"
    echo "----------------------------------------------"
    
    # Try to get A record specifically
    echo "🎯 A Records:"
    nslookup -type=A "$BLOB_HOSTNAME" 2>/dev/null | grep -E "^Name:|^Address:" || echo "No A records found"
    
    echo ""
    echo "🎯 CNAME Records:"
    CNAME_OUTPUT=$(nslookup -type=CNAME "$BLOB_HOSTNAME" 2>/dev/null | grep -E "canonical name|CNAME")
    if [ -n "$CNAME_OUTPUT" ]; then
        echo "$CNAME_OUTPUT"
    else
        echo "No CNAME records found"
    fi
    
    # Extract the final canonical name from the full nslookup output
    # Look for the last canonical name that points to blob.bnz49prdstrz19a.store.core.windows.net
    CANONICAL_NAME=$(echo "$NSLOOKUP_OUTPUT" | grep "canonical name.*blob\..*\.store\.core\.windows\.net" | tail -1 | sed 's/.*canonical name = //' | sed 's/\.$//')
    
    # If that didn't work, try to get any blob.* canonical name
    if [ -z "$CANONICAL_NAME" ]; then
        CANONICAL_NAME=$(echo "$NSLOOKUP_OUTPUT" | grep "canonical name.*blob\." | tail -1 | sed 's/.*canonical name = //' | sed 's/\.$//')
    fi
}



# Function to display summary
display_summary() {
    echo ""
    echo "📋 Summary"
    echo "=========="
    echo "🏪 Storage Account: $STORAGE_NAME"
    echo "🌐 Public Endpoint: $BLOB_ENDPOINT"
    echo "🖥️ Hostname: $BLOB_HOSTNAME"
    if [ -n "$CANONICAL_NAME" ]; then
        echo "🎯 Canonical Name: $CANONICAL_NAME"
    fi
    echo "📍 Location: $LOCATION"
    echo "📁 Resource Group: $RG_NAME"
    echo ""
    echo "💡 Note: If public access is disabled on the storage account,"
    echo "   you should access it through the private endpoint from within the VNet."
}

# Main execution
main() {
    check_prerequisites
    set_subscription
    get_storage_info
    get_public_endpoint
    perform_nslookup
    display_summary
}

# Run the script
main
