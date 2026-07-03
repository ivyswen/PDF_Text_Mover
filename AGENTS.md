# Repository Guidelines

## Project Structure & Module Organization
This is a Delphi Win64 desktop application for moving PDF label text areas. The project entry points are `PDFTextMover.dpr` and `PDFTextMover.dproj` in the repository root. Application code lives under `src/`: `src/forms/` contains the main VCL form and DFM resources, while `src/services/` contains PDF processing logic. `Source/` holds the PDFium Pascal bindings and should be treated as third-party integration code. Build outputs and compiler caches go to `bin/`, `Win32/`, `Win64/`, and `dcu/`; do not commit generated artifacts. `tests/` contains the console demo harness, and `sample-files/` is reserved for local PDF fixtures and generated output.

## Build, Test, and Development Commands
- `compile_mover.bat`: loads the Delphi environment, builds `PDFTextMover.dproj` as Win64 Release, and copies `PDFTextMover.exe` to `bin/`.
- `tests\run_demo.bat`: compiles and runs the console demo against PDFs in `sample-files/`.
- `msbuild PDFTextMover.dproj /t:Build /p:Config=Release /p:Platform=Win64 /p:DCC_CodePage=65001`: direct CI-friendly build command when the Delphi environment is already configured.
Ensure `pdfium.dll` is present beside the executable before running the GUI or demo.

## Coding Style & Naming Conventions
Use UTF-8 for all source edits. Follow Delphi conventions: two-space indentation inside blocks, `PascalCase` for classes, methods, and properties, `T` prefixes for classes, and clear unit names such as `uPDFTextMover`. Keep UI behavior in `src/forms/` and reusable processing code in `src/services/`. Avoid broad edits to `Source/` unless updating PDFium bindings intentionally.

## Testing Guidelines
There is no formal unit-test framework yet. Validate PDF behavior with `tests\run_demo.bat`, using representative PDFs in `sample-files/`. Name new demo or regression inputs by scenario, for example `label-right-bottom-text.pdf`. Check both successful output generation and visual placement in the resulting PDFs.

## Commit & Pull Request Guidelines
This repository currently has no commit history, so use concise imperative commit subjects such as `Add adaptive target positioning`. Pull requests should describe the PDF scenario changed, list build or demo commands run, mention required `pdfium.dll` setup, and include before/after screenshots or sample output notes for UI/PDF layout changes.

## Security & Configuration Tips
Do not commit customer PDFs, generated output, local `.ini` files, or `pdfium.dll`. Keep machine-specific Delphi paths in scripts documented when changed, and prefer environment setup instructions over hard-coded local paths where practical.
