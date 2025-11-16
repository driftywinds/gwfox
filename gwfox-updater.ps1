# Firefox GWFox Chrome Folder Updater
# This script downloads the latest gwfox release and updates your Firefox profile

# Configuration
$RepoOwner = "akkva"
$RepoName = "gwfox"
$FirefoxProfilesBase = "$env:APPDATA\Mozilla\Firefox\Profiles"
$TempDir = "$env:TEMP\gwfox_update"

# Colors for output
function Write-ColorOutput($ForegroundColor) {
    $fc = $host.UI.RawUI.ForegroundColor
    $host.UI.RawUI.ForegroundColor = $ForegroundColor
    if ($args) {
        Write-Output $args
    }
    $host.UI.RawUI.ForegroundColor = $fc
}

Write-Host "==================================" -ForegroundColor Cyan
Write-Host "Firefox GWFox Chrome Updater" -ForegroundColor Cyan
Write-Host "==================================" -ForegroundColor Cyan
Write-Host ""

# Detect Firefox profile
Write-Host "Detecting Firefox profile..." -ForegroundColor Green
if (-not (Test-Path $FirefoxProfilesBase)) {
    Write-Host "ERROR: Firefox profiles directory not found!" -ForegroundColor Red
    Write-Host "Expected location: $FirefoxProfilesBase" -ForegroundColor Yellow
    Write-Host "Please make sure Firefox is installed." -ForegroundColor Yellow
    Read-Host "Press Enter to exit"
    exit 1
}

# Find all profiles with a chrome folder
$profilesWithChrome = Get-ChildItem -Path $FirefoxProfilesBase -Directory | Where-Object {
    Test-Path (Join-Path $_.FullName "chrome")
}

if ($profilesWithChrome.Count -eq 0) {
    Write-Host "No Firefox profiles with a 'chrome' folder found." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Available profiles:" -ForegroundColor Cyan
    Get-ChildItem -Path $FirefoxProfilesBase -Directory | ForEach-Object {
        Write-Host "  - $($_.Name)" -ForegroundColor Gray
    }
    Write-Host ""
    $manualProfile = Read-Host "Enter the profile folder name to use (or press Enter to cancel)"
    if ([string]::IsNullOrWhiteSpace($manualProfile)) {
        Write-Host "Operation cancelled." -ForegroundColor Red
        exit 1
    }
    $FirefoxProfilePath = Join-Path $FirefoxProfilesBase $manualProfile
    if (-not (Test-Path $FirefoxProfilePath)) {
        Write-Host "ERROR: Profile not found: $FirefoxProfilePath" -ForegroundColor Red
        Read-Host "Press Enter to exit"
        exit 1
    }
} elseif ($profilesWithChrome.Count -eq 1) {
    # Only one profile with chrome folder found, use it automatically
    $FirefoxProfilePath = $profilesWithChrome[0].FullName
    Write-Host "Using profile: $($profilesWithChrome[0].Name)" -ForegroundColor Cyan
} else {
    # Multiple profiles found, let user choose
    Write-Host "Multiple Firefox profiles with 'chrome' folder found:" -ForegroundColor Yellow
    Write-Host ""
    for ($i = 0; $i -lt $profilesWithChrome.Count; $i++) {
        Write-Host "  [$($i + 1)] $($profilesWithChrome[$i].Name)" -ForegroundColor Cyan
    }
    Write-Host ""
    $selection = Read-Host "Select profile number (1-$($profilesWithChrome.Count))"
    $selectedIndex = [int]$selection - 1
    if ($selectedIndex -lt 0 -or $selectedIndex -ge $profilesWithChrome.Count) {
        Write-Host "Invalid selection!" -ForegroundColor Red
        Read-Host "Press Enter to exit"
        exit 1
    }
    $FirefoxProfilePath = $profilesWithChrome[$selectedIndex].FullName
    Write-Host "Using profile: $($profilesWithChrome[$selectedIndex].Name)" -ForegroundColor Green
}

Write-Host ""

