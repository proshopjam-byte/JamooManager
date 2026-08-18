; JamooManager Windows Installer
; Version 1.2.0 - per-user installation and safe in-place upgrades

#define MyAppName "JamooManager"
#define MyAppVersion "1.2.0"
#define MyAppPublisher "プロショップJAM"
#define MyAppExeName "JamooManager.exe"

[Setup]
AppId={{6B2F6215-6E35-4C9B-92B6-90FC3C277D8D}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}

DefaultDirName={localappdata}\Programs\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
UsePreviousAppDir=yes
UsePreviousTasks=yes

OutputDir=..\dist\installer
OutputBaseFilename=JamooManager_Setup_{#MyAppVersion}
SetupIconFile=..\jamoo_app\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}

Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern

ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog

CloseApplications=yes
RestartApplications=no
SetupLogging=yes

VersionInfoVersion=1.2.0.0
VersionInfoCompany={#MyAppPublisher}
VersionInfoDescription=JamooManager Windows Installer
VersionInfoProductName={#MyAppName}
VersionInfoProductVersion={#MyAppVersion}
VersionInfoCopyright=Copyright (C) 2026 Pro Shop JAM

[Languages]
Name: "japanese"; MessagesFile: "compiler:Languages\Japanese.isl"

[Tasks]
Name: "desktopicon"; Description: "デスクトップにショートカットを作成する"; GroupDescription: "追加アイコン:"; Flags: checkedonce
Name: "initialsetup"; Description: "Booking.com・CHILLNNの初回セットアップを実行する"; GroupDescription: "初回設定:"; Flags: checkedonce

[Files]
Source: "..\dist\JamooManager\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; Tasks: desktopicon
Name: "{autoprograms}\{#MyAppName}\初回セットアップ"; Filename: "{app}\初回セットアップ.cmd"; WorkingDir: "{app}"
Name: "{autoprograms}\{#MyAppName}\はじめにお読みください"; Filename: "{app}\はじめにお読みください.txt"

[Run]
Filename: "{app}\初回セットアップ.cmd"; Description: "Booking.com・CHILLNNの初回セットアップを実行する"; WorkingDir: "{app}"; Tasks: initialsetup; Flags: postinstall shellexec waituntilterminated skipifsilent
Filename: "{app}\{#MyAppExeName}"; Description: "JamooManagerを起動する"; WorkingDir: "{app}"; Flags: postinstall nowait skipifsilent

[UninstallDelete]
Type: filesandordirs; Name: "{app}\booking_bot\node_modules"
Type: filesandordirs; Name: "{app}\booking_bot\booking-profile"
Type: filesandordirs; Name: "{app}\booking_bot\output"