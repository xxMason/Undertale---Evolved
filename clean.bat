@echo off
rem Removes everything setup.bat made in THIS folder, so setup can start fresh:
rem   source\            (the copy of Undertale's data.win and music)
rem   godot\extracted\   (the extracted game code and assets)
rem   tools\             (UndertaleModTool's command-line tool and its download)
rem   config\godot_path.txt
rem Your Undertale install and its saves are not touched, and nothing outside this folder is.
rem Works on folders nested too deep for Explorer to delete (robocopy mirrors an empty folder
rem over them first).
setlocal
cd /d "%~dp0"
if not exist "setup.bat" goto wrong_place
if not exist "scripts\prepare-godot.ps1" goto wrong_place

echo This deletes, inside %~dp0 :
echo   source\  godot\extracted\  tools\  config\godot_path.txt
if /i "%~1"=="/y" goto go
choice /m "Continue"
if errorlevel 2 exit /b 0
:go

set "EMPTY=%TEMP%\ube_empty_%RANDOM%%RANDOM%"
mkdir "%EMPTY%"
for %%D in ("source" "godot\extracted" "tools") do call :wipe %%D
rmdir "%EMPTY%"
if exist "config\godot_path.txt" del /q "config\godot_path.txt"
echo.
echo Done. Run setup.bat to set up again.
if /i not "%~1"=="/y" pause
exit /b 0

:wipe
if not exist "%~1\" exit /b 0
echo Removing %~1 ...
robocopy "%EMPTY%" "%~1" /MIR /NFL /NDL /NJH /NJS /NP /R:1 /W:1 >nul
rmdir /s /q "%~1"
if exist "%~1\" echo   Couldn't remove all of %~1 (a file may be open; close the game and try again).
exit /b 0

:wrong_place
echo clean.bat must stay in the UltimateBattleEngine folder, next to setup.bat.
pause
exit /b 1
