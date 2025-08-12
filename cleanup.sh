#!/usr/bin/env bash

# Cleanup script for Private Endpoint POC
# This script will delete all resources created by setup.sh

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
NIC_NAME="${VM_NAME}VMNIC"
NSG_NAME="${VM_NAME}-nsg"
DISK_NAME="${VM_NAME}_OsDisk_1_*"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if resource exists
resource_exists() {
    local resource_type=$1
    local resource_name=$2
    local resource_group=$3
    
    case $resource_type in
        "vm")
            az vm show --name "$resource_name" --resource-group "$resource_group" &>/dev/null
            ;;
        "storage")
            az storage account show --name "$resource_name" --resource-group "$resource_group" &>/dev/null
            ;;
        "private-endpoint")
            az network private-endpoint show --name "$resource_name" --resource-group "$resource_group" &>/dev/null
            ;;
        "vnet")
            az network vnet show --name "$resource_name" --resource-group "$resource_group" &>/dev/null
            ;;
        "nic")
            az network nic show --name "$resource_name" --resource-group "$resource_group" &>/dev/null
            ;;
        "nsg")
            az network nsg show --name "$resource_name" --resource-group "$resource_group" &>/dev/null
            ;;
        "disk")
            az disk list --resource-group "$resource_group" --query "[?contains(name, '$resource_name')]" --output tsv | head -1 | grep -q .
            ;;
        "rg")
            az group show --name "$resource_name" &>/dev/null
            ;;
    esac
    return $?
}

# Function to delete resource with confirmation
delete_resource() {
    local resource_type=$1
    local resource_name=$2
    local resource_group=$3
    
    if resource_exists "$resource_type" "$resource_name" "$resource_group"; then
        print_status "Deleting $resource_type: $resource_name"
        
        case $resource_type in
            "vm")
                az vm delete --name "$resource_name" --resource-group "$resource_group" --yes --no-wait
                ;;
            "storage")
                az storage account delete --name "$resource_name" --resource-group "$resource_group" --yes
                ;;
            "private-endpoint")
                az network private-endpoint delete --name "$resource_name" --resource-group "$resource_group" --no-wait
                ;;
            "nic")
                az network nic delete --name "$resource_name" --resource-group "$resource_group" --no-wait
                ;;
            "nsg")
                az network nsg delete --name "$resource_name" --resource-group "$resource_group" --no-wait
                ;;
            "disk")
                # Find the actual disk name and delete it
                local disk_name=$(az disk list --resource-group "$resource_group" --query "[?contains(name, '$resource_name')].name" --output tsv | head -1)
                if [ -n "$disk_name" ]; then
                    az disk delete --name "$disk_name" --resource-group "$resource_group" --yes --no-wait
                    print_status "Deleting disk: $disk_name"
                fi
                ;;
            "vnet")
                az network vnet delete --name "$resource_name" --resource-group "$resource_group" --no-wait
                ;;
        esac
        
        if [ $? -eq 0 ]; then
            print_success "$resource_type '$resource_name' deletion initiated"
        else
            print_error "Failed to delete $resource_type '$resource_name'"
            return 1
        fi
    else
        print_warning "$resource_type '$resource_name' not found, skipping"
    fi
}

# Set subscription context
print_status "Setting subscription context to: $SUBSCRIPTION_ID"
az account set --subscription $SUBSCRIPTION_ID

if [ $? -ne 0 ]; then
    print_error "Failed to set subscription context. Please check your Azure CLI login."
    exit 1
fi

# Check if resource group exists
if ! resource_exists "rg" "$RG_NAME" ""; then
    print_warning "Resource group '$RG_NAME' not found. Nothing to clean up."
    exit 0
fi

print_status "Starting cleanup of resources in resource group: $RG_NAME"
echo ""

# Confirmation prompt
read -p "Are you sure you want to delete ALL resources in '$RG_NAME'? (yes/no): " confirm
if [[ $confirm != "yes" ]]; then
    print_warning "Cleanup cancelled by user"
    exit 0
fi

echo ""
print_status "=== CLEANUP STARTED ==="

