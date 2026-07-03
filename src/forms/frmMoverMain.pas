unit frmMoverMain;

interface

uses
  Winapi.Windows,
  Winapi.Messages,
  System.SysUtils,
  System.Classes,
  Vcl.Graphics,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.Dialogs,
  Vcl.StdCtrls,
  Vcl.ComCtrls,
  Vcl.ExtCtrls,
  Vcl.FileCtrl,
  System.IOUtils,
  System.Threading,
  System.Generics.Collections,
  System.IniFiles,
  Winapi.ShellAPI,
  System.UITypes,
  uPDFTextMover;

type
  TfrmMoverMain = class(TForm)
    grpPresetConfig: TGroupBox;
    lblPreset: TLabel;
    cmbPresets: TComboBox;
    btnSavePreset: TButton;
    btnQuickSavePreset: TButton;
    btnDeletePreset: TButton;
    grpFileConfig: TGroupBox;
    lblSrcFile: TLabel;
    lblOutputDir: TLabel;
    edtSrcFile: TEdit;
    btnSelectFile: TButton;
    edtOutputDir: TEdit;
    btnSelectOutputDir: TButton;
    grpCoordsConfig: TGroupBox;
    lblMode: TLabel;
    lblSrcRegionTitle: TLabel;
    lblDestRegionTitle: TLabel;
    lblX1: TLabel;
    lblY1: TLabel;
    lblX2: TLabel;
    lblY2: TLabel;
    lblTx: TLabel;
    lblTy: TLabel;
    rbSmartMode: TRadioButton;
    rbPercentMode: TRadioButton;
    rbAbsoluteMode: TRadioButton;
    edtX1: TEdit;
    udX1: TUpDown;
    edtY1: TEdit;
    udY1: TUpDown;
    edtX2: TEdit;
    udX2: TUpDown;
    edtY2: TEdit;
    udY2: TUpDown;
    edtTx: TEdit;
    udTx: TUpDown;
    edtTy: TEdit;
    udTy: TUpDown;
    grpStyleConfig: TGroupBox;
    lblFont: TLabel;
    lblFontSize: TLabel;
    lblLineHeight: TLabel;
    cmbFonts: TComboBox;
    edtFontSize: TEdit;
    udFontSize: TUpDown;
    edtLineHeight: TEdit;
    udLineHeight: TUpDown;
    chkEraseSource: TCheckBox;
    btnStart: TButton;
    pnlProgress: TPanel;
    pbProgress: TProgressBar;
    memLog: TMemo;
    pnlDestMode: TPanel;
    rbDestPercent: TRadioButton;
    rbDestAbsolute: TRadioButton;
    pgcMain: TPageControl;
    tshMover: TTabSheet;
    tshHelp: TTabSheet;
    memHelp: TMemo;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure btnSelectFileClick(Sender: TObject);
    procedure btnSelectOutputDirClick(Sender: TObject);
    procedure rbModeClick(Sender: TObject);
    procedure udClick(Sender: TObject; Button: TUDBtnType);
    procedure btnStartClick(Sender: TObject);
    procedure rbDestModeClick(Sender: TObject);
    procedure edtCoordsChange(Sender: TObject);
    procedure cmbPresetsChange(Sender: TObject);
    procedure btnSavePresetClick(Sender: TObject);
    procedure btnQuickSavePresetClick(Sender: TObject);
    procedure btnDeletePresetClick(Sender: TObject);
  private
    FSelectedFiles: TStringList;
    FProcessing: Boolean;
    FLoadingSettings: Boolean;
    
    // UI input snapshots for safe thread access
    FSnapFiles: TArray<string>;
    FSnapOutputDir: string;
    FSnapSortX1, FSnapSortY1, FSnapSortX2, FSnapSortY2, FSnapDestTx, FSnapDestTy: Single;
    FSnapDestAbsolute: Boolean;
    FSnapFontSize: Single;
    FSnapLineHeight: Single;
    FSnapErase: Boolean;
    FSnapAvoid: Boolean;
    FSnapMode: TMoveMode;
    FSnapFontIndex: Integer;
    FCurrentSrcAbsolute: Boolean;
    FCurrentDestAbsolute: Boolean;
    procedure ConvertSourceCoords(ToAbsolute: Boolean);
    procedure ConvertDestCoords(ToAbsolute: Boolean);
    function GetAppVersion: string;

    procedure SetupChineseCaptions;
    procedure UpdateControlsState;
    procedure AppendLog(const Msg: string);
    procedure DoProcessWork;
    procedure ProcessFilesAsync;
    
    // Load and Save UI Settings
    procedure LoadUISettings;
    procedure SaveUISettings;
    procedure LoadPresetList;
    procedure LoadPreset(const PresetName: string);
    procedure SavePreset(const PresetName: string);
    
    // Windows Drag & Drop support
    procedure WMDropFiles(var Msg: TWMDropFiles); message WM_DROPFILES;
  public
    { Public declarations }
  end;

var
  MoverMainForm: TfrmMoverMain;

implementation

uses
  PdfiumLib;

{$R *.dfm}

{ TfrmMoverMain }

