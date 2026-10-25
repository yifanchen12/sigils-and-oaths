@echo off
setlocal
cd /d "%~dp0"
set "TACTICS_GODOT=%~dp0.tools\godot\Godot_v4.7.2-stable_win64.exe"
set "TACTICS_CONSOLE=%~dp0.tools\godot\Godot_v4.7.2-stable_win64_console.exe"
if not exist "%TACTICS_GODOT%" (
  echo Godot portable runtime was not found in .tools\godot.
  echo Open project.godot with Godot 4.7.2 or later instead.
  pause
  exit /b 1
)
"%TACTICS_CONSOLE%" --headless --path "%~dp0." --editor --quit --log-file "%~dp0import.log" >nul 2>&1
if errorlevel 1 (
  echo Project import failed. See import.log.
  pause
  exit /b 1
)
findstr /C:"SCRIPT ERROR:" /C:"ERROR:" "%~dp0import.log" >nul
if not errorlevel 1 (
  echo Project import reported errors. See import.log.
  pause
  exit /b 1
)
start "Sigils and Oaths" "%TACTICS_GODOT%" --path "%~dp0." --log-file "%~dp0play.log"
