$ErrorActionPreference = "Stop"

$repoRoot = $PSScriptRoot
$version = "1.2.0"
$portableBuilder = Join-Path $repoRoot "run_build_portable.ps1"
$issPath = Join-Path $repoRoot "installer\JamooManager.iss"
$distRoot = Join-Path $repoRoot "dist"
$installerPath = Join-Path $distRoot "installer\JamooManager_Setup_$version.exe"
$portableSource = Join-Path $distRoot "JamooManager_Windows_Portable.zip"
$portableVersioned = Join-Path $distRoot "JamooManager_Windows_Portable_$version.zip"
$hashPath = Join-Path $distRoot "SHA256SUMS_$version.txt"

Write-Host ""
Write-Host "========================================"
Write-Host " JamooManager $version 配布版作成"
Write-Host "========================================"
Write-Host ""

if (-not (Test-Path -LiteralPath $portableBuilder)) {
    throw "run_build_portable.ps1が見つかりません: $portableBuilder"
}

if (-not (Test-Path -LiteralPath $issPath)) {
    throw "JamooManager.issが見つかりません: $issPath"
}

Write-Host "Windowsアプリとポータブル版を作成します..."
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $portableBuilder
if ($LASTEXITCODE -ne 0) {
    throw "ポータブル版の作成に失敗しました。"
}

if (-not (Test-Path -LiteralPath $portableSource)) {
    throw "ポータブルZIPが作成されていません: $portableSource"
}

Copy-Item -LiteralPath $portableSource -Destination $portableVersioned -Force

$isccCandidates = @((Join-Path $env:LOCALAPPDATA "Programs\Inno Setup 6\ISCC.exe"))
if (${env:ProgramFiles(x86)}) {
    $isccCandidates += (Join-Path ${env:ProgramFiles(x86)} "Inno Setup 6\ISCC.exe")
}
if ($env:ProgramFiles) {
    $isccCandidates += (Join-Path $env:ProgramFiles "Inno Setup 6\ISCC.exe")
}

$isccPath = $isccCandidates |
    Where-Object { Test-Path -LiteralPath $_ } |
    Select-Object -First 1

if (-not $isccPath) {
    $isccCommand = Get-Command "ISCC.exe" -ErrorAction SilentlyContinue
    if ($isccCommand) {
        $isccPath = $isccCommand.Source
    }
}

if (-not $isccPath) {
    throw "Inno Setup 6が見つかりません。https://jrsoftware.org/isdl.php からインストールしてください。"
}

Write-Host "インストーラーを作成します..."
& $isccPath $issPath
if ($LASTEXITCODE -ne 0) {
    throw "インストーラーの作成に失敗しました。"
}

if (-not (Test-Path -LiteralPath $installerPath)) {
    throw "完成したインストーラーが見つかりません: $installerPath"
}

$hashLines = @()
foreach ($target in @($installerPath, $portableVersioned)) {
    $hash = Get-FileHash -LiteralPath $target -Algorithm SHA256
    $hashLines += "$($hash.Hash)  $([System.IO.Path]::GetFileName($target))"
}

[System.IO.File]::WriteAllLines(
    $hashPath,
    $hashLines,
    [System.Text.UTF8Encoding]::new($false)
)

Write-Host ""
Write-Host "========================================"
Write-Host " JamooManager $version 配布版が完成しました"
Write-Host "========================================"
Write-Host "Installer: $installerPath"
Write-Host "Portable:  $portableVersioned"
Write-Host "SHA-256:   $hashPath"
Write-Host ""

explorer.exe $distRoot