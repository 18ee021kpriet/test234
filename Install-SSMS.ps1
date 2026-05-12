# SSMS Installation Script
# Run as Administrator

param(
    [string]$DownloadPath = "C:\SQLInstaller",
    [string]$SSMSUrl      = "https://download.microsoft.com/download/9/b/e/9bee9f00-2ee2-429a-9462-c9bc1ce14c28/SSMS-Setup-ENU.exe"
)

# ── Helpers ───────────────────────────────────────────────────────────────────
function Write-Info    { Write-Host $args -ForegroundColor Cyan }
function Write-Success { Write-Host $args -ForegroundColor Green }
function Write-Err     { Write-Host $args -ForegroundColor Red }
function Write-Warn    { Write-Host $args -ForegroundColor Yellow }

# ── Admin Check ───────────────────────────────────────────────────────────────
$isAdmin = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $isAdmin.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Err "Please run this script as Administrator."
    exit 1
}
Write-Success "Running as Administrator"

# ── Check if SSMS Already Installed ──────────────────────────────────────────
Write-Info "Checking for existing SSMS installation..."
$existingSSMS = Get-WmiObject -Class Win32_Product -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -like "*SQL Server Management Studio*" } |
    Select-Object Name, Version

if ($existingSSMS) {
    Write-Warn "SSMS already installed:"
    $existingSSMS | ForEach-Object { Write-Warn "  $($_.Name) - Version $($_.Version)" }
    $choice = Read-Host "Reinstall/Upgrade? (yes/no)"
    if ($choice -ne "yes") {
        Write-Info "Installation cancelled."
        exit 0
    }
}

# ── Create Download Folder ────────────────────────────────────────────────────
New-Item -ItemType Directory -Path $DownloadPath -Force | Out-Null
Write-Success "Download folder ready: $DownloadPath"

# ── Step 1: Download SSMS ─────────────────────────────────────────────────────
$ssmsPath = Join-Path $DownloadPath "SSMS-Setup-ENU.exe"

if (Test-Path $ssmsPath) {
    Write-Warn "SSMS installer already exists at $ssmsPath, skipping download."
} else {
    Write-Info "Downloading SSMS installer..."
    Write-Info "Source: $SSMSUrl"
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $SSMSUrl -OutFile $ssmsPath -UseBasicParsing
        Write-Success "Download complete: $ssmsPath"
    } catch {
        Write-Err "Download failed: $_"
        exit 1
    }
}

# ── Verify Downloaded File ────────────────────────────────────────────────────
$fileSize = (Get-Item $ssmsPath).Length / 1MB
Write-Info "Installer size: $([math]::Round($fileSize, 2)) MB"

if ($fileSize -lt 10) {
    Write-Err "Downloaded file seems too small. It may be corrupted. Please re-download."
    Remove-Item $ssmsPath -Force
    exit 1
}

# ── Step 2: Install SSMS ──────────────────────────────────────────────────────
Write-Info "Installing SSMS silently (this may take 10-20 minutes)..."
Write-Info "Please do not close this window."

try {
    $installArgs = @(
        "/Install",
        "/Quiet",
        "/Norestart",
        "/Log `"$DownloadPath\SSMS-Install.log`""
    )

    $process = Start-Process -FilePath $ssmsPath `
        -ArgumentList $installArgs `
        -Wait -PassThru -NoNewWindow

    switch ($process.ExitCode) {
        0 {
            Write-Success "SSMS installed successfully!"
        }
        3010 {
            Write-Success "SSMS installed successfully!"
            Write-Warn "A system restart is required to complete the installation."
        }
        default {
            Write-Err "SSMS installation failed with exit code: $($process.ExitCode)"
            Write-Warn "Check log at: $DownloadPath\SSMS-Install.log"
            exit 1
        }
    }
} catch {
    Write-Err "Failed to launch SSMS installer: $_"
    exit 1
}

# ── Step 3: Verify Installation ───────────────────────────────────────────────
Write-Info "Verifying SSMS installation..."
$ssmsExePaths = @(
    "C:\Program Files (x86)\Microsoft SQL Server Management Studio 20\Common7\IDE\Ssms.exe",
    "C:\Program Files (x86)\Microsoft SQL Server Management Studio 19\Common7\IDE\Ssms.exe",
    "C:\Program Files (x86)\Microsoft SQL Server Management Studio 18\Common7\IDE\Ssms.exe"
)

$found = $false
foreach ($path in $ssmsExePaths) {
    if (Test-Path $path) {
        $version = (Get-Item $path).VersionInfo.FileVersion
        Write-Success "SSMS found at: $path"
        Write-Success "Version: $version"
        $found = $true
        break
    }
}

if (-not $found) {
    Write-Warn "SSMS executable not found in default paths."
    Write-Warn "It may still be installing or was installed to a custom path."
    Write-Warn "Check: C:\Program Files (x86)\Microsoft SQL Server Management Studio*"
}

# ── Step 4: Cleanup ───────────────────────────────────────────────────────────
$cleanup = Read-Host "`nRemove installer file to free space? (yes/no)"
if ($cleanup -eq "yes") {
    Remove-Item $ssmsPath -Force -ErrorAction SilentlyContinue
    Write-Success "Installer removed."
} else {
    Write-Info "Installer kept at: $ssmsPath"
}

# ── Done ──────────────────────────────────────────────────────────────────────
Write-Info ""
Write-Info "=== SSMS Installation Complete ==="
Write-Host "To launch SSMS: Start Menu → Search 'SQL Server Management Studio'"
Write-Host "Or run: Ssms.exe"
Write-Host "Install log: $DownloadPath\SSMS-Install.log"

if ($process.ExitCode -eq 3010) {
    Write-Warn ""
    Write-Warn "*** Please restart your computer to complete the installation ***"
}