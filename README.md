# GS Drone Detector

**Turbo Drone Awareness for Linux**

Created by **GhostStrats** | Version 2.5

**PRIVACY IS AN ILLUSION. KNOWLEDGE IS A TOOL.**

---

## About GS Drone Detector

GS Drone Detector is a free, standalone Linux-based wireless detection tool designed to help users identify possible drones through Wi-Fi, Bluetooth Low Energy (BLE), and supported Remote ID broadcasts.

My goal with this project is simple: make drone awareness technology more accessible without requiring expensive commercial equipment or a cloud account.

The software uses radio information already available to your computer, combines it with drone-related identification clues, and displays possible matches in a live terminal dashboard.

**No complicated interface. No cloud account. Just your Linux computer and supported wireless hardware.**

This is an educational wireless-awareness tool, not a guaranteed drone detection or aircraft safety system.

## Features

- Turbo wireless scanning
- Drone-focused Wi-Fi discovery
- Bluetooth Low Energy (BLE) detection
- Supported Open Drone ID decoding
- Possible drone manufacturer identification
- Real-time signal strength indicators
- Green, yellow, and red signal warnings
- Audible detection alerts
- Automatic detection updates
- Black-and-purple GhostStrats terminal interface
- Optional manufacturer database updates
- Optional local detection logs
- Offline demonstration and self-testing
- Esc to stop scanning

---

## How It Works

GS Drone Detector examines nearby supported wireless broadcasts and attempts to identify information associated with drones.

The program uses three main detection methods.

### 1. Wi-Fi Drone Discovery

The software uses Linux NetworkManager to survey nearby Wi-Fi networks.

It examines available information including:

- Network names (SSIDs)
- MAC addresses and BSSIDs
- Manufacturer-prefix information
- Signal strength
- Wireless channels and frequencies

The tool compares these observations against drone-related names and manufacturers.

Potential matches include DJI, Autel, Parrot, Skydio, BETAFPV, and other recognizable drone-related products.

**Important:** A manufacturer or network-name match only identifies a possible drone-related device. It does not confirm that an aircraft is present.

### 2. Bluetooth Drone Detection

GS Drone Detector also supports Bluetooth Low Energy advertisements.

When compatible Bluetooth hardware and software are available, it can listen for:

- BLE device names
- Bluetooth identifiers
- Received signal strength (RSSI)
- Advertised services
- Manufacturer identifiers
- Supported Remote ID service data

BLE discovery does not require pairing with a drone.

Unrelated Bluetooth devices are filtered from the drone candidate display.

### 3. Remote ID Detection

Remote ID is a technology that allows compatible drones to broadcast identification and flight information.

With supported receiving hardware, GS Drone Detector can decode certain Open Drone ID messages.

Available information may include:

- Drone identification
- GPS latitude and longitude
- Altitude
- Speed
- Flight heading
- Reported controller or launch location
- Other supported broadcast fields

Remote ID data availability varies by drone, broadcast method, and receiving hardware.

A decoded Remote ID-format message is not independently authenticated by the scanner.

---

## Turbo Scanning

The tool launches directly into its Turbo scanning mode.

There is no additional menu to navigate before starting.

| Feature | Default setting |
|---|---|
| Wi-Fi scan requests | Every 3 seconds |
| Dashboard refresh | Every 0.15 seconds |
| Optional monitor-mode dwell | 0.5 seconds |
| BLE listening | Continuous when available |
| Stop scanning | Esc or Ctrl+C |

Actual Wi-Fi scan frequency depends on your adapter, drivers, and NetworkManager. Some adapters may throttle repeated scans.

### Stopping the scanner

**Press Esc to stop scanning and return control to the terminal or the calling toolkit.**

`Ctrl+C` is also supported.

---

## Signal Strength Warning System

GS Drone Detector displays color-coded warnings based on received signal levels.

| Signal index | Warning | Interpretation |
|---|---|---|
| 0–49 | 🟢 GREEN | Weak signal — possibly farther away |
| 50–89 | 🟡 YELLOW | Moderate signal — proximity uncertain |
| 90–99 | 🔴 RED | Very strong signal — possibly close |
| 100 | 🔴 RED | DANGER: MAX SIGNAL — POSSIBLY CLOSE |

The program can produce an audible alert when a new candidate is detected or when a qualifying signal enters the red zone.

**Signal strength does not equal distance.** A strong signal cannot confirm how close a drone actually is, and the warning system must not be treated as a collision or threat prediction.

---

## Installation

### Requirements

- Linux operating system
- Bash
- Python 3
- Compatible Wi-Fi adapter for wireless network surveys
- NetworkManager for normal Wi-Fi discovery
- Optional Bluetooth hardware and Bleak for BLE detection
- Optional Scapy and monitor-mode Wi-Fi adapter for raw Wi-Fi Remote ID capture

### Step 1 — Install dependencies

