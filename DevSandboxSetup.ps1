# ==========================================================
# PRODUCTION DEVELOPER SANDBOX SETUP
# Designed for Azure Custom Script Extension
# ==========================================================

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$LogPath = "C:\DevSandbox-Install.log"
Start-Transcript -Path $LogPath -Append

Write-Host "Starting Developer Sandbox Installation..."

# ----------------------------------------------------------
# Install Chocolatey (if not installed)
# ----------------------------------------------------------
if (!(Get-Command choco -ErrorAction SilentlyContinue)) {
    Write-Host "Installing Chocolatey..."
    Set-ExecutionPolicy Bypass -Scope Process -Force
    [System.Net.ServicePointManager]::SecurityProtocol = 3072
    Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
}

choco feature enable -n allowGlobalConfirmation

# ----------------------------------------------------------
# Install Core Developer Packages
# ----------------------------------------------------------
$packages = @(
    "vscode",
    "intellijidea-community",
    "sublimetext3",
    "git",
    "github-desktop",
    "googlechrome",
    "firefox",
    "nodejs-lts",
    "python",
    "openjdk",
    "docker-desktop",
    "kubernetes-cli",
    "minikube",
    "postman",
    "mysql",
    "postgresql",
    "mongodb",
    "dbeaver",
    "slack",
    "notion",
    "obsidian",
    "keepassxc"
)

foreach ($pkg in $packages) {
    Write-Host "Installing $pkg ..."
    choco install $pkg --no-progress -y
}

# ----------------------------------------------------------
# Enable WSL2
# ----------------------------------------------------------
Write-Host "Enabling WSL2..."
Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -NoRestart
Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -NoRestart

wsl --set-default-version 2

if (!(wsl -l | Select-String "Ubuntu")) {
    wsl --install -d Ubuntu
}

Write-Host "Installation Completed Successfully."
Stop-Transcript

# Do NOT auto reboot (let CSE finish cleanly)
Write-Host "Developer Sandbox setup complete."
