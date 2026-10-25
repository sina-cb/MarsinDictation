# Focused patch for the existing Windows installation. No mirror/delete, model or settings writes.
[CmdletBinding()]
param(
    [switch]$Apply,
    [switch]$Rollback,
    [string]$PayloadDirectory = '',
    [string]$BackupDirectory = '',
    [int]$ExpectedProcessId = 0,
    [string]$ExpectedStartUtc = ''
)
$ErrorActionPreference = 'Stop'

# Pure selection/confirmation functions are also exercised by test_local_api_update.ps1.
function Get-DictationUpdateProcessSnapshot {
    param([object[]]$Inventory, [string]$InstalledExe, [int]$ExpectedProcessId = 0, [string]$ExpectedStartUtc = '')
    if (@($Inventory | Where-Object { !$_.ExecutablePath -or !$_.StartTimeUtc }).Count) { throw 'A dictation process has unknown identity; inspect it before updating.' }
    $dictationMatches = @($Inventory | Where-Object { [string]::Equals($_.ExecutablePath, $InstalledExe, [StringComparison]::OrdinalIgnoreCase) })
    if ($dictationMatches.Count -gt 1) { throw 'Multiple processes use the installed executable; close extra instances before updating.' }
    if (!$dictationMatches.Count) {
        if ($ExpectedProcessId -or $ExpectedStartUtc) { throw 'The explicitly expected process is no longer running.' }
        return $null
    }
    $dictationSelected = $dictationMatches[0]
    if (($ExpectedProcessId -and $dictationSelected.ProcessId -ne $ExpectedProcessId) -or
        ($ExpectedStartUtc -and $dictationSelected.StartTimeUtc -ne $ExpectedStartUtc)) { throw 'Explicit process identity/start time does not match the installed app.' }
    return $dictationSelected
}
function Confirm-DictationUpdateProcessSnapshot {
    param($Snapshot, [object[]]$Inventory, [string]$InstalledExe)
    $dictationNow = Get-DictationUpdateProcessSnapshot -Inventory $Inventory -InstalledExe $InstalledExe
    if (($null -eq $Snapshot) -ne ($null -eq $dictationNow)) { throw 'Installed app started or exited during update preparation; no files were copied.' }
    if ($Snapshot -and ($Snapshot.ProcessId -ne $dictationNow.ProcessId -or $Snapshot.StartTimeUtc -ne $dictationNow.StartTimeUtc)) { throw 'Installed app identity changed during update preparation; no files were copied.' }
}
function Get-DictationUpdateProcessInventory {
    @(Get-CimInstance Win32_Process -Filter "Name='MarsinDictation.App.exe'") | ForEach-Object {
        $dictationObserved = Get-Process -Id $_.ProcessId -ErrorAction Stop
        if (!$_.ExecutablePath -or !$dictationObserved.Path -or $_.ExecutablePath -ne $dictationObserved.Path) { throw 'A dictation process has unknown or changing identity; inspect it before updating.' }
        [pscustomobject]@{ ProcessId = $_.ProcessId; ExecutablePath = $dictationObserved.Path; StartTimeUtc = $dictationObserved.StartTime.ToUniversalTime().ToString('O') }
    }
}
$dictationRepo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$dictationInstalled = 'C:\Program Files\MarsinDictation'
$dictationExe = Join-Path $dictationInstalled 'MarsinDictation.App.exe'
$dictationBundled = Test-Path -LiteralPath (Join-Path $PSScriptRoot 'payload') -PathType Container
$dictationPublish = if ($PayloadDirectory) { [IO.Path]::GetFullPath($PayloadDirectory) }
    elseif ($dictationBundled) { Join-Path $PSScriptRoot 'payload' }
    else { Join-Path $dictationRepo 'tmp\local_api_publish' }
