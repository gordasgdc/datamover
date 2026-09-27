; Instalator Windows pentru clientul WPF NOU al DataMover (2026-08-28),
; separat de installer.iss din radacina repo-ului (acela ramane pentru
; clientul Python/PyInstaller vechi - cei doi clienti coexista, vezi
; CLAUDE.md etapa "Client Windows nou, WPF + Wpf.Ui").
;
; Regula 19 (CLAUDE.md, Consent Gate) - LicenseFile de mai jos e
; OBLIGATORIU pentru orice installer.iss NOU, nu opt-in: Inno Setup arata
; nativ o pagina cu "I accept"/"I do not accept", butonul Next dezactivat
; pana la acceptare explicita.
;
; Compilare MANUALA (pe Windows, Inno Setup Compiler instalat):
;   1. dotnet publish DataMover.Client -c Release -r win-x64 --self-contained -o publish
;   2. Deschide acest fisier cu Inno Setup Compiler, Compile (F9)
;   3. Rezultatul apare in Output\DataMoverSetup.exe
; CI-ul (.github/workflows/build-windows-wpf.yml) face toti pasii automat.

#define MyAppName "DataMover"
#define MyAppVersion "2.17.1"
#define MyAppPublisher "Cristi Gordas"
#define MyAppExeName "DataMover.exe"
#define MyAppURL "https://gordas.dev/datamover"

[Setup]
AppId={{B7F2E4D5-9A1C-4F3B-8E2D-DATAMOVERWPF1}}
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
SetupIconFile=DataMover.Client\app.ico
LicenseFile=License.txt
; Nu semnat cu certificat platit - Windows SmartScreen arata un
; avertisment "Unrecognized app" la prima rulare, normal pentru
; distributie indie (acelasi caz ca installer.iss-ul vechi).
UninstallDisplayIcon={app}\{#MyAppExeName}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "publish\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\Dezinstaleaza {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
; "nowait postinstall skipifsilent" relanseaza aplicatia dupa instalare -
; folosit si de Self-Updater (SelfUpdater.cs va trece la reteta
; "descarca .exe si lanseaza-l" dupa acest installer, in loc de swap
; manual de exe - vezi TODO in CLAUDE.md).
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#MyAppName}}"; Flags: nowait postinstall skipifsilent

; REGULA PERMANENTA de Clean Uninstall - trebuie sa stearga TOT ce scrie
; aplicatia (LicenseManager/UserProfileStore/TransferProfileStore/
; HistoryStore, toate in %LocalAppData%\DataMover si %AppData%\DataMover).
[UninstallDelete]
Type: filesandordirs; Name: "{localappdata}\DataMover"
Type: filesandordirs; Name: "{userappdata}\DataMover"
; Jurnalele si exporturile de diagnostic (StructuredLog/DiagnosticExporter).
; Doar subfolderul DataMover; "GDC" se sterge numai daca a ramas gol, ca sa
; nu atinga datele altor produse GDC.
Type: filesandordirs; Name: "{localappdata}\GDC\DataMover"
Type: dirifempty; Name: "{localappdata}\GDC"

[Code]
// Dupa dezinstalare, Windows poate lasa goale folderele de resurse (ex. "es")
// cat timp un alt proces (antivirus, indexare) tine scurt un fisier din ele.
// RemoveDir sterge DOAR foldere goale, deci nu poate atinge alte fisiere;
// se reincearca cateva secunde.
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  App: String;
  I: Integer;
begin
  if CurUninstallStep = usPostUninstall then
  begin
    App := ExpandConstant('{app}');
    for I := 1 to 10 do
    begin
      RemoveDir(App + '\es');
      RemoveDir(App);
      if not DirExists(App) then Break;
      Sleep(500);
    end;
  end;
end;
