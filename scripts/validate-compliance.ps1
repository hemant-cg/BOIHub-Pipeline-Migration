# PowerShell script to validate In Control compliance for BOIHub Azure resources
param(
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory=$true)]
    [string]$SubscriptionId
)

# Set error action preference
$ErrorActionPreference = "Stop"

Write-Host "Starting In Control compliance validation for Resource Group: $ResourceGroupName" -ForegroundColor Green

# Connect to Azure (assumes already authenticated in pipeline)
try {
    Set-AzContext -SubscriptionId $SubscriptionId
    Write-Host "✓ Connected to Azure subscription: $SubscriptionId" -ForegroundColor Green
}
catch {
    Write-Error "Failed to connect to Azure subscription: $($_.Exception.Message)"
    exit 1
}

# Initialize compliance results
$complianceResults = @{
    Passed = 0
    Failed = 0
    Issues = @()
}

function Test-TLSCompliance {
    param($ResourceGroupName)
    
    Write-Host "Checking TLS 1.2 compliance..." -ForegroundColor Yellow
    
    # Check Function Apps
    $functionApps = Get-AzWebApp -ResourceGroupName $ResourceGroupName
    foreach ($app in $functionApps) {
        if ($app.SiteConfig.MinTlsVersion -ne "1.2") {
            $complianceResults.Issues += "Function App '$($app.Name)' does not enforce TLS 1.2"
            $complianceResults.Failed++
        } else {
            Write-Host "✓ Function App '$($app.Name)' enforces TLS 1.2" -ForegroundColor Green
            $complianceResults.Passed++
        }
        
        if (-not $app.HttpsOnly) {
            $complianceResults.Issues += "Function App '$($app.Name)' does not enforce HTTPS only"
            $complianceResults.Failed++
        } else {
            Write-Host "✓ Function App '$($app.Name)' enforces HTTPS only" -ForegroundColor Green
            $complianceResults.Passed++
        }
    }
    
    # Check Storage Accounts
    $storageAccounts = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName
    foreach ($storage in $storageAccounts) {
        if ($storage.MinimumTlsVersion -ne "TLS1_2") {
            $complianceResults.Issues += "Storage Account '$($storage.StorageAccountName)' does not enforce TLS 1.2"
            $complianceResults.Failed++
        } else {
            Write-Host "✓ Storage Account '$($storage.StorageAccountName)' enforces TLS 1.2" -ForegroundColor Green
            $complianceResults.Passed++
        }
        
        if (-not $storage.EnableHttpsTrafficOnly) {
            $complianceResults.Issues += "Storage Account '$($storage.StorageAccountName)' does not enforce HTTPS only"
            $complianceResults.Failed++
        } else {
            Write-Host "✓ Storage Account '$($storage.StorageAccountName)' enforces HTTPS only" -ForegroundColor Green
            $complianceResults.Passed++
        }
    }
}

function Test-NetworkSecurity {
    param($ResourceGroupName)
    
    Write-Host "Checking network security compliance..." -ForegroundColor Yellow
    
    # Check Network Security Groups
    $nsgs = Get-AzNetworkSecurityGroup -ResourceGroupName $ResourceGroupName
    foreach ($nsg in $nsgs) {
        $hasDefaultDenyRule = $false
        foreach ($rule in $nsg.SecurityRules) {
            if ($rule.Name -eq "DenyAllInbound" -and $rule.Access -eq "Deny" -and $rule.Priority -eq 4096) {
                $hasDefaultDenyRule = $true
                break
            }
        }
        
        if (-not $hasDefaultDenyRule) {
            $complianceResults.Issues += "NSG '$($nsg.Name)' does not have a default deny rule"
            $complianceResults.Failed++
        } else {
            Write-Host "✓ NSG '$($nsg.Name)' has proper default deny rule" -ForegroundColor Green
            $complianceResults.Passed++
        }
    }
    
    # Check VNet configuration
    $vnets = Get-AzVirtualNetwork -ResourceGroupName $ResourceGroupName
    foreach ($vnet in $vnets) {
        Write-Host "✓ VNet '$($vnet.Name)' configured with address space: $($vnet.AddressSpace.AddressPrefixes -join ', ')" -ForegroundColor Green
        $complianceResults.Passed++
        
        # Check subnets have proper delegation for Function Apps
        foreach ($subnet in $vnet.Subnets) {
            if ($subnet.Name -like "*function-app*") {
                $hasWebDelegation = $subnet.Delegations | Where-Object { $_.ServiceName -eq "Microsoft.Web/serverFarms" }
                if (-not $hasWebDelegation) {
                    $complianceResults.Issues += "Function App subnet '$($subnet.Name)' does not have proper delegation"
                    $complianceResults.Failed++
                } else {
                    Write-Host "✓ Function App subnet '$($subnet.Name)' has proper delegation" -ForegroundColor Green
                    $complianceResults.Passed++
                }
            }
        }
    }
}

