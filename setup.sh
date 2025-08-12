#!/usr/bin/env bash

# Configuration
SUBSCRIPTION_ID="423c1491-b453-40f2-b5c9-4718d66c87d5"
LOCATION="eastus2"
ENVIRONMENT="poc"
WORKLOAD="stgdemo"
INSTANCE="01"

# Derived names
RG_NAME="rg-${WORKLOAD}-${ENVIRONMENT}-${LOCATION}-${INSTANCE}"
STORAGE_NAME="${WORKLOAD}${ENVIRONMENT}${LOCATION}${INSTANCE}"
VNET_NAME="vnet-${WORKLOAD}-${ENVIRONMENT}-${LOCATION}-${INSTANCE}"
VM_SUBNET_NAME="snet-${WORKLOAD}-${ENVIRONMENT}-${LOCATION}-vm-${INSTANCE}"
PE_SUBNET_NAME="snet-${WORKLOAD}-${ENVIRONMENT}-${LOCATION}-pe-${INSTANCE}"
PE_NAME="pe-${WORKLOAD}-${ENVIRONMENT}-${LOCATION}-storage-${INSTANCE}"
VM_NAME="vm-${WORKLOAD}-${ENVIRONMENT}-${LOCATION}-${INSTANCE}"

# Network configuration
VNET_ADDRESS_SPACE="10.0.0.0/16"
VM_SUBNET_ADDRESS="10.0.1.0/24"
PE_SUBNET_ADDRESS="10.0.2.0/24"

# VM configuration
VM_SIZE="Standard_B2s"
VM_IMAGE="Ubuntu2204"
VM_ADMIN_USERNAME="azureuser"

# Storage Account configuration
STORAGE_SKU="Standard_ZRS"  # Zone-Redundant Storage (LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS)
HIERARCHICAL_NAMESPACE="false"  # Set to "true" for Data Lake Storage Gen2

# Feature Flags
ENABLE_PRIVATE_DNS="true"  # Set to "false" to skip Private DNS Zone integration

# Tags
TAGS="Environment=${ENVIRONMENT} Workload=${WORKLOAD} Purpose=POC Owner=ianphil"

# Set subscription context
az account set --subscription $SUBSCRIPTION_ID

# Create resource group
az group create \
    --name $RG_NAME \
    --location $LOCATION \
    --tags $TAGS

echo "Creating resources in $LOCATION with naming pattern: $WORKLOAD-$ENVIRONMENT-$LOCATION-$INSTANCE"

echo "Step 3: Creating VNet and subnets..."

# Create VNet
echo "Creating VNet: $VNET_NAME with address space: $VNET_ADDRESS_SPACE"
az network vnet create \
    --resource-group $RG_NAME \
    --name $VNET_NAME \
    --address-prefixes $VNET_ADDRESS_SPACE \
    --location $LOCATION \
    --tags $TAGS

# Create VM subnet
echo "Creating VM subnet: $VM_SUBNET_NAME with address range: $VM_SUBNET_ADDRESS"
az network vnet subnet create \
    --resource-group $RG_NAME \
    --vnet-name $VNET_NAME \
    --name $VM_SUBNET_NAME \
    --address-prefixes $VM_SUBNET_ADDRESS

# Create Private Endpoint subnet with special configuration
echo "Creating Private Endpoint subnet: $PE_SUBNET_NAME with address range: $PE_SUBNET_ADDRESS"
az network vnet subnet create \
    --resource-group $RG_NAME \
    --vnet-name $VNET_NAME \
    --name $PE_SUBNET_NAME \
    --address-prefixes $PE_SUBNET_ADDRESS \
    --private-endpoint-network-policies Disabled

echo "VNet and subnets created successfully!"
echo "- VNet: $VNET_NAME ($VNET_ADDRESS_SPACE)"
echo "- VM Subnet: $VM_SUBNET_NAME ($VM_SUBNET_ADDRESS)"
echo "- Private Endpoint Subnet: $PE_SUBNET_NAME ($PE_SUBNET_ADDRESS)"

echo ""
echo "Step 4: Creating Storage Account and configuring IAM..."

