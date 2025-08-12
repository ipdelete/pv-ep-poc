# PowerShell script to update Azure Storage Account firewall rules from a text file
param(
    [Parameter(Mandatory=$true, HelpMessage="Path to text file containing IP addresses")]
    [string]$IPFilePath,
    
    [Parameter(Mandatory=$true, HelpMessage="Storage account name")]
    [string]$StorageAccountName,
    
    [Parameter(Mandatory=$true, HelpMessage="Resource group name")]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory=$false, HelpMessage="Azure subscription ID")]
    [string]$SubscriptionId,
    
    [Parameter(Mandatory=$false, HelpMessage="Replace existing rules (true) or add to existing rules (false)")]
    [bool]$ReplaceExisting = $false,
    
    [Parameter(Mandatory=$false, HelpMessage="Backup existing rules before updating")]
    [bool]$BackupExisting = $true
)

Write-Host "=================================================" -ForegroundColor Cyan
Write-Host "Azure Storage Account - Update Firewall Rules" -ForegroundColor Cyan
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

# Function to validate and read IP file
function Read-IPFile {
    Write-Host "📁 Reading IP addresses from file..." -ForegroundColor Yellow
    Write-Host "📝 File Path: $IPFilePath" -ForegroundColor Blue
    
    # Check if file exists
    if (-not (Test-Path $IPFilePath)) {
        Write-Host "❌ ERROR: File '$IPFilePath' not found" -ForegroundColor Red
        exit 1
    }
    
    try {
        # Read file content
        $fileContent = Get-Content $IPFilePath -ErrorAction Stop
        
        # Filter and validate IP addresses
        $validIPs = @()
        $invalidLines = @()
        $lineNumber = 0
        
        foreach ($line in $fileContent) {
            $lineNumber++
            $ip = $line.Trim()
            
            # Skip empty lines and comments
            if ($ip -eq "" -or $ip.StartsWith("#")) {
                continue
            }
            
            # Validate IP format
            if ($ip -match '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$') {
                # Validate IP ranges (0-255 for each octet)
                $octets = $ip -split '\.'
                $validOctets = $true
                foreach ($octet in $octets) {
                    if ([int]$octet -gt 255) {
                        $validOctets = $false
                        break
                    }
                }
                
                if ($validOctets) {
                    $validIPs += $ip
                }
                else {
                    $invalidLines += "Line $lineNumber`: $ip (invalid IP range)"
                }
            }
            else {
                $invalidLines += "Line $lineNumber`: $ip (invalid IP format)"
            }
        }
        
        # Remove duplicates and sort
        $uniqueIPs = $validIPs | Sort-Object -Unique
        
        Write-Host "✅ File read successfully" -ForegroundColor Green
        Write-Host "📊 Total lines processed: $lineNumber" -ForegroundColor Blue
        Write-Host "📊 Valid IP addresses found: $($validIPs.Count)" -ForegroundColor Blue
        Write-Host "📊 Unique IP addresses: $($uniqueIPs.Count)" -ForegroundColor Blue
        
        if ($invalidLines.Count -gt 0) {
            Write-Host "⚠️ Invalid lines found:" -ForegroundColor Yellow
            $invalidLines | ForEach-Object { Write-Host "   $_" -ForegroundColor Yellow }
        }
        
        if ($uniqueIPs.Count -eq 0) {
            Write-Host "❌ ERROR: No valid IP addresses found in file" -ForegroundColor Red
            exit 1
        }
        
        return $uniqueIPs
    }
    catch {
        Write-Host "❌ ERROR: Failed to read file: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

# Function to backup existing rules
function Backup-ExistingRules {
    Write-Host "💾 Backing up existing firewall rules..." -ForegroundColor Yellow
    
    try {
        $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $backupFile = "backup-$StorageAccountName-$timestamp.txt"
        
        # Get existing IP rules
        $existingIPs = az storage account network-rule list --account-name $StorageAccountName --resource-group $ResourceGroupName --query "ipRules[].ipAddressOrRange" --output tsv
        
        if ($existingIPs) {
            $cleanExistingIPs = $existingIPs -split "`n" | Where-Object { 
                $ip = $_.Trim()
                $ip -ne "" -and $ip -match '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$'
            } | Sort-Object -Unique
            
            $cleanExistingIPs | Out-File -FilePath $backupFile -Encoding UTF8
            Write-Host "✅ Backup saved to: $backupFile" -ForegroundColor Green
            Write-Host "📊 Backed up $($cleanExistingIPs.Count) IP addresses" -ForegroundColor Blue
            return $backupFile
        }
        else {
            Write-Host "ℹ️ No existing IP rules to backup" -ForegroundColor Blue
            return $null
        }
    }
    catch {
        Write-Host "⚠️ WARNING: Failed to backup existing rules: $($_.Exception.Message)" -ForegroundColor Yellow
        return $null
    }
}

# Function to get current rules
function Get-CurrentRules {
    Write-Host "🔍 Checking current firewall rules..." -ForegroundColor Yellow
    
    $existingIPs = az storage account network-rule list --account-name $StorageAccountName --resource-group $ResourceGroupName --query "ipRules[].ipAddressOrRange" --output tsv
    
    if ($existingIPs) {
        $cleanExistingIPs = $existingIPs -split "`n" | Where-Object { 
            $ip = $_.Trim()
            $ip -ne "" -and $ip -match '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$'
        } | Sort-Object -Unique
        
        Write-Host "📋 Current IP rules ($($cleanExistingIPs.Count)):" -ForegroundColor Blue
        $cleanExistingIPs | ForEach-Object { Write-Host "   $_" -ForegroundColor White }
        return $cleanExistingIPs
    }
    else {
        Write-Host "ℹ️ No existing IP rules found" -ForegroundColor Blue
        return @()
    }
}

# Function to remove all existing IP rules
function Remove-AllIPRules {
    param($existingIPs)
    
    if ($existingIPs.Count -gt 0) {
        Write-Host "🗑️ Removing existing IP rules..." -ForegroundColor Yellow
        
        foreach ($ip in $existingIPs) {
            Write-Host "   Removing: $ip" -ForegroundColor White
            az storage account network-rule remove --account-name $StorageAccountName --resource-group $ResourceGroupName --ip-address $ip --output none
            
            if ($LASTEXITCODE -ne 0) {
                Write-Host "⚠️ WARNING: Failed to remove IP rule: $ip" -ForegroundColor Yellow
            }
        }
        Write-Host "✅ Existing rules removed" -ForegroundColor Green
    }
}

# Function to add IP rules
function Add-IPRules {
    param($ipAddresses)
    
    Write-Host "➕ Adding new IP rules..." -ForegroundColor Yellow
    
    $successCount = 0
    $failCount = 0
    
    foreach ($ip in $ipAddresses) {
        Write-Host "   Adding: $ip" -ForegroundColor White
        az storage account network-rule add --account-name $StorageAccountName --resource-group $ResourceGroupName --ip-address $ip --output none
        
        if ($LASTEXITCODE -eq 0) {
            $successCount++
        }
        else {
            Write-Host "   ❌ Failed to add: $ip" -ForegroundColor Red
            $failCount++
        }
    }
    
    Write-Host "✅ IP rules update completed" -ForegroundColor Green
    Write-Host "📊 Successfully added: $successCount" -ForegroundColor Blue
    if ($failCount -gt 0) {
        Write-Host "📊 Failed to add: $failCount" -ForegroundColor Red
    }
}

# Function to display summary
function Show-Summary {
    param($backupFile, $newIPs, $mode)
    
    Write-Host ""
    Write-Host "📋 Summary" -ForegroundColor Cyan
    Write-Host "==========" -ForegroundColor Cyan
    Write-Host "🏪 Storage Account: $StorageAccountName" -ForegroundColor Blue
    Write-Host "📁 Resource Group: $ResourceGroupName" -ForegroundColor Blue
    Write-Host "📝 IP File: $IPFilePath" -ForegroundColor Blue
    Write-Host "🔧 Update Mode: $mode" -ForegroundColor Blue
    Write-Host "📊 IPs Processed: $($newIPs.Count)" -ForegroundColor Blue
    
    if ($backupFile) {
        Write-Host "💾 Backup File: $backupFile" -ForegroundColor Blue
    }
    
    # Show current rules after update
    Write-Host ""
    Write-Host "🎯 Current firewall rules:" -ForegroundColor Yellow
    az storage account network-rule list --account-name $StorageAccountName --resource-group $ResourceGroupName --query "ipRules[].ipAddressOrRange" --output table
    
    Write-Host ""
    Write-Host "✅ Update completed successfully!" -ForegroundColor Green
}

# Function to show usage help
function Show-Usage {
    Write-Host "Usage Examples:" -ForegroundColor Yellow
    Write-Host "  .\update-storage-firewall.ps1 -IPFilePath 'ips.txt' -StorageAccountName 'mystorageaccount' -ResourceGroupName 'myresourcegroup'" -ForegroundColor White
    Write-Host "  .\update-storage-firewall.ps1 -IPFilePath 'ips.txt' -StorageAccountName 'mystorageaccount' -ResourceGroupName 'myresourcegroup' -ReplaceExisting `$true" -ForegroundColor White
    Write-Host "  .\update-storage-firewall.ps1 -IPFilePath 'ips.txt' -StorageAccountName 'mystorageaccount' -ResourceGroupName 'myresourcegroup' -SubscriptionId 'sub-id' -BackupExisting `$false" -ForegroundColor White
    Write-Host ""
    Write-Host "Parameters:" -ForegroundColor Yellow
    Write-Host "  -IPFilePath          : Path to text file containing IP addresses (required)" -ForegroundColor White
    Write-Host "  -StorageAccountName  : Name of the storage account (required)" -ForegroundColor White
    Write-Host "  -ResourceGroupName   : Name of the resource group (required)" -ForegroundColor White
    Write-Host "  -SubscriptionId      : Azure subscription ID (optional)" -ForegroundColor White
    Write-Host "  -ReplaceExisting     : Replace all existing rules (default: false - adds to existing)" -ForegroundColor White
    Write-Host "  -BackupExisting      : Backup existing rules before updating (default: true)" -ForegroundColor White
}

# Main execution
function Main {
    # Validate parameters
    if (-not $IPFilePath -or -not $StorageAccountName -or -not $ResourceGroupName) {
        Write-Host "❌ ERROR: Missing required parameters" -ForegroundColor Red
        Show-Usage
        exit 1
    }
    
    Test-Prerequisites
    Set-AzureSubscription
    Test-StorageAccount
    
    # Read and validate IP addresses from file
    $newIPs = Read-IPFile
    
    # Get current rules
    $existingIPs = Get-CurrentRules
    
    # Backup existing rules if requested
    $backupFile = $null
    if ($BackupExisting -and $existingIPs.Count -gt 0) {
        $backupFile = Backup-ExistingRules
    }
    
    # Determine update mode
    $updateMode = if ($ReplaceExisting) { "Replace all existing rules" } else { "Add to existing rules" }
    Write-Host "🔧 Update mode: $updateMode" -ForegroundColor Yellow
    
    # Remove existing rules if replacing
    if ($ReplaceExisting) {
        Remove-AllIPRules -existingIPs $existingIPs
    }
    
    # Add new IP rules
    Add-IPRules -ipAddresses $newIPs
    
    # Display summary
    Show-Summary -backupFile $backupFile -newIPs $newIPs -mode $updateMode
}

# Run the script
Main
