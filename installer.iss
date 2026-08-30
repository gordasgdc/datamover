; Instalator Windows pentru DataMover, cu Inno Setup (gratuit,
; https://jrsoftware.org/isinfo.php). Aceeasi structura ca la
; gdc-plugin-manager-win/installer.iss — instaleaza in Program Files,
; creeaza scurtaturi in Start Menu (DataMover + DataMover Monitor),
; apare corect in "Apps & Features" cu dezinstalare curata. Inlocuieste
; distributia "portabila" veche (exe rulat direct din orice folder,
; niciodata instalat propriu-zis).
;
; Cum se compileaza (pe Windows, o data ai nevoie de Inno Setup
; Compiler instalat — gratuit, https://jrsoftware.org/isdl.php, sau
; `winget install JRSoftware.InnoSetup --source winget`):
;   1. Ruleaza pasii din .github/workflows/build-windows.yml local
;      (PyInstaller pentru DataMover.exe si "DataMover Monitor.exe",
;      rezultatele in dist_release\)
;   2. Compileaza acest fisier:
;      & "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe" installer.iss
;   3. Rezultatul apare in Output\DataMoverSetup.exe
;
; NU compila pe macOS/CI Mac — Inno Setup ruleaza doar pe Windows (spre
; deosebire de proiectul .NET al gdc-plugin-manager-win, care are
; EnableWindowsTargeting si poate fi verificat cu `dotnet build` de pe
; Mac; nu exista un echivalent pentru Inno Setup).

#define MyAppName "DataMover"
#define MyAppVersion "2.10.1"
#define MyAppPublisher "Cristi Gordas"
#define MyAppExeName "DataMover.exe"
#define MyAppMonitorExeName "DataMover Monitor.exe"
#define MyAppURL "https://gordas.dev/datamover"

[Setup]
AppId={{A4E1C3F0-2F0F-4B0E-9C1A-DATAMOVERSETUP1}}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\DataMover
DefaultGroupName=DataMover
DisableProgramGroupPage=yes
OutputDir=Output
OutputBaseFilename=DataMoverSetup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; Nu semnat cu certificat platit (acelasi caz ca .pkg-urile de pe Mac,
; nesemnate) — Windows SmartScreen va arata un avertisment "Unrecognized
; app" la prima rulare a instalatorului. Normal pentru distributie indie,
; se trece cu "More info" -> "Run anyway".
UninstallDisplayIcon={app}\{#MyAppExeName}

[Languages]
; Doar engleza - "Romanian.isl" e un add-on separat, neinclus in
; instalarea de baza a Inno Setup (vezi gdc-plugin-manager-win/installer.iss
; pentru bug-ul exact intalnit). Aplicatia in sine ramane RO/EN/ES.
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "dist_release\DataMover.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "dist_release\DataMover Monitor.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "docs\guides\DataMover_Ghid_RO.pdf"; DestDir: "{app}\Ghiduri"; Flags: ignoreversion
Source: "docs\guides\DataMover_Guide_EN.pdf"; DestDir: "{app}\Ghiduri"; Flags: ignoreversion
Source: "docs\guides\DataMover_Guia_ES.pdf"; DestDir: "{app}\Ghiduri"; Flags: ignoreversion

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\DataMover Monitor"; Filename: "{app}\{#MyAppMonitorExeName}"
Name: "{group}\Dezinstaleaza {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#MyAppName}}"; Flags: nowait postinstall skipifsilent