# Create Storage Account
echo "Creating Storage Account: $STORAGE_NAME"
echo "  - SKU: $STORAGE_SKU"
echo "  - Hierarchical Namespace: $HIERARCHICAL_NAMESPACE"
echo "  - Public Network Access: Disabled (Private Endpoints only)"
az storage account create \
    --name $STORAGE_NAME \
    --resource-group $RG_NAME \
    --location $LOCATION \
    --sku $STORAGE_SKU \
    --kind StorageV2 \
    --access-tier Hot \
    --allow-blob-public-access false \
    --public-network-access Disabled \
    --enable-hierarchical-namespace $HIERARCHICAL_NAMESPACE \
    --allow-shared-key-access true \
    --https-only true \
    --min-tls-version TLS1_2 \
    --default-action Deny \
    --tags $TAGS

echo "Storage Account created with the following configuration:"
echo "  - Redundancy: $STORAGE_SKU"
echo "  - Hierarchical Namespace (Data Lake Gen2): $HIERARCHICAL_NAMESPACE"
echo "  - Public Access: Disabled"
echo "  - HTTPS Only: Enabled"
echo "  - Minimum TLS Version: 1.2"
echo "  - Default Network Action: Deny"

# Create a test VM with System-Assigned Managed Identity
echo "Creating VM with System-Assigned Managed Identity: $VM_NAME"
az vm create \
    --resource-group $RG_NAME \
    --name $VM_NAME \
    --image $VM_IMAGE \
    --size $VM_SIZE \
    --admin-username $VM_ADMIN_USERNAME \
    --generate-ssh-keys \
    --vnet-name $VNET_NAME \
    --subnet $VM_SUBNET_NAME \
    --public-ip-address "" \
    --nsg "" \
    --assign-identity \
    --tags $TAGS

# Get the VM's Managed Identity principal ID
echo "Retrieving VM's Managed Identity principal ID..."
VM_IDENTITY=$(az vm identity show \
    --resource-group $RG_NAME \
    --name $VM_NAME \
    --query principalId \
    --output tsv)

echo "VM Managed Identity Principal ID: $VM_IDENTITY"

# Get Storage Account resource ID
echo "Retrieving Storage Account resource ID..."
STORAGE_ID=$(az storage account show \
    --name "$STORAGE_NAME" \
    --resource-group "$RG_NAME" \
    --query "id" \
    --output tsv 2>/dev/null | tr -d '\r')

if [ -z "$STORAGE_ID" ]; then
    echo "ERROR: Failed to retrieve Storage Account ID"
    echo "Attempting to construct resource ID manually..."
    STORAGE_ID="/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RG_NAME/providers/Microsoft.Storage/storageAccounts/$STORAGE_NAME"
fi

echo "Storage Account ID: $STORAGE_ID"
echo "Storage Account ID Length: ${#STORAGE_ID}"

# Assign Storage Blob Data Contributor role to VM's Managed Identity
echo "Assigning Storage Blob Data Contributor role to VM's Managed Identity..."
az role assignment create \
    --assignee $VM_IDENTITY \
    --role "Storage Blob Data Contributor" \
    --scope $STORAGE_ID

# Assign Storage Account Contributor role (for container operations)
echo "Assigning Storage Account Contributor role to VM's Managed Identity..."
az role assignment create \
    --assignee $VM_IDENTITY \
    --role "Storage Account Contributor" \
    --scope $STORAGE_ID

echo ""
echo "Step 4 completed successfully!"
echo "Storage Account: $STORAGE_NAME"
echo "VM: $VM_NAME"
echo "VM Managed Identity: $VM_IDENTITY"
echo ""
echo "Assigned Roles:"
echo "- Storage Blob Data Contributor (for blob operations)"
echo "- Storage Account Contributor (for container management)"

echo ""
echo "Step 5: Creating Private Endpoint for Storage Account..."

# Verify storage account ID is valid
if [ -z "$STORAGE_ID" ]; then
    echo "ERROR: Storage Account ID is empty. Cannot create private endpoint."
    exit 1
fi

echo "Using Storage Account ID: $STORAGE_ID"
echo "Storage Account ID Length: ${#STORAGE_ID}"

# Validate the resource ID format
if [[ ! "$STORAGE_ID" =~ ^/subscriptions/.*/resourceGroups/.*/providers/Microsoft.Storage/storageAccounts/.* ]]; then
    echo "ERROR: Storage Account ID format is invalid: $STORAGE_ID"
    exit 1
