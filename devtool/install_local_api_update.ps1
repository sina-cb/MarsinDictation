# Focused patch for the existing Windows installation. No mirror/delete, model or settings writes.
[CmdletBinding()]
param(
    [switch]$Apply,
    [switch]$Rollback,
    [string]$PayloadDirectory = '',
    [string]$BackupDirectory = '',
    [int]$ExpectedProcessId = 45576,
    [string]$ExpectedStartUtc = '2026-10-15T20:46:56.4803376Z'
)
$ErrorActionPreference = 'Stop'
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
$dictationIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
$dictationPrincipal = [Security.Principal.WindowsPrincipal]::new($dictationIdentity)
if (!$dictationPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Program Files update requires an elevated PowerShell approved through Windows UAC. No files or processes were changed.'
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
$dictationRunning = @(Get-CimInstance Win32_Process -Filter "Name='MarsinDictation.App.exe'")
if ($dictationRunning.Count -gt 1 -or (!$Rollback -and $dictationRunning.Count -ne 1)) { throw 'Expected one identified process for apply, or zero/one for rollback.' }
$dictationProcess = $null
if ($dictationRunning.Count -eq 1) {
    $dictationProcess = Get-Process -Id $ExpectedProcessId -ErrorAction Stop
    if ($dictationRunning[0].ProcessId -ne $ExpectedProcessId -or $dictationProcess.Path -ne $dictationExe -or
        $dictationProcess.StartTime.ToUniversalTime().ToString('O') -ne $ExpectedStartUtc) { throw 'Process identity/start time changed; inspect before stopping it.' }
}
if (!$Rollback) {
    if (Test-Path -LiteralPath $dictationBackup) { throw 'Backup already exists; choose a fresh directory.' }
    New-Item -ItemType Directory -Path $dictationBackup | Out-Null
    foreach ($dictationName in $dictationFiles) { Copy-Item -LiteralPath (Join-Path $dictationInstalled $dictationName) -Destination (Join-Path $dictationBackup $dictationName) }
    [pscustomobject]@{ installed = $dictationInstalled; executable = $dictationExe; originalPid = $ExpectedProcessId; originalStartUtc = $ExpectedStartUtc; files = $dictationFiles; oldVersion = (Get-Item -LiteralPath (Join-Path $dictationInstalled 'MarsinDictation.App.dll')).VersionInfo.FileVersion } |
        ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $dictationBackup 'manifest.json')
}
# Tray apps may have no main window: try graceful close, then stop only the verified PID.
if ($dictationProcess) {
    $null = $dictationProcess.CloseMainWindow()
    if (!$dictationProcess.WaitForExit(3000)) { Stop-Process -Id $ExpectedProcessId; $dictationProcess.WaitForExit() }
}
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
