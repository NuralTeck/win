; =========================================================================
; OPSCORE PRO - ENTERPRISE WINDOWS INSTALLER (INNO SETUP 7)
; Modern UI Wizard • Deepest LZMA2 Ultra64 Solid Compression • Full Windows 7/10/11 Support
; =========================================================================

#define MyAppName "OpsCore Pro - Lottery Management System"
#define MyAppVersion "2.0.0"
#define MyAppPublisher "Radhe Radhe Enterprises"
#define MyAppExeName "opscore_pro.exe"
#define MyAppURL "https://opscore.com"

[Setup]
; Unique application GUID
AppId={{5E1698E0-9E11-477D-9D22-C89C579BE771}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\OpsCore Pro
DefaultGroupName=OpsCore Pro
DisableProgramGroupPage=yes
OutputDir=build\installer
OutputBaseFilename=OpsCore_Pro_Windows_Setup_v2.0.0
SetupIconFile=windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\app_icon.ico

; ⚡ Deepest LZMA2 Ultra64 Solid Compression for Minimum File Size
Compression=lzma2/ultra64
SolidCompression=yes
LZMADictionarySize=262144
LZMANumBlockThreads=8

; Modern UI Wizard
WizardStyle=modern
ShowLanguageDialog=no
ArchitecturesInstallIn64BitMode=x64compatible
CloseApplications=yes
RestartApplications=no
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a &Desktop Shortcut"; GroupDescription: "Additional Shortcuts:"
Name: "autostart"; Description: "Start WhatsApp Sync Engine automatically on Windows startup"; GroupDescription: "Background Services:"; Flags: unchecked

[Files]
; 🚀 Official Microsoft Visual C++ 2015-2022 Redistributable (Guarantees zero missing DLL on Windows 7/10/11)
Source: "installer_prereqs\vc_redist.x64.exe"; DestDir: "{tmp}"; Flags: ignoreversion deleteafterinstall skipifsourcedoesntexist

; Main Flutter Windows Release Executables and Libraries (Excludes PDB debug symbols & build artifacts)
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs; Excludes: "*.pdb,*.obj,*.iobj,*.ipdb,*.exp,*.lib,*.ilk"

; Environment config & CSV templates
Source: ".env"; DestDir: "{app}"; Flags: ignoreversion skipifsourcedoesntexist
Source: "bulk_booking_template.csv"; DestDir: "{app}"; Flags: ignoreversion skipifsourcedoesntexist

; High-Resolution App Icon
Source: "windows\runner\resources\app_icon.ico"; DestDir: "{app}"; Flags: ignoreversion

; Node.js WhatsApp Engine (Deeply pruned: excludes caches, docs, typescript, tests, and source maps for compact size)
Source: "whatsapp_engine\*"; DestDir: "{app}\whatsapp_engine"; Flags: ignoreversion recursesubdirs createallsubdirs; Excludes: "whatsapp_session\*,app_session\*,*.log,node_modules\.cache\*,scratch_*,*.md,*.markdown,*.map,*.ts,*.d.ts,*.flow,*.nycrc,test\*,tests\*,example\*,examples\*,docs\*,doc\*,.git\*,.github\*,node_modules\**\*.md,node_modules\**\*.markdown,node_modules\**\*.map,node_modules\**\*.ts,node_modules\**\*.d.ts,node_modules\**\test\*,node_modules\**\tests\*,node_modules\**\example\*,node_modules\**\examples\*,node_modules\**\docs\*,node_modules\**\doc\*,node_modules\**\.github\*"

; Python Scripts (PDF Sambad Parser)
Source: "scripts\*"; DestDir: "{app}\scripts"; Flags: ignoreversion recursesubdirs createallsubdirs skipifsourcedoesntexist; Excludes: "__pycache__\*,*.pyc"

; Background Engine Launcher Scripts
Source: "start_whatsapp_server.bat"; DestDir: "{app}"; Flags: ignoreversion
Source: "start_whatsapp_server_silent.vbs"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; IconFilename: "{app}\app_icon.ico"
Name: "{group}\Start WhatsApp Engine Server"; Filename: "{app}\start_whatsapp_server.bat"; WorkingDir: "{app}"; IconFilename: "{app}\app_icon.ico"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"

Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; Tasks: desktopicon; IconFilename: "{app}\app_icon.ico"
Name: "{userstartup}\OpsCore Pro WhatsApp Server"; Filename: "{app}\start_whatsapp_server_silent.vbs"; WorkingDir: "{app}"; Tasks: autostart

[Dirs]
Name: "{app}"; Permissions: users-full
Name: "{app}\whatsapp_engine"; Permissions: users-full
Name: "{localappdata}\OpsCore_Pro"; Permissions: users-full
Name: "C:\Lottery_Reports"; Permissions: users-full

[Run]
; Silently install Microsoft VC++ Redistributable if missing on Windows 7/10/11 target machine
Filename: "{tmp}\vc_redist.x64.exe"; Parameters: "/install /quiet /norestart"; Flags: waituntilterminated; StatusMsg: "Configuring Microsoft Visual C++ Runtime (Required for Windows 7/10/11)..."; Check: NeedsVCRedist
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

[Code]
function NeedsVCRedist: Boolean;
var
  installed: Cardinal;
begin
  // Check if VC++ 2015-2022 (v14.x) runtime is already installed in 64-bit registry
  if RegQueryDWordValue(HKLM64, 'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64', 'Installed', installed) and (installed = 1) then
  begin
    Result := False;
  end
  else if RegQueryDWordValue(HKLM, 'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64', 'Installed', installed) and (installed = 1) then
  begin
    Result := False;
  end
  else
  begin
    Result := True;
  end;
end;
