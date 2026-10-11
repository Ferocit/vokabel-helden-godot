@echo off
setlocal
title Vokabel-Helden
cd /d "%~dp0"

rem Godot suchen: Umgebungsvariable GODOT, bekannter Pfad, dann PATH.
if defined GODOT if exist "%GODOT%" goto run
set "GODOT=E:\Spiele\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"
if exist "%GODOT%" goto run
for %%G in (godot.exe godot4.exe Godot_v4.7.2-stable_win64.exe) do (
  for /f "delims=" %%P in ('where %%G 2^>nul') do (
    set "GODOT=%%P"
    goto run
  )
)
echo Godot 4.7 wurde nicht gefunden.
echo Bitte von https://godotengine.org herunterladen und den Pfad in der
echo Umgebungsvariable GODOT eintragen, z. B.:
echo   setx GODOT "C:\Programme\Godot\Godot_v4.7.2-stable_win64.exe"
pause
exit /b 1

:run
if /i "%~1"=="test" (
  echo Starte Tests ...
  "%GODOT%" --headless --path "%~dp0." -s res://tests/run_tests.gd
  pause
  exit /b %errorlevel%
)
if /i "%~1"=="export" (
  echo Exportiere nach build\windows\Vokabel-Helden.exe ...
  if not exist "build\windows" mkdir "build\windows"
  "%GODOT%" --headless --path "%~dp0." --export-release "Windows Desktop" "build/windows/Vokabel-Helden.exe"
  pause
  exit /b %errorlevel%
)
rem Beim ersten Start einmal importieren (Texturen, Sounds, Schriften).
if not exist ".godot\imported" (
  echo Erster Start: importiere Ressourcen ...
  "%GODOT%" --headless --path "%~dp0." --import
)
start "" "%GODOT%" --path "%~dp0."
