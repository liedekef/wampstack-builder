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
  PreInstallPage, PostInstallPage: TWizardPage;
  PreInstallMemo, PostInstallMemo, UninstMemo: TNewMemo;
  CurMemo: TNewMemo; // where the batch that is running right now writes
  PreInstallDone, PostInstallDone: Boolean;

// Win32 API import, purely to scroll the memo to the bottom as new lines
// come in -- Inno's own scripting doesn't expose a "scroll to end" method
// on TNewMemo, but it does let you call arbitrary DLL functions like this.
function SendMessage(hWnd: Longint; Msg, wParam, lParam: Longint): Longint;
  external 'SendMessageA@user32.dll stdcall';
const
  WM_VSCROLL = $115;
  SB_BOTTOM = 7;

function CreateLogMemo(Page: TWizardPage): TNewMemo;
var
  Memo: TNewMemo;
begin
  Memo := TNewMemo.Create(Page);
  Memo.Parent := Page.Surface;
  Memo.Left := 0;
  Memo.Top := 0;
  Memo.Width := Page.SurfaceWidth;
  Memo.Height := Page.SurfaceHeight;
  Memo.ScrollBars := ssVertical;
  Memo.ReadOnly := True;
  Memo.Font.Name := 'Consolas';
  Memo.Font.Size := 8;
  Result := Memo;
end;

