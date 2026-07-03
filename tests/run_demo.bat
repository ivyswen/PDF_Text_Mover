@echo off
echo ========================================
echo Building PDFTextMoverDemo (Console Application)
echo ========================================
call "d:\program files (x86)\embarcadero\studio\22.0\bin\rsvars.bat"
if errorlevel 1 (
  echo Error: Failed to load Delphi environment (rsvars.bat).
  exit /b 1
)

cd /d "%~dp0"
dcc64.exe -Q -W -H -E. -I..\Source -U..\Source -N. PDFTextMoverDemo.dpr
if errorlevel 1 (
  echo Error: Compilation failed.
  exit /b 1
)

echo.
echo ========================================
echo Running PDFTextMoverDemo
echo ========================================
PDFTextMoverDemo.exe
if errorlevel 1 (
  echo Error: Execution failed.
  exit /b 1
)

echo.
echo Demo finished successfully.
pause
