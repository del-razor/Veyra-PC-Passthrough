#ifndef PayloadList
  #error Build this installer with scripts/passthrough/repack.py.
#endif

#define DisplayName "OverRez (" + Flavor + ")"
#define InstallId "OverRez.Win64." + Flavor

[Setup]
AppId={#InstallId}
AppName={#DisplayName}
AppVersion={#AppVersion}
AppPublisher=OverRez
DefaultDirName={localappdata}\Programs\{#DisplayName}
DefaultGroupName={#DisplayName}
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
SetupArchitecture=x64
MinVersion=10.0.19041
SetupMutex=OverRez.Windows.Setup
DisableWelcomePage=no
DisableDirPage=no
DisableProgramGroupPage=yes
UsePreviousTasks=yes
AllowRootDirectory=no
CloseApplications=no
RestartApplications=no
UninstallDisplayName={#DisplayName}
UninstallDisplayIcon={app}\OverRez.exe
UninstallFilesDir={app}
SetupIconFile={#AppIcon}
WizardStyle=modern dark hidebevels
WizardBackImageFile={#BrandBackground}
WizardBackColor=#100E1D
WizardImageFile={#BrandPanel}
WizardImageBackColor=#161425
WizardSmallImageFile={#BrandIcon}
WizardSmallImageBackColor=#161425
WizardSizePercent=118,112
Compression=lzma2/fast
SolidCompression=yes
LZMANumBlockThreads=1
OutputDir={#OutputDir}
OutputBaseFilename=OverRez-{#AppVersion}-{#Flavor}-win64-setup
VersionInfoVersion={#AppVersion}.0
VersionInfoProductName=OverRez
VersionInfoDescription=OverRez Setup ({#Flavor})
VersionInfoCompany=OverRez
#ifdef PublisherSigning
SignTool=publisher
SignedUninstaller=yes
SignedUninstallerDir={#OutputDir}
#endif

[Languages]
Name: "en"; MessagesFile: "compiler:Default.isl"

[CustomMessages]
en.CloseOverRez=Close the OverRez instance in this folder and try again.
en.SeparateFolder=Select a folder without another OverRez installation or portable copy.
en.AlreadyInstalled=This edition is already installed at %1. Use that location, or uninstall it before choosing another.
en.UnsafeFolder=Select a local folder without symbolic links or junctions in its path.
en.VersionWriteFailed=OverRez could not save the active version. Check that the installation folder is writable.
en.InstalledVersion=The active installation already has a newer version of OverRez.

[Messages]
en.WelcomeLabel2=Beyond Ultra.%n%nThis will install OverRez {#AppVersion} for your Windows account.%n%nYou can choose an installation folder and whether to add a desktop shortcut.

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
#include PayloadList

[Icons]
Name: "{group}\OverRez"; Filename: "{app}\OverRez.exe"; WorkingDir: "{app}"
Name: "{group}\{cm:UninstallProgram,OverRez}"; Filename: "{uninstallexe}"
Name: "{userdesktop}\{#DisplayName}"; Filename: "{app}\OverRez.exe"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\OverRez.exe"; Description: "{cm:LaunchProgram,OverRez}"; WorkingDir: "{app}"; Flags: nowait postinstall skipifsilent unchecked

[Code]
const
  UninstallKey = 'Software\Microsoft\Windows\CurrentVersion\Uninstall\{#InstallId}_is1';
  ReparsePoint = $400;
  MoveReplaceExisting = $1;
  MoveWriteThrough = $8;
  InstalledMarker = 'overrez-installation.txt';
var
  PreviousVersion: String;
  ManagedInstall: Boolean;

function GetFileAttributes(Name: String): LongWord;
  external 'GetFileAttributesW@kernel32.dll stdcall';
function MoveFileEx(ExistingFile, NewFile: String; Flags: LongWord): Boolean;
  external 'MoveFileExW@kernel32.dll stdcall';

function LocalPath(const Path: String): String;
begin
  Result := Path;
  if Copy(Path, 1, 4) = '\\?\' then
    Delete(Result, 1, 4);
end;

function PlainPath(Path: String): Boolean;
var
  Parent: String;
  Attributes: LongWord;
begin
  Result := False;
  Path := LocalPath(Path);
  if Length(Path) < 3 then
    Exit;
  if (Path[2] <> ':') or (Path[3] <> '\') then
    Exit;
  repeat
    Attributes := GetFileAttributes(Path);
    if (Attributes <> $FFFFFFFF) and ((Attributes and ReparsePoint) <> 0) then
      Exit;
    Parent := ExtractFileDir(Path);
    if (Parent = '') or (CompareText(Parent, Path) = 0) then
      Break;
    Path := Parent;
  until False;
  Result := True;
end;

function SameFolder(Left, Right: String): Boolean;
begin
  Result := CompareText(RemoveBackslashUnlessRoot(LocalPath(Left)),
                        RemoveBackslashUnlessRoot(LocalPath(Right))) = 0;
end;

function HasOwnedMarker(const Root: String): Boolean;
var
  Data: AnsiString;
begin
  Result := LoadStringFromFile(AddBackslash(Root) + InstalledMarker, Data) and
            (Data = '{#InstallId}');
end;

function OverRezIsRunning(const Root: String): Boolean;
var
  LockFile: String;
  Data: AnsiString;
begin
  LockFile := AddBackslash(Root) + '.overrez-running.lock';
  Result := FileExists(LockFile) and not LoadStringFromFile(LockFile, Data);
end;

function DestinationError(const Root: String): String;
var
  Registered, Folder: String;
  OwnsFolder: Boolean;
begin
  Result := CustomMessage('UnsafeFolder');
  if not (PlainPath(Root) and PlainPath(AddBackslash(Root) + 'versions') and
     PlainPath(AddBackslash(Root) + 'versions\{#AppVersion}') and
     PlainPath(AddBackslash(Root) + '.overrez-update') and
     PlainPath(AddBackslash(Root) + 'current-version.txt') and
     PlainPath(AddBackslash(Root) + 'current-version.txt.new')) then
    Exit;
  OwnsFolder := RegQueryStringValue(HKCU64, UninstallKey, 'InstallLocation', Registered) and
                (Registered <> '') and DirExists(Registered);
  if OwnsFolder and not SameFolder(Root, Registered) then begin
    Result := FmtMessage(CustomMessage('AlreadyInstalled'), [Registered]);
    Exit;
  end;
  Folder := AddBackslash(Root);
  if (not OwnsFolder or not HasOwnedMarker(Root)) and
     (FileExists(Folder + 'OverRez.exe') or FileExists(Folder + 'OverRezApp.exe') or
      FileExists(Folder + 'portable-package.txt') or FileExists(Folder + 'current-version.txt') or
      FileExists(Folder + InstalledMarker) or DirExists(Folder + 'versions') or
      DirExists(Folder + '.overrez-update')) then begin
    Result := CustomMessage('SeparateFolder');
    Exit;
  end;
  if OverRezIsRunning(Root) then begin
    Result := CustomMessage('CloseOverRez');
    Exit;
  end;
  Result := '';
end;

function NextButtonClick(CurPageID: Integer): Boolean;
var
  Problem: String;
begin
  Result := True;
  if CurPageID <> wpSelectDir then
    Exit;
  Problem := DestinationError(WizardDirValue);
  if Problem <> '' then begin
    SuppressibleMsgBox(Problem, mbError, MB_OK, IDOK);
    Result := False;
  end;
end;

function PreviousInstalledVersion(const Root: String; var FolderName: String): String;
var
  Data: AnsiString;
  FirstLineEnd, Dash, I: Integer;
  BuildNumber: Int64;
begin
  Result := '';
  FolderName := '';
  if not LoadStringFromFile(AddBackslash(Root) + 'current-version.txt', Data) then
    Exit;
  FirstLineEnd := Pos(#10, Data);
  if (FirstLineEnd <= 1) or (FirstLineEnd > 32) then
    Exit;
  FolderName := Copy(Data, 1, FirstLineEnd - 1);
  for I := 1 to Length(FolderName) do
    if Pos(FolderName[I], '0123456789.-abcdef') = 0 then begin
      FolderName := '';
      Exit;
    end;
  Dash := Pos('-', FolderName);
  if Dash = 0 then
    Result := FolderName
  else
    Result := Copy(FolderName, 1, Dash - 1);
  if not StrToVersion(Result + '.0', BuildNumber) or
     not FileExists(AddBackslash(Root) + 'versions\' + FolderName + '\OverRezApp.exe') then begin
    Result := '';
    FolderName := '';
  end;
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  VersionText: String;
  Current, Incoming: Int64;
begin
  Result := DestinationError(WizardDirValue);
  if Result <> '' then
    Exit;
  VersionText := PreviousInstalledVersion(WizardDirValue, PreviousVersion);
  if (VersionText <> '') and StrToVersion(VersionText + '.0', Current) and
     StrToVersion('{#AppVersion}.0', Incoming) and (ComparePackedVersion(Current, Incoming) > 0) then
    Result := CustomMessage('InstalledVersion');
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  StateFile, NewFile: String;
begin
  if CurStep <> ssPostInstall then
    Exit;
  if PreviousVersion = '{#AppVersion}' then
    Exit;
  StateFile := ExpandConstant('{app}\current-version.txt');
  NewFile := StateFile + '.new';
  if not SaveStringToFile(NewFile, '{#AppVersion}' + #10 + PreviousVersion + #10, False) or
     not MoveFileEx(NewFile, StateFile, MoveReplaceExisting or MoveWriteThrough) then
    RaiseException(CustomMessage('VersionWriteFailed'));
end;

function InitializeUninstall: Boolean;
var
  Root, Registered: String;
begin
  Root := LocalPath(ExpandConstant('{app}'));
  Result := PlainPath(Root) and PlainPath(Root + '\versions') and PlainPath(Root + '\versions\{#AppVersion}');
  if not Result then begin
    SuppressibleMsgBox(CustomMessage('UnsafeFolder'), mbError, MB_OK, IDOK);
    Exit;
  end;
  ManagedInstall := HasOwnedMarker(Root) and
    RegQueryStringValue(HKCU64, UninstallKey, 'InstallLocation', Registered) and
    SameFolder(Root, Registered);
  Result := not OverRezIsRunning(Root);
  if not Result then
    SuppressibleMsgBox(CustomMessage('CloseOverRez'), mbError, MB_OK, IDOK);
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  Root: String;
begin
  if (CurUninstallStep <> usPostUninstall) or not ManagedInstall then
    Exit;
  Root := LocalPath(ExpandConstant('{app}'));
  if not PlainPath(Root) then
    Exit;
  Log('Removing managed application versions and update cache.');
  DeleteFile(Root + '\current-version.txt');
  DeleteFile(Root + '\current-version.txt.new');
  DeleteFile(Root + '\.overrez-running.lock');
  DelTree(Root + '\versions', True, True, True);
  DelTree(Root + '\.overrez-update', True, True, True);
  RemoveDir(Root);
end;