procedure TfrmMoverMain.FormCreate(Sender: TObject);
begin
  FSelectedFiles := TStringList.Create;
  FProcessing := False;
  FLoadingSettings := False;
  
  // Accept drag & drop files
  DragAcceptFiles(Self.Handle, True);
  
  SetupChineseCaptions;
  
  // Load preset list
  LoadPresetList;
  
  // Load preset if one is active, otherwise load general settings
  if cmbPresets.ItemIndex >= 0 then
    LoadPreset(cmbPresets.Items[cmbPresets.ItemIndex])
  else
    LoadUISettings;
  
  UpdateControlsState;
  
  memLog.Text := '系统运行日志将在此输出...';
  
  // 尝试预加载 PDFium 库，若失败则在日志框中提示用户
  try
    InitPDFium;
  except
    on E: Exception do
    begin
      memLog.Clear;
      memLog.Lines.Add('================================================================');
      memLog.Lines.Add('【严重警告】PDF 核心动态库加载失败！');
      memLog.Lines.Add('错误信息: ' + E.Message);
      memLog.Lines.Add('本工具依赖 Google PDFium 渲染库。请进行以下操作修复：');
      memLog.Lines.Add('1. 下载 64 位版本的 pdfium.dll');
      memLog.Lines.Add('   推荐下载地址: https://github.com/bblanchon/pdfium-binaries/releases');
      memLog.Lines.Add('2. 将下载的 pdfium.dll 文件复制到本程序的同级目录下（与 PDFTextMover.exe 放在同一文件夹）');
      memLog.Lines.Add('3. 重新启动本程序。');
      memLog.Lines.Add('================================================================');
    end;
  end;
  FCurrentSrcAbsolute := rbAbsoluteMode.Checked;
  FCurrentDestAbsolute := rbDestAbsolute.Checked;
end;

procedure TfrmMoverMain.FormDestroy(Sender: TObject);
begin
  try
    SaveUISettings;
  except
    // Prevent exception on close
  end;
  FSelectedFiles.Free;
end;

procedure TfrmMoverMain.SetupChineseCaptions;
begin
  grpPresetConfig.Caption := ' 预设配置管理 ';
  lblPreset.Caption := '选择预设:';
  btnQuickSavePreset.Caption := '保存到当前预设';
  btnSavePreset.Caption := '另存为新预设...';
  btnDeletePreset.Caption := '删除选中预设';

  tshMover.Caption := '参数配置与处理';
  tshHelp.Caption := '软件使用说明';

  memHelp.Lines.Clear;
  memHelp.Lines.Add('======================================================================');
  memHelp.Lines.Add('                PDF 标签文本区域迁移工具 - 使用说明书');
  memHelp.Lines.Add('======================================================================');
  memHelp.Lines.Add('');
  memHelp.Lines.Add('一、软件简介');
  memHelp.Lines.Add('    本软件用于批量将 PDF 格式的标签文件中，右下角（或特定区域）的快递单号');
  memHelp.Lines.Add('    文本自动识别、迁移（移动）到顶部指定的空白框内，并支持擦除原有单号。');
  memHelp.Lines.Add('');
  memHelp.Lines.Add('二、核心功能与配置说明');
  memHelp.Lines.Add('  1. 智能识别模式 (推荐)');
  memHelp.Lines.Add('     - 自动定位右下角单号文字区域（无需人工设置源提取坐标）。');
  memHelp.Lines.Add('     - 支持在下方微调目标写入的 tx、ty 坐标位置。');
  memHelp.Lines.Add('  2. 百分比自适应模式');
  memHelp.Lines.Add('     - 坐标原点在【左上角】（X 从左往右 0-100%, Y 从上往下 0-100%）。');
  memHelp.Lines.Add('     - 适合不同大小的 PDF 页面，控件大小会自动按比例缩放。');
  memHelp.Lines.Add('  3. 绝对坐标模式');
  memHelp.Lines.Add('     - 坐标原点在【左下角】（单位：pt / 磅，PDF 底层绝对物理点）。');
  memHelp.Lines.Add('  4. 目标定位独立配置');
  memHelp.Lines.Add('     - 目标的 tx、ty 写入位置，可独立选择以百分比 (%) 或是绝对坐标 (pt) 定位，');
  memHelp.Lines.Add('       免去了源提取区域与目标写入区域单位不同带来的混淆。');
  memHelp.Lines.Add('  5. 重建文本样式');
  memHelp.Lines.Add('     - 擦除原始文字：勾选后会在目标位置写入新字体的同时，擦除源位置的旧文字。');
  memHelp.Lines.Add('     - 自适应避让重叠：防止写入位置与页面原先已有的其他文字发生重叠覆盖。');
  memHelp.Lines.Add('');
  memHelp.Lines.Add('三、使用步骤');
  memHelp.Lines.Add('  1. 下载并将 64 位版本的 "pdfium.dll" 文件存放在本程序的同级目录下。');
  memHelp.Lines.Add('  2. 打开本程序，点击“选择文件”导入待处理的 PDF 标签文件（或直接将文件/文件夹拖拽入窗口）。');
  memHelp.Lines.Add('  3. 设置您的目标保存目录、提取和目标坐标（默认值已优化）。');
  memHelp.Lines.Add('  4. 点击“开始批量迁移文本”按钮，稍等片刻即可在输出目录中查收处理完成的 PDF 标签。');
  memHelp.Lines.Add('');
  memHelp.Lines.Add('======================================================================');

  Self.Caption := 'PDF 标签文本区域迁移工具 v' + GetAppVersion;
  
  grpFileConfig.Caption := ' 文件与目录配置 ';
  lblSrcFile.Caption := '待处理 PDF:';
  lblOutputDir.Caption := '输出目录:';
  btnSelectFile.Caption := '选择文件';
  btnSelectOutputDir.Caption := '选择目录';
  
  grpCoordsConfig.Caption := ' 坐标系与文本区域配置 (提示: 百分比模式原点在左上角，绝对坐标在左下角) ';
  lblMode.Caption := '定位模式:';
  rbSmartMode.Caption := '智能识别模式 (推荐，免配置移动右下角单号)';
  rbPercentMode.Caption := '百分比自适应模式 (手动微调区域)';
  rbAbsoluteMode.Caption := '绝对坐标模式 (单位: pt / 磅)';
  
  lblSrcRegionTitle.Caption := '源文本提取区域 (完美框选您的单号行):';
  lblDestRegionTitle.Caption := '目标写入起始点 (对应顶部空白框内部):';
  rbDestPercent.Caption := '目标使用百分比模式 (%)';
  rbDestAbsolute.Caption := '目标使用绝对坐标模式 (pt)';
  
  grpStyleConfig.Caption := ' 重建文本样式设置 ';
  lblFont.Caption := '字体库:';
  lblFontSize.Caption := '字号 (px):';
  lblLineHeight.Caption := '行距 (pt):';
  btnStart.Caption := '开始批量迁移文本';
  cmbFonts.Clear;
  cmbFonts.Items.Add('Helvetica (无衬线常用体)');
  cmbFonts.Items.Add('Times-Roman (衬线报刊体)');
  cmbFonts.Items.Add('Courier (等宽打字机体)');
  cmbFonts.ItemIndex := 0;
  chkEraseSource.Caption := '擦除原始区域文本';
