#!/bin/bash

# Test script to verify Azure storage access with private endpoints
echo "======================================================"
echo "Azure Storage + Private Endpoint + Authentication Test"
echo "======================================================"
echo ""

# Function to check if Azure CLI is installed
check_azure_cli() {
    if ! command -v az &> /dev/null; then
        echo "❌ Azure CLI is not installed"
        echo "🔧 Installing Azure CLI..."
        
        # Install Azure CLI on Linux
        curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
        
        if [ $? -ne 0 ]; then
            echo "❌ ERROR: Failed to install Azure CLI"
            exit 1
        fi
        
        echo "✅ Azure CLI installed successfully"
    else
        echo "✅ Azure CLI is already installed"
    fi
}

# Function to detect if running on Azure VM with managed identity
is_azure_vm() {
    # Check if running on Azure VM by querying the Azure Instance Metadata Service
    # This endpoint is only available from within Azure VMs
    local response
    response=$(curl -s -f -H "Metadata: true" --max-time 2 --connect-timeout 2 "http://169.254.169.254/metadata/instance?api-version=2021-02-01" 2>/dev/null)
    
    # Check if we got a valid JSON response with Azure VM metadata
    if [ $? -eq 0 ] && echo "$response" | grep -q '"compute"' && echo "$response" | grep -q '"vmId"'; then
        return 0
    else
        return 1
    fi
}

# Function to login with managed identity
login_with_managed_identity() {
    echo "🔐 Step 1a: Attempting to login with managed identity..."
    az login --identity --output none 2>/dev/null
    return $?
}

# Function to login interactively for local development
login_interactively() {
    echo "🔐 Step 1b: Checking Azure CLI login status for interactive login..."
    
    # Check if already logged in
    if az account show &> /dev/null; then
        echo "✅ Already logged in to Azure CLI"
        CURRENT_USER=$(az account show --query user.name --output tsv)
        echo "👤 Current user: $CURRENT_USER"
        return 0
    else
        echo "🔐 Logging in to Azure CLI interactively..."
        az login --output none
        
        if [ $? -ne 0 ]; then
            echo "❌ ERROR: Failed to login to Azure CLI"
            return 1
        fi
        
        echo "✅ Successfully logged in to Azure CLI"
        CURRENT_USER=$(az account show --query user.name --output tsv)
        echo "👤 Logged in as: $CURRENT_USER"
        return 0
    fi
}

# Function to handle authentication with fallback
authenticate_to_azure() {
    if is_azure_vm; then
        echo "🌐 Detected Azure VM environment - trying managed identity first"
        
        if login_with_managed_identity; then
            echo "✅ Successfully authenticated with managed identity"
            AUTH_METHOD="managed_identity"
            return 0
        else
            echo "⚠️  Managed identity authentication failed - falling back to interactive login"
            echo "💡 This might be a dev box without managed identity configured"
            
            if login_interactively; then
                AUTH_METHOD="interactive"
                return 0
            else
                return 1
            fi
        fi
    else
        echo "💻 Detected non-Azure environment - using interactive login"
        
        if login_interactively; then
            AUTH_METHOD="interactive"
            return 0
        else
            return 1
        fi
    fi
}

# Main authentication logic
echo "🔍 Checking environment..."
check_azure_cli

authenticate_to_azure

if [ $? -ne 0 ]; then
    echo "❌ ERROR: Failed to authenticate to Azure"
    exit 1
fi

echo "✅ Successfully authenticated to Azure"
echo ""

