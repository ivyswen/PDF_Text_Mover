program PDFTextMoverDemo;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  System.Generics.Defaults,
  System.IOUtils,
  Winapi.Windows,
  PdfiumCore in '..\Source\PdfiumCore.pas',
  PdfiumLib in '..\Source\PdfiumLib.pas';

type
  TCharInfo = class
  public
    Text: string;
    Left: Single;
    Bottom: Single;
    Right: Single;
    Top: Single;
    constructor Create(const AText: string; ALeft, ABottom, ARight, ATop: Single);
  end;

constructor TCharInfo.Create(const AText: string; ALeft, ABottom, ARight, ATop: Single);
begin
  inherited Create;
  Text := AText;
  Left := ALeft;
  Bottom := ABottom;
  Right := ARight;
  Top := ATop;
end;

// Helper to get text from a text page object
function GetTextObjectString(TextObj: FPDF_PAGEOBJECT; TextPage: FPDF_TEXTPAGE): string;
var
  Len: LongWord;
  Buf: array of WideChar;
begin
  Result := '';
  if not Assigned(FPDFTextObj_GetText) then Exit;
  Len := FPDFTextObj_GetText(TextObj, TextPage, nil, 0);
  if Len > 0 then
  begin
    SetLength(Buf, Len);
    if FPDFTextObj_GetText(TextObj, TextPage, PFPDF_WCHAR(@Buf[0]), Len) > 0 then
    begin
      Result := PWideChar(@Buf[0]);
      // Remove trailing null-terminator or whitespace
      Result := Trim(Result);
    end;
  end;
end;

// Helper to get font base name
function GetFontBaseName(Font: FPDF_FONT): string;
var
  Len: SIZE_T;
  Buf: array of AnsiChar;
begin
  Result := '';
  if not Assigned(FPDFFont_GetBaseFontName) or (Font = nil) then Exit;
  Len := FPDFFont_GetBaseFontName(Font, nil, 0);
  if Len > 0 then
  begin
    SetLength(Buf, Len);
    if FPDFFont_GetBaseFontName(Font, PAnsiChar(@Buf[0]), Len) > 0 then
    begin
      Result := string(PAnsiChar(@Buf[0]));
    end;
  end;
end;

procedure Log(const Msg: string);
begin
  Writeln(Msg);
end;

// Setup DLL path for pdfium.dll
procedure SetupDllSearchPath;
var
  ExeDir, DllDir: string;
begin
  ExeDir := ExtractFilePath(ParamStr(0));
  // Try different relative paths to find bin directory
  if FileExists(TPath.Combine(ExeDir, 'pdfium.dll')) then
    Exit; // Already in the same folder

  DllDir := TPath.Combine(ExeDir, '..\bin');
  if FileExists(TPath.Combine(DllDir, 'pdfium.dll')) then
  begin
    SetDllDirectory(PChar(DllDir));
    Exit;
  end;

  DllDir := TPath.Combine(ExeDir, '..\..\bin');
  if FileExists(TPath.Combine(DllDir, 'pdfium.dll')) then
  begin
    SetDllDirectory(PChar(DllDir));
    Exit;
  end;

  DllDir := TPath.Combine(ExeDir, '..\..\..\bin');
  if FileExists(TPath.Combine(DllDir, 'pdfium.dll')) then
  begin
    SetDllDirectory(PChar(DllDir));
    Exit;
  end;
end;

// Compare function to sort characters by Left (X0) coordinate
function CompareChars(const Left, Right: TCharInfo): Integer;
begin
  if Left.Left < Right.Left then
    Result := -1
  else if Left.Left > Right.Left then
    Result := 1
  else
    Result := 0;
end;

procedure DumpPDFObjects(const FilePath: string);
var
  Doc: TPdfDocument;
  Page: TPdfPage;
  LPage: FPDF_PAGE;
  TextPage: FPDF_TEXTPAGE;
  ObjCount, I: Integer;
  Obj: FPDF_PAGEOBJECT;
  L, B, R, T: Single;
  Txt: string;
  Font: FPDF_FONT;
  FontName: string;
