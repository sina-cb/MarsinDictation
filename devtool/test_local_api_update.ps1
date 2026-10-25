# Focused, dependency-free selection/race tests. No installation, process stop or file-copy calls.
$ErrorActionPreference = 'Stop'
$dictationSource = Join-Path $PSScriptRoot 'install_local_api_update.ps1'
$dictationTokens = $null
$dictationParseErrors = $null
$dictationAst = [Management.Automation.Language.Parser]::ParseFile($dictationSource, [ref]$dictationTokens, [ref]$dictationParseErrors)
if ($dictationParseErrors.Count) { throw 'Updater source does not parse.' }
foreach ($dictationFunction in @('Get-DictationUpdateProcessSnapshot', 'Confirm-DictationUpdateProcessSnapshot')) {
    $dictationNode = $dictationAst.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $dictationFunction }, $true)
    if (!$dictationNode) { throw "Missing pure selection function $dictationFunction" }
    . ([scriptblock]::Create($dictationNode.Extent.Text))
}
$dictationTarget = 'C:\Program Files\MarsinDictation\MarsinDictation.App.exe'
$dictationOne = [pscustomobject]@{ProcessId=123; ExecutablePath=$dictationTarget; StartTimeUtc='2026-10-25T12:00:00.1234567Z'}
$dictationDev = [pscustomobject]@{ProcessId=456; ExecutablePath='C:\dev\MarsinDictation.App.exe'; StartTimeUtc='2026-10-25T12:00:01.0000000Z'}
$dictationRelaunch = [pscustomobject]@{ProcessId=789; ExecutablePath=$dictationTarget; StartTimeUtc='2026-10-25T12:00:02.0000000Z'}
$dictationReusedPid = [pscustomobject]@{ProcessId=123; ExecutablePath=$dictationTarget; StartTimeUtc='2026-10-25T12:00:03.0000000Z'}
$dictationPassed = 0
function Assert-DictationCase {
    param([string]$Name, [scriptblock]$Check)
    & $Check
    $script:dictationPassed++
    Write-Output "PASS $Name"
}
function Assert-DictationThrows {
    param([scriptblock]$Action)
    $dictationThrew = $false
    try { & $Action | Out-Null } catch { $dictationThrew = $true }
    if (!$dictationThrew) { throw 'Expected identity/race refusal.' }
}
Assert-DictationCase 'Closed app is accepted with no expected identity' {
    if ($null -ne (Get-DictationUpdateProcessSnapshot -Inventory @() -InstalledExe $dictationTarget)) { throw 'Closed app selected a process.' }
}
Assert-DictationCase 'Current exact installed path is discovered without historical PID defaults' {
    if ((Get-DictationUpdateProcessSnapshot -Inventory @($dictationOne) -InstalledExe $dictationTarget).ProcessId -ne 123) { throw 'Wrong process selected.' }
}
Assert-DictationCase 'Explicit valid ID and full-precision start snapshot match' {
    $null = Get-DictationUpdateProcessSnapshot -Inventory @($dictationOne) -InstalledExe $dictationTarget -ExpectedProcessId 123 -ExpectedStartUtc $dictationOne.StartTimeUtc
}
Assert-DictationCase 'Explicit stale ID is refused' { Assert-DictationThrows { Get-DictationUpdateProcessSnapshot -Inventory @($dictationOne) -InstalledExe $dictationTarget -ExpectedProcessId 999 } }
Assert-DictationCase 'Explicit stale start time is refused' { Assert-DictationThrows { Get-DictationUpdateProcessSnapshot -Inventory @($dictationOne) -InstalledExe $dictationTarget -ExpectedStartUtc 'old' } }
Assert-DictationCase 'Explicit expected identity is not ignored when app is closed' { Assert-DictationThrows { Get-DictationUpdateProcessSnapshot -Inventory @() -InstalledExe $dictationTarget -ExpectedProcessId 123 } }
Assert-DictationCase 'Multiple installed instances are refused' { Assert-DictationThrows { Get-DictationUpdateProcessSnapshot -Inventory @($dictationOne,$dictationRelaunch) -InstalledExe $dictationTarget } }
Assert-DictationCase 'Unknown executable path is refused' { Assert-DictationThrows { Get-DictationUpdateProcessSnapshot -Inventory @([pscustomobject]@{ProcessId=1;ExecutablePath=$null;StartTimeUtc='now'}) -InstalledExe $dictationTarget } }
Assert-DictationCase 'Known development path is never selected or stopped' {
    if ($null -ne (Get-DictationUpdateProcessSnapshot -Inventory @($dictationDev) -InstalledExe $dictationTarget)) { throw 'Development app selected as installed target.' }
    if ((Get-DictationUpdateProcessSnapshot -Inventory @($dictationDev,$dictationOne) -InstalledExe $dictationTarget).ProcessId -ne 123) { throw 'Installed app not selected independently of development app.' }
}
Assert-DictationCase 'Closed app remaining closed passes pre-copy confirmation' { Confirm-DictationUpdateProcessSnapshot -Snapshot $null -Inventory @() -InstalledExe $dictationTarget }
Assert-DictationCase 'App appearing during backup is refused before copy' { Assert-DictationThrows { Confirm-DictationUpdateProcessSnapshot -Snapshot $null -Inventory @($dictationOne) -InstalledExe $dictationTarget } }
Assert-DictationCase 'App disappearing during backup is refused before stop or copy' { Assert-DictationThrows { Confirm-DictationUpdateProcessSnapshot -Snapshot $dictationOne -Inventory @() -InstalledExe $dictationTarget } }
Assert-DictationCase 'New PID during backup is refused before stop or copy' { Assert-DictationThrows { Confirm-DictationUpdateProcessSnapshot -Snapshot $dictationOne -Inventory @($dictationRelaunch) -InstalledExe $dictationTarget } }
Assert-DictationCase 'Reused PID with changed start time is refused before stop or copy' { Assert-DictationThrows { Confirm-DictationUpdateProcessSnapshot -Snapshot $dictationOne -Inventory @($dictationReusedPid) -InstalledExe $dictationTarget } }
Assert-DictationCase 'Unchanged exact snapshot passes confirmation' { Confirm-DictationUpdateProcessSnapshot -Snapshot $dictationOne -Inventory @($dictationOne) -InstalledExe $dictationTarget }
Write-Output "Selection tests passed: $dictationPassed/15; no installed files or real processes changed."
