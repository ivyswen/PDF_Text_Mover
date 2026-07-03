unit uPDFTextMover;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  System.Generics.Defaults,
  System.IOUtils,
  Winapi.Windows,
  PdfiumCore,
  PdfiumLib;

type
  TMoveMode = (mmSmart, mmPercent, mmAbsolute);

  TCharInfo = class
  public
    Text: string;
    Left: Single;
    Bottom: Single;
    Right: Single;
    Top: Single;
    constructor Create(const AText: string; ALeft, ABottom, ARight, ATop: Single);
  end;

  TPDFTextMover = class
  private
    FMoveMode: TMoveMode;
    FSrcX1, FSrcY1, FSrcX2, FSrcY2: Single;
    FDestTx, FDestTy: Single;
    FFontName: string;
    FFontSize: Single;
    FEraseSource: Boolean;
    FAvoidOverlap: Boolean;
    FDestUseAbsolute: Boolean;

    function GetFontBaseName(Font: FPDF_FONT): string;
    function GetTextObjectString(TextObj: FPDF_PAGEOBJECT; TextPage: FPDF_TEXTPAGE): string;
  public
    constructor Create;
    
    function ProcessFile(const ASrcFile, ADstFile: string; out ALog: string): Boolean;

    property MoveMode: TMoveMode read FMoveMode write FMoveMode;
    property SrcX1: Single read FSrcX1 write FSrcX1;
    property SrcY1: Single read FSrcY1 write FSrcY1;
    property SrcX2: Single read FSrcX2 write FSrcX2;
    property SrcY2: Single read FSrcY2 write FSrcY2;
    property DestTx: Single read FDestTx write FDestTx;
    property DestTy: Single read FDestTy write FDestTy;
    property FontName: string read FFontName write FFontName;
    property FontSize: Single read FFontSize write FFontSize;
    property EraseSource: Boolean read FEraseSource write FEraseSource;
    property AvoidOverlap: Boolean read FAvoidOverlap write FAvoidOverlap;
    property DestUseAbsolute: Boolean read FDestUseAbsolute write FDestUseAbsolute;
  end;

implementation

constructor TCharInfo.Create(const AText: string; ALeft, ABottom, ARight, ATop: Single);
begin
  inherited Create;
  Text := AText;
  Left := ALeft;
  Bottom := ABottom;
  Right := ARight;
  Top := ATop;
end;

{ TPDFTextMover }

constructor TPDFTextMover.Create;
begin
  inherited;
  FMoveMode := mmSmart;
  FSrcX1 := 35.0;
  FSrcY1 := 80.0;
  FSrcX2 := 95.0;
  FSrcY2 := 98.0;
  FDestTx := 44.0;
  FDestTy := 11.0;
  FFontName := 'Helvetica';
  FFontSize := 8.0;
  FEraseSource := True;
  FAvoidOverlap := False;
  FDestUseAbsolute := False;
end;

function TPDFTextMover.GetFontBaseName(Font: FPDF_FONT): string;
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

function TPDFTextMover.GetTextObjectString(TextObj: FPDF_PAGEOBJECT; TextPage: FPDF_TEXTPAGE): string;
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
      Result := Trim(Result);
    end;
  end;
end;

function CompareChars(const Left, Right: TCharInfo): Integer;
begin
  if Left.Left < Right.Left then
    Result := -1
  else if Left.Left > Right.Left then
    Result := 1
  else
    Result := 0;
end;

function TPDFTextMover.ProcessFile(const ASrcFile, ADstFile: string; out ALog: string): Boolean;
var
  Doc: TPdfDocument;
  Page: TPdfPage;
  LPage: FPDF_PAGE;
  TextPage: FPDF_TEXTPAGE;
  ObjCount, I: Integer;
  Obj: FPDF_PAGEOBJECT;
  L, B, R, T: Single;
  Txt, FName: string;
  AnsiFontName: AnsiString;
  Font: FPDF_FONT;
  CollectedChars: TList<TCharInfo>;
  PageWidth, PageHeight: Double;
  // Bounds
  LeftLim, RightLim, BottomLim, TopLim: Single;
  DestXVal, DestYVal: Single;
  // Grouping
  YGroups: TDictionary<Integer, TList<TCharInfo>>;
  GroupKeys: TList<Integer>;
  RoundedY, YVal: Integer;
  CharList: TList<TCharInfo>;
  LineTexts: TStringList;
  NewObj: FPDF_PAGEOBJECT;
  LineY: Single;
  LogList: TStringList;
  Success: Boolean;
