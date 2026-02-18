param (
    [string]$AzureUserName,
    [string]$AzurePassword,
    [string]$AzureTenantID,
    [string]$AzureSubscriptionID,
    [string]$ODLID,
    [string]$InstallCloudLabsShadow,
    [string]$vmAdminUsername,
    [string]$trainerUserName,
    [string]$trainerUserPassword,
    [string]$AWSAccessKey,
    [string]$AWSSecretKey,
    [string]$AWSRegion,
    [string]$AWSAccountId,
    [string]$VMAdminUsername,
    [string]$VMAdminPassword,
    [string]$VMDNSName
)

Start-Transcript -Path C:\WindowsAzure\Logs\CloudLabsCustomScriptExtension.txt -Append
[Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls
[Net.ServicePointManager]::SecurityProtocol = "tls12, tls11, tls" 

#Import Common Functions
$path = pwd
$path=$path.Path
$commonscriptpath = "$path" + "\cloudlabs-common\cloudlabs-windows-functions.ps1"
. $commonscriptpath

# Run Imported functions from cloudlabs-windows-functions.ps1
WindowsServerCommon
InstallCloudLabsShadow $ODLID $InstallCloudLabsShadow
CreateCredFile $AzureUserName $AzurePassword $AzureTenantID $AzureSubscriptionID $ODLID

Enable-CloudLabsEmbeddedShadow $vmAdminUsername $trainerUserName $trainerUserPassword

# ========== CREATE COMBINED CREDENTIAL FILE ==========
Write-Host "Creating combined CloudLabs credentials file..." -ForegroundColor Green

# Create directories
New-Item -ItemType directory -Path C:\LabFiles -Force | Out-Null
New-Item -ItemType directory -Path C:\ProgramData\CloudLabs -Force | Out-Null

# Download the template credential file from GitHub
$WebClient = New-Object System.Net.WebClient
$credsTemplateUrl = "https://raw.githubusercontent.com/YOUR_USERNAME/YOUR_REPO/main/CloudLabs-Creds.txt"
$credsFile = "C:\ProgramData\CloudLabs\CloudLabs-Creds.txt"

try {
    $WebClient.DownloadFile($credsTemplateUrl, $credsFile)
    Write-Host "Downloaded credential template" -ForegroundColor Green
} catch {
    Write-Host "Failed to download template, creating from scratch..." -ForegroundColor Yellow
    # Create basic template if download fails
    @"
================================================================
                CLOUDLABS CREDENTIALS
================================================================
Generated on: __DATE__
Deployment ID: __DEPLOYMENT_ID__

----------------------------------------------------------------
                   AZURE CREDENTIALS
----------------------------------------------------------------
🔹 Azure Username (UPN)      : __AZURE_USERNAME__
🔹 Azure Password            : __AZURE_PASSWORD__
🔹 Azure Tenant ID           : __AZURE_TENANT_ID__
🔹 Azure Subscription ID     : __AZURE_SUBSCRIPTION_ID__
🔹 Azure Tenant Domain       : __AZURE_TENANT_DOMAIN__

----------------------------------------------------------------
                    AWS CREDENTIALS
----------------------------------------------------------------
🔹 AWS Account ID            : __AWS_ACCOUNT_ID__
🔹 AWS Region                : __AWS_REGION__
🔹 AWS Access Key ID         : __AWS_ACCESS_KEY__
🔹 AWS Secret Access Key     : __AWS_SECRET_KEY__

----------------------------------------------------------------
              CONNECTION INFORMATION
----------------------------------------------------------------
🔹 VM Admin Username         : __VM_ADMIN_USERNAME__
🔹 VM Admin Password         : __VM_ADMIN_PASSWORD__
🔹 VM DNS Name               : __VM_DNS_NAME__

================================================================
        Save this file securely - Contains sensitive credentials
================================================================
"@ | Out-File -FilePath $credsFile -Encoding UTF8 -Force
}

# Get current date
$currentDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

# Replace placeholders with actual values
(Get-Content -Path $credsFile) | ForEach-Object {
    $_ -replace "__DATE__", "$currentDate" `
       -replace "__DEPLOYMENT_ID__", "$ODLID" `
       -replace "__AZURE_USERNAME__", "$AzureUserName" `
       -replace "__AZURE_PASSWORD__", "$AzurePassword" `
       -replace "__AZURE_TENANT_ID__", "$AzureTenantID" `
       -replace "__AZURE_SUBSCRIPTION_ID__", "$AzureSubscriptionID" `
       -replace "__AZURE_TENANT_DOMAIN__", "onmicrosoft.com" `
       -replace "__AWS_ACCOUNT_ID__", "$AWSAccountId" `
       -replace "__AWS_REGION__", "$AWSRegion" `
       -replace "__AWS_ACCESS_KEY__", "$AWSAccessKey" `
       -replace "__AWS_SECRET_KEY__", "$AWSSecretKey" `
       -replace "__VM_ADMIN_USERNAME__", "$VMAdminUsername" `
       -replace "__VM_ADMIN_PASSWORD__", "$VMAdminPassword" `
       -replace "__VM_DNS_NAME__", "$VMDNSName"
} | Set-Content -Path $credsFile

Write-Host "✅ Credential file created at: $credsFile" -ForegroundColor Green

# Copy to LabFiles and Desktop for easy access
Copy-Item $credsFile -Destination "C:\LabFiles\CloudLabs-Creds.txt" -Force
Copy-Item $credsFile -Destination "C:\Users\Public\Desktop\CloudLabs-Creds.txt" -Force

# ========== DOWNLOAD AND CREATE LOGIN SCRIPT ==========
$loginScriptUrl = "https://raw.githubusercontent.com/YOUR_USERNAME/YOUR_REPO/main/CloudLabs-Login.ps1"
$loginScriptPath = "C:\ProgramData\CloudLabs\CloudLabs-Login.ps1"

try {
    $WebClient.DownloadFile($loginScriptUrl, $loginScriptPath)
    Write-Host "✅ Login script downloaded" -ForegroundColor Green
} catch {
    Write-Host "Failed to download login script" -ForegroundColor Red
}

# Copy login script to accessible locations
Copy-Item $loginScriptPath -Destination "C:\LabFiles\CloudLabs-Login.ps1" -Force

# ========== CREATE DESKTOP SHORTCUTS ==========
$WshShell = New-Object -ComObject WScript.Shell
$PublicDesktop = "C:\Users\Public\Desktop"

# Main login shortcut
$shortcut = $WshShell.CreateShortcut("$PublicDesktop\CloudLabs Login.lnk")
$shortcut.TargetPath = "powershell.exe"
$shortcut.Arguments = "-ExecutionPolicy Bypass -NoExit -File C:\ProgramData\CloudLabs\CloudLabs-Login.ps1"
$shortcut.Description = "Login to Azure and AWS"
$shortcut.WorkingDirectory = "C:\ProgramData\CloudLabs"
$shortcut.Save()

# View credentials shortcut
$credsShortcut = $WshShell.CreateShortcut("$PublicDesktop\View Credentials.lnk")
$credsShortcut.TargetPath = "notepad.exe"
$credsShortcut.Arguments = "C:\ProgramData\CloudLabs\CloudLabs-Creds.txt"
$credsShortcut.Description = "View CloudLabs Credentials"
$credsShortcut.Save()

Write-Host "✅ Desktop shortcuts created" -ForegroundColor Green

# ========== CREATE README ==========
$readme = @"
========================================
      CLOUDLABS ENVIRONMENT README
========================================

Deployment ID: $ODLID

📁 CREDENTIALS FILE:
   • Location: C:\ProgramData\CloudLabs\CloudLabs-Creds.txt
   • Desktop shortcut: "View Credentials"

🚀 TO LOGIN:
   Double-click "CloudLabs Login" on desktop
   This will automatically:
   • Log you into Azure
   • Configure AWS CLI with your credentials

📋 CREDENTIALS INCLUDED:
   • Azure Username/Password
   • Azure Tenant/Subscription IDs
   • AWS Access Key/Secret
   • AWS Account ID/Region
   • VM Admin credentials

🔒 SECURITY NOTE:
   Credentials file is only accessible by Administrators
   You can delete it after successful login

========================================
"@

$readme | Out-File -FilePath "C:\Users\Public\Desktop\README.txt" -Encoding UTF8 -Force

Write-Host "=========================================" -ForegroundColor Green
Write-Host "SETUP COMPLETE!" -ForegroundColor Green
Write-Host "=========================================" -ForegroundColor Green
Write-Host "Double-click 'CloudLabs Login' on desktop" -ForegroundColor Yellow
