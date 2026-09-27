; ============================================================================
; wampstack.iss -- Inno Setup script for the wampstack GUI installer.
;
; Build it (on Windows, or via Wine on Linux -- see notes below):
;   ISCC.exe wampstack.iss
; Expects the fully-assembled "wampstack" folder (the same one build.sh
; already produces before zipping) to sit next to this .iss file.
; ============================================================================

#define MyAppName "WAMPstack"
#define MyAppVersion "1.0"
#define SourceDir "wampstack"

[Setup]
; This GUID identifies "the same product" across versions so Windows'
; Add/Remove Programs shows one entry that gets replaced, not duplicated.
; Generate your own once (Inno Setup IDE: Tools > Generate GUID) and never
; change it afterwards.
AppId={{B7E2B6B0-6C1E-4B7B-9C7D-4E9B7E1E9E10}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
DefaultDirName=C:\wampstack
DisableDirPage=no
DisableProgramGroupPage=yes
PrivilegesRequired=admin
ArchitecturesInstallIn64BitMode=x64compatible
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
OutputBaseFilename=wampstack-setup
OutputDir=.

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Code]
var
  LogMemo: TNewMemo;       // live output of install.bat on the installing page
  UninstMemo: TNewMemo;    // live output of uninstall.bat in the uninstaller
  CurMemo: TNewMemo;       // where the batch that is running right now writes

// Win32 API import, purely to scroll the memo to the bottom as new lines
   // come in -- Inno's own scripting doesn't expose a "scroll to end" method
   // on TNewMemo, but it does let you call arbitrary DLL functions like this.
function SendMessage(hWnd: Longint; Msg, wParam, lParam: Longint): Longint;
  external 'SendMessageA@user32.dll stdcall';
const
  WM_VSCROLL = $115;
  SB_BOTTOM = 7;

// A read-only log box underneath the progress bar of an "installing" page.
   // It starts out hidden: it is only shown while a batch file is running, so
   // the ordinary file-copy phase looks exactly like a stock Inno Setup install.
function CreateLogMemo(Owner: TComponent; Page: TWinControl;
  ALeft, ATop: Integer): TNewMemo;
var
  Memo: TNewMemo;
begin
  Memo := TNewMemo.Create(Owner);
  Memo.Parent := Page;
  Memo.Left := ALeft;
  Memo.Top := ATop;
  Memo.Width := Page.Width - ALeft - ScaleX(8);
  Memo.Height := Page.Height - ATop - ScaleY(8);
  Memo.ScrollBars := ssVertical;
  Memo.ReadOnly := True;
  Memo.Font.Name := 'Consolas';
  Memo.Font.Size := 8;
  Memo.Visible := False;
  Result := Memo;
end;

procedure MemoAdd(Memo: TNewMemo; const S: String);
begin
  Memo.Lines.Add(S);
  // Scroll down and paint right away. ExecAndLogOutput pumps the wizard's
     // message queue while it waits, so a line would appear by itself, but
     // forcing the repaint means the log is readable even if the next line
     // takes a while to come.
  SendMessage(Memo.Handle, WM_VSCROLL, SB_BOTTOM, 0);
  Memo.Refresh;
end;

// Called by ExecAndLogOutput for every line the running batch produces, while
   // it is still running.
procedure StreamOutput(const S: String; const Error, FirstLine: Boolean);
begin
  if Error then
    MemoAdd(CurMemo, '*** ' + S)
  else
    MemoAdd(CurMemo, S);

  Log(S);  // so the output ends up in the setup log too
end;

procedure InitializeWizard();
begin
  // Reuse Inno's own built-in "Installing" page instead of adding a new
     // wizard page: a new page would only become visible AFTER the file copy
     // and our batch runs already finished (they happen synchronously, driven
     // from CurStepChanged, while the built-in Installing page is showing) --
     // so the memo needs to live on that same page to actually be visible
     // while things are happening.
  LogMemo := CreateLogMemo(WizardForm, WizardForm.InstallingPage,
    WizardForm.StatusLabel.Left, WizardForm.ProgressGauge.Top +
    WizardForm.ProgressGauge.Height + ScaleY(12));
end;

// Runs a batch file and shows its output live.
procedure RunBatchLive(const BatchFile, StepLabel: String);
var
  ResultCode: Integer;
  Started: Boolean;
  ErrorMsg: String;