begin
  Log('--- Dumping page objects for: ' + ExtractFileName(FilePath) + ' ---');
  Doc := TPdfDocument.Create;
  try
    Doc.LoadFromFile(FilePath);
    Page := Doc.Pages[0];
    LPage := Page.Handle;
    TextPage := FPDFText_LoadPage(LPage);
    try
      ObjCount := FPDFPage_CountObjects(LPage);
      Log(Format('Total objects in page 0: %d', [ObjCount]));
      for I := 0 to ObjCount - 1 do
      begin
        Obj := FPDFPage_GetObject(LPage, I);
        if FPDFPageObj_GetType(Obj) = FPDF_PAGEOBJ_TEXT then
        begin
          if FPDFPageObj_GetBounds(Obj, L, B, R, T) <> 0 then
          begin
            Txt := GetTextObjectString(Obj, TextPage);
            Font := FPDFTextObj_GetFont(Obj);
            FontName := GetFontBaseName(Font);
            Log(Format('[Obj %d] Text: "%s" | Font: %s | Bounds: L=%.2f, B=%.2f, R=%.2f, T=%.2f',
              [I, Txt, FontName, L, B, R, T]));
          end;
        end;
      end;
    finally
      FPDFText_ClosePage(TextPage);
    end;
  finally
    Doc.Free;
  end;
  Log('----------------------------------------------------');
end;

function ProcessPDFMove(const SrcFile, DstFile: string): Boolean;
const
  DEST_X = 135.0;
  DEST_TOP_FIRST_LINE = 50.0;
  LINE_SPACING = 18.0;
  FONT_SIZE = 9.0;
var
  Doc: TPdfDocument;
  Page: TPdfPage;
  LPage: FPDF_PAGE;
  TextPage: FPDF_TEXTPAGE;
  ObjCount, I: Integer;
  Obj: FPDF_PAGEOBJECT;
  L, B, R, T: Single;
  Txt: string;
  Font: FPDF_FONT;
  FontName: string;
  CollectedChars: TList<TCharInfo>;
  PageWidth, PageHeight: Double;
  // Sorting & grouping
  YGroups: TDictionary<Integer, TList<TCharInfo>>;
  GroupKeys: TList<Integer>;
  RoundedY, YVal: Integer;
  CharList: TList<TCharInfo>;
  LineTexts: TStringList;
  NewObj: FPDF_PAGEOBJECT;
  LineY: Single;
  Success: Boolean;
