@echo off
rem One-time setup: finds your Undertale (Steam), checks it's v1.08, copies it into source\,
rem downloads UndertaleModTool's command-line tool, and extracts the game's code and assets
rem for the engine. Your Undertale install and its saves are only read, never changed.
rem   setup.bat                                   (finds Undertale and Godot itself)
rem   setup.bat -Undertale "D:\Games\Undertale" -Godot "C:\Godot\Godot_v4.7-stable_win64.exe"
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\prepare-godot.ps1 %*
if errorlevel 1 (
    echo.
    echo Setup failed; the message above says why.
) else (
    echo.
    echo Setup finished. Double-click play.bat to start.
)
pause