$dictationFiles = @('MarsinDictation.App.dll', 'MarsinDictation.Core.dll', 'MarsinDictation.App.pdb', 'MarsinDictation.Core.pdb')
$dictationBackupBase = if ($dictationBundled) { Join-Path $PSScriptRoot 'backups' } else { Join-Path $dictationRepo 'tmp' }
if (!$BackupDirectory) { $BackupDirectory = Join-Path $dictationBackupBase ('local_api_backup_' + (Get-Date -Format 'yyyyMMdd_HHmmss')) }
$dictationBackup = [IO.Path]::GetFullPath($BackupDirectory)
$dictationBackupRoot = [IO.Path]::GetFullPath($dictationBackupBase) + [IO.Path]::DirectorySeparatorChar
if (!$dictationBackup.StartsWith($dictationBackupRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'Backup must remain inside the updater backup directory.' }
if ($Apply -and $Rollback) { throw 'Choose apply or rollback.' }
if (!$Apply -and !$Rollback) {
    [pscustomobject]@{ operation = 'plan'; installed = $dictationInstalled; publish = $dictationPublish; backup = $dictationBackup; files = $dictationFiles; expectedPid = $ExpectedProcessId; expectedStartUtc = $ExpectedStartUtc } | ConvertTo-Json -Depth 3
    return
}
if (!$Rollback) {
    $dictationPayloadManifest = Get-Content -LiteralPath (Join-Path $dictationPublish 'manifest.json') | ConvertFrom-Json
    if ($dictationPayloadManifest.version -ne '1.0.1.0' -or $dictationPayloadManifest.files.Count -ne 4) { throw 'Unexpected payload manifest.' }
    foreach ($dictationName in $dictationFiles) {
        $dictationEntry = @($dictationPayloadManifest.files | Where-Object { $_.name -eq $dictationName })
        if ($dictationEntry.Count -ne 1 -or (Get-FileHash -LiteralPath (Join-Path $dictationPublish $dictationName) -Algorithm SHA256).Hash -ne $dictationEntry[0].sha256) { throw "Payload integrity failed: $dictationName" }
    }
}
foreach ($dictationName in $dictationFiles) {
    $dictationSource = Join-Path $(if ($Rollback) { $dictationBackup } else { $dictationPublish }) $dictationName
    if (!(Test-Path -LiteralPath $dictationSource -PathType Leaf)) { throw "Missing update/backup file: $dictationName" }
    if (!(Test-Path -LiteralPath (Join-Path $dictationInstalled $dictationName) -PathType Leaf)) { throw "Missing installed file: $dictationName" }
}
if (!$Rollback) {
    $dictationAlreadyCurrent = $true
    foreach ($dictationEntry in $dictationPayloadManifest.files) {
        if ((Get-FileHash -LiteralPath (Join-Path $dictationInstalled $dictationEntry.name) -Algorithm SHA256).Hash -ne $dictationEntry.sha256) { $dictationAlreadyCurrent = $false }
    }
    if ($dictationAlreadyCurrent) {
        if ($ExpectedProcessId -or $ExpectedStartUtc) {
            $null = Get-DictationUpdateProcessSnapshot -Inventory @(Get-DictationUpdateProcessInventory) -InstalledExe $dictationExe -ExpectedProcessId $ExpectedProcessId -ExpectedStartUtc $ExpectedStartUtc
        }
        [pscustomobject]@{ operation = 'already_current'; version = '1.0.1.0'; filesChanged = $false; processesChanged = $false; note = 'All four installed files match the approved payload. No update is needed. If the app is closed, open it normally; runtime health was not checked by this updater.' } | ConvertTo-Json
        return
    }
    $dictationInstalledVersion = (Get-Item -LiteralPath (Join-Path $dictationInstalled 'MarsinDictation.App.dll')).VersionInfo.FileVersion
    if ($dictationInstalledVersion -notin @('1.0.0.0', '1.0.1.0')) { throw 'Installed version is outside this patch scope; do not overwrite a different release.' }
}
$dictationIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
$dictationPrincipal = [Security.Principal.WindowsPrincipal]::new($dictationIdentity)
if (!$dictationPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Program Files update requires an elevated PowerShell approved through Windows UAC. No files or processes were changed.' }
$dictationSnapshot = Get-DictationUpdateProcessSnapshot -Inventory @(Get-DictationUpdateProcessInventory) -InstalledExe $dictationExe -ExpectedProcessId $ExpectedProcessId -ExpectedStartUtc $ExpectedStartUtc
if (!$Rollback) {
    if (Test-Path -LiteralPath $dictationBackup) { throw 'Backup already exists; choose a fresh directory.' }
    New-Item -ItemType Directory -Path $dictationBackup | Out-Null
    foreach ($dictationName in $dictationFiles) { Copy-Item -LiteralPath (Join-Path $dictationInstalled $dictationName) -Destination (Join-Path $dictationBackup $dictationName) }
    [pscustomobject]@{ installed = $dictationInstalled; executable = $dictationExe; originalPid = $(if ($dictationSnapshot) { $dictationSnapshot.ProcessId } else { $null }); originalStartUtc = $(if ($dictationSnapshot) { $dictationSnapshot.StartTimeUtc } else { $null }); files = $dictationFiles; oldVersion = (Get-Item -LiteralPath (Join-Path $dictationInstalled 'MarsinDictation.App.dll')).VersionInfo.FileVersion } |
        ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $dictationBackup 'manifest.json')
}
# Tray apps may have no main window: try graceful close, then stop only the verified PID.
Confirm-DictationUpdateProcessSnapshot -Snapshot $dictationSnapshot -Inventory @(Get-DictationUpdateProcessInventory) -InstalledExe $dictationExe
if ($dictationSnapshot) {
    $dictationProcess = Get-Process -Id $dictationSnapshot.ProcessId -ErrorAction Stop
    $null = $dictationProcess.CloseMainWindow()
    if (!$dictationProcess.WaitForExit(3000)) {
        Confirm-DictationUpdateProcessSnapshot -Snapshot $dictationSnapshot -Inventory @(Get-DictationUpdateProcessInventory) -InstalledExe $dictationExe
        Stop-Process -InputObject $dictationProcess
        $dictationProcess.WaitForExit()
    }
}
# A previously closed/stopped app must not have been launched concurrently before file copying.
Confirm-DictationUpdateProcessSnapshot -Snapshot $null -Inventory @(Get-DictationUpdateProcessInventory) -InstalledExe $dictationExe
try {
    foreach ($dictationName in $dictationFiles) {
        $dictationSource = Join-Path $(if ($Rollback) { $dictationBackup } else { $dictationPublish }) $dictationName
        Copy-Item -LiteralPath $dictationSource -Destination (Join-Path $dictationInstalled $dictationName) -Force
    }
} catch {
    if (!$Rollback) {
        foreach ($dictationName in $dictationFiles) { Copy-Item -LiteralPath (Join-Path $dictationBackup $dictationName) -Destination (Join-Path $dictationInstalled $dictationName) -Force }
    }
    Write-Warning 'Update failed. Close this Administrator PowerShell and open MarsinDictation normally from Start or its desktop shortcut after checking the restored files.'
    throw
}
# Never launch from this elevated shell: the normal tray app/API should run at user integrity.
$dictationReceipt = [pscustomobject]@{ operation = $(if ($Rollback) { 'files_rolled_back' } else { 'files_updated' }); launchRequired = $true; executable = $dictationExe; backup = $dictationBackup; version = (Get-Item -LiteralPath (Join-Path $dictationInstalled 'MarsinDictation.App.dll')).VersionInfo.FileVersion; note = 'Close Administrator PowerShell and open MarsinDictation normally from Start or its desktop shortcut. Health and real WAV verification are pending that launch.' }
$dictationReceipt | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $dictationBackup $(if ($Rollback) { 'rollback_receipt.json' } else { 'update_receipt.json' }))
$dictationReceipt | ConvertTo-Json -Depth 4
Write-Host 'Close this Administrator PowerShell and open MarsinDictation normally from Start or its desktop shortcut.'
