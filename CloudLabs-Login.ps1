<#
.SYNOPSIS
    CloudLabs Unified Login Script - Logs into both Azure and AWS
.DESCRIPTION
    This script reads the CloudLabs-Creds.txt file and automatically
    configures Azure PowerShell and AWS CLI with the provided credentials
#>

param(
    [string]$CredsFilePath = "C:\ProgramData\CloudLabs\CloudLabs-Creds.txt"
)

Clear-Host
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "            CLOUDLABS - AZURE & AWS LOGIN" -ForegroundColor Cyan
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host ""

# Check if credentials file exists
if (-not (Test-Path $CredsFilePath)) {
    Write-Host "❌ Credentials file not found at: $CredsFilePath" -ForegroundColor Red
    
    # Try alternative locations
    $altPaths = @(
        "C:\LabFiles\CloudLabs-Creds.txt",
        "C:\Users\Public\Desktop\CloudLabs-Creds.txt",
        "C:\CloudLabs-Creds.txt"
    )
    
    foreach ($path in $altPaths) {
        if (Test-Path $path) {
            $CredsFilePath = $path
            Write-Host "✅ Found credentials at: $path" -ForegroundColor Green
            break
        }
    }
    
    if (-not (Test-Path $CredsFilePath)) {
        Write-Host "❌ Could not find credentials file. Exiting." -ForegroundColor Red
        Read-Host "Press Enter to exit"
        exit
    }
}

Write-Host "📁 Reading credentials from: $CredsFilePath" -ForegroundColor Gray
Write-Host ""

# Read the credentials file
$credsContent = Get-Content $CredsFilePath
$creds = @{}

# Extract values using the __VARIABLE__ pattern
$patterns = @{
    "AzureUserName" = 'Azure Username \(UPN\)\s+:\s+(.+)'
    "AzurePassword" = 'Azure Password\s+:\s+(.+)'
    "AzureTenantID" = 'Azure Tenant ID\s+:\s+(.+)'
    "AzureSubscriptionID" = 'Azure Subscription ID\s+:\s+(.+)'
    "AzureTenantDomain" = 'Azure Tenant Domain\s+:\s+(.+)'
    "AWSAccountId" = 'AWS Account ID\s+:\s+(.+)'
    "AWSRegion" = 'AWS Region\s+:\s+(.+)'
    "AWSAccessKey" = 'AWS Access Key ID\s+:\s+(.+)'
    "AWSSecretKey" = 'AWS Secret Access Key\s+:\s+(.+)'
    "DeploymentID" = 'Deployment ID\s+:\s+(.+)'
    "VMAdminUsername" = 'VM Admin Username\s+:\s+(.+)'
    "VMAdminPassword" = 'VM Admin Password\s+:\s+(.+)'
    "VMDNSName" = 'VM DNS Name\s+:\s+(.+)'
}

foreach ($key in $patterns.Keys) {
    $pattern = $patterns[$key]
    foreach ($line in $credsContent) {
        if ($line -match $pattern) {
            $creds[$key] = $matches[1].Trim()
            break
        }
    }
}

# Display what we found
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "                     CREDENTIALS LOADED" -ForegroundColor Cyan
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "📋 DEPLOYMENT INFO:" -ForegroundColor Yellow
Write-Host "   • Deployment ID: $($creds['DeploymentID'])" -ForegroundColor White
Write-Host ""

Write-Host "☁️  AZURE CONFIGURATION:" -ForegroundColor Blue
Write-Host "   • Username: $($creds['AzureUserName'])" -ForegroundColor White
Write-Host "   • Tenant ID: $($creds['AzureTenantID'])" -ForegroundColor White
Write-Host "   • Subscription: $($creds['AzureSubscriptionID'])" -ForegroundColor White
Write-Host ""

Write-Host "🌩️  AWS CONFIGURATION:" -ForegroundColor Magenta
Write-Host "   • Account ID: $($creds['AWSAccountId'])" -ForegroundColor White
Write-Host "   • Region: $($creds['AWSRegion'])" -ForegroundColor White
Write-Host "   • Access Key ID: $($creds['AWSAccessKey'].Substring(0,5))********" -ForegroundColor White
Write-Host ""

Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "                     LOGGING INTO AZURE" -ForegroundColor Cyan
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host ""

# Azure Login
try {
    Write-Host "⏳ Connecting to Azure..." -ForegroundColor Yellow
    
    # Create credential object
    $securePassword = ConvertTo-SecureString $creds['AzurePassword'] -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential ($creds['AzureUserName'], $securePassword)
    
    # Connect to Azure
    Connect-AzAccount -ServicePrincipal -Credential $credential -Tenant $creds['AzureTenantID'] -ErrorAction Stop | Out-Null
    
    # Set subscription context
    Set-AzContext -Subscription $creds['AzureSubscriptionID'] -ErrorAction Stop | Out-Null
    
    Write-Host "✅ Azure login successful!" -ForegroundColor Green
    
    # Get subscription info
    $subscription = Get-AzSubscription -SubscriptionId $creds['AzureSubscriptionID']
    Write-Host "   Subscription Name: $($subscription.Name)" -ForegroundColor Gray
    
} catch {
    Write-Host "❌ Azure login failed: $_" -ForegroundColor Red
}

Write-Host ""
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "                     CONFIGURING AWS CLI" -ForegroundColor Cyan
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host ""

# AWS Configuration
try {
    Write-Host "⏳ Configuring AWS CLI..." -ForegroundColor Yellow
    
    # Check if AWS CLI is installed
    $awsVersion = aws --version 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "⚠️  AWS CLI not found. Installing..." -ForegroundColor Yellow
        
        # Download AWS CLI installer
        $installerPath = "$env:TEMP\AWSCLIV2.msi"
        Invoke-WebRequest -Uri "https://awscli.amazonaws.com/AWSCLIV2.msi" -OutFile $installerPath
        
        # Install AWS CLI silently
        Start-Process msiexec.exe -Wait -ArgumentList "/i $installerPath /quiet /norestart"
        
        # Refresh environment variables
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
        
        Write-Host "✅ AWS CLI installed" -ForegroundColor Green
    } else {
        Write-Host "✅ AWS CLI detected: $awsVersion" -ForegroundColor Green
    }
    
    # Configure AWS CLI
    aws configure set aws_access_key_id $creds['AWSAccessKey']
    aws configure set aws_secret_access_key $creds['AWSSecretKey']
    aws configure set default.region $creds['AWSRegion']
    aws configure set default.output json
    
    Write-Host "✅ AWS CLI configured successfully!" -ForegroundColor Green
    
    # Verify credentials
    Write-Host ""
    Write-Host "⏳ Verifying AWS credentials..." -ForegroundColor Yellow
    $identity = aws sts get-caller-identity | ConvertFrom-Json
    
    Write-Host "✅ AWS authentication successful!" -ForegroundColor Green
    Write-Host "   Account: $($identity.Account)" -ForegroundColor Gray
    
} catch {
    Write-Host "❌ AWS configuration failed: $_" -ForegroundColor Red
}

Write-Host ""
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "                         READY TO GO!" -ForegroundColor Cyan
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "📌 QUICK COMMANDS:" -ForegroundColor Yellow
Write-Host ""
Write-Host "   AZURE: Get-AzResourceGroup" -ForegroundColor Blue
Write-Host "   AWS:   aws s3 ls" -ForegroundColor Magenta
Write-Host ""
Write-Host "=================================================================" -ForegroundColor Cyan
