#ifndef AppVersion
  #error AppVersion must be provided with /DAppVersion=x.y.z
#endif
#ifndef SourceDir
  #error SourceDir must be provided with /DSourceDir=path
#endif
#ifndef OutputDir
  #error OutputDir must be provided with /DOutputDir=path
#endif

#define AppPublisher "NEXT"
#define AppExeName "PanelVR.exe"
#define FirewallRuleName "Panel VR"

[Setup]
AppId={{341A0DD0-9AF9-42E7-A828-6D9B1D0E44F6}
AppName=Panel VR
AppVersion={#AppVersion}
AppVerName=Panel VR {#AppVersion}
AppPublisher={#AppPublisher}
VersionInfoVersion={#AppVersion}
VersionInfoCompany={#AppPublisher}
VersionInfoDescription=Panel VR installer
VersionInfoProductName=Panel VR
VersionInfoProductVersion={#AppVersion}
DefaultDirName={autopf}\NEXT\Panel VR
DefaultGroupName=Panel VR
UninstallDisplayName=Panel VR
UninstallDisplayIcon={app}\{#AppExeName}
OutputDir={#OutputDir}
OutputBaseFilename=PanelVR-Setup-{#AppVersion}-win-x64
ArchitecturesAllowed=x64os
ArchitecturesInstallIn64BitMode=x64os
MinVersion=10.0
PrivilegesRequired=admin
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
DisableProgramGroupPage=yes
CloseApplications=yes
CloseApplicationsFilter={#AppExeName}
RestartApplications=no
SetupLogging=yes

[Languages]
Name: "polish"; MessagesFile: "compiler:Languages\Polish.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Utwórz skrót na pulpicie"; GroupDescription: "Dodatkowe skróty:"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "README_PL.txt"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\Panel VR"; Filename: "{app}\{#AppExeName}"; WorkingDir: "{app}"
Name: "{autodesktop}\Panel VR"; Filename: "{app}\{#AppExeName}"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall delete rule name=""{#FirewallRuleName}"" program=""{app}\{#AppExeName}"""; Flags: runhidden waituntilterminated
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall add rule name=""{#FirewallRuleName}"" dir=in action=allow program=""{app}\{#AppExeName}"" enable=yes profile=private"; Flags: runhidden waituntilterminated
Filename: "{app}\{#AppExeName}"; Description: "Uruchom Panel VR"; WorkingDir: "{app}"; Flags: nowait postinstall skipifsilent

[UninstallRun]
Filename: "{cmd}"; Parameters: "/C taskkill /F /IM {#AppExeName} >nul 2>&1"; Flags: runhidden waituntilterminated; RunOnceId: "StopPanelVR"
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall delete rule name=""{#FirewallRuleName}"" program=""{app}\{#AppExeName}"""; Flags: runhidden waituntilterminated; RunOnceId: "RemovePanelVRFirewallRule"
