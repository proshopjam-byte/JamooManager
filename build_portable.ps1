$ErrorActionPreference = "Stop"

$repoRoot = $PSScriptRoot
$appRoot = Join-Path $repoRoot "jamoo_app"
$bookingBotRoot = Join-Path $repoRoot "booking_bot"
$chillnnBotRoot = Join-Path $repoRoot "chillnn_mail_bot"
$releaseRoot = Join-Path $appRoot "build\windows\x64\runner\Release"
$distRoot = Join-Path $repoRoot "dist"
$packageRoot = Join-Path $distRoot "JamooManager"
$zipPath = Join-Path $distRoot "JamooManager_Windows_Portable.zip"
$exeName = "JamooManager.exe"
$exePath = Join-Path $releaseRoot $exeName

Write-Host ""
Write-Host "========================================"
Write-Host " JamooManager 配布用パッケージ作成"
Write-Host "========================================"
Write-Host ""

if (-not (Test-Path -LiteralPath $appRoot)) {
    throw "jamoo_app フォルダが見つかりません。 $appRoot"
}

if (-not (Test-Path -LiteralPath $bookingBotRoot)) {
    throw "booking_bot フォルダが見つかりません。 $bookingBotRoot"
}

Write-Host "最新のWindows完成版をビルドします。"
Push-Location $appRoot
try {
    & flutter build windows --release
    if ($LASTEXITCODE -ne 0) {
        throw "FlutterのWindowsビルドに失敗しました。"
    }
}
finally {
    Pop-Location
}

if (-not (Test-Path -LiteralPath $exePath)) {
    throw "JamooManager.exe が作成されていません。 $exePath"
}

if (-not (Test-Path -LiteralPath $distRoot)) {
    New-Item -ItemType Directory -Path $distRoot -Force | Out-Null
}

if (Test-Path -LiteralPath $packageRoot) {
    Remove-Item -LiteralPath $packageRoot -Recurse -Force
}

if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
}

New-Item -ItemType Directory -Path $packageRoot -Force | Out-Null

Write-Host "アプリ本体をコピーしています..."

Get-ChildItem -LiteralPath $releaseRoot | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination $packageRoot -Recurse -Force
}

$portableBotRoot = Join-Path $packageRoot "booking_bot"
New-Item -ItemType Directory -Path $portableBotRoot -Force | Out-Null

Write-Host "Booking.com取得ファイルをコピーしています..."

$bookingFiles = @(
    "booking.js",
    "package.json",
    "package-lock.json"
)

foreach ($fileName in $bookingFiles) {
    $sourcePath = Join-Path $bookingBotRoot $fileName
    if (Test-Path -LiteralPath $sourcePath) {
        Copy-Item -LiteralPath $sourcePath -Destination $portableBotRoot -Force
    }
}

$outputRoot = Join-Path $portableBotRoot "output"
New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null
$portableChillnnBotRoot = Join-Path $packageRoot "chillnn_mail_bot"
New-Item -ItemType Directory -Path $portableChillnnBotRoot -Force | Out-Null

Write-Host "CHILLNN取得ファイルをコピーしています..."

$chillnnFiles = @(
"fetch_chillnn.py",
"requirements.txt"
)

foreach ($fileName in $chillnnFiles) {
$sourcePath = Join-Path $chillnnBotRoot $fileName
if (-not (Test-Path -LiteralPath $sourcePath)) {
throw "CHILLNN配布ファイルが見つかりません。 $sourcePath"
}
Copy-Item -LiteralPath $sourcePath -Destination $portableChillnnBotRoot -Force
}

$chillnnOutputRoot = Join-Path $portableChillnnBotRoot "output"
New-Item -ItemType Directory -Path $chillnnOutputRoot -Force | Out-Null

