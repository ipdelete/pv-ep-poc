#!/usr/bin/env bash

# Dry-run cleanup script for Private Endpoint POC
# This script shows what resources would be deleted without actually deleting them

# Configuration (must match setup.sh)
SUBSCRIPTION_ID="423c1491-b453-40f2-b5c9-4718d66c87d5"
LOCATION="eastus2"
ENVIRONMENT="poc"
WORKLOAD="stgdemo"
INSTANCE="01"

# Derived names (must match setup.sh)
RG_NAME="rg-${WORKLOAD}-${ENVIRONMENT}-${LOCATION}-${INSTANCE}"
STORAGE_NAME="${WORKLOAD}${ENVIRONMENT}${LOCATION}${INSTANCE}"
VNET_NAME="vnet-${WORKLOAD}-${ENVIRONMENT}-${LOCATION}-${INSTANCE}"
VM_SUBNET_NAME="snet-${WORKLOAD}-${ENVIRONMENT}-${LOCATION}-vm-${INSTANCE}"
PE_SUBNET_NAME="snet-${WORKLOAD}-${ENVIRONMENT}-${LOCATION}-pe-${INSTANCE}"
PE_NAME="pe-${WORKLOAD}-${ENVIRONMENT}-${LOCATION}-storage-${INSTANCE}"
VM_NAME="vm-${WORKLOAD}-${ENVIRONMENT}-${LOCATION}-${INSTANCE}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

print_header() {
    echo -e "${CYAN}=== $1 ===${NC}"
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_found() {
    echo -e "${GREEN}[FOUND]${NC} $1"
}

print_not_found() {
    echo -e "${YELLOW}[NOT FOUND]${NC} $1"
}

# Set subscription context
print_info "Checking subscription: $SUBSCRIPTION_ID"
az account set --subscription $SUBSCRIPTION_ID &>/dev/null

if [ $? -ne 0 ]; then
    echo -e "${RED}[ERROR]${NC} Failed to set subscription context. Please check your Azure CLI login."
    exit 1
fi

print_header "DRY RUN - RESOURCES THAT WOULD BE DELETED"
echo ""

# Check Resource Group
print_info "Checking Resource Group: $RG_NAME"
if az group show --name "$RG_NAME" &>/dev/null; then
    print_found "Resource Group: $RG_NAME"
    
    # List all resources in the resource group
    echo ""
    print_info "All resources in resource group:"
    az resource list --resource-group "$RG_NAME" --query "[].{Name:name, Type:type, Location:location}" --output table
    
    echo ""
    print_info "Checking specific resources..."
    
    # Check VM
    if az vm show --name "$VM_NAME" --resource-group "$RG_NAME" &>/dev/null; then
        print_found "Virtual Machine: $VM_NAME"
        
        # Check VM details without jq
        vm_size=$(az vm show --name "$VM_NAME" --resource-group "$RG_NAME" --query "hardwareProfile.vmSize" --output tsv 2>/dev/null)
        vm_state=$(az vm get-instance-view --name "$VM_NAME" --resource-group "$RG_NAME" --query "instanceView.statuses[1].displayStatus" --output tsv 2>/dev/null)
        echo "    └─ State: ${vm_state:-Unknown} | Size: ${vm_size:-Unknown}"
    else
        print_not_found "Virtual Machine: $VM_NAME"
    fi
    
    # Check Storage Account
    if az storage account show --name "$STORAGE_NAME" --resource-group "$RG_NAME" &>/dev/null; then
        print_found "Storage Account: $STORAGE_NAME"
        
        # Check storage details without jq
        storage_sku=$(az storage account show --name "$STORAGE_NAME" --resource-group "$RG_NAME" --query "sku.name" --output tsv 2>/dev/null)
        public_access=$(az storage account show --name "$STORAGE_NAME" --resource-group "$RG_NAME" --query "publicNetworkAccess" --output tsv 2>/dev/null)
        echo "    └─ SKU: ${storage_sku:-Unknown} | Public Access: ${public_access:-Unknown}"
    else
        print_not_found "Storage Account: $STORAGE_NAME"
    fi
    
    # Check Private Endpoint
    if az network private-endpoint show --name "$PE_NAME" --resource-group "$RG_NAME" &>/dev/null; then
        print_found "Private Endpoint: $PE_NAME"
        
        # Check PE details without jq
        connection_state=$(az network private-endpoint show --name "$PE_NAME" --resource-group "$RG_NAME" --query "privateLinkServiceConnections[0].privateLinkServiceConnectionState.status" --output tsv 2>/dev/null)
        echo "    └─ Connection Status: ${connection_state:-Unknown}"
    else
        print_not_found "Private Endpoint: $PE_NAME"
    fi
    
    # Check VNet
    if az network vnet show --name "$VNET_NAME" --resource-group "$RG_NAME" &>/dev/null; then
        print_found "Virtual Network: $VNET_NAME"
        
        # Check subnets without jq
        echo "    └─ Subnets:"
        az network vnet subnet list --vnet-name "$VNET_NAME" --resource-group "$RG_NAME" --query "[].{Name:name, AddressPrefix:addressPrefix}" --output tsv 2>/dev/null | while read name prefix; do
            echo "        • $name: $prefix"
        done
    else
        print_not_found "Virtual Network: $VNET_NAME"
    fi
    
    echo ""
    print_header "ESTIMATED DELETION ORDER"
    echo "1. Virtual Machine: $VM_NAME (includes NICs, disks, NSGs)"
    echo "2. Private Endpoint: $PE_NAME"
    echo "3. Storage Account: $STORAGE_NAME"
    echo "4. Virtual Network: $VNET_NAME (includes all subnets)"
    echo "5. Resource Group: $RG_NAME (optional)"
    
    echo ""
    print_info "To perform actual deletion, run: ./cleanup.sh"
    
else
    print_not_found "Resource Group: $RG_NAME"
    echo ""
    echo -e "${GREEN}✓ Nothing to clean up - resource group doesn't exist${NC}"
fi