fi

# Create Private Endpoint for Storage Account Blob service
echo "Creating Private Endpoint: $PE_NAME"
az network private-endpoint create \
    --resource-group "$RG_NAME" \
    --name "$PE_NAME" \
    --vnet-name "$VNET_NAME" \
    --subnet "$PE_SUBNET_NAME" \
    --private-connection-resource-id "$STORAGE_ID" \
    --group-id blob \
    --connection-name "${PE_NAME}-connection" \
    --location "$LOCATION" \
    --tags $TAGS

# Check if private endpoint was created successfully
if [ $? -eq 0 ]; then
    echo "Private endpoint created successfully!"
    
    # Get the Private Endpoint's network interface ID
    echo "Retrieving private endpoint network interface details..."
    PE_NIC_ID=$(az network private-endpoint show \
        --resource-group "$RG_NAME" \
        --name "$PE_NAME" \
        --query 'networkInterfaces[0].id' \
        --output tsv)

    if [ -n "$PE_NIC_ID" ]; then
        # Get the private IP address of the Private Endpoint
        PE_PRIVATE_IP=$(az network nic show \
            --ids "$PE_NIC_ID" \
            --query 'ipConfigurations[0].privateIpAddress' \
            --output tsv)

        echo "Private Endpoint configuration:"
        echo "  - Name: $PE_NAME"
        echo "  - Private IP: $PE_PRIVATE_IP"
        echo "  - Target Service: Storage Account Blob"
        echo "  - Connection Status: Connected"
    else
        echo "Warning: Could not retrieve private endpoint network interface details"
    fi
else
    echo "ERROR: Failed to create private endpoint"
    exit 1
fi

echo ""
echo "Step 6: Creating Private DNS Zone for Storage Account..."

if [ "$ENABLE_PRIVATE_DNS" = "true" ]; then
    echo "Private DNS integration is ENABLED"
    
    # Define DNS zone name for blob storage
    DNS_ZONE_NAME="privatelink.blob.core.windows.net"
    DNS_ZONE_LINK_NAME="vnet-${WORKLOAD}-${ENVIRONMENT}-${LOCATION}-dns-link"

    # Create Private DNS Zone
    echo "Creating Private DNS Zone: $DNS_ZONE_NAME"
    az network private-dns zone create \
        --resource-group "$RG_NAME" \
        --name "$DNS_ZONE_NAME" \
        --tags $TAGS

    # Check if DNS zone was created successfully
    if [ $? -ne 0 ]; then
        echo "ERROR: Failed to create Private DNS Zone"
        exit 1
    fi

    # Link the Private DNS Zone to the VNet
    echo "Linking Private DNS Zone to VNet: $VNET_NAME"
    az network private-dns link vnet create \
        --resource-group "$RG_NAME" \
        --zone-name "$DNS_ZONE_NAME" \
        --name "$DNS_ZONE_LINK_NAME" \
        --virtual-network "$VNET_NAME" \
        --registration-enabled false \
        --tags $TAGS

    # Check if DNS zone link was created successfully
    if [ $? -ne 0 ]; then
        echo "ERROR: Failed to create Private DNS Zone VNet Link"
        exit 1
    fi

    # Get the Private DNS Zone resource ID for the DNS zone group
    echo "Retrieving Private DNS Zone resource ID..."
    # Use explicit construction to avoid truncation issues
    DNS_ZONE_ID="/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RG_NAME/providers/Microsoft.Network/privateDnsZones/$DNS_ZONE_NAME"

    echo "DNS Zone ID: $DNS_ZONE_ID"
    echo "DNS Zone ID Length: ${#DNS_ZONE_ID}"

    # Validate the DNS zone ID format
    if [[ ! "$DNS_ZONE_ID" =~ ^/subscriptions/.*/resourceGroups/.*/providers/Microsoft.Network/privateDnsZones/.* ]]; then
        echo "ERROR: DNS Zone ID format is invalid: $DNS_ZONE_ID"
        exit 1
    fi

    # Create DNS zone group for automatic DNS record management
    echo "Creating Private DNS Zone Group for automatic record management..."
    DNS_ZONE_GROUP_NAME="${PE_NAME}-dns-zone-group"
    az network private-endpoint dns-zone-group create \
        --resource-group "$RG_NAME" \
        --endpoint-name "$PE_NAME" \
        --name "$DNS_ZONE_GROUP_NAME" \
        --private-dns-zone "$DNS_ZONE_ID" \
        --zone-name blob

    # Check if DNS zone group was created successfully
    if [ $? -ne 0 ]; then
        echo "ERROR: Failed to create Private DNS Zone Group"
        exit 1
    fi

    # Verify DNS configuration
    echo "Verifying Private DNS Zone configuration..."
    echo "DNS Zone: $DNS_ZONE_NAME"
    echo "VNet Link: $DNS_ZONE_LINK_NAME"
    echo "DNS Zone Group: $DNS_ZONE_GROUP_NAME"

    # Verify DNS zone group configuration
    echo "Verifying DNS Zone Group configuration..."
    az network private-endpoint dns-zone-group show \
        --resource-group "$RG_NAME" \
        --endpoint-name "$PE_NAME" \
        --name "$DNS_ZONE_GROUP_NAME" \
        --output table

    # Show DNS records (will show the A record created for the storage account)
    echo ""
    echo "DNS Records in Private DNS Zone:"
    az network private-dns record-set list \
        --resource-group "$RG_NAME" \
        --zone-name "$DNS_ZONE_NAME" \
        --query "[?type == 'Microsoft.Network/privateDnsZones/A']" \
        --output table

    echo ""
    echo "Step 6 completed successfully!"
    echo "Private DNS Zone configured for blob storage private endpoint resolution"
    