// Same idea, but for the uninstall progress form, which isn't a TWizardPage
// and doesn't offer a Surface/SurfaceWidth/SurfaceHeight -- it's positioned
// under the existing ProgressBar instead of filling a whole page.
function CreateLogMemoOnForm(Owner: TComponent; Page: TWinControl;
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
  Log(S); // so the output ends up in the setup log too
end;

procedure InitializeWizard();
begin
  // Two dedicated pages instead of embedding a memo in the built-in
  // Installing page: that page has no Next button to gate on, so its
  // output would flash by and disappear the moment the batch finishes.
  // A real page in the sequence lets the user actually read (and stay on)
  // the output until they choose to click Next.
  PreInstallPage := CreateCustomPage(wpReady, 'Removing previous install',
    'Please wait while the previous install is removed, then click Next to continue.');
  PreInstallMemo := CreateLogMemo(PreInstallPage);

  PostInstallPage := CreateCustomPage(wpInstalling, 'Setup output',
    'Review the output below, then click Next to continue.');
  PostInstallMemo := CreateLogMemo(PostInstallPage);
end;

// Skip the "removing previous install" page entirely on a fresh install --
// nothing to clean up, no need to show an empty page.
function ShouldSkipPage(PageID: Integer): Boolean;
begin
  Result := False;
  if PageID = PreInstallPage.ID then
    Result := not FileExists(ExpandConstant('{app}\uninstall.bat'));
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

// Runs a batch file into the given memo and gates the navigation buttons
// until it finishes, so the installation (or the next page) can't proceed out
// from under the user before they've had a chance to read the output.
procedure RunBatchLive(const BatchFile: String; Memo: TNewMemo);
var
  ResultCode: Integer;
  Started: Boolean;
  ErrorMsg: String;
  NextWasEnabled, BackWasEnabled: Boolean;
begin
  if not FileExists(BatchFile) then
  begin
    MemoAdd(Memo, '(nothing to do)');
    Exit;
  end;

  CurMemo := Memo;
  Memo.Lines.Clear;
  // Next is gated so the output can't be skipped, and Back too: the message
  // pump inside ExecAndLogOutput keeps handling clicks while the batch runs,
  // so a Back click would otherwise leave the page and let the user come back
  // and run the batch a second time.
  NextWasEnabled := WizardForm.NextButton.Enabled;
  BackWasEnabled := WizardForm.BackButton.Enabled;
  WizardForm.NextButton.Enabled := False;
  WizardForm.BackButton.Enabled := False;
  try
    ResultCode := 0;
    Started := False;
    ErrorMsg := '';
    try
      // Console programs are always hidden regardless of ShowCmd per
      // ExecAndLogOutput's own docs, which recommend SW_SHOWNORMAL over
      // SW_HIDE for that reason. "nopause" is passed through as %1 to the
      // batch file so its trailing "pause" is skipped.
      Started := ExecAndLogOutput(BatchFile, 'nopause', ExtractFileDir(BatchFile),
        SW_SHOWNORMAL, ewWaitUntilTerminated, ResultCode, @StreamOutput);
    except
      ErrorMsg := GetExceptionMessage;
    end;

    if ErrorMsg <> '' then
      MemoAdd(Memo, 'Could not run ' + BatchFile + ': ' + ErrorMsg)
    else if not Started then
      MemoAdd(Memo, 'Could not run ' + BatchFile + ' (error ' + IntToStr(ResultCode) + ')')
    else if ResultCode <> 0 then
      MemoAdd(Memo, '*** ' + BatchFile + ' finished with exit code ' + IntToStr(ResultCode))
    else
    begin
      MemoAdd(Memo, '');
      MemoAdd(Memo, 'Done -- click Next to continue.');
    end;
  finally
    WizardForm.NextButton.Enabled := NextWasEnabled;
    WizardForm.BackButton.Enabled := BackWasEnabled;
  end;
end;

procedure CurPageChanged(CurPageID: Integer);
begin
  // The Done flags are the second line of defence: the user can walk back and
  // forth through the page sequence at any time, and re-entering a page that
  // has already been dealt with must not run its batch again. (Its output is
  // still in the memo, along with the "click Next" reminder.)
  if (CurPageID = PreInstallPage.ID) and not PreInstallDone then
  begin
    PreInstallDone := True;
    DeleteStaleRunFiles;
    RunBatchLive(ExpandConstant('{app}\uninstall.bat'), PreInstallMemo);
  end
  else if (CurPageID = PostInstallPage.ID) and not PostInstallDone then
  begin
    PostInstallDone := True;
    RunBatchLive(ExpandConstant('{app}\install.bat'), PostInstallMemo);
  end
end;

// The uninstaller has no page sequence of its own to gate on -- give it a
// log box in the same spot on its own progress window, and a MsgBox at the
// end (which blocks on its own OK button) so the output doesn't just flash
// by before the uninstaller moves on to removing files.
procedure InitializeUninstallProgressForm();
var
  Form: TUninstallProgressForm;
begin
  Form := GetUninstallProgressForm;
  UninstMemo := CreateLogMemoOnForm(Form, Form.InstallingPage, Form.StatusLabel.Left,
    Form.ProgressBar.Top + Form.ProgressBar.Height + ScaleY(12));
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  WorkDir, BatchFile, Summary: String;
  ResultCode: Integer;
  Started: Boolean;
  ErrorMsg: String;
  Flags: TMsgBoxType;
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
    Started := ExecAndLogOutput(BatchFile, 'nopause', WorkDir, SW_SHOWNORMAL,
      ewWaitUntilTerminated, ResultCode, @StreamOutput);
  except
    ErrorMsg := GetExceptionMessage;
  end;

  if ErrorMsg <> '' then
  begin
    MemoAdd(UninstMemo, 'Could not run ' + BatchFile + ': ' + ErrorMsg);
    Summary := 'Could not run uninstall.bat:' + #13#10 + ErrorMsg;
    Flags := mbError;
  end
  else if not Started then
  begin
    MemoAdd(UninstMemo, 'Could not run ' + BatchFile + ' (error ' +
      IntToStr(ResultCode) + ')');
    Summary := 'Could not run uninstall.bat (error ' + IntToStr(ResultCode) +
      ').';
    Flags := mbError;
  end
  else if ResultCode <> 0 then
  begin
    MemoAdd(UninstMemo, '*** uninstall.bat finished with exit code ' +
      IntToStr(ResultCode));
    Summary := 'uninstall.bat stopped with exit code ' + IntToStr(ResultCode) +
      ', so the services may still be registered.';
    Flags := mbError;
  end
  else
  begin
    Summary := 'Removed the previous services and certificate.';
    Flags := mbInformation;
  end;

  // The uninstaller has no page sequence of its own to gate on, so this
  // blocking dialog is the equivalent: no file on disk is touched until the
  // user dismisses it. The full output stays on screen behind the dialog, so
  // it isn't repeated in here.
  MsgBox(Summary + #13#10#13#10 + 'Click OK to continue removing the files.',
    Flags, MB_OK);
end;
