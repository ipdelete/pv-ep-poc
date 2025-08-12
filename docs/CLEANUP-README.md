# Private Endpoint POC - Cleanup Scripts

This directory contains scripts to manage the Azure resources created by `setup.sh`.

## Scripts

### 1. `cleanup.sh` - Resource Deletion Script
**Purpose**: Safely deletes all resources created by the setup script.

**Features**:
- ✅ Colored output with clear status indicators
- ✅ Resource existence checks before deletion
- ✅ User confirmation prompts for safety
- ✅ Sequential deletion in proper order
- ✅ Option to force delete entire resource group
- ✅ Error handling and status reporting

**Usage**:
```bash
./cleanup.sh
```

**What it deletes** (in order):
1. **Virtual Machine** (`vm-stgdemo-poc-eastus2-01`)
   - Automatically includes associated NICs, disks, and NSGs
2. **Private Endpoint** (`pe-stgdemo-poc-eastus2-storage-01`)
3. **Storage Account** (`stgdemopoceastus201`)
4. **Virtual Network** (`vnet-stgdemo-poc-eastus2-01`)
   - Automatically includes all subnets
5. **Resource Group** (`rg-stgdemo-poc-eastus2-01`) - Optional

### 2. `list-resources.sh` - Dry Run / Resource Discovery
**Purpose**: Shows what resources exist and would be deleted without actually deleting them.

**Features**:
- ✅ Dry-run mode - no actual deletions
- ✅ Detailed resource information
- ✅ Resource status and configuration details
- ✅ Clear deletion order preview

**Usage**:
```bash
./list-resources.sh
```

**What it shows**:
- All resources in the target resource group
- Detailed information for each key resource:
  - VM: Power state, size
  - Storage Account: SKU, public access status
  - Private Endpoint: Connection status
  - VNet: Subnet configuration
- Estimated deletion order

## Safety Features

### Confirmation Prompts
Both scripts include safety measures:
- **First prompt**: Confirms you want to delete resources
- **Second prompt**: Option to force delete entire resource group

### Resource Existence Checks
- Scripts check if resources exist before attempting deletion
- Gracefully handles missing resources
- Provides clear status for each operation

### Error Handling
- Validates Azure CLI authentication
- Checks subscription context
- Reports success/failure for each operation
- Continues with remaining resources if one fails

## Configuration

Both scripts use the same configuration variables as `setup.sh`:

```bash
SUBSCRIPTION_ID="423c1491-b453-40f2-b5c9-4718d66c87d5"
LOCATION="eastus2"
ENVIRONMENT="poc"
WORKLOAD="stgdemo"
INSTANCE="01"
```

## Example Usage Workflow

1. **Check what exists**:
   ```bash
   ./list-resources.sh
   ```

2. **Review the output** and verify these are the resources you want to delete

3. **Run cleanup** when ready:
   ```bash
   ./cleanup.sh
   ```

4. **Follow the prompts**:
   - Type `yes` to confirm resource deletion
   - Type `yes` again if you want to force delete the resource group

## Output Colors

- 🔵 **Blue [INFO]**: General information
- 🟢 **Green [SUCCESS/FOUND]**: Successful operations or found resources
- 🟡 **Yellow [WARNING/NOT FOUND]**: Warnings or missing resources
- 🔴 **Red [ERROR]**: Errors that need attention

## Notes

- **Asynchronous Deletions**: Some Azure resource deletions happen in the background
- **Completion Time**: Full cleanup may take 5-10 minutes to complete
- **Verification**: You can check the Azure portal or run `az group show --name <resource-group>` to verify completion
- **Force Delete**: The resource group force delete option will remove ALL resources immediately, even if they're in use

## Troubleshooting

### "Resource not found" errors
- This is normal if resources were partially deleted or never created
- Scripts will continue with remaining resources

### "Access denied" errors
- Ensure you're logged into Azure CLI: `az login`
- Verify you have Contributor access to the subscription/resource group

### Incomplete deletions
- Some resources may have dependencies that prevent immediate deletion
- Wait a few minutes and run the cleanup script again
- Use the force delete option for the resource group as a last resort
