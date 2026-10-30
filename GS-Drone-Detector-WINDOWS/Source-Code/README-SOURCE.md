# Developer Source — GS Drone Detector v0.9

The main app and setup are standalone Windows Go applications. These source files are **not required** for end users.

## Structure

- `app/main.go` — local Wi-Fi survey backend
- `app/web/index.html` — dashboard
- `app/web/brand.png` and `app/web/icon.png` — supplied purple drone artwork in the app
- `app/rsrc_windows_amd64.syso` — embedded Windows icon resource
- `setup/installer.go` — installer / uninstaller and setup UI
- `setup/brand.png`, `setup/icon.ico` — installer artwork and installed shortcut icon
- `setup/GS-Drone-Detector.exe` — embedded payload used when building the installer
- `setup/rsrc_windows_amd64.syso` — embedded setup EXE icon

To rebuild both EXEs on a Windows development computer, install Go 1.23+ and run `BUILD_WINDOWS_RELEASE.bat`. It builds the application first and then includes it in the installer.

The project uses the Windows Wi-Fi survey (`netsh`), not raw Remote ID packet decoding or Bluetooth detection.
