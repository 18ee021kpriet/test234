# SQL Server 2025 - Download and Install
# Run as Administrator

param(
    [string]$DownloadPath = "C:\SQLInstaller",
    [string]$InstanceName = "MSSQLSERVER",
    [string]$SAPassword   = "YourStrongPassword123!"
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

# ── Check for Existing SQL Installation ───────────────────────────────────────
Write-Info "Checking for existing SQL Server installations..."
$existingServices = Get-Service | Where-Object { $_.Name -like "MSSQL*" }
if ($existingServices) {
    Write-Warn "Existing SQL Server services found:"
    $existingServices | ForEach-Object { Write-Warn "  $($_.Name) - $($_.Status)" }
    Write-Warn "If installation fails, consider uninstalling existing instances first."
}

$existingInstalls = Get-WmiObject -Class Win32_Product -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -like "*SQL Server*" } |
    Select-Object Name, Version
if ($existingInstalls) {
    Write-Warn "Existing SQL Server products found:"
    $existingInstalls | ForEach-Object { Write-Warn "  $($_.Name) - $($_.Version)" }
}

# ── Create Download Folder ────────────────────────────────────────────────────
New-Item -ItemType Directory -Path $DownloadPath -Force | Out-Null
Write-Success "Download folder ready: $DownloadPath"

# ── Step 1: Download the Bootstrapper ────────────────────────────────────────
$bootstrapperUrl  = "https://go.microsoft.com/fwlink/?linkid=2342429&clcid=0x409&culture=en-us&country=us"
$bootstrapperPath = Join-Path $DownloadPath "SQLServer-Setup.exe"

if (Test-Path $bootstrapperPath) {
    Write-Warn "Bootstrapper already exists, skipping download."
} else {
    Write-Info "Downloading SQL Server bootstrapper..."
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $bootstrapperUrl -OutFile $bootstrapperPath -UseBasicParsing
        Write-Success "Download complete: $bootstrapperPath"
    } catch {
        Write-Err "Download failed: $_"
        exit 1
    }
}

# ── Step 2: Download Full ISO Media ──────────────────────────────────────────
$fullInstallerPath = Join-Path $DownloadPath "SQLServer-Full"
New-Item -ItemType Directory -Path $fullInstallerPath -Force | Out-Null

$existingISO = Get-ChildItem -Path $fullInstallerPath -Filter "*.iso" -ErrorAction SilentlyContinue | Select-Object -First 1

