@echo off
rem Deletes an old UltimateBattleEngine folder, however deeply nested its copies are.
rem
rem HOW TO USE: drag the old UltimateBattleEngine folder (for example the one inside
rem   ...\steamapps\common\Undertale\) and drop it ONTO this file.
rem
rem It only deletes a folder that is an UltimateBattleEngine folder (it must contain
rem setup.bat or scripts\prepare-godot.ps1), it asks before deleting, and it asks for
rem administrator rights only if Windows refuses without them (folders under
rem Program Files usually need them). Nothing else is touched.
setlocal
set "TARGET=%~1"
if "%TARGET%"=="" goto usage
if not exist "%TARGET%\" goto not_folder
if exist "%TARGET%\setup.bat" goto ours
if exist "%TARGET%\scripts\prepare-godot.ps1" goto ours
goto not_ours

:ours
if /i "%~2"=="/elevated" goto go
echo This will permanently delete:
echo   "%TARGET%"
echo and everything inside it.
choice /m "Delete it"
if errorlevel 2 exit /b 0

:go
echo Deleting, this can take a few minutes if there are many copies...
set "EMPTY=%TEMP%\ube_empty_%RANDOM%%RANDOM%"
mkdir "%EMPTY%"
robocopy "%EMPTY%" "%TARGET%" /MIR /NFL /NDL /NJH /NJS /NP /R:1 /W:1 >nul
rmdir "%EMPTY%"
rmdir /s /q "%TARGET%" 2>nul
if not exist "%TARGET%\" goto done
if /i "%~2"=="/elevated" goto still_there
echo Windows needs administrator rights for this folder; asking for them now...
powershell -NoProfile -Command "Start-Process -FilePath $env:ComSpec -ArgumentList ('/c \"\"' + '%~f0' + '\" \"' + $env:TARGET + '\" /elevated\"') -Verb RunAs"
exit /b 0

:done
echo.
echo Deleted.
echo Optional: in Steam, right-click Undertale, Properties, Installed Files,
echo "Verify integrity of game files" to double-check the game itself.
pause
exit /b 0

:still_there
echo.
echo Some files couldn't be deleted. Close every setup or game window (or restart the
echo PC), then drop the folder onto this file again.
pause
exit /b 1

:usage
echo Drag the old UltimateBattleEngine folder and drop it onto this file.
pause
exit /b 1

:not_folder
echo "%TARGET%" is not a folder. Drop the UltimateBattleEngine folder itself onto this file.
pause
exit /b 1

:not_ours
echo "%TARGET%" doesn't look like an UltimateBattleEngine folder (no setup.bat in it),
echo so it was left alone. Drop the UltimateBattleEngine folder itself onto this file.
pause
exit /b 1
