# PowerShell script to get allowed IPs from Azure Storage Account firewall rules
param(
    [Parameter(Mandatory=$true, HelpMessage="Storage account name")]
    [string]$StorageAccountName,
    
    [Parameter(Mandatory=$true, HelpMessage="Resource group name")]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory=$false, HelpMessage="Azure subscription ID")]
    [string]$SubscriptionId,
    
    [Parameter(Mandatory=$false, HelpMessage="Output format: table, json, or tsv")]
    [ValidateSet("table", "json", "tsv")]
    [string]$OutputFormat = "table",
    
    [Parameter(Mandatory=$false, HelpMessage="Save allowed IPs to file (default: true)")]
    [bool]$SaveToFile = $true,
    
    [Parameter(Mandatory=$false, HelpMessage="Output file path for allowed IPs")]
    [string]$OutputFilePath
)

Write-Host "=================================================" -ForegroundColor Cyan
Write-Host "Azure Storage Account - Get Allowed IPs" -ForegroundColor Cyan
Write-Host "=================================================" -ForegroundColor Cyan
Write-Host ""

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
        az account show --output none 2>$null
        if ($LASTEXITCODE -ne 0) {
            throw "Not logged in"
        }
    }
    catch {
        Write-Host "❌ ERROR: Not logged in to Azure CLI" -ForegroundColor Red
        Write-Host "💡 Please run 'az login' first" -ForegroundColor Blue
        exit 1
    }
    
    Write-Host "✅ Prerequisites check passed" -ForegroundColor Green
}

# Function to set the subscription if provided
function Set-AzureSubscription {
    if ($SubscriptionId) {
        Write-Host "🔧 Setting Azure subscription to: $SubscriptionId" -ForegroundColor Yellow
        
        az account set --subscription $SubscriptionId
        if ($LASTEXITCODE -ne 0) {
            Write-Host "❌ ERROR: Failed to set subscription to $SubscriptionId" -ForegroundColor Red
            exit 1
        }
        Write-Host "✅ Subscription set successfully" -ForegroundColor Green
    }
    else {
        $currentSub = az account show --query name --output tsv
        Write-Host "📋 Using current subscription: $currentSub" -ForegroundColor Blue
    }
}

# Function to validate storage account exists
function Test-StorageAccount {
    Write-Host "🏪 Validating storage account..." -ForegroundColor Yellow
    Write-Host "📝 Storage Account: $StorageAccountName" -ForegroundColor Blue
    Write-Host "📝 Resource Group: $ResourceGroupName" -ForegroundColor Blue
    
    $storageExists = az storage account show --name $StorageAccountName --resource-group $ResourceGroupName --query "name" --output tsv 2>$null
    
    if (-not $storageExists -or $LASTEXITCODE -ne 0) {
        Write-Host "❌ ERROR: Storage account '$StorageAccountName' not found in resource group '$ResourceGroupName'" -ForegroundColor Red
        Write-Host "💡 Please verify the storage account name and resource group are correct" -ForegroundColor Blue
        exit 1
    }
    
    Write-Host "✅ Storage account validated: $storageExists" -ForegroundColor Green
}

# Function to get network configuration details
function Get-NetworkConfiguration {
    Write-Host "🔍 Retrieving network configuration..." -ForegroundColor Yellow
    
    # Get public network access status
    $publicAccess = az storage account show --name $StorageAccountName --resource-group $ResourceGroupName --query "publicNetworkAccess" --output tsv
    
    # Get default action
    $defaultAction = az storage account show --name $StorageAccountName --resource-group $ResourceGroupName --query "networkRuleSet.defaultAction" --output tsv
    
    Write-Host "📋 Network Configuration:" -ForegroundColor Blue
    Write-Host "   Public Network Access: $publicAccess" -ForegroundColor White
    Write-Host "   Default Action: $defaultAction" -ForegroundColor White
    Write-Host ""
    
    return @{
        PublicAccess = $publicAccess
        DefaultAction = $defaultAction
    }
}