For supported Debian-based distributions such as Linux Mint, Kali Linux, and Parrot OS:

```bash
sudo apt update
sudo apt install python3 network-manager bluez iw python3-scapy ieee-data
```

If available from your distribution, install the optional BLE library:

```bash
sudo apt install python3-bleak
```

Not every distribution provides `python3-bleak` through its package repositories.

### Step 2 — Download the script

Download `gs-drone-detector.sh` from this GitHub repository.

Place the script inside a folder such as Downloads.

### Step 3 — Run GS Drone Detector

Open a terminal in the script's folder:

```bash
cd ~/Downloads
bash gs-drone-detector.sh
```

Turbo scanning will begin automatically.

### Optional — Make it executable

```bash
chmod +x gs-drone-detector.sh
./gs-drone-detector.sh
```

No separate application installation is required to run the standalone script.

---

## Available Commands

| Command | Purpose |
|---|---|
| `bash gs-drone-detector.sh` | Start Turbo scanning |
| `bash gs-drone-detector.sh scan` | Start scanning explicitly |
| `bash gs-drone-detector.sh check` | Check system dependencies and adapters |
| `bash gs-drone-detector.sh demo` | Display simulated drone detections |
| `bash gs-drone-detector.sh test` | Run the offline software self-test |
| `bash gs-drone-detector.sh update-db` | Download optional manufacturer information |
| `bash gs-drone-detector.sh install` | Display installation instructions |
| `bash gs-drone-detector.sh help` | Display command options |

### BLE-only scanning

To scan supported Bluetooth advertisements without Wi-Fi network surveys:

```bash
bash gs-drone-detector.sh scan --ble-only
```

### Advanced Wi-Fi Remote ID scanning

Normal Wi-Fi discovery identifies nearby networks and possible drone names. It does not automatically decode raw Wi-Fi Remote ID messages.

For supported raw Wi-Fi beacon detection, use an appropriate monitor-mode adapter and Scapy:

```bash
sudo bash gs-drone-detector.sh scan --monitor wlan1
```

Replace `wlan1` with your actual compatible interface.

A separate USB Wi-Fi adapter is recommended. The tool is designed to avoid repurposing a connected adapter for monitor mode.

### Save detection events

Logging is optional and disabled by default.

```bash
bash gs-drone-detector.sh scan --log "$HOME/drone-events.jsonl"
```

Logs may contain device identifiers and reported location information. Protect them appropriately.

---

## Test the Detector Without a Drone

An offline demonstration is included.

Run:

```bash
bash gs-drone-detector.sh demo
```

The demonstration displays simulated drone signals, including example drone-related wireless names and Remote ID data.

**All demo detections are fictional.**

You can also test the software decoder:

```bash
bash gs-drone-detector.sh test
```

The test checks supported Remote ID decoding, drone-name matching, wireless data parsing, signal warning thresholds, and related functions.

The offline self-test does not establish that actual radio reception will work on your hardware.

---

## Optional Manufacturer Database

The tool supports an optional IEEE manufacturer-prefix database.

Run:

```bash
bash gs-drone-detector.sh update-db
```

This downloads public manufacturer-prefix information over HTTPS to improve possible vendor identification.

The database is stored locally.

The database update does not upload scanned device identifiers or detected locations.

A manufacturer prefix does not establish that a device is a drone, and randomized addresses can limit manufacturer identification.

---

## Limitations

GS Drone Detector is a wireless-awareness tool, not a universal drone radar.

Please understand the following:

- Not every drone broadcasts recognizable Wi-Fi or Bluetooth information.
- Proprietary radio links may be invisible to ordinary computer wireless adapters.
- Remote ID availability varies across drone models and configurations.
- Signal strength cannot reliably establish distance.
- A matched manufacturer does not prove a drone is present.
- Remote ID-format data can potentially be spoofed.
- Some advanced functions require additional hardware or administrator permissions.
- Fast scans may affect Wi-Fi performance or miss short transmissions.
- Normal Wi-Fi surveys can transmit probe requests, so not every scanning method is entirely passive.

This project does not include drone jamming, takeover, flight control, or unauthorized camera access.

---

## Privacy & Responsible Use

GS Drone Detector is designed for education, wireless awareness, and responsible research.

It does not require a cloud account or a subscription service.

Normal detection takes place locally. Internet access is optional for updating the manufacturer database.

Only scan networks and devices you are authorized to inspect, and respect applicable radio, privacy, and interception laws.

**This project is not intended to serve as a safety-certified aircraft warning or collision-avoidance system.**

---

## About GhostStrats

GhostStrats focuses on Linux, cybersecurity education, wireless technology, digital privacy, survival technology, and practical DIY projects.

My mission is to help people learn how technology works and give them the knowledge to become more aware and self-reliant.

You don't always need expensive equipment or complicated solutions.

Sometimes the tools you need are already available. You just need to understand how to use them.

**YouTube:** https://www.youtube.com/@GhostStrats

