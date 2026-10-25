@echo off
setlocal
cd /d "%~dp0"
set "TACTICS_GODOT=%~dp0.tools\godot\Godot_v4.7.2-stable_win64.exe"
if not exist "%TACTICS_GODOT%" (
  echo Open project.godot with Godot 4.7.2 or later.
  pause
  exit /b 1
)
start "Sigils and Oaths - Editor" "%TACTICS_GODOT%" --editor --path "%~dp0."
