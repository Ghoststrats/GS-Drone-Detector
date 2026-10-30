# GS Drone Detector — Windows v0.9 Beta

**GhostStrats LLC | Safety Is an Illusion**

A Windows tool for passive wireless awareness. The updated release uses the GhostStrats purple drone design for the dashboard, setup interface, and installed app shortcuts.

## Option 1: Install on your computer

1. Extract the ZIP file.
2. Double-click **GS-Drone-Detector-v0.9-Setup.exe**.
3. Your default browser opens the branded setup screen.
4. Choose whether to create a desktop shortcut, then select **INSTALL APPLICATION**.
5. When installation completes, select **CLOSE SETUP**.
6. Open **GS Drone Detector** from the Start Menu or desktop shortcut.

The installer creates a current-user installation, normally under:
`%LOCALAPPDATA%\Programs\GhostStrats\GS Drone Detector`

The installed version is registered in Windows **Installed apps**, where it can be uninstalled. If a shortcut cannot be created due to Windows or folder restrictions, open the app directly from the installation folder.

## Option 2: Run from a USB flash drive (no installation)

1. Extract the ZIP file.
2. Copy **GS-Drone-Detector-v0.9-Portable.exe** to a USB flash drive.
3. Plug the USB drive into your Windows 10/11 x64 computer.
4. Double-click the portable EXE from File Explorer.
5. The dashboard opens in your browser. Choose **START SCANNING**.
6. When finished, press **EXIT APP** and close the browser tab before removing the drive.

The portable EXE has everything needed for this Windows beta. Plugging in the USB drive does not start it automatically.

## Features

- Quiet Wi-Fi SSID scans without repeatedly popping up a command window.
- Two-second interval target between completed surveys (Windows hardware and drivers control actual refresh speed).
- A GhostStrats purple drone-themed local dashboard, alert tones, survey count, signal strength labels, and CSV export.
- Dedicated Stop and Exit controls. Closing the dashboard also requests backend shutdown, with a lost-contact fallback.
- Installer, optional shortcuts, portable app, and source code included.

## Important limitations

- These are **name-based Wi-Fi candidates**, not confirmed aircraft or decoded Remote ID broadcasts. Most drones will not be detected through ordinary Wi-Fi surveys.
- Signal strength is **not a drone distance measurement**.
- Requires Windows 10/11 x64 and a working Wi-Fi adapter. English-language `netsh` output is currently expected.
- Bluetooth scanning, raw packet capture, and Remote ID location decoding are **not** included in this release.
- Runs locally on your computer; it does not control drones or interfere with wireless signals.
- The app and installer are unsigned, so Windows may show a security warning. Check the file source and avoid disabling security tools.

## Source code

`Source-Code/` contains the application source, local HTML dashboard, installer source, bundled artwork and rebuild instructions. These are for developers; they are not needed to run the installer or portable EXE.

## Version note

v0.9 adds the new drone branding to the app and installer and removes unnecessary development-tool references from the setup screen. It preserves the v0.8 installer close/watchdog behavior and v0.6 app window-close watchdog behavior.

**Beta — the executables were cross-compiled but must still be tested on Windows hardware.**
