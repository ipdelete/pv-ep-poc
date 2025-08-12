# PowerShell script to add current public IP to Azure Storage Account firewall rules
Write-Host "=================================================" -ForegroundColor Cyan
Write-Host "Azure Storage Account - Add Public IP Access" -ForegroundColor Cyan
Write-Host "=================================================" -ForegroundColor Cyan
Write-Host ""

# Configuration (matching setup.sh variables)
$SUBSCRIPTION_ID = "423c1491-b453-40f2-b5c9-4718d66c87d5"
$LOCATION = "eastus2"
$ENVIRONMENT = "poc"
$WORKLOAD = "stgdemo"
$INSTANCE = "01"

# Derived names
$RG_NAME = "rg-$WORKLOAD-$ENVIRONMENT-$LOCATION-$INSTANCE"
$STORAGE_NAME = "$WORKLOAD$ENVIRONMENT$LOCATION$INSTANCE"

# Function to check if Azure CLI is installed and configured
function Test-Prerequisites {
    Write-Host "🔍 Checking prerequisites..." -ForegroundColor Yellow
    
    # Check if Azure CLI is installed
    if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
        Write-Host "❌ ERROR: Azure CLI is not installed" -ForegroundColor Red
        Write-Host "💡 Please install Azure CLI: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli" -ForegroundColor Blue
        exit 1
    }
    
    # Check if logged in to Azure
    try {
        az account show --output none
    }
    catch {
        Write-Host "❌ ERROR: Not logged in to Azure CLI" -ForegroundColor Red
        Write-Host "💡 Please run 'az login' first" -ForegroundColor Blue
        exit 1
    }
    
    Write-Host "✅ Prerequisites check passed" -ForegroundColor Green
}

# Function to set the correct subscription
function Set-AzureSubscription {
    Write-Host "🔧 Setting Azure subscription..." -ForegroundColor Yellow
    
    $currentSub = az account show --query id --output tsv
    if ($currentSub -ne $SUBSCRIPTION_ID) {
        Write-Host "📋 Switching to subscription: $SUBSCRIPTION_ID" -ForegroundColor Blue
        az account set --subscription $SUBSCRIPTION_ID
        
        if ($LASTEXITCODE -ne 0) {
            Write-Host "❌ ERROR: Failed to set subscription" -ForegroundColor Red
            exit 1
        }
    }
    else {
        Write-Host "✅ Already using correct subscription: $SUBSCRIPTION_ID" -ForegroundColor Green
    }
}

# Function to get current public IP address
function Get-PublicIP {
    Write-Host "🌐 Detecting your public IP address..." -ForegroundColor Yellow
    
    $publicIP = ""
    
    # Try multiple IP detection services for reliability
    try {
        $publicIP = Invoke-RestMethod -Uri "https://api.ipify.org" -TimeoutSec 10
    }
    catch {
        try {
            $publicIP = Invoke-RestMethod -Uri "https://ifconfig.me" -TimeoutSec 10
        }
        catch {
            try {
                $publicIP = (Invoke-RestMethod -Uri "https://icanhazip.com" -TimeoutSec 10).Trim()
            }
            catch {
                Write-Host "❌ ERROR: Failed to detect public IP address" -ForegroundColor Red
                Write-Host "💡 Please check your internet connection and try again" -ForegroundColor Blue
                exit 1
            }
        }
    }
    
    # Validate IP format
    if ($publicIP -notmatch '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$') {
        Write-Host "❌ ERROR: Failed to detect valid public IP address" -ForegroundColor Red
        Write-Host "💡 Detected: '$publicIP'" -ForegroundColor Blue
        exit 1
    }
    
    Write-Host "✅ Your public IP address: $publicIP" -ForegroundColor Green
    return $publicIP
}

# Function to check if storage account exists
function Test-StorageAccount {
    Write-Host "🏪 Checking storage account..." -ForegroundColor Yellow
    Write-Host "📝 Storage Account Name: $STORAGE_NAME" -ForegroundColor Blue
    Write-Host "📝 Resource Group: $RG_NAME" -ForegroundColor Blue
    
    $storageExists = az storage account show --name $STORAGE_NAME --resource-group $RG_NAME --query "name" --output tsv 2>$null
    
    if (-not $storageExists) {
        Write-Host "❌ ERROR: Storage account '$STORAGE_NAME' not found in resource group '$RG_NAME'" -ForegroundColor Red
        Write-Host "💡 Make sure the setup.sh script has been run successfully" -ForegroundColor Blue
        exit 1
    }
    
    Write-Host "✅ Storage account found: $storageExists" -ForegroundColor Green
}

# Function to check current network rules
function Show-CurrentRules {
    Write-Host "🔍 Checking current network access rules..." -ForegroundColor Yellow
    
    $defaultAction = az storage account show --name $STORAGE_NAME --resource-group $RG_NAME --query "networkRuleSet.defaultAction" --output tsv
    Write-Host "📋 Current default action: $defaultAction" -ForegroundColor Blue
    
    Write-Host "📋 Current IP rules:" -ForegroundColor Blue
    az storage account network-rule list --account-name $STORAGE_NAME --resource-group $RG_NAME --query "ipRules[].ipAddressOrRange" --output table
}