//  chkAvoidOverlap.Caption := '自适应避让重叠文字';
end;

procedure TfrmMoverMain.UpdateControlsState;
var
  LModeEnable: Boolean;
begin
  LModeEnable := not rbSmartMode.Checked;
  
  // Enable or disable manual coordinate controls
  edtX1.Enabled := LModeEnable;
  udX1.Enabled := LModeEnable;
  edtY1.Enabled := LModeEnable;
  udY1.Enabled := LModeEnable;
  edtX2.Enabled := LModeEnable;
  udX2.Enabled := LModeEnable;
  edtY2.Enabled := LModeEnable;
  udY2.Enabled := LModeEnable;
  
  // 目标坐标控件在任何模式下均保持启用
  edtTx.Enabled := True;
  udTx.Enabled := True;
  edtTy.Enabled := True;
  udTy.Enabled := True;
  
  // Change labels based on mode
  if rbPercentMode.Checked then
  begin
    lblX1.Caption := 'x1 (左 %):';
    lblY1.Caption := 'y1 (上 %):';
    lblX2.Caption := 'x2 (右 %):';
    lblY2.Caption := 'y2 (下 %):';
  end
  else if rbAbsoluteMode.Checked then
  begin
    lblX1.Caption := 'x1 (左 pt):';
    lblY1.Caption := 'y1 (底 pt):';
    lblX2.Caption := 'x2 (右 pt):';
    lblY2.Caption := 'y2 (顶 pt):';
  end
  else
  begin
    // Smart mode defaults
    lblX1.Caption := 'x1:';
    lblY1.Caption := 'y1:';
    lblX2.Caption := 'x2:';
    lblY2.Caption := 'y2:';
  end;

  // 目标写入坐标提示由独立的模式单选框决定
  if rbDestAbsolute.Checked then
  begin
    lblTx.Caption := '目标 tx (pt):';
    lblTy.Caption := '目标 ty (pt):';
  end
  else
  begin
    lblTx.Caption := '目标 tx (%):';
    lblTy.Caption := '目标 ty (%):';
  end;
end;

procedure TfrmMoverMain.ConvertSourceCoords(ToAbsolute: Boolean);
var
  ValX1, ValY1, ValX2, ValY2: Double;
  NewX1, NewY1, NewX2, NewY2: Integer;
begin
  ValX1 := udX1.Position / 100.0;
  ValY1 := udY1.Position / 100.0;
  ValX2 := udX2.Position / 100.0;
  ValY2 := udY2.Position / 100.0;

  if ToAbsolute then
  begin
    NewX1 := Round(ValX1 * 5.95 * 100.0);
    NewX2 := Round(ValX2 * 5.95 * 100.0);
    NewY1 := Round((100.0 - ValY2) * 8.42 * 100.0);
    NewY2 := Round((100.0 - ValY1) * 8.42 * 100.0);
  end
  else
  begin
    NewX1 := Round((ValX1 / 5.95) * 100.0);
    NewX2 := Round((ValX2 / 5.95) * 100.0);
    NewY1 := Round((100.0 - (ValY2 / 8.42)) * 100.0);
    NewY2 := Round((100.0 - (ValY1 / 8.42)) * 100.0);
  end;

  if not ToAbsolute then
  begin
    if NewX1 < 0 then NewX1 := 0; if NewX1 > 10000 then NewX1 := 10000;
    if NewX2 < 0 then NewX2 := 0; if NewX2 > 10000 then NewX2 := 10000;
    if NewY1 < 0 then NewY1 := 0; if NewY1 > 10000 then NewY1 := 10000;
    if NewY2 < 0 then NewY2 := 0; if NewY2 > 10000 then NewY2 := 10000;
  end;

  udX1.Position := NewX1;
  udX2.Position := NewX2;
  udY1.Position := NewY1;
  udY2.Position := NewY2;

  edtX1.Text := Format('%.2f', [udX1.Position / 100.0]);
  edtX2.Text := Format('%.2f', [udX2.Position / 100.0]);
  edtY1.Text := Format('%.2f', [udY1.Position / 100.0]);
  edtY2.Text := Format('%.2f', [udY2.Position / 100.0]);
end;

procedure TfrmMoverMain.ConvertDestCoords(ToAbsolute: Boolean);
var
  ValTx, ValTy: Double;
  NewTx, NewTy: Integer;
begin
  ValTx := udTx.Position / 100.0;
  ValTy := udTy.Position / 100.0;

  if ToAbsolute then
  begin
    NewTx := Round(ValTx * 5.95 * 100.0);
    NewTy := Round((100.0 - ValTy) * 8.42 * 100.0);
  end
  else
  begin
    NewTx := Round((ValTx / 5.95) * 100.0);
    NewTy := Round((100.0 - (ValTy / 8.42)) * 100.0);
  end;

  if not ToAbsolute then
  begin
    if NewTx < 0 then NewTx := 0; if NewTx > 10000 then NewTx := 10000;
    if NewTy < 0 then NewTy := 0; if NewTy > 10000 then NewTy := 10000;
  end;

  udTx.Position := NewTx;
  udTy.Position := NewTy;

  edtTx.Text := Format('%.2f', [udTx.Position / 100.0]);
  edtTy.Text := Format('%.2f', [udTy.Position / 100.0]);
end;

