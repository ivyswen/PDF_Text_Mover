@echo off
echo ========================================
echo Building PDFTextMover (Win64 Release)...
echo ========================================

cd /d "%~dp0"

:: Ensure res file exists for compiled resources
if not exist "PDFTextMover.res" (
  if exist "PDFRenamer.res" (
    copy /Y "PDFRenamer.res" "PDFTextMover.res" > nul
    echo Duplicated resource file.
  )
)

if not exist "dcu" (
  mkdir "dcu"
)

:: Initialize Delphi environment for msbuild
call "d:\program files (x86)\embarcadero\studio\22.0\bin\rsvars.bat"
if errorlevel 1 (
  echo Error: Failed to load Delphi build environment.
  pause
  exit /b 1
)

:: Compile using MSBuild to embed the High DPI manifest from dproj
msbuild PDFTextMover.dproj /t:Build /p:Config=Release /p:Platform=Win64 /p:DCC_CodePage=65001
if errorlevel 1 (
  echo.
  echo Build failed! Please fix the errors and try again.
  pause
  exit /b 1
)

:: Copy to bin directory
copy /Y "Win64\Release\PDFTextMover.exe" "bin\PDFTextMover.exe"
if errorlevel 1 (
  echo Error: Failed to copy executable to bin folder.
  pause
  exit /b 1
)

echo.
echo Build succeeded! 
echo Executable generated: bin\PDFTextMover.exe
echo.

