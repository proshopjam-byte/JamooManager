$ErrorActionPreference = "Stop"

$repoRoot = $PSScriptRoot
$targetScript = Join-Path $repoRoot "build_portable.ps1"

$scriptText = [System.IO.File]::ReadAllText(
    $targetScript,
    [System.Text.Encoding]::UTF8
)

$scriptText = $scriptText.Replace(
    '$repoRoot = $PSScriptRoot',
    ''
)

$scriptBlock = [System.Management.Automation.ScriptBlock]::Create(
    $scriptText
)

& $scriptBlock