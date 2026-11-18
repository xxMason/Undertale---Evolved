@echo off
rem Starts the Ultimate Battle Engine in its own window (not embedded in the Godot editor).
rem Messages such as "REPORT saved ..." appear in this console while you play.
rem Extra options pass through, e.g.:  play.bat --playback "C:\...\replay.json"
rem
rem The first time (or after an engine update that needs it) it runs the setup itself: it
rem finds your Undertale, checks it, and extracts the game's data into this folder once. Your
rem Undertale install and its saves are only read, never changed, and nothing of the game is
rem downloaded: it all comes from your own copy.
cd /d "%~dp0"
set "need_setup="
if not exist "godot\extracted\engine.json" (
    set "need_setup=1"
    echo First start: setting up from your copy of Undertale. This takes a few minutes, once.
) else (
    findstr /r /c:"^.extract_version.: 2," "godot\extracted\engine.json" >nul || (
        set "need_setup=1"
        echo This engine needs the game data extracted again. Setting up from your copy of
        echo Undertale; this takes a few minutes, once.
    )
)
if defined need_setup (
    echo.
    powershell -NoProfile -ExecutionPolicy Bypass -File scripts\prepare-godot.ps1
    if errorlevel 1 goto setup_failed
    echo.
    echo Setup finished. Starting the engine...
)
rem Godot: the path setup remembered (config\godot_path.txt), else %GODOT%, else Steam's copy.
if exist "config\godot_path.txt" set /p GODOT=<"config\godot_path.txt"
if not defined GODOT set "GODOT=C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"
if not exist "%GODOT%" goto no_godot
"%GODOT%" --path godot -- %*
if errorlevel 1 pause
exit /b

:setup_failed
echo.
echo Setup failed; the message above says why. If Undertale is somewhere unusual, run:
echo   setup.bat -Undertale "D:\Games\Undertale"
echo and then play.bat again.
pause
exit /b 1

:no_godot
echo Godot was not found at:
echo   "%GODOT%"
echo Run setup.bat with your Godot 4.7 executable, for example:
echo   setup.bat -Godot "C:\Godot\Godot_v4.7-stable_win64.exe"
pause
exit /b 1