begin
  Result := False;
  Success := True;
  CollectedChars := TList<TCharInfo>.Create;
  YGroups := TDictionary<Integer, TList<TCharInfo>>.Create;
  GroupKeys := TList<Integer>.Create;
  LineTexts := TStringList.Create;
  
  Doc := TPdfDocument.Create;
  try
    Doc.LoadFromFile(SrcFile);
    Page := Doc.Pages[0];
    LPage := Page.Handle;
    PageWidth := Page.Width;
    PageHeight := Page.Height;
    Log(Format('Page size: Width=%.2f, Height=%.2f', [PageWidth, PageHeight]));

    TextPage := FPDFText_LoadPage(LPage);
    try
      ObjCount := FPDFPage_CountObjects(LPage);
      // Iterate backwards since we will remove objects
      for I := ObjCount - 1 downto 0 do
      begin
        Obj := FPDFPage_GetObject(LPage, I);
        if FPDFPageObj_GetType(Obj) <> FPDF_PAGEOBJ_TEXT then
          Continue;

        if FPDFPageObj_GetBounds(Obj, L, B, R, T) = 0 then
          Continue;

        // Position check: Bottom part of page (B < 150) and Right-ish (L > 100)
        if (L < 100.0) or (B > 150.0) then
          Continue;

        Font := FPDFTextObj_GetFont(Obj);
        FontName := GetFontBaseName(Font);

        // Match Helvetica and not Bold
        if (Pos('Helvetica', FontName) > 0) and (Pos('Bold', FontName) = 0) then
        begin
          Txt := GetTextObjectString(Obj, TextPage);
          if Txt <> '' then
          begin
            CollectedChars.Add(TCharInfo.Create(Txt, L, B, R, T));
            // Remove from page
            FPDFPage_RemoveObject(LPage, Obj);
            FPDFPageObj_Destroy(Obj);
          end;
        end;
      end;

      if CollectedChars.Count = 0 then
      begin
        Log('No target text found in right-bottom area.');
        // Just save a copy
        Doc.SaveToFile(DstFile);
        Exit(True);
      end;

      Log(Format('Found %d text objects to move.', [CollectedChars.Count]));

      // Group by Y-coordinate with a small tolerance (say, 3 units)
      for I := 0 to CollectedChars.Count - 1 do
      begin
        RoundedY := Round(CollectedChars[I].Bottom);
        // Find existing group within 3 units tolerance
        YVal := RoundedY;
        for var Key in YGroups.Keys do
        begin
          if Abs(Key - RoundedY) <= 3 then
          begin
            YVal := Key;
            Break;
          end;
        end;

        if not YGroups.ContainsKey(YVal) then
        begin
          YGroups.Add(YVal, TList<TCharInfo>.Create);
        end;
        YGroups[YVal].Add(CollectedChars[I]);
      end;

      // Collect keys and sort them descending (Line 1 first, then Line 2)
      for var Key in YGroups.Keys do
        GroupKeys.Add(Key);
      GroupKeys.Sort;
      GroupKeys.Reverse; 

      for I := 0 to GroupKeys.Count - 1 do
      begin
        CharList := YGroups[GroupKeys[I]];
        // Sort characters left to right
        CharList.Sort(TComparer<TCharInfo>.Construct(CompareChars));
        
        Txt := '';
        for var CInfo in CharList do
          Txt := Txt + CInfo.Text;
        
        LineTexts.Add(Txt);
        Log(Format('Line %d: "%s"', [I + 1, Txt]));
      end;

      // Re-create text objects at target position
      for I := 0 to LineTexts.Count - 1 do
      begin
        LineY := PageHeight - (DEST_TOP_FIRST_LINE + I * LINE_SPACING) - 8.0;
        
        NewObj := FPDFPageObj_NewTextObj(Doc.Handle, 'Helvetica', FONT_SIZE);
        if NewObj = nil then
        begin
          Log('Failed to create new text object.');
          Success := False;
          Break;
        end;

        if FPDFText_SetText(NewObj, PWideChar(WideString(LineTexts[I]))) = 0 then
        begin
          Log('Failed to set text for new object.');
          FPDFPageObj_Destroy(NewObj);
          Success := False;
          Break;
        end;

        // Move to DEST_X, LineY
        FPDFPageObj_Transform(NewObj, 1.0, 0.0, 0.0, 1.0, DEST_X, LineY);
        
        // Insert into page
        FPDFPage_InsertObject(LPage, NewObj);
        Log(Format('Inserted "%s" at X=%.2f, Y=%.2f', [LineTexts[I], DEST_X, LineY]));
      end;

      if Success then
      begin
        // Generate content streams again
        if FPDFPage_GenerateContent(LPage) <> 0 then
        begin
          TDirectory.CreateDirectory(TPath.GetDirectoryName(DstFile));
          Doc.SaveToFile(DstFile);
          Log('Successfully saved to: ' + DstFile);
          Result := True;
        end
        else
        begin
          Log('Failed to generate page content.');
        end;
      end;

    finally
      FPDFText_ClosePage(TextPage);
    end;
  finally
    Doc.Free;
    
    // Clean up lists
    for var Key in YGroups.Keys do
      YGroups[Key].Free;
    YGroups.Free;
    
    for var CInfo in CollectedChars do
      CInfo.Free;
    CollectedChars.Free;
    GroupKeys.Free;
    LineTexts.Free;
  end;
end;

var
  DstPDF, SampleDir: string;
  FileList: TArray<string>;
begin
  try
    SetupDllSearchPath;
    
    SampleDir := '..\sample-files';
    if not TDirectory.Exists(SampleDir) then
      SampleDir := 'sample-files';
      
    if not TDirectory.Exists(SampleDir) then
    begin
      Writeln('Error: sample-files folder not found.');
      ExitCode := 1;
      Exit;
    end;

    FileList := TDirectory.GetFiles(SampleDir, '*.pdf');
    if Length(FileList) = 0 then
    begin
      Writeln('No PDF files found in sample-files directory.');
      Exit;
    end;

    Writeln(Format('Found %d PDF files. Starting test processing...', [Length(FileList)]));
    for var FName in FileList do
    begin
      Writeln('');
      Writeln('========================================');
      Writeln('Processing: ' + ExtractFileName(FName));
      
      // 1. Dump details
      DumpPDFObjects(FName);
      
      // 2. Perform process
      DstPDF := TPath.Combine(TPath.Combine(SampleDir, 'output_moved'), ExtractFileName(FName));
      if ProcessPDFMove(FName, DstPDF) then
      begin
        Writeln('SUCCESS!');
        Writeln('--- Verifying output file structure ---');
        DumpPDFObjects(DstPDF);
      end
      else
        Writeln('FAILED!');
    end;
    
  except
    on E: Exception do
    begin
      Writeln('Unexpected Exception: ' + E.ClassName + ': ' + E.Message);
      ExitCode := 1;
    end;
  end;
end.
