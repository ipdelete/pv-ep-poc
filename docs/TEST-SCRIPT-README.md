# Test Storage Access Script

## Overview
The `test-storage-access.sh` script demonstrates how to use Azure CLI to authenticate with Managed Identity and then extract the access token for direct REST API calls to Azure Storage.

## What the Script Does

1. **🔐 Authentication**: Uses `az login --identity` to authenticate with the VM's managed identity
2. **🎟️ Token Extraction**: Extracts an OAuth 2.0 access token using `az account get-access-token`
3. **📊 Storage Properties**: Tests access to storage account properties via REST API
4. **📦 Container Operations**: Creates a container using direct curl with Bearer token
5. **📄 Blob Operations**: Uploads a blob using direct curl with Bearer token
6. **📋 Verification**: Compares results with Azure CLI operations

## Key Features

- **Hybrid Approach**: Combines Azure CLI authentication with direct REST API calls
- **Bearer Token Authentication**: Shows proper use of OAuth 2.0 tokens with Azure Storage REST API
- **Error Handling**: Includes proper error checking and response validation
- **Comprehensive Testing**: Tests multiple storage operations (properties, containers, blobs)

## Usage

### Run on the VM directly:
```bash
# Copy the script to the VM and execute
./test-storage-access.sh
```

### Run remotely via Azure CLI:
```bash
az vm run-command invoke \
  --resource-group rg-stgdemo-poc-eastus2-01 \
  --name vm-stgdemo-poc-eastus2-01 \
  --command-id RunShellScript \
  --scripts "$(cat test-storage-access.sh)"
```

## Sample Output

```
======================================================
Azure Storage + Private Endpoint + Managed Identity Test
======================================================

🔐 Step 1: Logging in with managed identity using Azure CLI...
✅ Successfully logged in with managed identity

🎟️ Step 2: Getting access token for storage operations...
✅ Token obtained successfully (length: 1731 characters)

📊 Step 3: Testing storage account properties access with Bearer token...
HTTP Response Code: 200
✅ SUCCESS: Storage account access working correctly!
📝 Storage service properties retrieved successfully

📦 Step 4: Testing container creation with Bearer token...
HTTP Response Code: 201
✅ SUCCESS: Container created successfully!

📄 Step 5: Testing blob upload with Bearer token...
HTTP Response Code: 201
✅ SUCCESS: Blob upload working correctly!

📋 Step 6: Testing container listing using Azure CLI for comparison...
Name                 Lease Status    Last Modified
-------------------  --------------  -------------------------
test-container                       2025-08-12T16:56:04+00:00
test-container-curl                  2025-08-12T17:03:55+00:00

======================================================
✅ All tests completed successfully!
🔐 Managed Identity authentication: WORKING
🌐 Private Endpoint connectivity: WORKING
📊 Storage Account access via curl: WORKING
📦 Container operations via curl: WORKING
📄 Blob operations via curl: WORKING
======================================================
```

## Technical Details

### Authentication Flow
1. VM's managed identity authenticates with Azure AD
2. Azure CLI obtains and caches the access token
3. Script extracts the token for direct REST API calls
4. Token is used as Bearer authentication header

### REST API Headers Used
- `Authorization: Bearer $TOKEN` - OAuth 2.0 authentication
- `x-ms-version: 2021-04-10` - Azure Storage API version
- `Content-Length: 0` - Required for container creation
- `x-ms-blob-type: BlockBlob` - Blob type for uploads

### Error Codes Handled
- **200**: Success for GET operations
- **201**: Success for PUT operations (creation)
- **409**: Conflict (resource already exists)
- **411**: Length Required (missing Content-Length header)

This script provides a comprehensive test of the entire authentication and access chain from managed identity through to storage operations via both Azure CLI and direct REST API calls.
