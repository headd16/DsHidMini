#define ProductVersion "0.1.2"

[Setup]
AppId={{134C5FB3-28AB-4336-A640-5661C826CE25}
AppName=Dual Controller (PS3 + PS4) — Experimental
AppVersion={#ProductVersion}
AppPublisher=headd16 community fork
AppPublisherURL=https://github.com/headd16/DsHidMini
DefaultDirName={autopf}\DualController
DefaultGroupName=Dual Controller
OutputDir=..\artifacts\installer
OutputBaseFilename=DualController-Setup-{#ProductVersion}-x64
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.17763
PrivilegesRequired=admin
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
LicenseFile=..\THIRD-PARTY-NOTICES.txt
InfoBeforeFile=..\INSTALL.txt
UninstallDisplayIcon={app}\DualController.exe
CloseApplications=yes
RestartApplications=no
SetupLogging=yes

[Types]
Name: "full"; Description: "PS3 + PS4, USB and Bluetooth"
Name: "ps4"; Description: "PS4 bridge only (USB and Bluetooth)"
Name: "custom"; Description: "Choose components"; Flags: iscustom

[Components]
Name: "bridge"; Description: "PS4 Xbox input bridge and signed ViGEmBus driver"; Types: full ps4 custom; Flags: fixed
Name: "ps3"; Description: "PS3: signed DsHidMini driver, ControlApp and .NET 10 Desktop Runtime"; Types: full; Flags: checkablealone
Name: "ps3\bluetooth"; Description: "PS3 Bluetooth: signed BthPS3 drivers"; Types: full

[Tasks]
Name: "startup"; Description: "Start the PS4 bridge when I sign in to Windows"; Flags: unchecked
Name: "desktopicon"; Description: "Create a desktop shortcut"; Flags: unchecked

[Files]
Source: "..\artifacts\app\DualController.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\README.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\INSTALL.txt"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\THIRD-PARTY-NOTICES.txt"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\*-LICENSE.txt"; DestDir: "{app}\licenses"; Flags: ignoreversion
Source: "..\DOTNET-THIRD-PARTY-NOTICES.txt"; DestDir: "{app}\licenses"; Flags: ignoreversion
Source: "..\artifacts\dependencies\verified-dependencies.json"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\artifacts\dependencies\ViGEmBus.exe"; Flags: dontcopy
Source: "..\artifacts\dependencies\DesktopRuntime.exe"; Flags: dontcopy
Source: "..\artifacts\dependencies\Nefarius_DsHidMini_Drivers_x64_arm64_v3.17.1.msi"; Flags: dontcopy
Source: "..\artifacts\dependencies\Nefarius_BthPS3_Drivers_x64_arm64_v3.2.0.msi"; Flags: dontcopy

[Icons]
Name: "{group}\Dual Controller"; Filename: "{app}\DualController.exe"
Name: "{group}\Controller instructions"; Filename: "{app}\INSTALL.txt"
Name: "{group}\Uninstall Dual Controller"; Filename: "{uninstallexe}"
Name: "{autodesktop}\Dual Controller"; Filename: "{app}\DualController.exe"; Tasks: desktopicon

[Registry]
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "DualController"; ValueData: """{app}\DualController.exe"" --tray"; Flags: uninsdeletevalue; Tasks: startup

[Run]
Filename: "{app}\DualController.exe"; Description: "Open Dual Controller"; Flags: nowait postinstall skipifsilent runasoriginaluser
Filename: "{app}\INSTALL.txt"; Description: "Read PS3 and PS4 connection steps"; Flags: shellexec postinstall skipifsilent runasoriginaluser

[Code]
var
  DependencyRestart: Boolean;
  DependencyLogDir: String;

function EnsureDependencyLogs(): Boolean;
begin
  if DependencyLogDir = '' then
    DependencyLogDir := ExpandConstant('{commonappdata}\DualController\InstallerLogs\') +
      GetDateTimeString('yyyymmdd-hhnnss', '-', ':');
  Result := ForceDirectories(DependencyLogDir);
  if Result then Log('Permanent dependency logs: ' + DependencyLogDir);
end;

procedure WriteDependencyStatus(Name, Status: String);
var
  Lines: TArrayOfString;
begin
  SetArrayLength(Lines, 4);
  Lines[0] := 'Dual Controller {#ProductVersion}';
  Lines[1] := GetDateTimeString('yyyy-mm-dd hh:nn:ss', '-', ':');
  Lines[2] := Name;
  Lines[3] := Status;
  SaveStringsToUTF8File(DependencyLogDir + '\summary.txt', Lines, True);
  Log(Name + ': ' + Status);
end;

function RunDependency(Name, Parameters: String; Msi: Boolean): String;
var
  ProgramPath, Arguments, LogPath, BinaryPath, CacheDir, LegacyName: String;
  ExitCode: Integer;
  Started: Boolean;
begin
  Result := '';
  if not EnsureDependencyLogs() then begin
    Result := 'Could not create the installer log folder: ' + DependencyLogDir;
    Exit;
  end;
  LogPath := DependencyLogDir + '\' + Name + '.log';
  ExtractTemporaryFile(Name);
  BinaryPath := ExpandConstant('{tmp}\' + Name);
  if Msi then begin
    // Windows Installer remembers the source filename. Preserve the upstream
    // filename and retain aliases used by older Dual Controller builds so
    // SecureRepair can find the same signed package in either case.
    CacheDir := ExpandConstant('{commonappdata}\DualController\PackageCache\') +
      GetSHA256OfFile(BinaryPath);
    if not ForceDirectories(CacheDir) then begin
      Result := 'Could not create the MSI source folder: ' + CacheDir;
      Exit;
    end;
    if not FileCopy(BinaryPath, CacheDir + '\' + Name, False) then begin
      Result := 'Could not retain the MSI source: ' + CacheDir + '\' + Name;
      Exit;
    end;
    LegacyName := '';
    if Name = 'Nefarius_DsHidMini_Drivers_x64_arm64_v3.17.1.msi' then
      LegacyName := 'DsHidMini.msi'
    else if Name = 'Nefarius_BthPS3_Drivers_x64_arm64_v3.2.0.msi' then
      LegacyName := 'BthPS3.msi';
    if LegacyName <> '' then begin
      if not FileCopy(BinaryPath, CacheDir + '\' + LegacyName, False) then begin
        Result := 'Could not retain the previous MSI source name: ' + CacheDir + '\' + LegacyName;
        Exit;
      end;
    end;
    BinaryPath := CacheDir + '\' + Name;
    WriteDependencyStatus(Name, 'Retained signed MSI source: ' + BinaryPath);
    ProgramPath := ExpandConstant('{sys}\msiexec.exe');
    Arguments := '/i "' + BinaryPath +
      '" /passive /norestart /l*vx! "' + LogPath + '"';
  end else begin
    ProgramPath := BinaryPath;
    if Name = 'ViGEmBus.exe' then
      Arguments := Parameters + ' /L*V! "' + LogPath + '"'
    else
      Arguments := Parameters + ' /log "' + LogPath + '"';
  end;
  WizardForm.StatusLabel.Caption := 'Installing ' + Name + '...';
  WriteDependencyStatus(Name, 'Starting. Log: ' + LogPath);
  if Msi then
    Started := ExecWithNativeSysDir(ProgramPath, Arguments, '', SW_SHOW,
      ewWaitUntilTerminated, ExitCode)
  else
    Started := Exec(ProgramPath, Arguments, '', SW_SHOW, ewWaitUntilTerminated, ExitCode);
  if not Started then
    Result := 'Could not start ' + Name + '. ' + SysErrorMessage(ExitCode)
  else if (ExitCode = 3010) or (ExitCode = 1641) then DependencyRestart := True
  else if ExitCode <> 0 then begin
    Result := Name + ' failed with exit code ' + IntToStr(ExitCode) + '.';
    if ExitCode = 1618 then
      Result := Result + ' Another Windows installation is running. Let it finish and retry.'
    else if ExitCode = 1603 then
      Result := Result + ' Windows Installer reported a fatal error; the log is required to identify its cause.';
  end;
  WriteDependencyStatus(Name, 'Exit code: ' + IntToStr(ExitCode));
  if Result <> '' then begin
    Result := Result + #13#10#13#10 + 'Logs are saved permanently at:' + #13#10 +
      DependencyLogDir + #13#10#13#10 + 'Attach ' + Name + '.log and summary.txt when reporting this error.';
    Log(Result);
  end;
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  Result := '';
  if WizardIsComponentSelected('ps3') then begin
    Result := RunDependency('DesktopRuntime.exe', '/install /quiet /norestart', False);
    if Result <> '' then Exit;
    Result := RunDependency('Nefarius_DsHidMini_Drivers_x64_arm64_v3.17.1.msi', '', True);
    if Result <> '' then Exit;
    if WizardIsComponentSelected('ps3\bluetooth') then begin
      Result := RunDependency('Nefarius_BthPS3_Drivers_x64_arm64_v3.2.0.msi', '', True);
      if Result <> '' then Exit;
    end;
  end;
  Result := RunDependency('ViGEmBus.exe', '/exenoui /qn /norestart', False);
end;

function NeedRestart(): Boolean;
begin
  Result := DependencyRestart;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usPostUninstall then
    MsgBox('Dual Controller has been removed. Shared DsHidMini, BthPS3, ViGEmBus and .NET components remain installed. Remove them individually from Windows Apps if you no longer use them.', mbInformation, MB_OK);
end;
