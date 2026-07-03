program PDFTextMover;

uses
  Vcl.Forms,
  PdfiumLib in 'Source\PdfiumLib.pas',
  PdfiumCore in 'Source\PdfiumCore.pas',
  frmMoverMain in 'src\forms\frmMoverMain.pas' {frmMoverMain},
  uPDFTextMover in 'src\services\uPDFTextMover.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TfrmMoverMain, MoverMainForm);
  Application.Run;
end.
