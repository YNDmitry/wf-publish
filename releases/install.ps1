# install.ps1

# Enable strict mode for better error handling
Set-StrictMode -Version Latest

# Configuration
$RepoOwner = "yndmitry"
$RepoName = "wf-publish"
$ApiUrl = "https://api.github.com/repos/$RepoOwner/$RepoName/releases/latest"
$TempDir = [System.IO.Path]::GetTempPath() + "wf-publish-installer"
$GpgKeyUrl = "https://keys.openpgp.org/vks/v1/by-fingerprint/7D2E524716804412E3F49364015F2BF3ED1116E3"

# Determine Platform Architecture
$Arch = if ([Environment]::Is64BitOperatingSystem) { "amd64" } else { "x86" }

# Functions
function Cleanup {
    Remove-Item -Recurse -Force -Path $TempDir -ErrorAction SilentlyContinue
    Write-Host "`e[33m⚠️ Temporary files cleaned`e[0m"
}

function Error-Exit {
    param (
        [string]$Message
    )
    Write-Host "`e[31m❌ $Message`e[0m"
    Cleanup
    exit 1
}

function Check-Dependencies {
    $dependencies = @("curl", "gpg", "Expand-Archive")
    foreach ($dep in $dependencies) {
        if (-not (Get-Command $dep -ErrorAction SilentlyContinue)) {
            Error-Exit "Missing required command: $dep"
        }
    }
}

function Import-GpgKey {
    if (-not (gpg --list-keys "$RepoOwner" 2>$null)) {
        Write-Host "`e[36m🔑 Importing GPG key...`e[0m"
        curl -sSL "$GpgKeyUrl" | gpg --import - || Error-Exit "Failed to import GPG key"
    }
}

function Install-App {
    param (
        [string]$AssetPath
    )
    $InstallDir = "$env:ProgramFiles\wf-publish"

    Write-Host "`e[34m📦 Extracting Windows ZIP...`e[0m"
    Expand-Archive -Path $AssetPath -DestinationPath $TempDir -Force

    Write-Host "`e[34m📂 Installing wf-publish to $InstallDir`e[0m"
    if (-Not (Test-Path -Path $InstallDir)) {
        New-Item -ItemType Directory -Path $InstallDir | Out-Null
    }
    Copy-Item -Path "$TempDir\*" -Destination $InstallDir -Recurse -Force

    # Add to PATH
    $env:Path += ";$InstallDir"
    [System.Environment]::SetEnvironmentVariable("Path", $env:Path, [System.EnvironmentVariableTarget]::Machine)

    Write-Host "`e[32m✅ wf-publish successfully installed!`e[0m"
    Write-Host "You can verify the installation by running `wf-publish --version` in a new PowerShell window."
}

# Trap to ensure cleanup on exit
Trap {
    Cleanup
    throw $_
}

# Main Process
try {
    Cleanup
    New-Item -ItemType Directory -Path $TempDir -Force | Out-Null
    Check-Dependencies
    Import-GpgKey

    Write-Host "`e[34m🔍 Checking latest release...`e[0m"
    $response = Invoke-RestMethod -Uri $ApiUrl -UseBasicParsing

    # Determine Asset Name Pattern
    $AssetPattern = "wf-publish-windows-$Arch-.*\.zip$"

    # Find the matching asset
    $AssetInfo = $response.assets | Where-Object { $_.name -match $AssetPattern }

    if (-not $AssetInfo) {
        Write-Host "`e[31m❌ No matching asset found for Windows-$Arch`e[0m"
        Write-Host "`e[34m📦 Available assets:`e[0m"
        $response.assets | ForEach-Object { Write-Host $_.name }
        Error-Exit "Please ensure that the artifacts are correctly uploaded."
    }

    $AssetName = $AssetInfo.name
    $DownloadUrl = $AssetInfo.browser_download_url
    $SigUrl = "$DownloadUrl.asc"

    Write-Host "`e[35m⬇️ Downloading $AssetName...`e[0m"
    Invoke-WebRequest -Uri $DownloadUrl -OutFile "$TempDir\$AssetName" -UseBasicParsing
    Invoke-WebRequest -Uri $SigUrl -OutFile "$TempDir\$AssetName.asc" -UseBasicParsing

    Write-Host "`e[32m🔒 Verifying signature...`e[0m"
    gpg --verify "$TempDir\$AssetName.asc" "$TempDir\$AssetName" || Error-Exit "Signature verification failed!"

    Write-Host "`e[33m🚀 Installing...`e[0m"
    Install-App -AssetPath "$TempDir\$AssetName"

} catch {
    Error-Exit "An unexpected error occurred: $_"
}

# Ensure cleanup on successful completion
Cleanup