function Test-EncryptionCompliance {
    param($ResourceGroupName)
    
    Write-Host "Checking encryption compliance..." -ForegroundColor Yellow
    
    # Check Storage Account encryption
    $storageAccounts = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName
    foreach ($storage in $storageAccounts) {
        $encryptionServices = @("Blob", "File", "Table", "Queue")
        foreach ($service in $encryptionServices) {
            $serviceProperty = $storage.Encryption.Services.$service
            if (-not $serviceProperty.Enabled) {
                $complianceResults.Issues += "Storage Account '$($storage.StorageAccountName)' does not have $service encryption enabled"
                $complianceResults.Failed++
            } else {
                Write-Host "✓ Storage Account '$($storage.StorageAccountName)' has $service encryption enabled" -ForegroundColor Green
                $complianceResults.Passed++
            }
        }
        
        if (-not $storage.RequireInfrastructureEncryption) {
            $complianceResults.Issues += "Storage Account '$($storage.StorageAccountName)' does not require infrastructure encryption"
            $complianceResults.Failed++
        } else {
            Write-Host "✓ Storage Account '$($storage.StorageAccountName)' requires infrastructure encryption" -ForegroundColor Green
            $complianceResults.Passed++
        }
    }
    
    # Check Key Vault configuration
    $keyVaults = Get-AzKeyVault -ResourceGroupName $ResourceGroupName
    foreach ($kv in $keyVaults) {
        if (-not $kv.EnableSoftDelete) {
            $complianceResults.Issues += "Key Vault '$($kv.VaultName)' does not have soft delete enabled"
            $complianceResults.Failed++
        } else {
            Write-Host "✓ Key Vault '$($kv.VaultName)' has soft delete enabled" -ForegroundColor Green
            $complianceResults.Passed++
        }
        
        if (-not $kv.EnablePurgeProtection) {
            $complianceResults.Issues += "Key Vault '$($kv.VaultName)' does not have purge protection enabled"
            $complianceResults.Failed++
        } else {
            Write-Host "✓ Key Vault '$($kv.VaultName)' has purge protection enabled" -ForegroundColor Green
            $complianceResults.Passed++
        }
    }
}

function Test-MonitoringCompliance {
    param($ResourceGroupName)
    
    Write-Host "Checking monitoring and logging compliance..." -ForegroundColor Yellow
    
    # Check Application Insights
    $appInsights = Get-AzApplicationInsights -ResourceGroupName $ResourceGroupName
    foreach ($ai in $appInsights) {
        if ($ai.RetentionInDays -lt 90) {
            $complianceResults.Issues += "Application Insights '$($ai.Name)' retention period is less than 90 days"
            $complianceResults.Failed++
        } else {
            Write-Host "✓ Application Insights '$($ai.Name)' has adequate retention period ($($ai.RetentionInDays) days)" -ForegroundColor Green
            $complianceResults.Passed++
        }
    }
    
    # Check Log Analytics Workspaces
    $workspaces = Get-AzOperationalInsightsWorkspace -ResourceGroupName $ResourceGroupName
    foreach ($workspace in $workspaces) {
        if ($workspace.RetentionInDays -lt 90) {
            $complianceResults.Issues += "Log Analytics Workspace '$($workspace.Name)' retention period is less than 90 days"
            $complianceResults.Failed++
        } else {
            Write-Host "✓ Log Analytics Workspace '$($workspace.Name)' has adequate retention period ($($workspace.RetentionInDays) days)" -ForegroundColor Green
            $complianceResults.Passed++
        }
    }
}

function Test-AccessControlCompliance {
    param($ResourceGroupName)
    
    Write-Host "Checking access control compliance..." -ForegroundColor Yellow
    
    # Check Function Apps have managed identity
    $functionApps = Get-AzWebApp -ResourceGroupName $ResourceGroupName
    foreach ($app in $functionApps) {
        if ($app.Identity.Type -ne "SystemAssigned") {
            $complianceResults.Issues += "Function App '$($app.Name)' does not have system-assigned managed identity"
            $complianceResults.Failed++
        } else {
            Write-Host "✓ Function App '$($app.Name)' has system-assigned managed identity" -ForegroundColor Green
            $complianceResults.Passed++
        }
    }
    
    # Check Storage Account public access
    $storageAccounts = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName
    foreach ($storage in $storageAccounts) {
        if ($storage.AllowBlobPublicAccess) {
            $complianceResults.Issues += "Storage Account '$($storage.StorageAccountName)' allows public blob access"
            $complianceResults.Failed++
        } else {
            Write-Host "✓ Storage Account '$($storage.StorageAccountName)' disables public blob access" -ForegroundColor Green
            $complianceResults.Passed++
        }
    }
}

# Run all compliance tests
try {
    Test-TLSCompliance -ResourceGroupName $ResourceGroupName
    Test-NetworkSecurity -ResourceGroupName $ResourceGroupName
    Test-EncryptionCompliance -ResourceGroupName $ResourceGroupName
    Test-MonitoringCompliance -ResourceGroupName $ResourceGroupName
    Test-AccessControlCompliance -ResourceGroupName $ResourceGroupName
    
    # Generate compliance report
    Write-Host "`n" -NoNewline
    Write-Host "=== COMPLIANCE VALIDATION SUMMARY ===" -ForegroundColor Cyan
    Write-Host "Passed Checks: $($complianceResults.Passed)" -ForegroundColor Green
    Write-Host "Failed Checks: $($complianceResults.Failed)" -ForegroundColor Red
    
    if ($complianceResults.Issues.Count -gt 0) {
        Write-Host "`nCompliance Issues Found:" -ForegroundColor Red
        foreach ($issue in $complianceResults.Issues) {
            Write-Host "  ❌ $issue" -ForegroundColor Red
        }
    }
    
    # Set pipeline variables for reporting
    Write-Host "##vso[task.setvariable variable=CompliancePassed]$($complianceResults.Passed)"
    Write-Host "##vso[task.setvariable variable=ComplianceFailed]$($complianceResults.Failed)"
    
    if ($complianceResults.Failed -gt 0) {
        Write-Host "`nCompliance validation FAILED. Please address the issues above." -ForegroundColor Red
        exit 1
    } else {
        Write-Host "`n✅ All compliance checks PASSED!" -ForegroundColor Green
        exit 0
    }
}
catch {
    Write-Error "Compliance validation failed with error: $($_.Exception.Message)"
    exit 1
}
