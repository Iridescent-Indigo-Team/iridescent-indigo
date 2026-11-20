@echo off
rem ===========================================================================
rem CreateEventSource.bat FILE [EVENT_NAME]
rem ---------------------------------------------------------------------------
rem Opens an event's command script (src\tiled\events\<map>\<id>_<name>.rb)
rem in your editor, creating it first if needed. Called by the "Edit Event
rem Script" action of the Tiled extension (CreateRPGEvent.js). Uses %EDITOR%
rem when set, otherwise the program Windows opens .rb files with (Notepad if
rem none).
rem ===========================================================================
setlocal
set "FILE=%~1"
set "NAME=%~2"
if "%FILE%"=="" (
  echo Usage: %~nx0 FILE [EVENT_NAME] 1>&2
  exit /b 2
)
if "%NAME%"=="" set "NAME=event"
if not exist "%FILE%" (
  for %%D in ("%FILE%") do if not exist "%%~dpD" mkdir "%%~dpD"
  > "%FILE%" echo # Event "%NAME%"
  >> "%FILE%" echo # Page settings are on the event's object in Tiled. See docs/TILED.md.
  >> "%FILE%" echo.
  >> "%FILE%" echo page 0, [
  >> "%FILE%" echo ]
)
if not "%EDITOR%"=="" (
  start "" %EDITOR% "%FILE%"
  exit /b 0
)
assoc .rb >nul 2>&1 && (start "" "%FILE%" & exit /b 0)
start "" notepad "%FILE%"
exit /b 0