# Function to save allowed IPs to file
function Save-AllowedIPsToFile {
    param($ipData, $filePath)
    
    if (-not $ipData) {
        Write-Host "ℹ️ No IP addresses to save" -ForegroundColor Blue
        return
    }
    
    try {
        # Convert IP data to array if it's not already
        $ipArray = if ($ipData -is [array]) { $ipData } else { $ipData -split "`n" | Where-Object { $_.Trim() -ne "" } }
        
        # Save only IP addresses to file (no headers or comments)
        $ipArray | Out-File -FilePath $filePath -Encoding UTF8
        
        Write-Host "💾 Allowed IPs saved to: $filePath" -ForegroundColor Green
        Write-Host "📊 Total IPs saved: $($ipArray.Count)" -ForegroundColor Blue
    }
    catch {
        Write-Host "❌ ERROR: Failed to save IPs to file: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Function to get raw IP addresses for file saving (separate from display)
function Get-RawIPAddresses {
    $ipAddresses = az storage account network-rule list --account-name $StorageAccountName --resource-group $ResourceGroupName --query "ipRules[].ipAddressOrRange" --output tsv
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ ERROR: Failed to retrieve IP rules" -ForegroundColor Red
        exit 1
    }
    
    if (-not $ipAddresses -or $ipAddresses.Trim() -eq "") {
        return $null
    }
    
    # Return clean IP addresses array (from TSV output only)
    $cleanIPs = $ipAddresses -split "`n" | Where-Object { 
        $ip = $_.Trim()
        $ip -ne "" -and $ip -match '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$'
    } | Sort-Object -Unique
    
    return $cleanIPs
}

# Function to display IP addresses based on output format
function Show-AllowedIPs {
    Write-Host "🎯 Retrieving allowed IP addresses..." -ForegroundColor Yellow
    
    # Display based on output format
    switch ($OutputFormat.ToLower()) {
        "json" {
            $ipRules = az storage account network-rule list --account-name $StorageAccountName --resource-group $ResourceGroupName --query "ipRules" --output json
            if ($LASTEXITCODE -eq 0 -and $ipRules) {
                Write-Host "📋 Allowed IP Rules (JSON):" -ForegroundColor Green
                Write-Host $ipRules
            }
        }
        "tsv" {
            $ipAddresses = az storage account network-rule list --account-name $StorageAccountName --resource-group $ResourceGroupName --query "ipRules[].ipAddressOrRange" --output tsv
            if ($ipAddresses) {
                Write-Host "📋 Allowed IP Addresses (TSV):" -ForegroundColor Green
                $ipAddresses -split "`n" | Where-Object { $_.Trim() -ne "" } | ForEach-Object { Write-Host $_ -ForegroundColor White }
            }
        }
        default { # table
            Write-Host "📋 Allowed IP Addresses:" -ForegroundColor Green
            az storage account network-rule list --account-name $StorageAccountName --resource-group $ResourceGroupName --query "ipRules[].ipAddressOrRange" --output table
        }
    }
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ ERROR: Failed to retrieve IP rules for display" -ForegroundColor Red
    }
}

# Function to get virtual network rules
function Get-VirtualNetworkRules {
    Write-Host "🌐 Checking virtual network rules..." -ForegroundColor Yellow
    
    $vnetRules = az storage account network-rule list --account-name $StorageAccountName --resource-group $ResourceGroupName --query "virtualNetworkRules" --output json 2>$null
    
    if ($LASTEXITCODE -eq 0 -and $vnetRules -and $vnetRules -ne "[]") {
        Write-Host "📋 Virtual Network Rules found:" -ForegroundColor Green
        switch ($OutputFormat.ToLower()) {
            "json" { Write-Host $vnetRules }
            default { 
                az storage account network-rule list --account-name $StorageAccountName --resource-group $ResourceGroupName --query "virtualNetworkRules[].{VirtualNetwork:virtualNetworkResourceId,Subnet:subnetResourceId}" --output table
            }
        }
    }
    else {
        Write-Host "ℹ️ No virtual network rules found" -ForegroundColor Blue
    }
}