$setupLines = @(
    '@echo off',
    'chcp 65001 >nul',
    'title JamooManager 初回セットアップ',
    '',
    'echo.',
    'echo ========================================',
    'echo  JamooManager 初回セットアップ',
    'echo ========================================',
    'echo.',
    'where node >nul 2>&1',
    'if errorlevel 1 (',
    '    echo Node.jsが見つかりません。',
    '    echo 先にNode.jsをインストールしてください。',
    '    echo.',
    '    pause',
    '    exit /b 1',
    ')',
    '',
    'where py >nul 2>&1',
'if errorlevel 1 (',
'    echo Pythonが見つかりません。',
'    echo 先にPythonをインストールしてください。',
'    echo.',
'    pause',
'    exit /b 1',
')',
'',
'echo CHILLNN用Pythonライブラリをインストールしています...',
'py -m pip install --user -r "%~dp0chillnn_mail_bot\requirements.txt"',
'if errorlevel 1 (',
'    echo.',
'    echo CHILLNN用Pythonライブラリのインストールに失敗しました。',
'    pause',
'    exit /b 1',
')',
'',
'if not exist "%~dp0chillnn_mail_bot\credentials.json" (',
'    echo.',
'    echo 【注意】CHILLNN取得にはcredentials.jsonの配置が必要です。',
'    echo Please copy credentials.json into the chillnn_mail_bot folder.',
'    echo.',
')',
'',
'cd /d "%~dp0booking_bot"',
    'echo Playwrightをインストールしています...',
    'call npm.cmd install',
    'if errorlevel 1 (',
    '    echo.',
    '    echo npm install に失敗しました。',
    '    pause',
    '    exit /b 1',
    ')',
    '',
    'echo.',
    'echo Chromiumをインストールしています...',
    'call npx.cmd playwright install chromium',
    'if errorlevel 1 (',
    '    echo.',
    '    echo Chromiumのインストールに失敗しました。',
    '    pause',
    '    exit /b 1',
    ')',
    '',
    'echo.',
    'echo ========================================',
    'echo  初回セットアップが完了しました',
    'echo ========================================',
    'echo.',
    'pause'
)

Set-Content `
    -LiteralPath (Join-Path $packageRoot "初回セットアップ.cmd") `
    -Value $setupLines `
    -Encoding UTF8

$launcherLines = @(
    '@echo off',
    'cd /d "%~dp0"',
    'start "" "%~dp0JamooManager.exe"'
)

Set-Content `
    -LiteralPath (Join-Path $packageRoot "JamooManagerを起動.cmd") `
    -Value $launcherLines `
    -Encoding ASCII

$readmeLines = @(
    'JamooManager Windows版',
    '=======================',
    '',
    '【初めて使うとき】',
    '',
    '1. このZIPを任意の場所へ展開します。',
    '2. Node.jsとPythonが入っていない場合は、先にインストールします。',
    '3. 「初回セットアップ.cmd」をダブルクリックします。',
    '4. セットアップ完了後、「JamooManagerを起動.cmd」をダブルクリックします。',
    '5. アプリ右上の歯車から「環境を診断」を実行します。',
    '',
    '【Booking.comから取得する】',
    '',
    'アプリの「Booking.comから取得」を押します。',
    '別画面でBooking.comへのログインや確認操作を完了してください。',
    '',
    '【CHILLNNから取得する】',
'',
'1. Google Cloudで作成したOAuthデスクトップ用のcredentials.jsonを用意します。',
'2. credentials.jsonをchillnn_mail_botフォルダへコピーします。',
'3. アプリの「CHILLNNから取得」を押します。',
'4. 初回だけブラウザでGoogle認証を完了します。',
'',
'※ token.jsonは認証後に自動作成されます。',
'※ credentials.jsonとtoken.jsonは配布ZIPには含まれません。',
'',
'【重要】',
    '',
    '・JamooManager.exeだけを単独で移動しないでください。',
    '・このフォルダ内のファイルとフォルダは、一式のまま使用してください。',
    '・予約サイトの画面変更により、取得処理の修正が必要になる場合があります。',
    '・予約データは booking_bot\output に保存されます。',
    '・ログイン情報を含む booking-profile は配布ZIPには含めていません。'
)

Set-Content `
    -LiteralPath (Join-Path $packageRoot "はじめにお読みください.txt") `
    -Value $readmeLines `
    -Encoding UTF8

Write-Host "ZIPファイルを作成しています..."

Compress-Archive `
    -LiteralPath $packageRoot `
    -DestinationPath $zipPath `
    -CompressionLevel Optimal `
    -Force

Write-Host ""
Write-Host "========================================"
Write-Host " 配布用パッケージが完成しました"
Write-Host "========================================"
Write-Host ""
Write-Host $zipPath
Write-Host ""

explorer.exe $distRoot