# Step 1: Delete VM (this will also delete associated NIC, disk, and NSG)
print_status "Step 1: Deleting Virtual Machine and associated resources..."
delete_resource "vm" "$VM_NAME" "$RG_NAME"

# Wait a bit for VM deletion to process
sleep 5

# Step 1a: Clean up any remaining VM-associated resources
print_status "Step 1a: Cleaning up remaining VM resources..."
delete_resource "nic" "$NIC_NAME" "$RG_NAME"
delete_resource "nsg" "$NSG_NAME" "$RG_NAME"
delete_resource "disk" "$VM_NAME" "$RG_NAME"

# Step 2: Delete Private Endpoint
print_status "Step 2: Deleting Private Endpoint..."
delete_resource "private-endpoint" "$PE_NAME" "$RG_NAME"

# Step 3: Delete Storage Account
print_status "Step 3: Deleting Storage Account..."
delete_resource "storage" "$STORAGE_NAME" "$RG_NAME"

# Wait for network resources to be fully deleted before attempting VNet deletion
print_status "Waiting for network resources to be fully deleted..."
sleep 15

# Step 4: Delete VNet (this will also delete subnets)
print_status "Step 4: Deleting Virtual Network and subnets..."
delete_resource "vnet" "$VNET_NAME" "$RG_NAME"

# Wait a moment for deletions to process
print_status "Waiting for resource deletions to process..."
sleep 10

# Step 5: List remaining resources
print_status "Step 5: Checking for remaining resources..."
remaining_resources=$(az resource list --resource-group "$RG_NAME" --query "length([*])" --output tsv 2>/dev/null || echo "0")

# Handle case where resource group might not exist or command fails
if [[ ! "$remaining_resources" =~ ^[0-9]+$ ]]; then
    remaining_resources=0
fi

if [ "$remaining_resources" -gt 0 ]; then
    print_warning "Found $remaining_resources remaining resources in the resource group:"
    az resource list --resource-group "$RG_NAME" --query "[].{Name:name, Type:type, Location:location}" --output table
    echo ""
    print_warning "Some resources may still be deleting. You can:"
    print_warning "1. Wait a few minutes and run this script again"
    print_warning "2. Manually delete remaining resources from the Azure portal"
    print_warning "3. Force delete the entire resource group (see option below)"
else
    print_success "No remaining resources found in the resource group"
fi

# Step 6: Optional - Delete entire resource group
echo ""
read -p "Do you want to force delete the entire resource group '$RG_NAME'? This will remove ALL resources immediately. (yes/no): " force_delete

if [[ $force_delete == "yes" ]]; then
    print_status "Force deleting resource group: $RG_NAME"
    az group delete --name "$RG_NAME" --yes --no-wait
    
    if [ $? -eq 0 ]; then
        print_success "Resource group '$RG_NAME' deletion initiated"
        print_status "Note: Complete deletion may take several minutes to finish in the background"
    else
        print_error "Failed to delete resource group '$RG_NAME'"
        exit 1
    fi
else
    print_warning "Resource group '$RG_NAME' retained. You can delete it manually later if needed."
fi

echo ""
print_success "=== CLEANUP COMPLETED ==="
print_status "Summary:"
print_status "- VM '$VM_NAME': Deletion initiated"
print_status "- NIC '$NIC_NAME': Deletion initiated"
print_status "- NSG '$NSG_NAME': Deletion initiated"
print_status "- VM Disk: Deletion initiated"
print_status "- Private Endpoint '$PE_NAME': Deletion initiated"
print_status "- Storage Account '$STORAGE_NAME': Deletion initiated"
print_status "- VNet '$VNET_NAME': Deletion initiated"

if [[ $force_delete == "yes" ]]; then
    print_status "- Resource Group '$RG_NAME': Force deletion initiated"
else
    print_status "- Resource Group '$RG_NAME': Retained"
fi

echo ""
print_status "Note: Some deletions may continue in the background."
print_status "You can check the Azure portal or run 'az group show --name $RG_NAME' to verify completion."