else
    echo "Private DNS integration is DISABLED"
    echo "Private Endpoint created without DNS zone integration"
    echo ""
    echo "To resolve the storage account privately, you will need to:"
    echo "1. Create a Private DNS Zone manually: privatelink.blob.core.windows.net"
    echo "2. Link it to your VNet: $VNET_NAME"
    echo "3. Create an A record pointing to the private endpoint IP"
    echo "4. Or configure your own DNS solution"
    echo ""
    echo "Step 6 completed - Private DNS integration skipped"
fi

echo ""
echo "=== DEPLOYMENT COMPLETED SUCCESSFULLY ==="
echo "Resources created:"
echo "  - Resource Group: $RG_NAME"
echo "  - VNet: $VNET_NAME ($VNET_ADDRESS_SPACE)"
echo "  - VM Subnet: $VM_SUBNET_NAME ($VM_SUBNET_ADDRESS)"
echo "  - PE Subnet: $PE_SUBNET_NAME ($PE_SUBNET_ADDRESS)"
echo "  - Storage Account: $STORAGE_NAME (ZRS, Private access only)"
echo "  - VM: $VM_NAME (with Managed Identity)"
echo "  - Private Endpoint: $PE_NAME"

if [ "$ENABLE_PRIVATE_DNS" = "true" ]; then
    echo "  - Private DNS Zone: $DNS_ZONE_NAME"
    echo "  - DNS Zone VNet Link: $DNS_ZONE_LINK_NAME"
    echo "  - DNS Zone Group: $DNS_ZONE_GROUP_NAME"
else
    echo "  - Private DNS Zone: SKIPPED (feature flag disabled)"
fi

echo ""
echo "Security Configuration:"
echo "  - Storage Account: Public access disabled, HTTPS only, TLS 1.2+"
echo "  - Network: Private endpoint provides secure access to storage"

if [ "$ENABLE_PRIVATE_DNS" = "true" ]; then
    echo "  - DNS: Private DNS zone enables private resolution of storage account"
else
    echo "  - DNS: Manual configuration required for private resolution"
fi

echo "  - IAM: VM has Storage Blob Data Contributor and Storage Account Contributor roles"

if [ "$ENABLE_PRIVATE_DNS" = "false" ]; then
    echo ""
    echo "IMPORTANT: Private DNS is disabled. To access the storage account from the VM:"
    echo "1. Use the private endpoint IP directly: $(az network private-endpoint show --resource-group $RG_NAME --name $PE_NAME --query 'customDnsConfigs[0].ipAddresses[0]' --output tsv 2>/dev/null || echo 'Check private endpoint for IP')"
    echo "2. Or configure DNS manually to resolve $STORAGE_NAME.blob.core.windows.net to the private IP"
fi