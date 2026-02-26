Param (
    [Parameter(Mandatory = $true)]
    [string]
    $AzureUserName,

    [string]
    $AzurePassword,

    [string]
    $AzureTenantID,

    [string]
    $AzureSubscriptionID,

    [string]
    $ODLID,

    [string]
    $DeploymentID,

    [string]
    $InstallCloudLabsShadow,

    [string]
    $vmAdminUsername,

    [string]
    $trainerUserName,

    [string]
    $trainerUserPassword,

    [string]
    $resetUserPassword,

    [string]
    $ComputerName

)

Start-Transcript -Path C:\WindowsAzure\Logs\CLCustomScriptExtension.txt -Append
[Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls
[Net.ServicePointManager]::SecurityProtocol = "tls12, tls11, tls" 

# Create temp directory if it doesn't exist
if (!(Test-Path C:\temp)) { New-Item -ItemType Directory -Path C:\temp }

# Export current security policy
secedit /export /cfg C:\temp\secpol.cfg

# Disable the password complexity setting
(Get-Content C:\temp\secpol.cfg) -replace 'PasswordComplexity = 1', 'PasswordComplexity = 0' | Set-Content C:\temp\secpol.cfg

# Apply the modified policy
secedit /configure /db C:\temp\secedit.sdb /cfg C:\temp\secpol.cfg

# Force immediate policy update
gpupdate /force

# Convert plain-text password to SecureString
$resetSecurePassword = ConvertTo-SecureString $resetUserPassword -AsPlainText -Force

# Apply the password to the local user
Set-LocalUser -Name $vmAdminUsername -Password $resetSecurePassword

# Export current security policy (this will show PasswordComplexity = 0)
secedit /export /cfg C:\temp\secpol.cfg

# Change PasswordComplexity from 0 to 1 (enable complexity)
(Get-Content C:\temp\secpol.cfg) -replace 'PasswordComplexity = 0', 'PasswordComplexity = 1' | Set-Content C:\temp\secpol.cfg

# Apply the modified policy
secedit /configure /db C:\temp\secedit.sdb /cfg C:\temp\secpol.cfg

# Force immediate policy update
gpupdate /force

# Clean up temporary files
Remove-Item C:\temp\secpol.cfg, C:\temp\secedit.sdb, C:\temp\secedit.jfm -ErrorAction SilentlyContinue

# Remove the temp directory if it exists
Remove-Item C:\temp -Recurse -Force -ErrorAction SilentlyContinue

# Import Common Functions
$path = pwd
$path = $path.Path
$commonscriptpath = "$path" + "\cloudlabs-common\cloudlabs-windows-functions.ps1"
. $commonscriptpath

# Run Imported functions from cloudlabs-windows-functions.ps1
Disable-InternetExplorerESC
Enable-IEFileDownload
Enable-CopyPageContent-In-InternetExplorer
InstallChocolatey
DisableServerMgrNetworkPopup
CreateLabFilesDirectory
DisableWindowsFirewall

InstallCloudLabsShadow $ODLID $InstallCloudLabsShadow

Remove-Item -Path "C:\Users\Public\Desktop\Azure Portal.lnk" -ErrorAction SilentlyContinue

Function Enable-CloudLabsEmbeddedShadow($vmAdminUsername, $trainerUserName, $trainerUserPassword)
{
    Write-Host "Enabling CloudLabsEmbeddedShadow"
    $trainerUserPass = $trainerUserPassword | ConvertTo-SecureString -AsPlainText -Force

    New-LocalUser -Name $trainerUserName -Password $trainerUserPass -FullName "$trainerUserName" -Description "CloudLabs EmbeddedShadow User" -PasswordNeverExpires
    Add-LocalGroupMember -Group "Administrators" -Member "$trainerUserName"

    reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services" /v Shadow /t REG_DWORD /d 2 -f

    $drivepath = "C:\Users\Public\Documents"
    $WebClient = New-Object System.Net.WebClient
    $WebClient.DownloadFile("https://experienceazure.blob.core.windows.net/templates/paessler/win2025/updated/shadow.ps1","$drivepath\Shadow.ps1")
    $WebClient.DownloadFile("https://experienceazure.blob.core.windows.net/templates/cloudlabs-common/shadow.xml","$drivepath\shadow.xml")
    $WebClient.DownloadFile("https://experienceazure.blob.core.windows.net/templates/cloudlabs-common/ShadowSession.zip","C:\Packages\ShadowSession.zip")
    $WebClient.DownloadFile("https://experienceazure.blob.core.windows.net/templates/cloudlabs-common/executetaskscheduler.ps1","$drivepath\executetaskscheduler.ps1")
    $WebClient.DownloadFile("https://experienceazure.blob.core.windows.net/templates/cloudlabs-common/shadowshortcut.ps1","$drivepath\shadowshortcut.ps1")

    (Get-Content -Path "$drivepath\Shadow.ps1") | ForEach-Object {$_ -Replace "vmAdminUsernameValue", "$vmAdminUsername"} | Set-Content -Path "$drivepath\Shadow.ps1"
    (Get-Content -Path "$drivepath\shadow.xml") | ForEach-Object {$_ -Replace "vmAdminUsernameValue", "$trainerUserName"} | Set-Content -Path "$drivepath\shadow.xml"
    (Get-Content -Path "$drivepath\shadow.xml") | ForEach-Object {$_ -Replace "ComputerNameValue", "$($env:ComputerName)"} | Set-Content -Path "$drivepath\shadow.xml"
    (Get-Content -Path "$drivepath\shadowshortcut.ps1") | ForEach-Object {$_ -Replace "vmAdminUsernameValue", "$trainerUserName"} | Set-Content -Path "$drivepath\shadowshortcut.ps1"
    sleep 2

    schtasks.exe /Create /XML $drivepath\shadow.xml /tn Shadowtask

    $Trigger = New-ScheduledTaskTrigger -AtLogOn
    $User = "$($env:ComputerName)\$trainerUserName"
    $Action = New-ScheduledTaskAction -Execute "C:\Windows\System32\WindowsPowerShell\v1.0\Powershell.exe" -Argument "-executionPolicy Unrestricted -File $drivepath\shadowshortcut.ps1 -WindowStyle Hidden"
    Register-ScheduledTask -TaskName "shadowshortcut" -Trigger $Trigger -User $User -Action $Action -RunLevel Highest -Force
}

# Disable the privacy consent screen during OOBE
New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OOBE" -Force | Out-Null
New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OOBE" -Name "DisablePrivacyExperience" -PropertyType DWord -Value 1 -Force

# Set minimum diagnostic data level
New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Force | Out-Null
New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "AllowTelemetry" -PropertyType DWord -Value 0 -Force

# Set timezone
Set-TimeZone -Name "W. Europe Standard Time"

# Keyboard layout scheduled task
$psCommand = 'PowerShell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -Command "Set-WinUserLanguageList -LanguageList en-US, de-DE, fr-FR -Force"'
$action = New-ScheduledTaskAction -Execute "cmd.exe" -Argument "/c start /min $psCommand"
$trigger = New-ScheduledTaskTrigger -AtLogOn
$principal = New-ScheduledTaskPrincipal -UserId "$env:COMPUTERNAME\$vmAdminUsername" -LogonType Interactive -RunLevel Highest
Register-ScheduledTask -TaskName "SetKeyboardLanguages" -Action $action -Trigger $trigger -Principal $principal -Force

# =============================================================================
# PAESSLER CUSTOMIZATION
# =============================================================================

# 1. Rename Computer
if ($ComputerName) {
    Rename-Computer -NewName $ComputerName -Force -ErrorAction SilentlyContinue
    Write-Host "Computer renamed to $ComputerName"
}

# 2. Create 'training' user using resetUserPassword passed from ARM and add to Administrators
$trainingPassword = ConvertTo-SecureString $resetUserPassword -AsPlainText -Force
if (-not (Get-LocalUser -Name "training" -ErrorAction SilentlyContinue)) {
    New-LocalUser -Name "training" -Password $trainingPassword -FullName "Training" -PasswordNeverExpires -ErrorAction SilentlyContinue
    Write-Host "User 'training' created"
} else {
    Set-LocalUser -Name "training" -Password $trainingPassword
    Write-Host "User 'training' already exists - password updated"
}
Add-LocalGroupMember -Group "Administrators" -Member "training" -ErrorAction SilentlyContinue

# 3. Delete 'labuser' only after training user is confirmed active
$trainingExists = Get-LocalUser -Name "training" -ErrorAction SilentlyContinue
$trainingInAdmins = Get-LocalGroupMember -Group "Administrators" -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*training*" }
if ($trainingExists -and $trainingInAdmins) {
    if (Get-LocalUser -Name "labuser" -ErrorAction SilentlyContinue) {
        # Kill any active sessions for labuser before deleting
        $labuserSessions = query session 2>$null | Select-String "labuser"
        if ($labuserSessions) {
            $sessionId = ($labuserSessions -split '\s+')[2]
            logoff $sessionId /server:localhost 2>$null
            Start-Sleep -Seconds 2
        }
        Remove-LocalUser -Name "labuser" -ErrorAction SilentlyContinue
        Write-Host "User 'labuser' deleted"
    }
} else {
    Write-Host "WARNING: training user not confirmed - skipping labuser deletion"
}

Restart-Computer -Force
