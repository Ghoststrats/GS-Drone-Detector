@echo off
setlocal
cd /d "%~dp0"
set "GOOS=windows"
set "GOARCH=amd64"
echo Building Windows app...
go build -trimpath -ldflags="-H=windowsgui -s -w" -o "setup\GS-Drone-Detector.exe" .\app
if errorlevel 1 (echo App build failed & pause & exit /b 1)
echo Building Windows installer...
go build -trimpath -ldflags="-H=windowsgui -s -w" -o "GS-Drone-Detector-v0.9-Setup.exe" .\setup
if errorlevel 1 (echo Installer build failed & pause & exit /b 1)
copy /y "setup\GS-Drone-Detector.exe" "GS-Drone-Detector-v0.9-Portable.exe" >nul
echo Done. You can distribute the two EXE files.
pause
