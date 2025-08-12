# Step 3: VNet and Subnet Design for Azure Storage + Private Endpoint POC

## Overview
This step creates the virtual network infrastructure required for the Azure Storage + Private Endpoint POC. The design includes a VNet with two dedicated subnets following Azure best practices.

## Network Architecture

### VNet Configuration
- **Name**: `vnet-stgdemo-poc-eastus2-01`
- **Address Space**: `10.0.0.0/16` (65,536 IP addresses)
- **Location**: East US 2
- **Purpose**: Isolated network environment for the POC

### Subnet Design

#### 1. VM Subnet
- **Name**: `snet-stgdemo-poc-eastus2-vm-01`
- **Address Range**: `10.0.1.0/24` (256 IP addresses)
- **Purpose**: Hosts virtual machines and compute resources
- **Available IPs**: ~251 (Azure reserves 5 IPs per subnet)

#### 2. Private Endpoint Subnet
- **Name**: `snet-stgdemo-poc-eastus2-pe-01`
- **Address Range**: `10.0.2.0/24` (256 IP addresses)
- **Purpose**: Dedicated to private endpoints for Azure services
- **Special Configuration**: `disable-private-endpoint-network-policies=true`
- **Available IPs**: ~251

## Key Design Decisions

### Address Space Planning
- **Non-overlapping ranges**: Ensures no IP conflicts
- **Room for growth**: /16 VNet allows for additional subnets
- **Standard private ranges**: Uses RFC 1918 compliant addresses

### Private Endpoint Subnet Special Settings
The private endpoint subnet has `disable-private-endpoint-network-policies=true` because:
- **Required for private endpoints**: Network policies must be disabled on subnets hosting private endpoints
- **Security**: Private endpoints have their own security model via private DNS zones
- **Azure requirement**: This setting is mandatory for private endpoint functionality

## Naming Convention
Following Azure Cloud Adoption Framework naming standards:
- `vnet-{workload}-{environment}-{region}-{instance}`
- `snet-{workload}-{environment}-{region}-{purpose}-{instance}`

## Usage

### Run Step 3 Standalone
```bash
./step3-create-vnet.sh
```

### Run as Part of Complete Setup
```bash
./setup.sh
```

## Verification Commands
After creation, verify the resources:

```bash
# List VNet details
az network vnet show --resource-group rg-stgdemo-poc-eastus2-01 --name vnet-stgdemo-poc-eastus2-01

# List subnets
az network vnet subnet list --resource-group rg-stgdemo-poc-eastus2-01 --vnet-name vnet-stgdemo-poc-eastus2-01 --output table

# Check private endpoint network policies
az network vnet subnet show --resource-group rg-stgdemo-poc-eastus2-01 --vnet-name vnet-stgdemo-poc-eastus2-01 --name snet-stgdemo-poc-eastus2-pe-01 --query privateEndpointNetworkPolicies
```

## Next Steps
- Step 4: Create Azure Storage Account
- Step 5: Create Private Endpoint
- Step 6: Configure Private DNS Zone
- Step 7: Test connectivity from VM

## Security Considerations
- Subnets are isolated within the VNet
- Private endpoints provide secure access to Azure services
- No public IPs required for storage access
- Network Security Groups can be applied later if needed
