#!/usr/bin/env bash

# Script to add current public IP to Azure Storage Account firewall rules
echo "================================================="
echo "Azure Storage Account - Add Public IP Access"
echo "================================================="
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
    
    # Check if curl is available for IP detection
    if ! command -v curl &> /dev/null; then
        echo "❌ ERROR: curl command not found"
        echo "💡 Please install curl to detect public IP address"
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

# Function to get current public IP address
get_public_ip() {
    echo "🌐 Detecting your public IP address..."
    
    # Try multiple IP detection services for reliability
    PUBLIC_IP=""
    
    # Try ipify.org first
    PUBLIC_IP=$(curl -s --max-time 10 https://api.ipify.org 2>/dev/null)
    
    # If that fails, try ifconfig.me
    if [ -z "$PUBLIC_IP" ] || [ ${#PUBLIC_IP} -lt 7 ]; then
        PUBLIC_IP=$(curl -s --max-time 10 https://ifconfig.me 2>/dev/null)
    fi
    
    # If that fails, try icanhazip.com
    if [ -z "$PUBLIC_IP" ] || [ ${#PUBLIC_IP} -lt 7 ]; then
        PUBLIC_IP=$(curl -s --max-time 10 https://icanhazip.com 2>/dev/null | tr -d '\n')
    fi
    
    # Validate IP format
    if [[ ! $PUBLIC_IP =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        echo "❌ ERROR: Failed to detect valid public IP address"
        echo "💡 Detected: '$PUBLIC_IP'"
        echo "💡 Please check your internet connection and try again"
        exit 1
    fi
    
    echo "✅ Your public IP address: $PUBLIC_IP"
}

# Function to check if storage account exists
check_storage_account() {
    echo "🏪 Checking storage account..."
    echo "📝 Storage Account Name: $STORAGE_NAME"
    echo "📝 Resource Group: $RG_NAME"
    
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

# Function to check current network rules
check_current_rules() {
    echo "🔍 Checking current network access rules..."
    
    # Get current network rules
    DEFAULT_ACTION=$(az storage account show \
        --name "$STORAGE_NAME" \
        --resource-group "$RG_NAME" \
        --query "networkRuleSet.defaultAction" \
        --output tsv 2>/dev/null)
    
    echo "📋 Current default action: $DEFAULT_ACTION"
    
    # Get current IP rules
    echo "📋 Current IP rules:"
    az storage account network-rule list \
        --account-name "$STORAGE_NAME" \
        --resource-group "$RG_NAME" \
        --query "ipRules[].ipAddressOrRange" \
        --output table 2>/dev/null || echo "No IP rules found"
}

# Function to add IP to storage account firewall
add_ip_rule() {
    echo "🔧 Adding your IP to storage account firewall..."
    
    # Check if IP is already in the rules
    EXISTING_IP=$(az storage account network-rule list \
        --account-name "$STORAGE_NAME" \
        --resource-group "$RG_NAME" \
        --query "ipRules[?ipAddressOrRange=='$PUBLIC_IP'].ipAddressOrRange" \
        --output tsv 2>/dev/null)
    
    if [ -n "$EXISTING_IP" ]; then
        echo "ℹ️ Your IP address $PUBLIC_IP is already in the firewall rules"
        return 0
    fi
    
    # Add the IP rule
    echo "➕ Adding IP rule for: $PUBLIC_IP"
    az storage account network-rule add \
        --account-name "$STORAGE_NAME" \
        --resource-group "$RG_NAME" \
        --ip-address "$PUBLIC_IP" \
        --output none
    
    if [ $? -eq 0 ]; then
        echo "✅ Successfully added IP rule for $PUBLIC_IP"
    else
        echo "❌ ERROR: Failed to add IP rule"
        exit 1
    fi
}

# Function to ensure network access is configured properly
configure_network_access() {
    echo "🛡️ Configuring network access..."
    
    # Get current public network access setting
    PUBLIC_ACCESS=$(az storage account show \
        --name "$STORAGE_NAME" \
        --resource-group "$RG_NAME" \
        --query "publicNetworkAccess" \
        --output tsv 2>/dev/null)
    
    # Get current default action
    DEFAULT_ACTION=$(az storage account show \
        --name "$STORAGE_NAME" \
        --resource-group "$RG_NAME" \
        --query "networkRuleSet.defaultAction" \
        --output tsv 2>/dev/null)
    
    echo "📋 Current public network access: $PUBLIC_ACCESS"
    echo "📋 Current default action: $DEFAULT_ACTION"
    
    # Enable public network access if it's disabled
    if [ "$PUBLIC_ACCESS" = "Disabled" ]; then
        echo "🔧 Enabling public network access (required for IP firewall rules)..."
        
        az storage account update \
            --name "$STORAGE_NAME" \
            --resource-group "$RG_NAME" \
            --public-network-access Enabled \
            --output none
        
        if [ $? -eq 0 ]; then
            echo "✅ Enabled public network access"
        else
            echo "❌ ERROR: Failed to enable public network access"
            exit 1
        fi
    else
        echo "✅ Public network access already enabled"
    fi
    
    # Set default action to Deny to enable selective access
    if [ "$DEFAULT_ACTION" = "Allow" ]; then
        echo "🔧 Setting default action to 'Deny' to enable selective IP access..."
        
        az storage account update \
            --name "$STORAGE_NAME" \
            --resource-group "$RG_NAME" \
            --default-action Deny \
            --output none
        
        if [ $? -eq 0 ]; then
            echo "✅ Updated default action to 'Deny' (enables selective access)"
        else
            echo "❌ ERROR: Failed to update default action"
            exit 1
        fi
    else
        echo "✅ Default action already set to 'Deny' (selective access enabled)"
    fi
}

# Function to display final status
display_summary() {
    echo ""
    echo "📋 Summary"
    echo "=========="
    echo "🏪 Storage Account: $STORAGE_NAME"
    echo "🌐 Your Public IP: $PUBLIC_IP"
    echo "📁 Resource Group: $RG_NAME"
    echo ""
    
    # Show current configuration
    PUBLIC_ACCESS=$(az storage account show \
        --name "$STORAGE_NAME" \
        --resource-group "$RG_NAME" \
        --query "publicNetworkAccess" \
        --output tsv 2>/dev/null)
    
    DEFAULT_ACTION=$(az storage account show \
        --name "$STORAGE_NAME" \
        --resource-group "$RG_NAME" \
        --query "networkRuleSet.defaultAction" \
        --output tsv 2>/dev/null)
    
    echo "🔧 Network Configuration:"
    echo "   Public Network Access: $PUBLIC_ACCESS"
    echo "   Default Action: $DEFAULT_ACTION"
    echo ""
    echo "🎯 Allowed IP addresses:"
    az storage account network-rule list \
        --account-name "$STORAGE_NAME" \
        --resource-group "$RG_NAME" \
        --query "ipRules[].ipAddressOrRange" \
        --output table 2>/dev/null
    echo ""
    echo "✅ Configuration complete!"
    echo "💡 In Azure Portal, you should see:"
    echo "   - Public network access: Enabled from selected networks"
    echo "   - Your IP ($PUBLIC_IP) in the firewall allow list"
    echo "💡 You can manage these rules in: Storage Account > Networking"
}

# Main execution
main() {
    check_prerequisites
    set_subscription
    get_public_ip
    check_storage_account
    check_current_rules
    configure_network_access
    add_ip_rule
    display_summary
}

# Run the script
main