begin
  Result := False;
  ALog := '';
  LogList := TStringList.Create;
  CollectedChars := TList<TCharInfo>.Create;
  YGroups := TDictionary<Integer, TList<TCharInfo>>.Create;
  GroupKeys := TList<Integer>.Create;
  LineTexts := TStringList.Create;

  Doc := TPdfDocument.Create;
  try
    try
      Doc.LoadFromFile(ASrcFile);
      Page := Doc.Pages[0];
      LPage := Page.Handle;
      PageWidth := Page.Width;
      PageHeight := Page.Height;
      LogList.Add(Format('PDF loaded: size=%.2f x %.2f pt.', [PageWidth, PageHeight]));

      // Calculate source bounding limits
      case FMoveMode of
        mmSmart:
        begin
          LeftLim := 100.0;
          RightLim := 999999.0;
          BottomLim := 0.0;
          TopLim := 150.0;
          LogList.Add('Mode: Smart (extract right-bottom)');
        end;
        mmPercent:
        begin
          LeftLim := PageWidth * (FSrcX1 / 100.0);
          RightLim := PageWidth * (FSrcX2 / 100.0);
          BottomLim := PageHeight * (1.0 - (FSrcY2 / 100.0));
          TopLim := PageHeight * (1.0 - (FSrcY1 / 100.0));
          LogList.Add(Format('Mode: Percent (Src X: %.1f%%-%.1f%%, Y: %.1f%%-%.1f%%)', [FSrcX1, FSrcX2, FSrcY1, FSrcY2]));
          LogList.Add(Format('Calculated limits: X=[%.1f, %.1f], Y=[%.1f, %.1f]', [LeftLim, RightLim, BottomLim, TopLim]));
        end;
        mmAbsolute:
        begin
          LeftLim := FSrcX1;
          RightLim := FSrcX2;
          BottomLim := FSrcY1;
          TopLim := FSrcY2;
          LogList.Add(Format('Mode: Absolute (Src X: %.1f-%.1f, Y: %.1f-%.1f)', [FSrcX1, FSrcX2, FSrcY1, FSrcY2]));
        end;
      end;

      // Calculate target write location independently
      if FDestUseAbsolute then
      begin
        DestXVal := FDestTx;
        DestYVal := FDestTy;
        LogList.Add(Format('Target Position: Absolute (X: %.1f pt, Y: %.1f pt)', [FDestTx, FDestTy]));
      end
      else
      begin
        DestXVal := PageWidth * (FDestTx / 100.0);
        DestYVal := PageHeight * (1.0 - (FDestTy / 100.0)) - FFontSize;
        LogList.Add(Format('Target Position: Percent (X: %.1f%%, Y: %.1f%%)', [FDestTx, FDestTy]));
      end;

      TextPage := FPDFText_LoadPage(LPage);
      try
        ObjCount := FPDFPage_CountObjects(LPage);
        // Backwards iteration to support removing objects
        for I := ObjCount - 1 downto 0 do
        begin
          Obj := FPDFPage_GetObject(LPage, I);
          if FPDFPageObj_GetType(Obj) <> FPDF_PAGEOBJ_TEXT then
            Continue;

          if FPDFPageObj_GetBounds(Obj, L, B, R, T) = 0 then
            Continue;

          // Check limits
          if (L < LeftLim) or (L > RightLim) or (B < BottomLim) or (B > TopLim) then
            Continue;

          Font := FPDFTextObj_GetFont(Obj);
          FName := GetFontBaseName(Font);

          // For Smart Mode, we specifically filter for Helvetica (excluding Bold).
          // For other modes, we extract all text objects inside the user's defined region (no font restriction).
          if (FMoveMode <> mmSmart) or (Pos('Helvetica', FName) > 0) then
          begin
            // Check bold exclusion in smart mode
            if (FMoveMode = mmSmart) and (Pos('Bold', FName) > 0) then
              Continue;

            Txt := GetTextObjectString(Obj, TextPage);
            if Txt <> '' then
            begin
              CollectedChars.Add(TCharInfo.Create(Txt, L, B, R, T));
              if FEraseSource then
              begin
                FPDFPage_RemoveObject(LPage, Obj);
                FPDFPageObj_Destroy(Obj);
              end;
            end;
          end;
        end;

        if CollectedChars.Count = 0 then
        begin
          LogList.Add('No matching text objects found in the specified source area.');
          if FEraseSource then
          begin
            TDirectory.CreateDirectory(TPath.GetDirectoryName(ADstFile));
            Doc.SaveToFile(ADstFile);
            LogList.Add('Saved unmodified copy to output.');
            Result := True;
            Exit;
          end;
        end;

        LogList.Add(Format('Found %d character/text objects in source region.', [CollectedChars.Count]));

        // Group by Y (tolerance 3.0 units)
        for I := 0 to CollectedChars.Count - 1 do
        begin
          RoundedY := Round(CollectedChars[I].Bottom);
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
            YGroups.Add(YVal, TList<TCharInfo>.Create);
          YGroups[YVal].Add(CollectedChars[I]);
        end;

        // Sort keys descending (Top line first)
        for var Key in YGroups.Keys do
          GroupKeys.Add(Key);
        GroupKeys.Sort;
        GroupKeys.Reverse;

        for I := 0 to GroupKeys.Count - 1 do
        begin
          CharList := YGroups[GroupKeys[I]];
          CharList.Sort(TComparer<TCharInfo>.Construct(CompareChars));
          
          Txt := '';
          for var CInfo in CharList do
            Txt := Txt + CInfo.Text;
          
          LineTexts.Add(Txt);
          LogList.Add(Format('Extracted Line %d: "%s"', [I + 1, Txt]));
        end;

        // Insert at target positions
        Success := True;
        for I := 0 to LineTexts.Count - 1 do
        begin
          LineY := DestYVal - (I * 18.0);

          AnsiFontName := AnsiString(FFontName);
          if AnsiFontName = '' then AnsiFontName := 'Helvetica';
          NewObj := FPDFPageObj_NewTextObj(Doc.Handle, PAnsiChar(AnsiFontName), FFontSize);
          if NewObj = nil then
          begin
            LogList.Add('Error: Failed to create new PDF Text Object.');
            Success := False;
            Break;
          end;

          if FPDFText_SetText(NewObj, PWideChar(WideString(LineTexts[I]))) = 0 then
          begin
            LogList.Add('Error: Failed to set text content.');
            FPDFPageObj_Destroy(NewObj);
            Success := False;
            Break;
          end;

          // Set location
          FPDFPageObj_Transform(NewObj, 1.0, 0.0, 0.0, 1.0, DestXVal, LineY);
          
          // Insert
          FPDFPage_InsertObject(LPage, NewObj);
          LogList.Add(Format('Inserted "%s" at X=%.2f, Y=%.2f', [LineTexts[I], DestXVal, LineY]));
        end;

        if Success then
        begin
          if FPDFPage_GenerateContent(LPage) <> 0 then
          begin
            TDirectory.CreateDirectory(TPath.GetDirectoryName(ADstFile));
            Doc.SaveToFile(ADstFile);
            LogList.Add('Successfully saved output to: ' + ADstFile);
            Result := True;
          end
          else
          begin
            LogList.Add('Error: Failed to generate page content stream.');
          end;
        end;

      finally
        FPDFText_ClosePage(TextPage);
      end;
    except
      on E: Exception do
      begin
        LogList.Add('Exception occurred: ' + E.ClassName + ': ' + E.Message);
        Result := False;
      end;
    end;
  finally
    Doc.Free;
    
    // Clean lists
    for var Key in YGroups.Keys do
      YGroups[Key].Free;
    YGroups.Free;
    
    for var CInfo in CollectedChars do
      CInfo.Free;
    CollectedChars.Free;
    GroupKeys.Free;
    LineTexts.Free;

    ALog := LogList.Text;
    LogList.Free;
  end;
end;

end.