if ($existingISO) {
    Write-Warn "ISO already exists: $($existingISO.FullName), skipping download."
} else {
    Write-Info "Downloading full ISO media to $fullInstallerPath ..."
    $dlArgs = @(
        "/ACTION=Download",
        "/MEDIAPATH=`"$fullInstallerPath`"",
        "/MEDIATYPE=ISO",
        "/QUIET"
    )
    $dlProcess = Start-Process -FilePath $bootstrapperPath -ArgumentList $dlArgs -Wait -PassThru -NoNewWindow

    if ($dlProcess.ExitCode -ne 0) {
        Write-Err "ISO media download failed with exit code: $($dlProcess.ExitCode)"
        exit 1
    }
    Write-Success "ISO media downloaded successfully."
}

# ── Step 3: Detect ISO ────────────────────────────────────────────────────────
$isoFile = Get-ChildItem -Path $fullInstallerPath -Filter "*.iso" | Select-Object -First 1
if (-not $isoFile) {
    Write-Err "ISO file not found in $fullInstallerPath"
    exit 1
}
Write-Info "Found ISO: $($isoFile.FullName)"

# ── Step 4: Detect SQL Version from ISO Name ──────────────────────────────────
$isoName    = $isoFile.Name
$sqlVersion = "Unknown"
if ($isoName -match "2022") { $sqlVersion = "2022" }
elseif ($isoName -match "2019") { $sqlVersion = "2019" }
elseif ($isoName -match "2025") { $sqlVersion = "2025" }
Write-Info "Detected SQL Server version from ISO: $sqlVersion"

# ── Step 5: Build Configuration File ─────────────────────────────────────────
$configFile    = Join-Path $DownloadPath "sql_config.ini"
$configContent = @"
[OPTIONS]
ACTION=Install
IACCEPTSQLSERVERLICENSETERMS=1
QUIET=1
QUIETSIMPLE=0
UpdateEnabled=0
INSTANCENAME=$InstanceName
FEATURES=SQLENGINE,CONN
SQLSYSADMINACCOUNTS=BUILTIN\Administrators
SECURITYMODE=SQL
SAPWD=$SAPassword
TCPENABLED=1
NPENABLED=0
"@

Set-Content -Path $configFile -Value $configContent
Write-Success "Configuration file created: $configFile"

# ── Step 6: Mount ISO ─────────────────────────────────────────────────────────
Write-Info "Mounting ISO: $($isoFile.FullName)"
try {
    $mount       = Mount-DiskImage -ImagePath $isoFile.FullName -PassThru
    $driveLetter = ($mount | Get-Volume).DriveLetter
    $setupExe    = "$driveLetter`:\setup.exe"
    Write-Success "ISO mounted at drive $driveLetter`:"
} catch {
    Write-Err "Failed to mount ISO: $_"
    exit 1
}

# ── Step 7: Run Setup ─────────────────────────────────────────────────────────
Write-Info "Running SQL Server setup from $setupExe ..."
Write-Info "This may take 15-30 minutes, please wait..."

try {
    $setupProcess = Start-Process -FilePath $setupExe `
        -ArgumentList "/ConfigurationFile=`"$configFile`"" `
        -Wait -PassThru -NoNewWindow
} catch {
    Write-Err "Failed to launch setup: $_"
    Dismount-DiskImage -ImagePath $isoFile.FullName | Out-Null
    exit 1
}

# ── Step 8: Unmount ISO ───────────────────────────────────────────────────────
Dismount-DiskImage -ImagePath $isoFile.FullName | Out-Null
Write-Info "ISO unmounted."

# ── Step 9: Check Setup Result ────────────────────────────────────────────────
if ($setupProcess.ExitCode -eq 0) {
    Write-Success "SQL Server installed successfully!"
} else {
    Write-Err "Setup exited with code: $($setupProcess.ExitCode)"

    # Find and show latest log
    $logRoots = @(
        "C:\Program Files\Microsoft SQL Server\150\Setup Bootstrap\Log",
        "C:\Program Files\Microsoft SQL Server\160\Setup Bootstrap\Log",
        "C:\Program Files\Microsoft SQL Server\170\Setup Bootstrap\Log"
    )
    foreach ($logRoot in $logRoots) {
        if (Test-Path $logRoot) {
            $latestLog = Get-ChildItem $logRoot -Filter "Summary*.txt" |
                Sort-Object LastWriteTime -Descending |
                Select-Object -First 1
            if ($latestLog) {
                Write-Warn "Setup log: $($latestLog.FullName)"
                Write-Warn "---- Last 30 lines of log ----"
                Get-Content $latestLog.FullName | Select-Object -Last 30 | ForEach-Object { Write-Host $_ -ForegroundColor Yellow }
            }
        }
    }
    exit 1
}

# ── Step 10: Start SQL Server Service ────────────────────────────────────────
Write-Info "Starting SQL Server service..."
$serviceName = if ($InstanceName -eq "MSSQLSERVER") { "MSSQLSERVER" } else { "MSSQL`$$InstanceName" }

try {
    Start-Service -Name $serviceName -ErrorAction Stop
    Start-Sleep -Seconds 8

    $svc = Get-Service -Name $serviceName
    if ($svc.Status -eq "Running") {
        Write-Success "SQL Server service is running."
    } else {
        Write-Err "Service not running. Status: $($svc.Status)"
    }
} catch {
    Write-Err "Could not start service: $_"
}

# ── Step 11: Set Service to Auto-Start ───────────────────────────────────────
Set-Service -Name $serviceName -StartupType Automatic -ErrorAction SilentlyContinue
Write-Success "Service set to automatic startup."

# ── Step 12: Enable TCP Port 1433 in Firewall ────────────────────────────────
Write-Info "Adding firewall rule for SQL Server port 1433..."
New-NetFirewallRule -DisplayName "SQL Server 1433" `
    -Direction Inbound `
    -Protocol TCP `
    -LocalPort 1433 `
    -Action Allow `
    -ErrorAction SilentlyContinue | Out-Null
Write-Success "Firewall rule added."

# ── Done ──────────────────────────────────────────────────────────────────────
Write-Info ""
Write-Info "=== Installation Complete ==="
Write-Host "Instance Name      : $InstanceName"
Write-Host "SA Password        : $SAPassword"
Write-Host "Connection String  : Server=localhost;User Id=sa;Password=$SAPassword;"
Write-Host "Named Instance CS  : Server=localhost\$InstanceName;User Id=sa;Password=$SAPassword;"