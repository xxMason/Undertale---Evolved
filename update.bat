@echo off
rem Updates this folder from a newer tester zip: drag the zip onto this file, or double-click
rem it to use the newest UltimateBattleEngine-tester*.zip here or in Downloads. Keeps your
rem setup data, settings and saves; replaced files go to backup\ first (scripts\update.ps1).
rem (One line on purpose: this file may itself be replaced while it runs.)
cd /d "%~dp0" & powershell -NoProfile -ExecutionPolicy Bypass -File scripts\update.ps1 "%~1" & (if errorlevel 1 (echo. & echo The update did not happen; the message above says why.) else (echo. & echo Done. Double-click play.bat to start.)) & pause & exit /b