begin
  if not FileExists(BatchFile) then
  begin
    Log('Skipping ' + BatchFile + ': file not found');
    Exit;
  end;

  CurMemo := LogMemo;
  WizardForm.StatusLabel.Caption := StepLabel;
  LogMemo.Lines.Clear;
  LogMemo.Visible := True;

  ResultCode := 0;
  Started := False;
  ErrorMsg := '';
  try
    // ExecAndLogOutput sends the batch's output to StreamOutput line by line
       // and waits for it to finish, pumping the wizard's message queue all the
       // while -- so the log and the window keep up on their own. "nopause"
       // keeps the batch from sitting on its final "pause" waiting for a
       // keypress that will never come.
    try
      Started := ExecAndLogOutput(BatchFile, 'nopause', ExtractFileDir(BatchFile),
        SW_HIDE, ewWaitUntilTerminated, ResultCode, @StreamOutput);
    except
      ErrorMsg := GetExceptionMessage;
    end;

    if ErrorMsg <> '' then
      MemoAdd(LogMemo, 'Could not run ' + BatchFile + ': ' + ErrorMsg)
    else if not Started then
      MemoAdd(LogMemo, 'Could not run ' + BatchFile + ' (error ' +
        IntToStr(ResultCode) + ')')
    else if ResultCode <> 0 then
      MemoAdd(LogMemo, '*** ' + BatchFile + ' finished with exit code ' +
        IntToStr(ResultCode));
  finally
    // Hide the log again, so the file copy that follows (and the finished
       // page after that) look the way they normally do.
    LogMemo.Visible := False;
  end;
end;

// Files left behind by builds that ran the batches through a log file and a
   // sentinel file in the install directory.
procedure DeleteStaleRunFiles();
var
  AppDir: String;
begin
  AppDir := ExpandConstant('{app}');
  DeleteFile(AppDir + '\_wampstack_run.log');
  DeleteFile(AppDir + '\_wampstack_run.done');
  DeleteFile(AppDir + '\_wampstack_run.bat');
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  OldUninstall: String;
begin
  // ssInstall arrives just before the files are copied, so this is the last
     // moment at which the previous version's uninstall.bat is still there.
  if CurStep = ssInstall then
  begin
    DeleteStaleRunFiles;
    OldUninstall := ExpandConstant('{app}\uninstall.bat');
    if FileExists(OldUninstall) then
      RunBatchLive(OldUninstall, 'Removing the previous install...');
  end
  else if CurStep = ssPostInstall then
    RunBatchLive(ExpandConstant('{app}\install.bat'),
      'Setting up Apache, MariaDB and the certificate...');
end;

// The uninstaller has no output page of its own, so give it a log box in the
   // same spot on its own progress window.
procedure InitializeUninstallProgressForm();
var
  Form: TUninstallProgressForm;
begin
  Form := GetUninstallProgressForm;
  UninstMemo := CreateLogMemo(Form, Form.InstallingPage, Form.StatusLabel.Left,
    Form.ProgressBar.Top + Form.ProgressBar.Height + ScaleY(12));
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  WorkDir, BatchFile: String;
  ResultCode: Integer;
  Started: Boolean;
  ErrorMsg: String;
begin
  if CurUninstallStep <> usUninstall then
    Exit;

  WorkDir := ExpandConstant('{app}');
  BatchFile := WorkDir + '\uninstall.bat';
  if not FileExists(BatchFile) then
    Exit;

  CurMemo := UninstMemo;
  GetUninstallProgressForm.StatusLabel.Caption :=
    'Removing the Apache and MariaDB services...';
  UninstMemo.Lines.Clear;
  UninstMemo.Visible := True;

  ResultCode := 0;
  Started := False;
  ErrorMsg := '';
  try
    Started := ExecAndLogOutput(BatchFile, 'nopause', WorkDir, SW_HIDE,
      ewWaitUntilTerminated, ResultCode, @StreamOutput);
  except
    ErrorMsg := GetExceptionMessage;
  end;

  // Unlike during the install, the log stays on screen here: it is the record
     // of what the uninstaller did, and the uninstaller's own file-removal phase
     // follows anyway.
  if ErrorMsg <> '' then
    MemoAdd(UninstMemo, 'Could not run ' + BatchFile + ': ' + ErrorMsg)
  else if not Started then
    MemoAdd(UninstMemo, 'Could not run ' + BatchFile + ' (error ' +
      IntToStr(ResultCode) + ')')
  else if ResultCode <> 0 then
    MemoAdd(UninstMemo, '*** uninstall.bat finished with exit code ' +
      IntToStr(ResultCode));
end;
