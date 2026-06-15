; Inno Setup script for GitOpen on Windows.
; Built in CI by `iscc gitopen.iss` after `flutter build windows --release`.
; Pass /DAppVersion=x.y.z on the command line to embed a version.

#ifndef AppVersion
  #define AppVersion "0.1.0"
#endif

[Setup]
AppId={{A2D8F37C-2D31-4F3D-99A1-7D8B6C7E2A11}
AppName=GitOpen
AppVersion={#AppVersion}
AppPublisher=s.porta & zN3utr4l
AppPublisherURL=https://github.com/zN3utr4l/GitOpen
DefaultDirName={autopf}\GitOpen
DefaultGroupName=GitOpen
DisableProgramGroupPage=yes
UninstallDisplayIcon={app}\gitopen.exe
OutputDir=..\..\build\installer
OutputBaseFilename=GitOpen-Setup-{#AppVersion}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; No admin install -- writes to user-scoped Program Files when possible,
; so a normal user can install without elevation.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
; Inno Setup requires a .ico for SetupIconFile; assets ship only a .png,
; so we leave the default installer icon for now. Add a .ico under
; assets/icon/ later and set SetupIconFile= to embed a custom one.

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; \
  GroupDescription: "Additional shortcuts:"; Flags: unchecked

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; \
  Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\GitOpen"; Filename: "{app}\gitopen.exe"
Name: "{group}\Uninstall GitOpen"; Filename: "{uninstallexe}"
Name: "{userdesktop}\GitOpen"; Filename: "{app}\gitopen.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\gitopen.exe"; Description: "Launch GitOpen"; \
  Flags: nowait postinstall skipifsilent