# Function to display summary
function Show-Summary {
    param($networkConfig, $ipData, $savedFilePath)
    
    Write-Host ""
    Write-Host "📋 Summary" -ForegroundColor Cyan
    Write-Host "==========" -ForegroundColor Cyan
    Write-Host "🏪 Storage Account: $StorageAccountName" -ForegroundColor Blue
    Write-Host "📁 Resource Group: $ResourceGroupName" -ForegroundColor Blue
    Write-Host "🔧 Public Network Access: $($networkConfig.PublicAccess)" -ForegroundColor Blue
    Write-Host "🛡️ Default Action: $($networkConfig.DefaultAction)" -ForegroundColor Blue
    
    if ($ipData) {
        $ipCount = if ($ipData -is [array]) { $ipData.Count } else { ($ipData -split "`n" | Where-Object { $_.Trim() -ne "" }).Count }
        Write-Host "🎯 Total Allowed IPs: $ipCount" -ForegroundColor Blue
    }
    else {
        Write-Host "🎯 Total Allowed IPs: 0" -ForegroundColor Blue
    }
    
    if ($savedFilePath) {
        Write-Host "💾 IPs saved to: $savedFilePath" -ForegroundColor Blue
    }
    
    Write-Host ""
    Write-Host "✅ Query completed successfully!" -ForegroundColor Green
}

# Function to show usage help
function Show-Usage {
    Write-Host "Usage Examples:" -ForegroundColor Yellow
    Write-Host "  .\get-storage-allowed-ips.ps1 -StorageAccountName 'mystorageaccount' -ResourceGroupName 'myresourcegroup'" -ForegroundColor White
    Write-Host "  .\get-storage-allowed-ips.ps1 -StorageAccountName 'mystorageaccount' -ResourceGroupName 'myresourcegroup' -OutputFormat json" -ForegroundColor White
    Write-Host "  .\get-storage-allowed-ips.ps1 -StorageAccountName 'mystorageaccount' -ResourceGroupName 'myresourcegroup' -SubscriptionId 'sub-id' -OutputFormat tsv" -ForegroundColor White
    Write-Host ""
    Write-Host "Parameters:" -ForegroundColor Yellow
    Write-Host "  -StorageAccountName  : Name of the storage account (required)" -ForegroundColor White
    Write-Host "  -ResourceGroupName   : Name of the resource group (required)" -ForegroundColor White
    Write-Host "  -SubscriptionId      : Azure subscription ID (optional)" -ForegroundColor White
    Write-Host "  -OutputFormat        : Output format - table, json, or tsv (default: table)" -ForegroundColor White
    Write-Host "  -SaveToFile          : Save allowed IPs to text file (default: true)" -ForegroundColor White
    Write-Host "  -OutputFilePath      : Custom file path for saved IPs (optional)" -ForegroundColor White
}

# Main execution
function Main {
    # Validate parameters
    if (-not $StorageAccountName -or -not $ResourceGroupName) {
        Write-Host "❌ ERROR: Missing required parameters" -ForegroundColor Red
        Show-Usage
        exit 1
    }
    
    # Set default output file path if not provided
    $savedFilePath = $null
    if ($SaveToFile) {
        if (-not $OutputFilePath) {
            $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
            $OutputFilePath = "allowed-ips-$StorageAccountName-$timestamp.txt"
        }
        $savedFilePath = $OutputFilePath
    }
    
    Test-Prerequisites
    Set-AzureSubscription
    Test-StorageAccount
    
    $networkConfig = Get-NetworkConfiguration
    
    # Get raw IP data for file saving (separate from display)
    $ipData = Get-RawIPAddresses
    
    # Display IPs based on format preference
    Show-AllowedIPs
    
    # Check virtual network rules
    Get-VirtualNetworkRules
    
    # Save to file if requested
    if ($SaveToFile -and $ipData) {
        Save-AllowedIPsToFile -ipData $ipData -filePath $savedFilePath
    }
    
    Show-Summary -networkConfig $networkConfig -ipData $ipData -savedFilePath $savedFilePath
}

# Run the script
Main