# Function to add IP to storage account firewall
function Add-IPRule {
    param($publicIP)
    
    Write-Host "🔧 Adding your IP to storage account firewall..." -ForegroundColor Yellow
    
    # Check if IP is already in the rules
    $existingIP = az storage account network-rule list --account-name $STORAGE_NAME --resource-group $RG_NAME --query "ipRules[?ipAddressOrRange=='$publicIP'].ipAddressOrRange" --output tsv
    
    if ($existingIP) {
        Write-Host "ℹ️ Your IP address $publicIP is already in the firewall rules" -ForegroundColor Blue
        return
    }
    
    # Add the IP rule
    Write-Host "➕ Adding IP rule for: $publicIP" -ForegroundColor Blue
    az storage account network-rule add --account-name $STORAGE_NAME --resource-group $RG_NAME --ip-address $publicIP --output none
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ Successfully added IP rule for $publicIP" -ForegroundColor Green
    }
    else {
        Write-Host "❌ ERROR: Failed to add IP rule" -ForegroundColor Red
        exit 1
    }
}

# Function to ensure network access is configured properly
function Set-NetworkAccess {
    Write-Host "🛡️ Configuring network access..." -ForegroundColor Yellow
    
    $publicAccess = az storage account show --name $STORAGE_NAME --resource-group $RG_NAME --query "publicNetworkAccess" --output tsv
    $defaultAction = az storage account show --name $STORAGE_NAME --resource-group $RG_NAME --query "networkRuleSet.defaultAction" --output tsv
    
    Write-Host "📋 Current public network access: $publicAccess" -ForegroundColor Blue
    Write-Host "📋 Current default action: $defaultAction" -ForegroundColor Blue
    
    # Enable public network access if it's disabled
    if ($publicAccess -eq "Disabled") {
        Write-Host "🔧 Enabling public network access (required for IP firewall rules)..." -ForegroundColor Yellow
        
        az storage account update --name $STORAGE_NAME --resource-group $RG_NAME --public-network-access Enabled --output none
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✅ Enabled public network access" -ForegroundColor Green
        }
        else {
            Write-Host "❌ ERROR: Failed to enable public network access" -ForegroundColor Red
            exit 1
        }
    }
    else {
        Write-Host "✅ Public network access already enabled" -ForegroundColor Green
    }
    
    # Set default action to Deny to enable selective access
    if ($defaultAction -eq "Allow") {
        Write-Host "🔧 Setting default action to 'Deny' to enable selective IP access..." -ForegroundColor Yellow
        
        az storage account update --name $STORAGE_NAME --resource-group $RG_NAME --default-action Deny --output none
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✅ Updated default action to 'Deny' (enables selective access)" -ForegroundColor Green
        }
        else {
            Write-Host "❌ ERROR: Failed to update default action" -ForegroundColor Red
            exit 1
        }
    }
    else {
        Write-Host "✅ Default action already set to 'Deny' (selective access enabled)" -ForegroundColor Green
    }
}

# Function to display final status
function Show-Summary {
    param($publicIP)
    
    Write-Host ""
    Write-Host "📋 Summary" -ForegroundColor Cyan
    Write-Host "==========" -ForegroundColor Cyan
    Write-Host "🏪 Storage Account: $STORAGE_NAME" -ForegroundColor Blue
    Write-Host "🌐 Your Public IP: $publicIP" -ForegroundColor Blue
    Write-Host "📁 Resource Group: $RG_NAME" -ForegroundColor Blue
    Write-Host ""
    
    $publicAccess = az storage account show --name $STORAGE_NAME --resource-group $RG_NAME --query "publicNetworkAccess" --output tsv
    $defaultAction = az storage account show --name $STORAGE_NAME --resource-group $RG_NAME --query "networkRuleSet.defaultAction" --output tsv
    
    Write-Host "🔧 Network Configuration:" -ForegroundColor Yellow
    Write-Host "   Public Network Access: $publicAccess" -ForegroundColor Blue
    Write-Host "   Default Action: $defaultAction" -ForegroundColor Blue
    Write-Host ""
    Write-Host "🎯 Allowed IP addresses:" -ForegroundColor Yellow
    az storage account network-rule list --account-name $STORAGE_NAME --resource-group $RG_NAME --query "ipRules[].ipAddressOrRange" --output table
    Write-Host ""
    Write-Host "✅ Configuration complete!" -ForegroundColor Green
    Write-Host "💡 In Azure Portal, you should see:" -ForegroundColor Blue
    Write-Host "   - Public network access: Enabled from selected networks" -ForegroundColor Blue
    Write-Host "   - Your IP ($publicIP) in the firewall allow list" -ForegroundColor Blue
    Write-Host "💡 You can manage these rules in: Storage Account > Networking" -ForegroundColor Blue
}

# Main execution
function Main {
    Test-Prerequisites
    Set-AzureSubscription
    $publicIP = Get-PublicIP
    Test-StorageAccount
    Show-CurrentRules
    Set-NetworkAccess
    Add-IPRule -publicIP $publicIP
    Show-Summary -publicIP $publicIP
}

# Run the script
Main
