# Azure Storage + Private Endpoint POC

This repository contains a proof-of-concept (POC) for setting up Azure Storage with Private Endpoints, demonstrating secure private connectivity without public internet access.

## Architecture

The setup creates:
- **Virtual Network** with dedicated subnets for VMs and Private Endpoints
- **Storage Account** with public access disabled
- **Private Endpoint** for secure blob storage access
- **Virtual Machine** with Managed Identity for authentication
- **Private DNS Zone** for automatic name resolution (optional)

## Quick Start

1. **Run the setup script:**
   ```bash
   ./setup.sh
   ```

2. **Clean up resources:**
   ```bash
   ./cleanup.sh
   ```

## Testing Storage Access

The repository includes a comprehensive test script to verify storage access with different authentication methods and environments.

### Test Script: `test-storage-access.sh`

This script automatically detects the environment and uses the appropriate authentication method:

- **Azure VM with Managed Identity**: Uses managed identity for authentication
- **Azure VM without Managed Identity (dev box)**: Attempts managed identity first, then falls back to interactive Azure CLI login
- **Local Development Machine**: Uses interactive Azure CLI login

### Running Tests Locally (Expected to Fail)

```bash
# Run the test from your local development machine or dev box
./test-storage-access.sh
```

**Expected behavior:**
- ✅ Azure CLI installation check passes
- ✅ Authentication succeeds (interactive login)
- ❌ Storage operations fail with private endpoint connectivity errors
- 💡 This demonstrates that authentication works but private endpoints block external access

### Running Tests on Production VM (Expected to Pass)

Use the test runner scripts to execute tests on the VM with proper private endpoint connectivity:

```bash
# Run basic storage test on the VM
./run-storage-test.sh

# Run advanced storage test with detailed output
./run-storage-test-advanced.sh
```

**Expected behavior:**
- ✅ All tests pass when running from the VM
- ✅ Managed identity authentication works
- ✅ Private endpoint connectivity allows storage access
- ✅ Full CRUD operations on containers and blobs succeed

### Test Output Example

The test script provides detailed output showing:
- Environment detection (Azure VM vs local)
- Authentication method used (managed identity vs interactive)
- Step-by-step test results with HTTP response codes
- Clear explanations for any failures

## Configuration Options

### Private DNS Integration Feature Flag

You can control whether Private DNS Zone integration is enabled or disabled:

**Option 1: Edit the script directly**
```bash
# In setup.sh, change this line:
ENABLE_PRIVATE_DNS="true"   # Enable DNS integration (default)
ENABLE_PRIVATE_DNS="false"  # Disable DNS integration
```

**Option 2: Use the toggle helper script**
```bash
./toggle-dns.sh  # Toggles between enabled/disabled
```

### When to disable Private DNS integration:

- **Using existing DNS zones**: When you already have a `privatelink.blob.core.windows.net` zone
- **Custom DNS solutions**: When using your own DNS servers or configurations
- **Manual DNS management**: When you want to control DNS records manually
- **Testing scenarios**: When testing private endpoints without automatic DNS

### When DNS integration is disabled:

The private endpoint will still work, but you'll need to handle DNS resolution manually:
1. Create a Private DNS Zone: `privatelink.blob.core.windows.net`
2. Link it to your VNet
3. Create an A record pointing to the private endpoint IP
4. Or use the private IP directly

## Resources Created

| Resource Type | Name Pattern | Purpose |
|---------------|--------------|---------|
| Resource Group | `rg-{workload}-{env}-{location}-{instance}` | Container for all resources |
| Virtual Network | `vnet-{workload}-{env}-{location}-{instance}` | Network isolation |
| VM Subnet | `snet-{workload}-{env}-{location}-vm-{instance}` | Virtual machine subnet |
| PE Subnet | `snet-{workload}-{env}-{location}-pe-{instance}` | Private endpoint subnet |
| Storage Account | `{workload}{env}{location}{instance}` | Blob storage with private access |
| Virtual Machine | `vm-{workload}-{env}-{location}-{instance}` | Test VM with managed identity |
| Private Endpoint | `pe-{workload}-{env}-{location}-storage-{instance}` | Secure storage connection |
| Private DNS Zone | `privatelink.blob.core.windows.net` | Name resolution (if enabled) |

## Security Features

- ✅ **No Public Access**: Storage account blocks all public traffic
- ✅ **Private Network Only**: Access only through private endpoints
- ✅ **Managed Identity**: VM uses Azure AD authentication
- ✅ **HTTPS Only**: TLS 1.2+ encryption enforced
- ✅ **Zone-Redundant Storage**: High availability with ZRS
- ✅ **Private DNS**: Automatic name resolution (when enabled)

## Customization

Edit the configuration variables in `setup.sh`:

```bash
# Basic Configuration
SUBSCRIPTION_ID="your-subscription-id"
LOCATION="eastus2"
ENVIRONMENT="poc"
WORKLOAD="stgdemo"

# Network Configuration
VNET_ADDRESS_SPACE="10.0.0.0/16"
VM_SUBNET_ADDRESS="10.0.1.0/24"
PE_SUBNET_ADDRESS="10.0.2.0/24"

# Storage Configuration
STORAGE_SKU="Standard_ZRS"
HIERARCHICAL_NAMESPACE="false"

# Feature Flags
ENABLE_PRIVATE_DNS="true"  # Toggle DNS integration
```

## Troubleshooting

### Common Test Scenarios

| Environment | Authentication | Storage Access | Expected Result |
|-------------|----------------|----------------|-----------------|
| Local Dev Machine | Interactive Login | Private Endpoint | ❌ Fails (expected) |
| Azure Dev Box | Interactive Login | Private Endpoint | ❌ Fails (expected) |
| Azure VM (Production) | Managed Identity | Private Endpoint | ✅ Success |
| Azure VM (Dev without MI) | Fallback to Interactive | Private Endpoint | Depends on network config |

### Error Messages and Solutions

**"Failed to connect to MSI"**
- Expected on dev boxes without managed identity
- Script automatically falls back to interactive login

**HTTP 400/403 on storage operations**
- Expected when running from outside the VNet
- Indicates private endpoint security is working correctly

**DNS resolution issues**
- Check if Private DNS Zone is properly configured
- Verify VNet is linked to the DNS zone
- Consider disabling DNS integration and using manual configuration

## Files

- `setup.sh` - Main deployment script
- `cleanup.sh` - Resource cleanup script
- `test-storage-access.sh` - Storage access test with environment detection
- `run-storage-test.sh` - Basic storage test runner for VM execution
- `run-storage-test-advanced.sh` - Advanced storage test runner with detailed output
- `toggle-dns.sh` - Helper to toggle DNS integration
- `list-resources.sh` - List created resources
- `docs/` - Additional documentation
