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
$credsTemplateUrl = "https://raw.githubusercontent.com/harshithgowda16/cric-agasthya-scoring-app/refs/heads/main/CloudLabs-Creds.txt"
$credsFile = "C:\ProgramData\CloudLabs\CloudLabs-Creds.txt"

try {
    $WebClient.DownloadFile($credsTemplateUrl, $credsFile)
    Write-Host "✅ Downloaded credential template from GitHub" -ForegroundColor Green
} catch {
    Write-Host "⚠️ Failed to download template, creating from scratch..." -ForegroundColor Yellow
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
Write-Host "📝 Populating credentials file with values..." -ForegroundColor Yellow
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
Write-Host "✅ Credential file copied to LabFiles and Desktop" -ForegroundColor Green

# ========== DOWNLOAD AND CREATE LOGIN SCRIPT ==========
$loginScriptUrl = "https://raw.githubusercontent.com/harshithgowda16/cric-agasthya-scoring-app/refs/heads/main/CloudLabs-Login.ps1"
$loginScriptPath = "C:\ProgramData\CloudLabs\CloudLabs-Login.ps1"

try {
    $WebClient.DownloadFile($loginScriptUrl, $loginScriptPath)
    Write-Host "✅ Login script downloaded from GitHub" -ForegroundColor Green
} catch {
    Write-Host "❌ Failed to download login script" -ForegroundColor Red
}

# Copy login script to accessible locations
Copy-Item $loginScriptPath -Destination "C:\LabFiles\CloudLabs-Login.ps1" -Force
Copy-Item $loginScriptPath -Destination "C:\Users\Public\Desktop\CloudLabs-Login.ps1" -Force
Write-Host "✅ Login script copied to LabFiles and Desktop" -ForegroundColor Green

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
Write-Host "✅ Created 'CloudLabs Login' shortcut on Desktop" -ForegroundColor Green

# View credentials shortcut
$credsShortcut = $WshShell.CreateShortcut("$PublicDesktop\View Credentials.lnk")
$credsShortcut.TargetPath = "notepad.exe"
$credsShortcut.Arguments = "C:\ProgramData\CloudLabs\CloudLabs-Creds.txt"
$credsShortcut.Description = "View CloudLabs Credentials"
$credsShortcut.Save()
Write-Host "✅ Created 'View Credentials' shortcut on Desktop" -ForegroundColor Green

# PowerShell shortcut for quick access
$psShortcut = $WshShell.CreateShortcut("$PublicDesktop\PowerShell (Admin).lnk")
$psShortcut.TargetPath = "powershell.exe"
$psShortcut.Arguments = "-ExecutionPolicy Bypass"
$psShortcut.Description = "Open PowerShell"
$psShortcut.WorkingDirectory = "C:\ProgramData\CloudLabs"
$psShortcut.Save()
Write-Host "✅ Created 'PowerShell' shortcut on Desktop" -ForegroundColor Green

Write-Host "✅ All desktop shortcuts created" -ForegroundColor Green

# ========== CREATE README ==========
$readme = @"
========================================
      CLOUDLABS ENVIRONMENT README
========================================
Deployment ID: $ODLID
Generated on: $currentDate

📁 IMPORTANT FILES LOCATIONS:
   • Credentials: C:\ProgramData\CloudLabs\CloudLabs-Creds.txt
   • Login Script: C:\ProgramData\CloudLabs\CloudLabs-Login.ps1
   • Lab Files: C:\LabFiles\

📌 DESKTOP SHORTCUTS:
   1. "CloudLabs Login" - Automatically logs into Azure and AWS
   2. "View Credentials" - Opens the credentials file
   3. "PowerShell (Admin)" - Opens PowerShell for running commands

🚀 TO LOGIN:
   Double-click "CloudLabs Login" on desktop
   This will automatically:
   • Log you into Azure using Service Principal
   • Configure AWS CLI with your credentials
   • Verify both connections work

📋 CREDENTIALS INCLUDED:
   AZURE:
   • Username: $AzureUserName
   • Tenant ID: $AzureTenantID
   • Subscription ID: $AzureSubscriptionID
   
   AWS:
   • Account ID: $AWSAccountId
   • Region: $AWSRegion
   • Access Key: $($AWSAccessKey.Substring(0,5))********
   
   VM ACCESS:
   • Admin Username: $VMAdminUsername
   • DNS Name: $VMDNSName

🔒 SECURITY NOTE:
   • Credentials file is stored securely in C:\ProgramData
   • Only Administrators can access this file
   • You can delete the file after successful login:
     Remove-Item C:\ProgramData\CloudLabs\CloudLabs-Creds.txt -Force

🆘 TROUBLESHOOTING:
   • If login fails, check the file exists: Test-Path C:\ProgramData\CloudLabs\CloudLabs-Creds.txt
   • Run login script manually: & 'C:\ProgramData\CloudLabs\CloudLabs-Login.ps1'
   • Check transcript: C:\WindowsAzure\Logs\CloudLabsCustomScriptExtension.txt

========================================
        READY TO START YOUR LAB!
========================================
"@

$readme | Out-File -FilePath "C:\Users\Public\Desktop\README.txt" -Encoding UTF8 -Force
Write-Host "✅ README file created on Desktop" -ForegroundColor Green

# ========== VERIFY SETUP ==========
Write-Host ""
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "         SETUP VERIFICATION" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""

# Check if files exist
$filesToCheck = @{
    "Credentials File" = $credsFile
    "Login Script" = $loginScriptPath
    "README" = "C:\Users\Public\Desktop\README.txt"
}

foreach ($file in $filesToCheck.Keys) {
    if (Test-Path $filesToCheck[$file]) {
        Write-Host "✅ $file exists" -ForegroundColor Green
    } else {
        Write-Host "❌ $file missing" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "=========================================" -ForegroundColor Green
Write-Host "🎯 SETUP COMPLETE!" -ForegroundColor Green
Write-Host "=========================================" -ForegroundColor Green
Write-Host ""
Write-Host "👉 NEXT STEPS:" -ForegroundColor Yellow
Write-Host "   1. RDP into the VM" -ForegroundColor White
Write-Host "   2. Double-click 'CloudLabs Login' on Desktop" -ForegroundColor White
Write-Host "   3. Wait for automatic Azure and AWS configuration" -ForegroundColor White
Write-Host ""
Write-Host "=========================================" -ForegroundColor Cyan