function TfrmMoverMain.GetAppVersion: string;
var
  VerInfoSize, VerValueSize: DWORD;
  Dummy: DWORD;
  VerInfoBuffer: Pointer;
  VerValue: PVSFixedFileInfo;
  V1, V2, V3, V4: Word;
begin
  Result := '1.0.0.0';
  VerInfoSize := GetFileVersionInfoSize(PChar(ParamStr(0)), Dummy);
  if VerInfoSize > 0 then
  begin
    GetMem(VerInfoBuffer, VerInfoSize);
    try
      if GetFileVersionInfo(PChar(ParamStr(0)), 0, VerInfoSize, VerInfoBuffer) then
      begin
        if VerQueryValue(VerInfoBuffer, '\', Pointer(VerValue), VerValueSize) then
        begin
          V1 := HiWord(VerValue^.dwFileVersionMS);
          V2 := LoWord(VerValue^.dwFileVersionMS);
          V3 := HiWord(VerValue^.dwFileVersionLS);
          V4 := LoWord(VerValue^.dwFileVersionLS);
          Result := Format('%d.%d.%d.%d', [V1, V2, V3, V4]);
        end;
      end;
    finally
      FreeMem(VerInfoBuffer);
    end;
  end;
end;

procedure TfrmMoverMain.rbModeClick(Sender: TObject);
begin
  if FLoadingSettings then Exit;
  if not rbSmartMode.Checked then
  begin
    if rbAbsoluteMode.Checked <> FCurrentSrcAbsolute then
    begin
      ConvertSourceCoords(rbAbsoluteMode.Checked);
      FCurrentSrcAbsolute := rbAbsoluteMode.Checked;
    end;
  end;
  UpdateControlsState;
end;

procedure TfrmMoverMain.rbDestModeClick(Sender: TObject);
begin
  if FLoadingSettings then Exit;
  if rbDestAbsolute.Checked <> FCurrentDestAbsolute then
  begin
    ConvertDestCoords(rbDestAbsolute.Checked);
    FCurrentDestAbsolute := rbDestAbsolute.Checked;
  end;
  UpdateControlsState;
end;

procedure TfrmMoverMain.udClick(Sender: TObject; Button: TUDBtnType);
var
  UD: TUpDown;
  Edt: TEdit;
  Val: Double;
begin
  if Sender is TUpDown then
  begin
    UD := TUpDown(Sender);
    if UD = udFontSize then Exit;

    Edt := nil;
    if UD = udX1 then Edt := edtX1
    else if UD = udY1 then Edt := edtY1
    else if UD = udX2 then Edt := edtX2
    else if UD = udY2 then Edt := edtY2
    else if UD = udTx then Edt := edtTx
    else if UD = udTy then Edt := edtTy;

    if Edt <> nil then
    begin
      Val := UD.Position / 100.0;
      Edt.Text := Format('%.2f', [Val]);
    end;
  end;
end;

procedure TfrmMoverMain.edtCoordsChange(Sender: TObject);
var
  Edt: TEdit;
  UD: TUpDown;
  Val: Double;
  NewPos: Integer;
begin
  if FProcessing or FLoadingSettings then Exit;

  if Sender is TEdit then
  begin
    Edt := TEdit(Sender);
    UD := nil;
    if Edt = edtX1 then UD := udX1
    else if Edt = edtY1 then UD := udY1
    else if Edt = edtX2 then UD := udX2
    else if Edt = edtY2 then UD := udY2
    else if Edt = edtTx then UD := udTx
    else if Edt = edtTy then UD := udTy;

    if UD <> nil then
    begin
      Val := StrToFloatDef(Edt.Text, 0.0);
      NewPos := Round(Val * 100.0);
      if NewPos < UD.Min then NewPos := UD.Min;
      if NewPos > UD.Max then NewPos := UD.Max;

      if UD.Position <> NewPos then
        UD.Position := NewPos;
    end;
  end;
end;

procedure TfrmMoverMain.btnSelectFileClick(Sender: TObject);
var
  OpenDlg: TOpenDialog;
begin
  OpenDlg := TOpenDialog.Create(Self);
  try
    OpenDlg.Filter := 'PDF Files (*.pdf)|*.pdf|All Files (*.*)|*.*';
    OpenDlg.Options := OpenDlg.Options + [ofAllowMultiSelect, ofFileMustExist];
    if OpenDlg.Execute then
    begin
      FSelectedFiles.Clear;
      FSelectedFiles.Assign(OpenDlg.Files);
      
      if FSelectedFiles.Count = 1 then
      begin
        edtSrcFile.Text := FSelectedFiles[0];
        edtOutputDir.Text := TPath.Combine(ExtractFilePath(FSelectedFiles[0]), 'output_moved');
      end
      else if FSelectedFiles.Count > 1 then
      begin
        edtSrcFile.Text := Format('[已选择 %d 个 PDF 文件]', [FSelectedFiles.Count]);
        edtOutputDir.Text := TPath.Combine(ExtractFilePath(FSelectedFiles[0]), 'output_moved');
      end;
      
      AppendLog(Format('已载入 %d 个待处理 PDF 文件。', [FSelectedFiles.Count]));
    end;
  finally
    OpenDlg.Free;
  end;
end;

procedure TfrmMoverMain.btnSelectOutputDirClick(Sender: TObject);
var
  SelDir: string;
begin
  if SelectDirectory('选择输出保存的文件夹目录', '', SelDir) then
  begin
    edtOutputDir.Text := SelDir;
    AppendLog('已更新输出路径为: ' + SelDir);
  end;
end;

procedure TfrmMoverMain.AppendLog(const Msg: string);
begin
  TThread.Synchronize(nil, procedure
  begin
    if memLog.Text = '系统运行日志将在此输出...' then
      memLog.Clear;
    memLog.Lines.Add(FormatDateTime('[hh:nn:ss] ', Now) + Msg);
  end);
end;

procedure TfrmMoverMain.WMDropFiles(var Msg: TWMDropFiles);
var
  Count, I: Integer;
  FilePath: array[0..MAX_PATH] of Char;
  LPath: string;
begin
  Count := DragQueryFile(Msg.Drop, $FFFFFFFF, nil, 0);
  if Count > 0 then
  begin
    FSelectedFiles.Clear;
    for I := 0 to Count - 1 do
    begin
      DragQueryFile(Msg.Drop, I, FilePath, MAX_PATH);
      LPath := FilePath;
      if System.SysUtils.DirectoryExists(LPath) then
      begin
        var FilesInDir := TDirectory.GetFiles(LPath, '*.pdf', TSearchOption.soTopDirectoryOnly);
        for var FName in FilesInDir do
          FSelectedFiles.Add(FName);
      end
      else if SameText(ExtractFileExt(LPath), '.pdf') then
      begin
        FSelectedFiles.Add(LPath);
      end;
    end;
    
    if FSelectedFiles.Count = 1 then
    begin
      edtSrcFile.Text := FSelectedFiles[0];
      edtOutputDir.Text := TPath.Combine(ExtractFilePath(FSelectedFiles[0]), 'output_moved');
    end
    else if FSelectedFiles.Count > 1 then
    begin
      edtSrcFile.Text := Format('[已选择 %d 个 PDF 文件]', [FSelectedFiles.Count]);
      edtOutputDir.Text := TPath.Combine(ExtractFilePath(FSelectedFiles[0]), 'output_moved');
    end;
    
    AppendLog(Format('通过拖拽载入 %d 个待处理 PDF 文件。', [FSelectedFiles.Count]));
  end;
  DragFinish(Msg.Drop);
end;

procedure TfrmMoverMain.btnStartClick(Sender: TObject);
begin
  if FProcessing then Exit;
  
  // 确保 PDFium 库已成功加载
  try
    InitPDFium;
  except
    on E: Exception do
    begin
      AppendLog('【错误】无法开始处理：PDF 核心库加载失败！');
      AppendLog('  原因: ' + E.Message);
      AppendLog('  请确保 64 位 pdfium.dll 已放入程序同级目录下。');
      ShowMessage('PDF 核心库加载失败！请先根据日志框中的提示下载并配置 dll。');
      Exit;
    end;
  end;
  
  if FSelectedFiles.Count = 0 then
  begin
    ShowMessage('请先选择待处理的 PDF 文件或将其拖拽入窗口中！');
    Exit;
  end;
  
  if Trim(edtOutputDir.Text) = '' then
  begin
    ShowMessage('请输入输出的目标保存目录！');
    Exit;
  end;
  
  ProcessFilesAsync;
end;

procedure TfrmMoverMain.DoProcessWork;
var
  Mover: TPDFTextMover;
  I: Integer;
  SrcFile, DstFile: string;
  LogStr: string;
  SuccessCount: Integer;
  ProgressVal: Integer;
begin
  Mover := TPDFTextMover.Create;
  try
    Mover.MoveMode := FSnapMode;
    Mover.SrcX1 := FSnapSortX1;
    Mover.SrcY1 := FSnapSortY1;
    Mover.SrcX2 := FSnapSortX2;
    Mover.SrcY2 := FSnapSortY2;
    Mover.DestTx := FSnapDestTx;
    Mover.DestTy := FSnapDestTy;
    Mover.DestUseAbsolute := FSnapDestAbsolute;
    case FSnapFontIndex of
      0: Mover.FontName := 'Helvetica';
      1: Mover.FontName := 'Times-Roman';
      2: Mover.FontName := 'Courier';
    else
      Mover.FontName := 'Helvetica';
    end;
    Mover.FontSize := FSnapFontSize;
    Mover.EraseSource := FSnapErase;
    Mover.AvoidOverlap := FSnapAvoid;
    Mover.LineHeight := FSnapLineHeight;
    
    SuccessCount := 0;
    for I := 0 to Length(FSnapFiles) - 1 do
    begin
      SrcFile := FSnapFiles[I];
      DstFile := TPath.Combine(FSnapOutputDir, ExtractFileName(SrcFile));
      
      AppendLog(Format('[%d/%d] 正在处理: %s', [I + 1, Length(FSnapFiles), ExtractFileName(SrcFile)]));
      
      try
        if Mover.ProcessFile(SrcFile, DstFile, LogStr) then
        begin
          Inc(SuccessCount);
          AppendLog(Format('[%d/%d] 成功处理。', [I + 1, Length(FSnapFiles)]));
        end
        else
        begin
          AppendLog(Format('[%d/%d] 失败。', [I + 1, Length(FSnapFiles)]));
        end;
        
        if Trim(LogStr) <> '' then
        begin
          var TmpList := TStringList.Create;
          try
            TmpList.Text := LogStr;
            for var L in TmpList do
              AppendLog('   ' + L);
          finally
            TmpList.Free;
          end;
        end;
      except
        on E: Exception do
        begin
          AppendLog('   发生未捕获的错误: ' + E.Message);
        end;
      end;
      
      ProgressVal := Round(((I + 1) / Length(FSnapFiles)) * 100.0);
      TThread.Synchronize(nil, procedure
      begin
        pbProgress.Position := ProgressVal;
      end);
    end;
    
    AppendLog(Format('批量迁移处理完成！成功 %d/%d。', [SuccessCount, Length(FSnapFiles)]));
    
  finally
    Mover.Free;
    
    TThread.Synchronize(nil, procedure
    begin
      FProcessing := False;
      btnStart.Enabled := True;
      btnStart.Caption := '开始批量迁移文本';
      grpFileConfig.Enabled := True;
      grpCoordsConfig.Enabled := True;
      grpStyleConfig.Enabled := True;
      UpdateControlsState;
      ShowMessage(Format('批量迁移处理完成！'#13#10'总文件数: %d'#13#10'处理成功: %d'#13#10'处理失败: %d',
        [Length(FSnapFiles), SuccessCount, Length(FSnapFiles) - SuccessCount]));
    end);
  end;
end;

procedure TfrmMoverMain.ProcessFilesAsync;
begin
  FProcessing := True;
  btnStart.Enabled := False;
  btnStart.Caption := '正在处理...';
  pbProgress.Position := 0;
  memLog.Clear;
  
  // Freeze UI controls
  grpFileConfig.Enabled := False;
  grpCoordsConfig.Enabled := False;
  grpStyleConfig.Enabled := False;
  
  // Snap inputs into FSnap fields for thread-safe access
  FSnapFiles := FSelectedFiles.ToStringArray;
  FSnapOutputDir := Trim(edtOutputDir.Text);
  
  FSnapSortX1 := StrToFloatDef(edtX1.Text, 35.0);
  FSnapSortY1 := StrToFloatDef(edtY1.Text, 80.0);
  FSnapSortX2 := StrToFloatDef(edtX2.Text, 95.0);
  FSnapSortY2 := StrToFloatDef(edtY2.Text, 98.0);
  FSnapDestTx := StrToFloatDef(edtTx.Text, 44.0);
  FSnapDestTy := StrToFloatDef(edtTy.Text, 11.0);
  FSnapDestAbsolute := rbDestAbsolute.Checked;
  FSnapFontIndex := cmbFonts.ItemIndex;
  FSnapFontSize := StrToFloatDef(edtFontSize.Text, 8.0);
  FSnapLineHeight := StrToFloatDef(edtLineHeight.Text, 18.0);
  FSnapErase := chkEraseSource.Checked;
//  FSnapAvoid := chkAvoidOverlap.Checked;

  if rbSmartMode.Checked then
    FSnapMode := mmSmart
  else if rbPercentMode.Checked then
    FSnapMode := mmPercent
  else
    FSnapMode := mmAbsolute;
    
  AppendLog(Format('开始批量迁移文本，文件总数: %d...', [Length(FSnapFiles)]));
  
  // Launch Background Thread
  TTask.Run(DoProcessWork);
end;

procedure TfrmMoverMain.LoadUISettings;
var
  Ini: TIniFile;
  IniPath: string;
  ModeIndex: Integer;
  LFontSize: Integer;
begin
  IniPath := TPath.Combine(ExtractFilePath(Application.ExeName), 'PDFTextMover.ini');
  Ini := TIniFile.Create(IniPath);
  try
    edtOutputDir.Text := Ini.ReadString('Settings', 'OutputDir', '');
    
    ModeIndex := Ini.ReadInteger('Settings', 'Mode', 0);
    case ModeIndex of
      0: rbSmartMode.Checked := True;
      1: rbPercentMode.Checked := True;
      2: rbAbsoluteMode.Checked := True;
    end;
    
    udX1.Position := Ini.ReadInteger('Coordinates', 'X1', 3500);
    udY1.Position := Ini.ReadInteger('Coordinates', 'Y1', 8000);
    udX2.Position := Ini.ReadInteger('Coordinates', 'X2', 9500);
    udY2.Position := Ini.ReadInteger('Coordinates', 'Y2', 9800);
    udTx.Position := Ini.ReadInteger('Coordinates', 'Tx', 4400);
    udTy.Position := Ini.ReadInteger('Coordinates', 'Ty', 1100);
    
    LFontSize := Ini.ReadInteger('Style', 'FontSize', 8);
    if LFontSize >= 100 then
      LFontSize := LFontSize div 100;
    udFontSize.Position := LFontSize;
    
    var LLineHeight := Ini.ReadInteger('Style', 'LineHeight', 18);
    if LLineHeight >= 100 then
      LLineHeight := LLineHeight div 100;
    udLineHeight.Position := LLineHeight;
    
    chkEraseSource.Checked := Ini.ReadBool('Style', 'EraseSource', True);
//    chkAvoidOverlap.Checked := Ini.ReadBool('Style', 'AvoidOverlap', False);
    cmbFonts.ItemIndex := Ini.ReadInteger('Style', 'FontIndex', 0);
    
    var LDestMode := Ini.ReadInteger('Settings', 'DestMode', 0);
    if LDestMode = 1 then
      rbDestAbsolute.Checked := True
    else
      rbDestPercent.Checked := True;
  finally
    Ini.Free;
  end;
  
  // Update Edit texts from UpDown positions
  edtX1.Text := Format('%.2f', [udX1.Position / 100.0]);
  edtY1.Text := Format('%.2f', [udY1.Position / 100.0]);
  edtX2.Text := Format('%.2f', [udX2.Position / 100.0]);
  edtY2.Text := Format('%.2f', [udY2.Position / 100.0]);
  edtTx.Text := Format('%.2f', [udTx.Position / 100.0]);
  edtTy.Text := Format('%.2f', [udTy.Position / 100.0]);
  edtFontSize.Text := IntToStr(udFontSize.Position);
  edtLineHeight.Text := IntToStr(udLineHeight.Position);
  FCurrentSrcAbsolute := rbAbsoluteMode.Checked;
  FCurrentDestAbsolute := rbDestAbsolute.Checked;
end;

procedure TfrmMoverMain.SaveUISettings;
var
  Ini: TIniFile;
  IniPath: string;
  ModeIndex: Integer;
begin
  IniPath := TPath.Combine(ExtractFilePath(Application.ExeName), 'PDFTextMover.ini');
  Ini := TIniFile.Create(IniPath);
  try
    Ini.WriteString('Settings', 'OutputDir', edtOutputDir.Text);
    
    if rbSmartMode.Checked then
      ModeIndex := 0
    else if rbPercentMode.Checked then
      ModeIndex := 1
    else
      ModeIndex := 2;
    Ini.WriteInteger('Settings', 'Mode', ModeIndex);
    
    Ini.WriteInteger('Coordinates', 'X1', udX1.Position);
    Ini.WriteInteger('Coordinates', 'Y1', udY1.Position);
    Ini.WriteInteger('Coordinates', 'X2', udX2.Position);
    Ini.WriteInteger('Coordinates', 'Y2', udY2.Position);
    Ini.WriteInteger('Coordinates', 'Tx', udTx.Position);
    Ini.WriteInteger('Coordinates', 'Ty', udTy.Position);
    
    Ini.WriteInteger('Style', 'FontSize', udFontSize.Position);
    
    Ini.WriteInteger('Style', 'LineHeight', udLineHeight.Position);
    
    Ini.WriteBool('Style', 'EraseSource', chkEraseSource.Checked);
//    Ini.WriteBool('Style', 'AvoidOverlap', chkAvoidOverlap.Checked);
    Ini.WriteInteger('Style', 'FontIndex', cmbFonts.ItemIndex);
    
    var LDestMode := 0;
    if rbDestAbsolute.Checked then
      LDestMode := 1;
    Ini.WriteInteger('Settings', 'DestMode', LDestMode);
    
    if cmbPresets.ItemIndex >= 0 then
      Ini.WriteString('Presets', 'LastPreset', cmbPresets.Items[cmbPresets.ItemIndex])
    else
      Ini.WriteString('Presets', 'LastPreset', '');
  finally
    Ini.Free;
  end;
end;

procedure TfrmMoverMain.LoadPresetList;
var
  Ini: TIniFile;
  IniPath: string;
  ListStr: string;
  Presets: TStringList;
  I: Integer;
  LastPreset: string;
  OldIndex: Integer;
begin
  IniPath := TPath.Combine(ExtractFilePath(Application.ExeName), 'PDFTextMover.ini');
  Ini := TIniFile.Create(IniPath);
  Presets := TStringList.Create;
  try
    ListStr := Ini.ReadString('Presets', 'List', '');
    Presets.CommaText := ListStr;
    
    cmbPresets.Items.BeginUpdate;
    try
      cmbPresets.Items.Clear;
      for I := 0 to Presets.Count - 1 do
        cmbPresets.Items.Add(Presets[I]);
    finally
      cmbPresets.Items.EndUpdate;
    end;
    
    LastPreset := Ini.ReadString('Presets', 'LastPreset', '');
    if LastPreset <> '' then
    begin
      OldIndex := cmbPresets.Items.IndexOf(LastPreset);
      if OldIndex >= 0 then
        cmbPresets.ItemIndex := OldIndex;
    end;
  finally
    Presets.Free;
    Ini.Free;
  end;
end;

procedure TfrmMoverMain.LoadPreset(const PresetName: string);
var
  Ini: TIniFile;
  IniPath: string;
  Section: string;
  ModeIndex: Integer;
  LFontSize: Integer;
  LLineHeight: Integer;
  LDestMode: Integer;
begin
  if PresetName = '' then Exit;
  
  IniPath := TPath.Combine(ExtractFilePath(Application.ExeName), 'PDFTextMover.ini');
  Ini := TIniFile.Create(IniPath);
  try
    Section := 'Preset_' + PresetName;
    if not Ini.SectionExists(Section) then
    begin
      AppendLog('【错误】预设不存在: ' + PresetName);
      Exit;
    end;
    
    FLoadingSettings := True;
    try
      edtOutputDir.Text := Ini.ReadString(Section, 'OutputDir', edtOutputDir.Text);
      
      ModeIndex := Ini.ReadInteger(Section, 'Mode', 0);
      case ModeIndex of
        0: rbSmartMode.Checked := True;
        1: rbPercentMode.Checked := True;
        2: rbAbsoluteMode.Checked := True;
      end;
      
      udX1.Position := Ini.ReadInteger(Section, 'X1', 3500);
      udY1.Position := Ini.ReadInteger(Section, 'Y1', 8000);
      udX2.Position := Ini.ReadInteger(Section, 'X2', 9500);
      udY2.Position := Ini.ReadInteger(Section, 'Y2', 9800);
      udTx.Position := Ini.ReadInteger(Section, 'Tx', 4400);
      udTy.Position := Ini.ReadInteger(Section, 'Ty', 1100);
      
      LFontSize := Ini.ReadInteger(Section, 'FontSize', 8);
      if LFontSize >= 100 then LFontSize := LFontSize div 100;
      udFontSize.Position := LFontSize;
      
      LLineHeight := Ini.ReadInteger(Section, 'LineHeight', 18);
      if LLineHeight >= 100 then LLineHeight := LLineHeight div 100;
      udLineHeight.Position := LLineHeight;
      
      chkEraseSource.Checked := Ini.ReadBool(Section, 'EraseSource', True);
      cmbFonts.ItemIndex := Ini.ReadInteger(Section, 'FontIndex', 0);
      
      LDestMode := Ini.ReadInteger(Section, 'DestMode', 0);
      if LDestMode = 1 then
        rbDestAbsolute.Checked := True
      else
        rbDestPercent.Checked := True;
        
      // Update Edit texts manually as FLoadingSettings prevents automatic changes
      edtX1.Text := Format('%.2f', [udX1.Position / 100.0]);
      edtY1.Text := Format('%.2f', [udY1.Position / 100.0]);
      edtX2.Text := Format('%.2f', [udX2.Position / 100.0]);
      edtY2.Text := Format('%.2f', [udY2.Position / 100.0]);
      edtTx.Text := Format('%.2f', [udTx.Position / 100.0]);
      edtTy.Text := Format('%.2f', [udTy.Position / 100.0]);
      edtFontSize.Text := IntToStr(udFontSize.Position);
      edtLineHeight.Text := IntToStr(udLineHeight.Position);
      
      FCurrentSrcAbsolute := rbAbsoluteMode.Checked;
      FCurrentDestAbsolute := rbDestAbsolute.Checked;
      
      UpdateControlsState;
      AppendLog('成功加载配置预设: ' + PresetName);
    finally
      FLoadingSettings := False;
    end;
  finally
    Ini.Free;
  end;
end;

procedure TfrmMoverMain.SavePreset(const PresetName: string);
var
  Ini: TIniFile;
  IniPath: string;
  Section: string;
  ModeIndex: Integer;
  LDestMode: Integer;
  ListStr: string;
  Presets: TStringList;
begin
  if PresetName = '' then Exit;
  
  IniPath := TPath.Combine(ExtractFilePath(Application.ExeName), 'PDFTextMover.ini');
  Ini := TIniFile.Create(IniPath);
  Presets := TStringList.Create;
  try
    Section := 'Preset_' + PresetName;
    
    // Save settings
    Ini.WriteString(Section, 'OutputDir', edtOutputDir.Text);
    
    if rbSmartMode.Checked then
      ModeIndex := 0
    else if rbPercentMode.Checked then
      ModeIndex := 1
    else
      ModeIndex := 2;
    Ini.WriteInteger(Section, 'Mode', ModeIndex);
    
    Ini.WriteInteger(Section, 'X1', udX1.Position);
    Ini.WriteInteger(Section, 'Y1', udY1.Position);
    Ini.WriteInteger(Section, 'X2', udX2.Position);
    Ini.WriteInteger(Section, 'Y2', udY2.Position);
    Ini.WriteInteger(Section, 'Tx', udTx.Position);
    Ini.WriteInteger(Section, 'Ty', udTy.Position);
    
    Ini.WriteInteger(Section, 'FontSize', udFontSize.Position);
    Ini.WriteInteger(Section, 'LineHeight', udLineHeight.Position);
    Ini.WriteBool(Section, 'EraseSource', chkEraseSource.Checked);
    Ini.WriteInteger(Section, 'FontIndex', cmbFonts.ItemIndex);
    
    if rbDestAbsolute.Checked then
      LDestMode := 1
    else
      LDestMode := 0;
    Ini.WriteInteger(Section, 'DestMode', LDestMode);
    
    // Update Preset List
    ListStr := Ini.ReadString('Presets', 'List', '');
    Presets.CommaText := ListStr;
    if Presets.IndexOf(PresetName) < 0 then
    begin
      Presets.Add(PresetName);
      Ini.WriteString('Presets', 'List', Presets.CommaText);
    end;
    
    Ini.WriteString('Presets', 'LastPreset', PresetName);
    AppendLog('已保存配置预设: ' + PresetName);
  finally
    Presets.Free;
    Ini.Free;
  end;
end;

procedure TfrmMoverMain.cmbPresetsChange(Sender: TObject);
begin
  if cmbPresets.ItemIndex >= 0 then
  begin
    LoadPreset(cmbPresets.Items[cmbPresets.ItemIndex]);
  end;
end;

procedure TfrmMoverMain.btnSavePresetClick(Sender: TObject);
var
  PresetName: string;
  OldIndex: Integer;
begin
  PresetName := '';
  if InputQuery('保存预设', '请输入预设名称:', PresetName) then
  begin
    PresetName := Trim(PresetName);
    if PresetName = '' then
    begin
      ShowMessage('预设名称不能为空！');
      Exit;
    end;
    
    if (Pos(',', PresetName) > 0) or (Pos(';', PresetName) > 0) then
    begin
      ShowMessage('预设名称不能包含逗号或分号等分隔符！');
      Exit;
    end;
    
    SavePreset(PresetName);
    
    // Reload preset list and select the saved one
    LoadPresetList;
    OldIndex := cmbPresets.Items.IndexOf(PresetName);
    if OldIndex >= 0 then
      cmbPresets.ItemIndex := OldIndex;
  end;
end;

procedure TfrmMoverMain.btnQuickSavePresetClick(Sender: TObject);
var
  PresetName: string;
begin
  if cmbPresets.ItemIndex < 0 then
  begin
    ShowMessage('当前未选择任何预设，请使用“另存为新预设...”创建新预设！');
    Exit;
  end;
  
  PresetName := cmbPresets.Items[cmbPresets.ItemIndex];
  SavePreset(PresetName);
  ShowMessage(Format('已成功更新当前预设 "%s" 的配置！', [PresetName]));
end;

procedure TfrmMoverMain.btnDeletePresetClick(Sender: TObject);
var
  PresetName: string;
  Ini: TIniFile;
  IniPath: string;
  ListStr: string;
  Presets: TStringList;
  Idx: Integer;
begin
  if cmbPresets.ItemIndex < 0 then
  begin
    ShowMessage('请先选择一个预设进行删除！');
    Exit;
  end;
  
  PresetName := cmbPresets.Items[cmbPresets.ItemIndex];
  if MessageDlg(Format('确定要删除预设 "%s" 吗？', [PresetName]), mtConfirmation, [mbYes, mbNo], 0) = mrYes then
  begin
    IniPath := TPath.Combine(ExtractFilePath(Application.ExeName), 'PDFTextMover.ini');
    Ini := TIniFile.Create(IniPath);
    Presets := TStringList.Create;
    try
      // Delete the preset section
      Ini.EraseSection('Preset_' + PresetName);
      
      // Update Preset List
      ListStr := Ini.ReadString('Presets', 'List', '');
      Presets.CommaText := ListStr;
      Idx := Presets.IndexOf(PresetName);
      if Idx >= 0 then
      begin
        Presets.Delete(Idx);
        Ini.WriteString('Presets', 'List', Presets.CommaText);
      end;
      
      // Clear LastPreset if it was the deleted one
      if SameText(Ini.ReadString('Presets', 'LastPreset', ''), PresetName) then
        Ini.WriteString('Presets', 'LastPreset', '');
        
      AppendLog('已删除配置预设: ' + PresetName);
    finally
      Presets.Free;
      Ini.Free;
    end;
    
    LoadPresetList;
    if cmbPresets.Items.Count > 0 then
    begin
      cmbPresets.ItemIndex := 0;
      cmbPresetsChange(cmbPresets);
    end
    else
    begin
      cmbPresets.ItemIndex := -1;
    end;
  end;
end;

end.