# Check if Firefox is running
$firefoxProcesses = Get-Process firefox -ErrorAction SilentlyContinue
if ($firefoxProcesses) {
    Write-Host "WARNING: Firefox is currently running!" -ForegroundColor Yellow
    Write-Host "Please close Firefox before updating the chrome folder." -ForegroundColor Yellow
    $response = Read-Host "Do you want to continue anyway? (y/N)"
    if ($response -ne "y" -and $response -ne "Y") {
        Write-Host "Update cancelled." -ForegroundColor Red
        exit
    }
}

# Create temp directory
if (Test-Path $TempDir) {
    Remove-Item $TempDir -Recurse -Force
}
New-Item -ItemType Directory -Path $TempDir | Out-Null

try {
    # Get latest release info from GitHub API
    Write-Host "Checking for latest release..." -ForegroundColor Green
    $apiUrl = "https://api.github.com/repos/$RepoOwner/$RepoName/releases/latest"
    $release = Invoke-RestMethod -Uri $apiUrl -Headers @{ "User-Agent" = "PowerShell" }
    
    $latestVersion = $release.tag_name
    Write-Host "Latest version: $latestVersion" -ForegroundColor Cyan
    
    # Find the source code zip asset
    $zipAsset = $release.assets | Where-Object { $_.name -eq "source code.zip" }
    
    if (-not $zipAsset) {
        # If no asset named "source code.zip", try the zipball_url
        Write-Host "Using GitHub's generated source archive..." -ForegroundColor Yellow
        $downloadUrl = $release.zipball_url
    } else {
        $downloadUrl = $zipAsset.browser_download_url
    }
    
    # Download the zip file
    $zipPath = Join-Path $TempDir "gwfox.zip"
    Write-Host "Downloading from: $downloadUrl" -ForegroundColor Green
    Invoke-WebRequest -Uri $downloadUrl -OutFile $zipPath -Headers @{ "User-Agent" = "PowerShell" }
    Write-Host "Download complete!" -ForegroundColor Green
    
    # Extract the zip file
    Write-Host "Extracting archive..." -ForegroundColor Green
    $extractPath = Join-Path $TempDir "extracted"
    Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force
    
    # Find the chrome folder (it might be in a subdirectory)
    $chromeFolders = Get-ChildItem -Path $extractPath -Recurse -Directory -Filter "chrome"
    
    if ($chromeFolders.Count -eq 0) {
        throw "Chrome folder not found in the downloaded archive!"
    }
    
    # Use the first chrome folder found
    $sourceChromeFolder = $chromeFolders[0].FullName
    Write-Host "Found chrome folder at: $sourceChromeFolder" -ForegroundColor Green
    
    # Backup existing chrome folder
    $chromeDestPath = Join-Path $FirefoxProfilePath "chrome"
    if (Test-Path $chromeDestPath) {
        $backupPath = Join-Path $FirefoxProfilePath "chrome_backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        Write-Host "Creating backup at: $backupPath" -ForegroundColor Yellow
        Copy-Item -Path $chromeDestPath -Destination $backupPath -Recurse -Force
    }
    
    # Remove old chrome folder
    if (Test-Path $chromeDestPath) {
        Remove-Item $chromeDestPath -Recurse -Force
    }
    
    # Copy new chrome folder
    Write-Host "Installing new chrome folder..." -ForegroundColor Green
    Copy-Item -Path $sourceChromeFolder -Destination $chromeDestPath -Recurse -Force
    
    Write-Host ""
    Write-Host "==================================" -ForegroundColor Green
    Write-Host "Update completed successfully!" -ForegroundColor Green
    Write-Host "==================================" -ForegroundColor Green
    Write-Host "Version: $latestVersion" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Please restart Firefox to apply changes." -ForegroundColor Yellow
    
} catch {
    Write-Host ""
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Update failed!" -ForegroundColor Red
    exit 1
} finally {
    # Cleanup temp directory
    if (Test-Path $TempDir) {
        Remove-Item $TempDir -Recurse -Force
    }
}

Write-Host ""
Read-Host "Press Enter to exit"