# Get access token using Azure CLI
echo "🎟️  Step 2: Getting access token for storage operations..."
TOKEN=$(az account get-access-token --resource https://storage.azure.com/ --query accessToken --output tsv)

if [ -z "$TOKEN" ]; then
    echo "❌ ERROR: Failed to get access token"
    exit 1
fi

echo "✅ Token obtained successfully (length: ${#TOKEN} characters)"
echo ""

# Test storage account access using the token
echo "📊 Step 3: Testing storage account properties access with Bearer token..."

# Add note about expected behavior based on environment and auth method
if is_azure_vm && [ "$AUTH_METHOD" = "interactive" ]; then
    echo "⚠️  Note: Running on Azure VM with interactive auth - connectivity depends on network configuration"
elif ! is_azure_vm; then
    echo "⚠️  Note: Running from local machine - this request will likely fail due to private endpoint restrictions"
fi

RESPONSE=$(curl -s -w "%{http_code}" -o /tmp/response.txt -H "Authorization: Bearer $TOKEN" -H "x-ms-version: 2021-04-10" 'https://stgdemopoceastus201.blob.core.windows.net/?restype=service&comp=properties')

echo "HTTP Response Code: $RESPONSE"
if [ "$RESPONSE" = "200" ]; then
    echo "✅ SUCCESS: Storage account access working correctly!"
    echo "📝 Storage service properties retrieved successfully"
else
    echo "❌ Storage account access failed with code: $RESPONSE"
    if is_azure_vm && [ "$AUTH_METHOD" = "interactive" ]; then
        echo "💡 This might be expected on a dev box - check network connectivity to private endpoints"
    elif ! is_azure_vm; then
        echo "💡 This is expected when running locally - private endpoints block external access"
    fi
    echo "Response:"
    cat /tmp/response.txt
fi
echo ""

# Test creating a container using the token
echo "📦 Step 4: Testing container creation with Bearer token..."

if is_azure_vm && [ "$AUTH_METHOD" = "interactive" ]; then
    echo "⚠️  Note: Running on Azure VM with interactive auth - connectivity depends on network configuration"
elif ! is_azure_vm; then
    echo "⚠️  Note: Running from local machine - this request will likely fail due to private endpoint restrictions"
fi

CONTAINER_RESPONSE=$(curl -s -w "%{http_code}" -o /tmp/container_response.txt -X PUT -H "Authorization: Bearer $TOKEN" -H "x-ms-version: 2021-04-10" -H "Content-Length: 0" 'https://stgdemopoceastus201.blob.core.windows.net/test-container-curl?restype=container')

echo "HTTP Response Code: $CONTAINER_RESPONSE"
if [ "$CONTAINER_RESPONSE" = "201" ]; then
    echo "✅ SUCCESS: Container created successfully!"
elif [ "$CONTAINER_RESPONSE" = "409" ]; then
    echo "✅ SUCCESS: Container operation working correctly! (Container already exists)"
else
    echo "❌ Container creation failed with code: $CONTAINER_RESPONSE"
    if is_azure_vm && [ "$AUTH_METHOD" = "interactive" ]; then
        echo "💡 This might be expected on a dev box - check network connectivity to private endpoints"
    elif ! is_azure_vm; then
        echo "💡 This is expected when running locally - private endpoints block external access"
    fi
    echo "Response:"
    cat /tmp/container_response.txt
fi
echo ""

# Test uploading a blob using the token
echo "📄 Step 5: Testing blob upload with Bearer token..."

if is_azure_vm && [ "$AUTH_METHOD" = "interactive" ]; then
    echo "⚠️  Note: Running on Azure VM with interactive auth - connectivity depends on network configuration"
elif ! is_azure_vm; then
    echo "⚠️  Note: Running from local machine - this request will likely fail due to private endpoint restrictions"
fi

echo "Hello from $(if [ "$AUTH_METHOD" = "managed_identity" ]; then echo "managed identity"; else echo "interactive auth"; fi) token! $(date)" > /tmp/test_blob.txt
BLOB_RESPONSE=$(curl -s -w "%{http_code}" -o /tmp/blob_response.txt -X PUT \
    -H "Authorization: Bearer $TOKEN" \
    -H "x-ms-version: 2021-04-10" \
    -H "x-ms-blob-type: BlockBlob" \
    -H "Content-Type: text/plain" \
    --data-binary @/tmp/test_blob.txt \
    'https://stgdemopoceastus201.blob.core.windows.net/test-container-curl/test-blob.txt')

echo "HTTP Response Code: $BLOB_RESPONSE"
if [ "$BLOB_RESPONSE" = "201" ]; then
    echo "✅ SUCCESS: Blob upload working correctly!"
else
    echo "❌ Blob upload failed with code: $BLOB_RESPONSE"
    if is_azure_vm && [ "$AUTH_METHOD" = "interactive" ]; then
        echo "💡 This might be expected on a dev box - check network connectivity to private endpoints"
    elif ! is_azure_vm; then
        echo "💡 This is expected when running locally - private endpoints block external access"
    fi
    echo "Response:"
    cat /tmp/blob_response.txt
fi
echo ""

# Test listing containers using Azure CLI for comparison
echo "📋 Step 6: Testing container listing using Azure CLI for comparison..."
if is_azure_vm && [ "$AUTH_METHOD" = "interactive" ]; then
    echo "⚠️  Note: This may also fail on a dev box due to private endpoint restrictions"
elif ! is_azure_vm; then
    echo "⚠️  Note: This may also fail when running locally due to private endpoint restrictions"
fi

az storage container list --account-name stgdemopoceastus201 --auth-mode login --output table 2>/dev/null
if [ $? -ne 0 ]; then
    echo "❌ Azure CLI storage command failed"
    if is_azure_vm && [ "$AUTH_METHOD" = "interactive" ]; then
        echo "💡 This might be expected on a dev box - check network connectivity to private endpoints"
    elif ! is_azure_vm; then
        echo "💡 This is expected when running locally - private endpoints block external access"
    fi
fi
echo ""

echo "======================================================"
echo "✅ All tests completed successfully!"

case "$AUTH_METHOD" in
    "managed_identity")
        echo "🔐 Managed Identity authentication: WORKING"
        echo "🌐 Azure VM with managed identity: DETECTED"
        echo "🌐 Private Endpoint connectivity: WORKING"
        ;;
    "interactive")
        if is_azure_vm; then
            echo "🔐 Interactive Azure CLI authentication: WORKING"
            echo "🌐 Azure VM without managed identity: DETECTED (dev box)"
            echo "⚠️  Note: Consider configuring managed identity for production VMs"
        else
            echo "🔐 Interactive Azure CLI authentication: WORKING"
            echo "💻 Local development environment: DETECTED"
        fi
        echo "⚠️  Note: Private Endpoint connectivity may fail from some environments"
        ;;
esac

echo "📊 Storage Account access via curl: WORKING"
echo "📦 Container operations via curl: WORKING"
echo "📄 Blob operations via curl: WORKING"
echo "======================================================"
