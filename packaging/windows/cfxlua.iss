#define MyAppName "CfxLua"
#define MyAppVersion GetEnv("CFXLUA_VERSION")
#define MyAppPublisher "Polaris Naz"
#define MyAppURL "https://github.com/immapolar/CfxLua"
#define MyAppExeName "cfxlua.cmd"

[Setup]
AppId={{A5DA4E4E-D8F9-44DC-B1D8-4FE4749A0D61}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\CfxLua
DisableProgramGroupPage=yes
OutputDir=..\..\dist
OutputBaseFilename=cfxlua-{#MyAppVersion}-windows-x64
Compression=lzma
SolidCompression=yes
WizardStyle=modern
ChangesEnvironment=yes
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "addtopath"; Description: "Add CfxLua to PATH"; GroupDescription: "Additional tasks:"; Flags: checkedonce

[Files]
Source: "..\..\dist\windows\*"; DestDir: "{app}"; Flags: recursesubdirs ignoreversion createallsubdirs

[Icons]
Name: "{autoprograms}\CfxLua"; Filename: "{app}\bin\cfxlua.cmd"

[Run]
Filename: "{cmd}"; Parameters: "/c ""{app}\bin\cfxlua.cmd"" --version"; Flags: nowait postinstall skipifsilent

[Code]
function EnvRootKey: Integer;
begin
  if IsAdminInstallMode then
    Result := HKEY_LOCAL_MACHINE
  else
    Result := HKEY_CURRENT_USER;
end;

function EnvSubKey: string;
begin
  if IsAdminInstallMode then
    Result := 'SYSTEM\CurrentControlSet\Control\Session Manager\Environment'
  else
    Result := 'Environment';
end;

function GetPathValue(var Paths: string): Boolean;
begin
  Result := RegQueryStringValue(EnvRootKey, EnvSubKey, 'Path', Paths);
  if not Result then
    Paths := '';
end;

function PathContains(Paths: string; Dir: string): Boolean;
begin
  Result := Pos(';' + Uppercase(Dir) + ';', ';' + Uppercase(Paths) + ';') > 0;
end;

procedure AddPathEntry(Dir: string);
var
  Paths: string;
begin
  GetPathValue(Paths);
  if PathContains(Paths, Dir) then
    Exit;

  if (Paths <> '') and (Copy(Paths, Length(Paths), 1) <> ';') then
    Paths := Paths + ';';

  Paths := Paths + Dir;
  RegWriteExpandStringValue(EnvRootKey, EnvSubKey, 'Path', Paths);
end;

procedure RemovePathEntry(Dir: string);
var
  Paths: string;
  NewPaths: string;
  Token: string;
  SepPos: Integer;
begin
  if not GetPathValue(Paths) then
    Exit;

  NewPaths := '';
  while Paths <> '' do
  begin
    SepPos := Pos(';', Paths);
    if SepPos > 0 then
    begin
      Token := Copy(Paths, 1, SepPos - 1);
      Delete(Paths, 1, SepPos);
    end
    else
    begin
      Token := Paths;
      Paths := '';
    end;

    if (Token <> '') and (CompareText(Token, Dir) <> 0) then
    begin
      if NewPaths <> '' then
        NewPaths := NewPaths + ';';
      NewPaths := NewPaths + Token;
    end;
  end;

  RegWriteExpandStringValue(EnvRootKey, EnvSubKey, 'Path', NewPaths);
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  BinDir: string;
begin
  if (CurStep = ssPostInstall) and WizardIsTaskSelected('addtopath') then
  begin
    BinDir := ExpandConstant('{app}\bin');
    AddPathEntry(BinDir);
    Log('PATH updated with: ' + BinDir);
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  BinDir: string;
begin
  if CurUninstallStep = usUninstall then
  begin
    BinDir := ExpandConstant('{app}\bin');
    RemovePathEntry(BinDir);
    Log('PATH removed: ' + BinDir);
  end;
end;
