#!/usr/bin/env bash
# GS Drone Detector v2.5 — GhostStrats
# A single, stand-alone Bash script with an embedded Python 3 scanner.
# No affiliation with any drone manufacturer.
set -Eeuo pipefail
if ! command -v python3 >/dev/null 2>&1; then
  printf 'GS Drone Detector requires Python 3. On Mint: sudo apt install python3\n' >&2
  exit 1
fi
GS_TEMP_PY="$(mktemp "${TMPDIR:-/tmp}/gs-drone-detector.XXXXXXXX.py")"
chmod 600 "$GS_TEMP_PY"
trap 'rm -f "$GS_TEMP_PY"' EXIT
sed -n '/^# GS_PYTHON_START$/,/^GS_PYTHON_EOF$/p' "$0" | sed '1d;$d' > "$GS_TEMP_PY"
export GS_SOURCE_SH="$(realpath "${BASH_SOURCE[0]}")"
exec_python() { python3 -u "$GS_TEMP_PY" "$@"; }
exec_python "$@"
exit $?
: <<'GS_PYTHON_EOF'
# GS_PYTHON_START
import argparse
import contextlib
import asyncio
import collections
import datetime as dt
import json
import math
import os
import select
import termios
from pathlib import Path
import queue
import re
import shutil
import signal
import struct
import subprocess
import sys
import threading
import time
import urllib.request

APP = 'GS DRONE DETECTOR'
VERSION = '2.5'
HOME = Path(os.environ.get('XDG_DATA_HOME') or (Path.home()/'.local/share'))/'gs-drone-detector'
OUI_LOCATIONS = [HOME/'oui.txt', Path('/usr/share/ieee-data/oui.txt'),
                 Path('/usr/share/misc/oui.txt'), Path('/usr/share/hwdata/oui.txt')]
VENDOR_URL = 'https://standards-oui.ieee.org/oui/oui.txt'
RID_OUIS = (b'\xfa\x0b\xbc', b'\x90\x3a\xe6')
ODID_UUID = '0000fffa-0000-1000-8000-00805f9b34fb'
ODID_SHORT = 'fffa'
COLOR = sys.stdout.isatty() and not os.getenv('NO_COLOR')
PURPLE = '\033[38;5;141m' if COLOR else ''
LAV = '\033[38;5;183m' if COLOR else ''
YELLOW = '\033[38;5;220m' if COLOR else ''
RED = '\033[1;31m' if COLOR else ''
GREEN = '\033[1;32m' if COLOR else ''
GRAY = '\033[38;5;245m' if COLOR else ''
BOLD = '\033[1m' if COLOR else ''
RESET = '\033[0m' if COLOR else ''

# Descriptive clues, not authoritative aircraft signatures. Boundaries avoid
# matching words like "anomaly" as "neo". Extend using signatures.json.
RULES = [
    ('DJI-NEO', 'Possible DJI Neo Wi-Fi device', 'drone'),
    ('DJI NEO', 'Possible DJI Neo Wi-Fi device', 'drone'),
    ('DJI', 'Drone / DJI wireless product', 'drone'),
    ('MAVIC', 'Drone / DJI Mavic family', 'drone'),
    ('MATRICE', 'Drone / DJI Matrice family', 'drone'),
    ('PHANTOM', 'Possible DJI Phantom', 'drone'),
    ('AVATA', 'Possible DJI Avata', 'drone'),
    ('TELLO', 'Possible Ryze/DJI Tello', 'drone'),
    ('PARROT', 'Possible Parrot wireless device', 'drone'),
    ('ANAFI', 'Possible Parrot Anafi', 'drone'),
    ('SKYDIO', 'Possible Skydio wireless device', 'drone'),
    ('AUTEL', 'Possible Autel wireless device', 'drone'),
    ('HOLY STONE', 'Possible Holy Stone drone', 'drone'),
    ('HOLYSTONE', 'Possible Holy Stone drone', 'drone'),
    ('POTENSIC', 'Possible Potensic drone', 'drone'),
    ('HUBSAN', 'Possible Hubsan drone', 'drone'),
    ('BETAFPV', 'Possible BETAFPV drone', 'drone'),
    ('FIMI', 'Possible FIMI drone', 'drone'),
    ('EMAX', 'Possible EMAX FPV device', 'drone'),
    ('FPV', 'Possible FPV drone-related product (unverified)', 'drone'),
]


def run(cmd, timeout=12):
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout,
                           errors='replace', check=False)
        return p.returncode, p.stdout, p.stderr
    except (OSError, subprocess.TimeoutExpired) as e:
        return 127, '', str(e)


def safe(s, limit=65):
    # Avoid terminal escape/OSC injection from hostile SSIDs, Bluetooth names or IDs.
    s = re.sub(r'[\x00-\x1f\x7f-\x9f]', '?', str(s))
    return s[:limit]


def cmd_exists(c):
    return shutil.which(c) is not None


def supported():
    for name in ('scapy', 'bleak'):
        try:
            __import__(name)
            yield name, True
        except ImportError:
            yield name, False


def banner():
    print(f'\n{PURPLE}╔══════════════════════════════════════════════════════════════╗{RESET}')
    print(f'{PURPLE}║  {BOLD}GS DRONE DETECTOR  {VERSION:<37}{RESET}{PURPLE}║{RESET}')
    print(f'{PURPLE}║  GHOSTSTRATS  //  WIRELESS AWARENESS                          ║{RESET}')
    print(f'{PURPLE}╚══════════════════════════════════════════════════════════════╝{RESET}')
    print(f'{GRAY}Receive / discover  •  evidence-based matches  •  no tracking service{RESET}\n')


def vendor_db():
    for loc in OUI_LOCATIONS:
        if loc.is_file():
            return loc
    return None


def load_vendors():
    path = vendor_db()
    res = {}
    if not path:
        return res
    try:
        # IEEE (hex) format. Don't load everything into display; just OUI->vendor.
        with open(path, errors='replace') as f:
            for line in f:
                m = re.match(r'^\s*([0-9A-Fa-f]{6})\s+\(hex\)\s+(.+?)\s*$', line)
                if m:
                    res[m.group(1).upper()] = safe(m.group(2), 75)
    except OSError:
        return {}
    return res


def fetch_vendors():
    banner()
    print('Optional: download IEEE manufacturer prefix data (HTTPS).')
    print('No detected device IDs, names or locations are uploaded.')
    print('Manufacturer assignment only indicates a possible radio manufacturer.\n')
    try:
        req = urllib.request.Request(VENDOR_URL, headers={'User-Agent':'GS-Drone-Detector/2.4'})
        with urllib.request.urlopen(req, timeout=18) as resp:
            data = resp.read(12_000_001)
        if len(data) > 12_000_000 or len(data) < 200_000 or b'(hex)' not in data:
            raise ValueError('Received data did not look like the expected OUI text database')
        HOME.mkdir(parents=True, exist_ok=True)
        temp = HOME/'oui.txt.part'
        temp.write_bytes(data)
        temp.chmod(0o600)
        temp.replace(HOME/'oui.txt')
        print(f'{GREEN}Manufacturer database updated: {HOME / "oui.txt"}{RESET}')
    except Exception as e:
        print(f'{RED}Update failed: {safe(e)}{RESET}')
        return 1
    return 0


def lookup_vendor(mac, vendors):
    prefix = re.sub('[^0-9a-fA-F]', '', mac).upper()[:6]
    if len(prefix) != 6:
        return ''
    # Locally administered/randomized Wi-Fi and BLE MACs have no reliable OUI.
    try:
        if int(prefix[:2], 16) & 2:
            return 'Randomized/local address (no reliable maker)'
    except ValueError:
        return ''
    return vendors.get(prefix, '')


def classify(name, maker='', custom=None):
    name = safe(name or '', 90)
    maker = safe(maker or '', 90)
    # Important: "RID-" is an SSID hint, NOT a validated protocol payload.
    if name.upper().startswith('RID-'):
        return 'Possible Remote ID SSID (unverified)', 'drone', 'SSID prefix RID-', 2
    rules = (custom or []) + RULES
    for match_text, label, kind in rules:
        # Conservative name token matching; do not assert model identity.
        pat = r'(?<![A-Z0-9])' + re.escape(match_text.upper()) + r'(?![A-Z0-9])'
        if re.search(pat, name.upper()):
            return label, kind, f'Name includes "{match_text}"', 2
    for word in ('DJI','SKYDIO','PARROT','AUTEL','RYZE'):
        if word in maker.upper():
            return f'Possible {word} wireless product', 'drone', 'Manufacturer prefix only; not proof of an aircraft', 1
    return 'Unclassified wireless device', 'unknown', '', 0


def custom_rules():
    loc = HOME/'signatures.json'
    if not loc.is_file():
        return []
    try:
        data = json.loads(loc.read_text())
        out = []
        for entry in data[:100]:
            term = entry.get('match','')
            kind = entry.get('kind','unknown')
            # Only explicitly drone-tagged custom rules are accepted. Ignore
            # legacy RC-car/unknown signatures saved by earlier versions.
            if isinstance(term, str) and 2 <= len(term) <= 45 and kind == 'drone':
                out.append((term.upper(), safe(entry.get('label') or ('Possible '+term)), 'drone'))
        return out
    except (ValueError, OSError, TypeError):
        return []


def split_nmcli(s):
    return [x.replace('\\:', ':').replace('\\\\', '\\')
            for x in re.split(r'(?<!\\):', s.rstrip('\n'))]


def decode_message(m):
    if len(m) != 25 or (m[0] & 15) > 3:
        return None
    typ = m[0] >> 4
    if typ == 0:
        code = m[1] >> 4
        ident = safe(m[2:22].split(b'\0')[0].decode('ascii', 'replace').strip(), 30)
        if code == 0 or not ident:
            return None
        return {'type':'id', 'id':ident, 'id_type':code, 'uas_type':m[1]&15}
    if typ == 1:
        lat = struct.unpack_from('<i', m, 5)[0]/1e7
        lon = struct.unpack_from('<i', m, 9)[0]/1e7
        raw_direction = m[2]
        heading = raw_direction + (180 if (m[1] & 2) else 0)
        vraw = m[3]
        speed = (vraw*.75 + 63.75) if (m[1]&1) else vraw*.25
        vertical = struct.unpack_from('b', m, 4)[0]*.5
        raw_alt = struct.unpack_from('<H', m, 15)[0]
        raw_height = struct.unpack_from('<H', m, 17)[0]
        rec = {'type':'location'}
        if -90 <= lat <= 90 and -180 <= lon <= 180 and (lat != 0 or lon != 0):
            rec['lat'], rec['lon'] = round(lat,7), round(lon,7)
        if raw_direction < 180:
            rec['heading_deg'] = heading
        if speed < 254.25:
            rec['speed_mps'] = round(speed,2)
        if vertical != 63:
            rec['vertical_mps'] = vertical
        if raw_alt not in (0, 0xFFFF):
            rec['alt_m'] = round(raw_alt*.5-1000,1)
        if raw_height not in (0, 0xFFFF):
            rec['height_m'] = round(raw_height*.5-1000,1)
        rec['status'] = (m[1] >> 4) & 15
        return rec
    if typ == 4:
        lat = struct.unpack_from('<i', m, 2)[0]/1e7
        lon = struct.unpack_from('<i', m, 6)[0]/1e7
        rec = {'type':'system', 'operator_location_type':m[1]&3}
        if -90 <= lat <= 90 and -180 <= lon <= 180 and (lat != 0 or lon != 0):
            rec['operator_lat'], rec['operator_lon'] = round(lat,7),round(lon,7)
        return rec
    if typ == 5:
        ident = safe(m[2:22].split(b'\0')[0].decode('utf-8','replace'), 30)
        return {'type':'operator_id','operator_id':ident} if ident else None
    if typ == 3:
        label = safe(m[2:25].split(b'\0')[0].decode('utf-8','replace'), 40)
        return {'type':'self_id', 'self_id':label} if label else None
    return {'type':'other', 'message_type':typ} if typ == 2 else None


def decode_pack(blob):
    if len(blob) < 25:
        return []
    if blob[0] >> 4 == 15:
        if len(blob) < 3 or blob[1] != 25 or not 1 <= blob[2] <= 9:
            return []
        count = blob[2]
        if len(blob) < 3 + count*25:
            return []
        blocks = [blob[3+i*25:3+(i+1)*25] for i in range(count)]
    else:
        blocks = [blob[:25]]
    decoded = [decode_message(b) for b in blocks]
    return [d for d in decoded if d]


def decode_wifi_vendor(payload):
    if len(payload) < 30 or payload[:3] not in RID_OUIS or payload[3] != 0x0d:
        return []
    return decode_pack(payload[5:])  # vendor OUI/type (4 bytes) + counter (1)


def decode_scapy_vendor(oui, info):
    # Scapy Dot11EltVendorSpecific.info begins with vendor type 0x0D.
    # Generic Dot11Elt.info may instead contain the full 3-byte OUI.
    if isinstance(oui, int):
        if not 0 <= oui <= 0xffffff:
            return []
        return decode_wifi_vendor(oui.to_bytes(3, 'big') + bytes(info))
    if isinstance(oui, (bytes, bytearray)) and len(oui)==3:
        return decode_wifi_vendor(bytes(oui) + bytes(info))
    return decode_wifi_vendor(bytes(info))

def decode_ble_service(value):
    # Bluetooth 0xFFFA Service Data value: app 0x0D, counter, then 25 byte message.
    if len(value) < 27 or value[0] != 0x0d:
        return []
    return decode_pack(value[2:])


def signal_index(value, unit):
    """Display-only 0..100 signal index. It is never a distance measurement.

    NetworkManager offers a Wi-Fi quality percentage, while monitor-mode Wi-Fi
    and BLE often offer received power in dBm. The latter is scaled using a
    *rough* -100..-40 dBm visualization window and is not RF calibrated.
    """
    try:
        value = float(value)
    except (TypeError, ValueError):
        return None
    if not math.isfinite(value):
        return None
    if unit == 'dBm':
        return max(0, min(100, round((value + 100) / 60 * 100)))
    if unit == '%':
        return max(0, min(100, round(value)))
    return None


def signal_advisory(value, unit):
    """Color means received signal *level*, not verified proximity or threat."""
    idx = signal_index(value, unit)
    if idx is None:
        return {'index':None, 'level':'unknown', 'color':GRAY,
                'message':'SIGNAL UNKNOWN — DISTANCE UNKNOWN'}
    if idx == 100:
        return {'index':idx, 'level':'red', 'color':RED,
                'message':'DANGER: MAX SIGNAL — POSSIBLY CLOSE'}
    if idx >= 90:
        return {'index':idx, 'level':'red', 'color':RED,
                'message':'VERY STRONG SIGNAL — POSSIBLY CLOSE'}
    if idx >= 50:
        return {'index':idx, 'level':'yellow', 'color':YELLOW,
                'message':'MODERATE SIGNAL — PROXIMITY UNCERTAIN'}
    return {'index':idx, 'level':'green', 'color':GREEN,
            'message':'WEAK SIGNAL — POSSIBLY FARTHER AWAY'}


def radio_bar(value, unit):
    status = signal_advisory(value,unit)
    idx = status['index']
    if idx is None:
        return GRAY + '░'*12 + RESET + '  N/A'
    n = max(0, min(12,round(idx/100*12)))
    if unit == 'dBm':
        desc=f'{float(value):.0f} dBm (rough index {idx}/100)'
    else:
        desc=f'{float(value):.0f}% Wi-Fi quality'
    return f'{status["color"]}{"█"*n}{GRAY}{"░"*(12-n)}{RESET} {desc}'


def projected_approach(details, observer):
    # This is a *planar straight-line projection* from the broadcast velocity.
    # It is NOT time-to-collision, a safety warning or a reliable prediction.
    if not observer or any(k not in details for k in ('lat','lon','heading_deg','speed_mps')):
        return None
    lat, lon = details['lat'],details['lon']
    lat0, lon0 = observer
    if not (-90<=lat<=90 and -90<=lat0<=90 and -180<=lon<=180 and -180<=lon0<=180):
        return None
    speed = details['speed_mps']
    if speed < 1 or speed > 90:
        return None
    # East/North meters from observer, local equirectangular approximation.
    x = math.radians(lon-lon0)*6371000*math.cos(math.radians((lat+lat0)/2))
    y = math.radians(lat-lat0)*6371000
    theta = math.radians(details['heading_deg'])
    vx, vy = speed*math.sin(theta), speed*math.cos(theta)
    distance = math.hypot(x,y)
    if distance > 10000 or distance < 1:
        return {'distance_m':round(distance), 'eta':None, 'trend':'outside projection limits'}
    dot = x*vx+y*vy
    if dot >= 0:
        return {'distance_m':round(distance),'eta':None,'trend':'moving away / not closing'}
    tclose = -dot/(speed*speed)
    miss = abs(x*vy-y*vx)/speed
    if miss > 100 or tclose > 1800:
        return {'distance_m':round(distance),'eta':None,
                'trend':f'closest projected pass {miss:.0f} m away'}
    # Solve for earliest time when distance <= 100m using constant velocity.
    b = 2*dot
    c = distance*distance-100*100
    disc = b*b-4*speed*speed*c
    if disc < 0:
        return {'distance_m':round(distance),'eta':None,'trend':'no projected 100m crossing'}
    eta = max(0,(-b-math.sqrt(disc))/(2*speed*speed))
    return {'distance_m':round(distance),'eta':round(eta),'trend':'straight-line estimate'}


class Monitor:
    def __init__(self, args):
        self.args=args
        self.q=queue.Queue(maxsize=4096)  # bounded: a busy RF environment must not freeze the UI
        self.devices={}
        self.events=collections.deque(maxlen=7)
        self.wifi_count=0
        self.ble_count=0
        self.rid_count=0
        self.last_survey=0
        self.survey_attempts=0
        self.survey_in_progress=False
        self.dropped_packets=0
        self.packet_guard=threading.Lock()
        self.packet_seen={}
        self.survey_guard=threading.Lock()
        self.last_prune=0
        self.wifi_scan_lock=threading.Lock()
        self.error=''
        self.started=time.time()
        self.end=(self.started+args.duration) if args.duration else float('inf')
        self.stop=threading.Event()
        self.vendors=load_vendors()
        self.rules=custom_rules()
        self.logfile=None
        if args.log:
            p=Path(args.log).expanduser()
            p.parent.mkdir(parents=True,exist_ok=True)
            # Never overwrite existing logs; opt-in only.
            fd=os.open(p,os.O_WRONLY|os.O_CREAT|os.O_APPEND,0o600)
            self.logfile=os.fdopen(fd,'a',buffering=1)
        self.rid_sources=set()
        self.all_wifi=set()
        self.all_ble=set()
        self.monitor_interface=None
        self.owned_monitor=False
        self.sniffer=None
        self.ble_worker=None
        self.wifi_process=None
        self.wifi_process_lock=threading.Lock()

    def close(self):
        self.stop.set()
        # End any in-flight NetworkManager scan rather than leaving it running
        # after Esc has returned control to the toolkit.
        with self.wifi_process_lock:
            proc=self.wifi_process
        if proc is not None and proc.poll() is None:
            try:
                proc.terminate()
                proc.wait(timeout=0.8)
            except (OSError,subprocess.TimeoutExpired):
                try:proc.kill();proc.wait(timeout=0.8)
                except (OSError,subprocess.TimeoutExpired):pass
        if self.ble_worker is not None and self.ble_worker.is_alive():
            self.ble_worker.join(timeout=1.0)
        if self.sniffer is not None:
            try:
                self.sniffer.stop()
            except Exception:
                pass
        if self.owned_monitor and self.monitor_interface:
            run(['ip','link','set',self.monitor_interface,'down'])
            run(['iw','dev',self.monitor_interface,'del'])
        if self.logfile:
            self.logfile.close()

    def put(self, medium, ident, name, signal=None, unit='dBm', maker='', detail=None, rid=None, channel=''):
        evt={'medium':medium, 'ident':safe(ident,80), 'name':safe(name,65),
             'signal':signal, 'unit':unit, 'maker':maker, 'detail':detail or {},
             'rid':rid or [], 'channel':str(channel)}
        try:
            self.q.put_nowait(evt)
        except queue.Full:
            # Drop excess observations rather than starving display / keyboard controls.
            self.dropped_packets+=1

    def wifi_survey_once(self):
        if self.stop.is_set():
            return
        if not self.survey_guard.acquire(blocking=False):
            return
        try:
            if not self.stop.is_set():
                self.survey_in_progress=True
                self.wifi_survey()
        finally:
            self.survey_in_progress=False
            self.survey_guard.release()

    def wifi_survey(self):
        if not self.wifi_scan_lock.acquire(blocking=False):
            return
        try:
            self._wifi_survey_once()
        finally:
            self.wifi_scan_lock.release()

    def run_wifi_command(self, cmd):
        """Cancellable Wi-Fi survey; Esc stops its active nmcli process."""
        try:
            with self.wifi_process_lock:
                if self.stop.is_set():
                    return 130,'','Scan stopped'
                proc=subprocess.Popen(cmd,stdout=subprocess.PIPE,stderr=subprocess.PIPE,
                                      text=True,errors='replace')
                self.wifi_process=proc
            try:
                out,err=proc.communicate(timeout=15)
                return proc.returncode,out,err
            except subprocess.TimeoutExpired:
                proc.kill()
                out,err=proc.communicate()
                return 124,out,err or 'Wi-Fi survey timed out'
        except OSError as exc:
            return 127,'',str(exc)
        finally:
            with self.wifi_process_lock:
                self.wifi_process=None

    def _wifi_survey_once(self):
        if self.stop.is_set():
            return
        if not cmd_exists('nmcli'):
            self.error='NetworkManager nmcli unavailable; Wi-Fi survey disabled'
            return
        cmd=['nmcli','-t','-f','SSID,BSSID,CHAN,FREQ,SIGNAL','device','wifi','list']
        if self.args.wifi_iface:
            cmd+=['ifname',self.args.wifi_iface]
        cmd+=['--rescan','yes']
        self.survey_attempts+=1
        code,stdout,err=self.run_wifi_command(cmd)
        if code:
            if not self.stop.is_set():
                self.error='Wi-Fi survey: '+safe(err or stdout,105)
            return
        self.last_survey=time.time()
        for row in stdout.splitlines():
            fields=split_nmcli(row)
            if len(fields)<5:
                continue
            ssid,mac,chan,freq,quality=fields[:5]
            try: value=max(0,min(100,int(quality)))
            except ValueError: value=None
            key=mac.strip().lower() or ssid.strip()
            if not key: continue
            maker=lookup_vendor(mac,self.vendors)
            if classify(ssid,maker,self.rules)[1] != 'drone':
                continue
            self.all_wifi.add(key)
            self.put('Wi-Fi survey',key,ssid or '(hidden SSID)',value,'%',maker,
                     {'ssid':safe(ssid),'bssid':mac,'frequency_mhz':safe(freq)}, channel=chan)

    async def ble_loop(self):
        try:
            from bleak import BleakScanner
        except ImportError:
            self.error='Bluetooth BLE disabled: install python3-bleak (if available)'
            return
        def discovered(device, adv):
            name=adv.local_name or device.name or '(unnamed BLE device)'
            uuids=list(adv.service_uuids or [])
            service_data=adv.service_data or {}
            rid=[]
            for key,val in service_data.items():
                if ODID_SHORT in key.lower():
                    rid += decode_ble_service(bytes(val))
            rid_claimed=any(ODID_SHORT in x.lower() for x in uuids) or any(
                ODID_SHORT in x.lower() for x in service_data)
            # BLE advertisements are public data. Only forward drone evidence;
            # common headphones, watches and smart-home devices stay hidden.
            if not rid and not rid_claimed and classify(name, '', self.rules)[1] != 'drone':
                return
            det={'bluetooth_address':safe(device.address,60),
                 'service_uuids':','.join(safe(x,50) for x in uuids[:8]),
                 'rid_service_advertised':rid_claimed,
                 'ble_company_ids':','.join(f'0x{int(x):04X}' for x in list((adv.manufacturer_data or {}).keys())[:8])}
            tx_power=getattr(adv,'tx_power',None)
            if tx_power is not None:
                det['ble_tx_power_dbm']=tx_power
            self.all_ble.add(device.address)
            self.put('BLE',device.address,name,adv.rssi,'dBm','',det,rid)

        try:
            async with BleakScanner(discovered):
                while not self.stop.is_set() and time.time()<self.end:
                    await asyncio.sleep(.25)
        except Exception as e:
            self.error='Bluetooth scanning unavailable: '+safe(e,100)

    def ble_thread(self):
        asyncio.run(self.ble_loop())

    def on_packet(self,pkt):
        try:
            from scapy.layers.dot11 import Dot11,Dot11Beacon,Dot11Elt
            from scapy.layers.dot11 import RadioTap
            if not pkt.haslayer(Dot11Beacon): return
            mac=pkt[Dot11].addr2 or ''
            sig=None
            if pkt.haslayer(RadioTap):
                try: sig=int(pkt[RadioTap].dBm_AntSignal)
                except (TypeError,ValueError,AttributeError): pass
            ssid=''
            rid=[]
            elt=pkt.getlayer(Dot11Elt)
            while elt is not None:
                data=bytes(getattr(elt,'info',b'') or b'')
                if elt.ID==0:
                    ssid=data.decode('utf-8','replace')
                elif elt.ID==221:
                    rid+=decode_scapy_vendor(getattr(elt,'oui',None),data)
                elt=elt.payload.getlayer(Dot11Elt)
            maker=lookup_vendor(mac,self.vendors)
            if rid or ssid.upper().startswith('RID-') or classify(ssid,maker,self.rules)[3]:
                # A beaconing AP may send >10 frames/second. Keep newer readings,
                # coalesce repeated name-only frames, and preserve RID frames.
                if not rid:
                    now=time.monotonic()
                    with self.packet_guard:
                        if now-self.packet_seen.get(mac,0)<0.35:
                            return
                        self.packet_seen[mac]=now
                        if len(self.packet_seen)>2000:
                            self.packet_seen.clear()
                self.put('Wi-Fi beacon',mac,ssid or '(RID broadcaster)',sig,'dBm',maker,
                         {'ssid':safe(ssid),'bssid':mac},rid,channel=getattr(self.args,'_channel',''))
        except Exception as e:
            self.error='Beacon decoder: '+safe(e,85)

    def start_monitor(self):
        iface=self.args.monitor
        if not iface:
            return
        if os.geteuid()!=0:
            self.error='--monitor requires sudo/root; ordinary Wi-Fi and BLE scans do not'
            return
        try:
            from scapy.all import AsyncSniffer
        except ImportError:
            self.error='scapy unavailable for raw Wi-Fi Remote ID beacon capture'
            return
        rc,out,err=run(['iw','dev',iface,'info'])
        if rc:
            self.error='Monitor interface not found: '+safe(iface)
            return
        if 'type monitor' in out:
            mon=iface
        else:
            rc,link,_=run(['iw','dev',iface,'link'])
            if 'Connected to' in link:
                self.error='Refusing to interrupt connected Wi-Fi adapter; use a spare USB adapter'
                return
            mon='gsmon'+str(os.getpid()%100000)
            if len(mon)>15:
                mon=mon[:15]
            rc,_,err=run(['iw','dev',iface,'interface','add',mon,'type','monitor'])
            if rc:
                self.error='Cannot create monitor interface: '+safe(err,70)
                return
            self.monitor_interface=mon
            self.owned_monitor=True
            rc,_,err=run(['ip','link','set',mon,'up'])
            if rc:
                self.error='Cannot activate monitor interface: '+safe(err,70)
                return
        self.monitor_interface=mon
        self.args._channel=self.args.channels[0]
        run(['iw','dev',mon,'set','channel',str(self.args.channels[0])])
        try:
            self.sniffer=AsyncSniffer(iface=mon,prn=self.on_packet,store=False,
                                     lfilter=lambda p:True)
            self.sniffer.start()
            if len(self.args.channels)>1:
                threading.Thread(target=self.hop_channels,daemon=True).start()
        except Exception as e:
            self.error='Sniffer cannot start: '+safe(e,85)

    def hop_channels(self):
        # Only tunes a dedicated monitor interface. Some drivers cannot hop.
        idx=0
        while not self.stop.wait(max(0.25,self.args.dwell)):
            idx=(idx+1)%len(self.args.channels)
            chan=self.args.channels[idx]
            rc,_,err=run(['iw','dev',self.monitor_interface,'set','channel',str(chan)])
            if not rc:
                self.args._channel=chan
            else:
                self.error='Monitor channel hop rejected: '+safe(err,70)

    def apply(self,evt):
        now=time.time()
        ident=evt['ident']
        key=evt['medium']+':'+ident
        decoded=evt['rid']
        maker=evt['maker']
        name=evt['name']
        label,kind,reason,confidence=classify(name,maker,self.rules)
        if evt['detail'].get('rid_service_advertised') and not decoded and confidence < 2:
            label='Remote ID Bluetooth service claimed (not decoded)'
            kind='drone'
            reason='Advertises UUID 0xFFFA; not a validated drone transmission'
            confidence=2
        if decoded:
            label='Open Drone ID broadcast (protocol match)'
            kind='drone'
            reason='Decoded Open Drone ID payload; origin not authenticated'
            confidence=3
            self.rid_sources.add(key)
        # Drone-only means no stored candidate, warning, history or log for
        # unclassified signals, RC cars, or unrelated wireless electronics.
        if kind != 'drone' or confidence == 0:
            return
        old=self.devices.get(key)
        if old:
            # Sticky RID status and message fields; don't downgrade when broadcasts rotate.
            if old['confidence']>confidence:
                label,kind,reason,confidence=(old[k] for k in ('label','kind','reason','confidence'))
            old.update({'name':name,'maker':maker,'signal':evt['signal'],
                        'unit':evt['unit'],'channel':evt['channel'],'seen':now,
                        'label':label,'kind':kind,'reason':reason,'confidence':confidence})
            old['details'].update({k:v for k,v in evt['detail'].items() if v})
            item=old
        else:
            item={'key':key,'medium':evt['medium'],'ident':ident,'name':name,
                  'maker':maker,'signal':evt['signal'],'unit':evt['unit'],
                  'channel':evt['channel'],'seen':now,'first':now,
                  'label':label,'kind':kind,'reason':reason,'confidence':confidence,
                  'details':dict(evt['detail'])}
            self.devices[key]=item
        for rec in decoded:
            item['details'].update({k:v for k,v in rec.items() if k!='type'})
            if rec.get('type')=='location' and 'lat' in rec and 'lon' in rec:
                item['details']['telemetry_received_at']=now
        prev_conf=old.get('last_alert_conf',0) if old else 0
        prev_level=old.get('last_signal_level') if old else None
        status=signal_advisory(item['signal'], item['unit'])
        item['last_signal_level']=status['level']
        # Alert once on a new clue, an evidence upgrade, or a transition into
        # a very strong signal; repeated strong samples do not repeat the bell.
        new_evidence=confidence>0 and confidence>prev_conf
        new_red=(confidence>0 and old is not None and status['level']=='red'
                 and prev_level!='red')
        if new_evidence or new_red:
            if new_evidence:
                item['last_alert_conf']=confidence
                type_word='RID SIGNAL' if confidence==3 else 'POSSIBLE DRONE'
                msg=f'{type_word} • {label} • {safe(name,30)}'
                if status['level']=='red':
                    msg+=' • '+status['message']
            else:
                msg=f'VERY STRONG SIGNAL • {safe(name,30)} • {status["message"]}'
            self.events.appendleft((now,msg,confidence))
            if self.logfile:
                line={'timestamp':dt.datetime.now(dt.timezone.utc).isoformat(),
                      'event':msg,'medium':evt['medium'],'device':item}
                self.logfile.write(json.dumps(line,ensure_ascii=True,default=str)+'\n')
                item['last_telemetry_logged']=now
            if self.args.alert and (confidence>=2 or status['level']=='red') and sys.stdout.isatty():
                sys.stdout.write('\a')
                sys.stdout.flush()
            if not sys.stdout.isatty() or self.args.plain:
                print(f'[{dt.datetime.now():%H:%M:%S}] {safe(msg,140)}',flush=True)
        # Optional opt-in log: retain changing telemetry as well as initial alerts.
        # Limit snapshots to once per 3 seconds per source to avoid huge log files.
        if (decoded and self.logfile
                and now-item.get('last_telemetry_logged',0)>=3):
            self.logfile.write(json.dumps({
                'timestamp':dt.datetime.now(dt.timezone.utc).isoformat(),
                'event':'rid_telemetry', 'medium':evt['medium'], 'device':item
            },ensure_ascii=True,default=str)+'\n')
            item['last_telemetry_logged']=now
        self.wifi_count=len(self.all_wifi)
        self.ble_count=len(self.all_ble)
        self.rid_count=len(self.rid_sources)

    def format_item(self,item):
        det=item['details']
        age=int(time.time()-item['seen'])
        conf=item['confidence']
        flag=(GREEN+'RID FORMAT'+RESET if conf==3 else YELLOW+'POSSIBLE'+RESET if conf else GRAY+'UNCLASSIFIED'+RESET)
        chan=(' ch '+item['channel']) if item['channel'] else ''
        lines=[f'  {flag}   {safe(item["name"],36):36}  [{safe(item["medium"])}{chan}]',
               f'  {GRAY}{safe(item["label"],78)}{RESET}',
               f'  SIGNAL  {radio_bar(item["signal"],item["unit"])}     last seen {age}s ago',
               f'  SIGNAL ZONE  {signal_advisory(item["signal"],item["unit"])["color"]}{signal_advisory(item["signal"],item["unit"])["message"]}{RESET}',
               f'  RADIO ID {safe(item["ident"],40)}   |   EVIDENCE: {safe(item["reason"],62)}']
        if det.get('frequency_mhz'):
            lines.append('  Wi-Fi frequency: '+safe(det['frequency_mhz'])+' MHz')
        if det.get('service_uuids'):
            lines.append('  BLE services: '+safe(det['service_uuids'],93))
        if det.get('ble_company_ids'):
            lines.append('  BLE company IDs: '+safe(det['ble_company_ids'],70)+' (not drone proof)')
        if det.get('ble_tx_power_dbm') is not None:
            lines.append('  BLE advertised TX power: '+safe(det['ble_tx_power_dbm'])+' dBm (if supplied)')
        if item['maker']:
            lines.append('  MAKER   '+safe(item['maker'],68)+' (OUI clue only)')
        if conf==3:
            rows=[]
            for k,label in [('id','Drone ID'),('uas_type','Aircraft type code'),
                            ('lat','Latitude'),('lon','Longitude'),('alt_m','Altitude MSL m'),
                            ('height_m','Height m'),('speed_mps','Speed m/s'),
                            ('vertical_mps','Climb m/s'),('heading_deg','Heading deg'),
                            ('status','Status code'),('operator_lat','Controller/launch latitude'),
                            ('operator_lon','Controller/launch longitude'),('operator_id','Operator ID'),
                            ('self_id','Description')]:
                if k in det: rows.append(f'{label}: {det[k]}')
            for i in range(0,len(rows),2):
                lines.append('  '+ ' | '.join(rows[i:i+2])[:102])
            is_fresh = time.time() - det.get('telemetry_received_at',0) <= 10
            pr=projected_approach(det,self.args.observer) if is_fresh else None
            if pr:
                eta=pr['eta']
                estimate=(f'{eta}s until projected within 100 m (horizontal)' if eta is not None
                          else pr['trend'])
                lines.append(f'  POSITION ~{pr["distance_m"]} m from observer (broadcast GPS) | {estimate}')
                lines.append('  '+GRAY+'Straight-line estimate, not a safety or collision warning'+RESET)
            else:
                lines.append('  RANGE / ARRIVAL  Unknown (RSSI does not give distance or ETA)')
        else:
            lines.append('  RANGE / ARRIVAL  Unknown (no verified location/motion data)')
        return lines

    def display(self, remaining):
        if not sys.stdout.isatty() or self.args.plain:
            return
        cols=shutil.get_terminal_size((100,35)).columns
        w=max(54,min(cols-1,108))
        hline='─'*w
        recent=sorted((v for v in self.devices.values()
                       if time.time()-v['seen']<max(15,self.args.interval*3)),
                       key=lambda d:(d['confidence'],d['seen']),reverse=True)
        rows=shutil.get_terminal_size((100,35)).lines
        compact=rows < 32
        out=['\033[H\033[2J\033[?25l', f'{PURPLE}╔'+('═'*(w-2))+'╗'+RESET,
             f'{PURPLE}║{RESET}  {BOLD}{APP}  V{VERSION}{RESET}   •   LIVE WIRELESS WATCH'+(' '*max(0,w-52))+PURPLE+'║'+RESET,
             f'{PURPLE}╚'+('═'*(w-2))+'╝'+RESET,
             f'{GRAY}  PASSIVE LISTEN (BLE / monitor mode) • Wi-Fi name survey may send probes{RESET}',
             f'{LAV}  ACTIVE  {str(remaining)+"s remaining" if remaining is not None else "ESC = STOP + HOME"}{RESET}   Wi-Fi networks {self.wifi_count}   BLE {self.ble_count}   RID {self.rid_count}   MATCHES {len([x for x in self.devices.values() if x["confidence"]])}',
             f'  UPDATE {self.args.refresh:.2f}s | Wi-Fi {"OFF (BLE-only)" if self.args.no_wifi else f"scan request {self.args.interval:g}s"} | Channel dwell {self.args.dwell:g}s | Survey: {"disabled" if self.args.no_wifi else ("working" if self.survey_in_progress else (str(int(time.time()-self.last_survey))+"s ago" if self.last_survey else "waiting"))}',
             f'  SIGNAL GUIDE: {GREEN}GREEN <50{RESET}  {YELLOW}YELLOW 50–89{RESET}  {RED}RED 90–100{RESET}  •  Signal, not distance',
             hline, f'  {BOLD}MATCHES  —  strongest evidence first{RESET}']
        show=[x for x in recent if x['confidence']>0][:(1 if compact else 3)]
        if not show:
            out.extend(['  No drone-related name or Remote ID matches yet.',
                        '  Unseen proprietary links cannot be ruled out.'])
        for item in show:
            item_lines=self.format_item(item)
            if compact:
                item_lines=item_lines[:5]+(item_lines[-1:] if item['confidence']==3 else [])
            out.extend(item_lines)
            out.append('')
        out += [hline, f'  {YELLOW}RECENT ALERTS{RESET}']
        if not self.events:
            out.append('  Waiting for a candidate...')
        else:
            for when,msg,confidence in list(self.events)[:(1 if compact else 3)]:
                out.append(f'  {dt.datetime.fromtimestamp(when):%H:%M:%S}  '+safe(msg,100))
        if self.dropped_packets:
            out.append(f'  {YELLOW}Radio capture overload: {self.dropped_packets} observations dropped; try a less busy wireless channel{RESET}')
        if self.error:
            out.append(f'  {RED}NOTE: {safe(self.error,100)}{RESET}')
        out += [hline, '  ESC: STOP SCAN + RETURN HOME   •   Ctrl+C: stop   •   Signal ≠ drone distance',
                '  Possible match ≠ confirmed drone  •  ETA unavailable from RSSI',
                '  Labels are heuristics  •  Transmitters can impersonate Remote ID packets']
        print('\n'.join(out),end='\n\033[J',flush=True)

    @contextlib.contextmanager
    def scan_keyboard(self):
        """Enable a single nonblocking Esc key during live scan.

        Restore the exact TTY state on Esc, Ctrl+C, exceptions, and normal exit
        so the toolkit's main-menu number reader works on the next screen.
        """
        if not (sys.stdin.isatty() and sys.stdout.isatty()):
            yield None
            return
        fd=sys.stdin.fileno()
        original=termios.tcgetattr(fd)
        new=termios.tcgetattr(fd)
        new[3] &= ~(termios.ICANON | termios.ECHO)
        new[6][termios.VMIN]=0
        new[6][termios.VTIME]=0
        try:
            termios.tcsetattr(fd,termios.TCSANOW,new)
            yield fd
        finally:
            termios.tcsetattr(fd,termios.TCSANOW,original)

    @staticmethod
    def escape_requested(fd):
        if fd is None:
            return False
        readable,_,_=select.select([fd],[],[],0)
        if not readable:
            return False
        key=os.read(fd,1)
        if key != b'\x1b':
            return False
        # Arrow and function keys start with ESC [ / ESC O. Swallow these
        # rather than stopping a scan when an arrow key is pressed.
        readable,_,_=select.select([fd],[],[],0.045)
        if readable:
            following=os.read(fd,1)
            if following in (b'[',b'O'):
                for _ in range(20):
                    readable,_,_=select.select([fd],[],[],0.005)
                    if not readable: break
                    part=os.read(fd,1)
                    if not part or 65<=part[0]<=90 or 97<=part[0]<=122 or part==b'~':break
                return False
        return True

    def run(self):
        if self.args.demo:
            self.end=time.time()+min(self.args.duration or 12,12)
            self.demo_events()
        else:
            if self.args.monitor:
                self.start_monitor()
            if not self.args.no_ble:
                self.ble_worker=threading.Thread(target=self.ble_thread,daemon=True)
                self.ble_worker.start()
        try:
            with self.scan_keyboard() as keyfd:
                if sys.stdout.isatty() and not self.args.plain:
                    print('\033[?25l',end='',flush=True)
                self._scan_loop(keyfd)
        except KeyboardInterrupt:
            pass
        finally:
            self.close()
            if sys.stdout.isatty() and not self.args.plain:
                print('\033[?25h\n',end='',flush=True)
        print(f'\n{PURPLE}SCAN SUMMARY{RESET}: {len(self.devices)} drone-related candidates, '
              f'{len([x for x in self.devices.values() if x["medium"]=="BLE"])} BLE drone clues, '
              f'{self.rid_count} RID protocol sources.')
        if not self.rid_count:
            print('No Remote ID packets decoded. That does NOT mean no drones are nearby.')
        if self.error:
            print('Scanner note:',self.error)
        if self.args.demo:
            print('SIMULATION ONLY: All displayed signals, drone IDs and telemetry were fabricated.')

    def _scan_loop(self,keyfd):
        nextwifi=0
        prev_display=0
        while time.time()<self.end and not self.stop.is_set():
            if self.escape_requested(keyfd):
                self.stop.set()
                break
            now=time.time()
            if (not self.args.demo and not self.args.no_wifi and now>=nextwifi
                    and not self.survey_guard.locked()):
                # Never block BLE or the dashboard on a slow NetworkManager scan.
                threading.Thread(target=self.wifi_survey_once,daemon=True).start()
                nextwifi=now+self.args.interval
            try:
                for _ in range(300):
                    evt=self.q.get_nowait()
                    self.apply(evt)
            except queue.Empty:
                pass
            # A continuously running detector should not retain every address forever.
            if now-self.last_prune>90:
                self.last_prune=now
                expired=[k for k,v in self.devices.items() if now-v['seen']>900]
                for k in expired: self.devices.pop(k,None)
                if len(self.devices)>2500:
                    newest=sorted(self.devices.items(),key=lambda kv:kv[1]['seen'],reverse=True)[:2000]
                    self.devices=dict(newest)
            if now-prev_display>=self.args.refresh:
                self.display(max(0,round(self.end-now)) if math.isfinite(self.end) else None)
                prev_display=now
            self.stop.wait(min(0.05, self.args.refresh / 2))
    def demo_events(self):
        self.all_wifi.update(('demo1','demo2','demo3'))
        self.all_ble.add('demo4')
        self.put('Wi-Fi survey','demo1','DJI-NEO-TEST',100,'%',detail={'ssid':'DJI-NEO-TEST'})
        self.put('BLE','demo2','BETAFPV-TEST',-64,'dBm',detail={'service_uuids':'180f'})
        self.put('Wi-Fi survey','demo3','HomeWifi',85,'%',detail={'ssid':'HomeWifi'})  # filtered
        rec=[{'type':'id','id':'SYNTHETIC-TEST-ID','uas_type':2},
             {'type':'location','lat':40.0,'lon':-75.0,'alt_m':40.0,
              'speed_mps':8.0,'heading_deg':90}]
        self.put('Wi-Fi beacon','demo4','RID-TEST-ONLY',-85,'dBm',rid=rec)


def make_args(argv):
    parser=argparse.ArgumentParser(prog='bash gs-drone-detector.sh',
        description='GS Drone Detector v2.5: drone-only Wi-Fi/BLE clues and supported Open Drone ID reception.')
    parser.add_argument('command', nargs='?', default='scan',
                        choices=['menu','scan','demo','test','check','update-db','pcap','install','help'])
    parser.add_argument('pcapfile',nargs='?')
    parser.add_argument('--duration',type=int,default=0,
                        help='Scan seconds (0 = continuous until Ctrl+C, default)')
    parser.add_argument('--interval',type=float,default=3,
                        help='Turbo Wi-Fi survey requests every 3s (driver may throttle)')
    parser.add_argument('--refresh',type=float,default=0.15,
                        help='Turbo terminal dashboard refresh (default 0.15s)')
    parser.add_argument('--wifi-iface',default='',help='Optional Wi-Fi interface, e.g. wlan0')
    parser.add_argument('--no-wifi',action='store_true',help='Disable normal Wi-Fi network surveys')
    parser.add_argument('--no-ble',action='store_true',help='Disable Bluetooth Low Energy listening')
    parser.add_argument('--ble-only',action='store_true',help='Show only BLE drone clues and BLE Remote ID; do not survey Wi-Fi')
    parser.add_argument('--monitor',default='',metavar='IFACE',
                        help='Advanced: monitor-capable Wi-Fi adapter for raw RID beacons (sudo)')
    parser.add_argument('--channels',default='1,6,11',
                        help='Raw beacon channel list, default 1,6,11')
    parser.add_argument('--dwell',type=float,default=0.5,help='Monitor channel dwell in seconds (default 0.5)')
    parser.add_argument('--observer-lat',type=float)
    parser.add_argument('--observer-lon',type=float)
    parser.add_argument('--log',help='OPT-IN: save detection event JSON lines to this path')
    parser.add_argument('--silent',action='store_true',help='Disable terminal alert bell')
    parser.add_argument('--plain',action='store_true',help='Stream alert messages instead of redrawing screen')
    args=parser.parse_args(argv)
    if not 0<=args.duration<=86400:
        parser.error('--duration must be 0..86400 (0 = continuous)')
    if not 3<=args.interval<=300 or not math.isfinite(args.interval):
        parser.error('--interval must be between 3 and 300 seconds')
    if not 0.1<=args.refresh<=3 or not math.isfinite(args.refresh):
        parser.error('--refresh must be between 0.1 and 3 seconds')
    if not 0.25<=args.dwell<=60 or not math.isfinite(args.dwell):
        parser.error('--dwell must be between 0.25 and 60 seconds')
    try:
        args.channels=[int(c) for c in args.channels.split(',')]
        if any(c<1 or c>196 for c in args.channels) or not args.channels:
            raise ValueError('channel range')
    except ValueError:
        parser.error('--channels must be comma-separated integer Wi-Fi channels')
    if (args.observer_lat is None)!=(args.observer_lon is None):
        parser.error('Provide both --observer-lat and --observer-lon, or neither')
    if args.observer_lat is not None and not (-90<=args.observer_lat<=90 and -180<=args.observer_lon<=180):
        parser.error('Invalid observer latitude / longitude')
    args.observer=(args.observer_lat,args.observer_lon) if args.observer_lat is not None else None
    if args.ble_only:
        args.no_wifi=True
        args.monitor=''
    args.alert=not args.silent
    args.demo=args.command=='demo'
    return parser,args


def check():
    banner()
    print('SYSTEM CHECK')
    for name in ('python3','nmcli','iw','ip','bluetoothctl','sudo'):
        print(f'  {name:14}: {"present" if cmd_exists(name) else "missing / optional"}')
    for name,available in supported():
        print(f'  python {name:7}: {"installed" if available else "not installed / optional"}')
    print(f'  IEEE vendor DB: {vendor_db() or "none (optional)"}')
    print('  Wireless adapters:')
    for cmd in (['nmcli','-t','-f','DEVICE,TYPE,STATE','dev'],['iw','dev']):
        if cmd_exists(cmd[0]):
            _,out,err=run(cmd)
            print(out[:1800] if out else '  '+safe(err[:200]))
    print('Drone-only Wi-Fi name matching: nmcli; BLE drone clues: BlueZ + Bleak.')
    print('Valid Remote ID Wi-Fi beacon decoding requires Scapy + monitor mode adapter.')
    print('Some Bluetooth 5 extended advertisements may not reach older radios/drivers.')
    print('Pairing is NOT required for drone advertisement or BLE Remote ID detection.')
    print('Only drone-related clues are displayed. Generic BLE devices stay hidden.')


def offline_test():
    banner()
    print(f'{YELLOW}OFFLINE SOFTWARE SELF-TEST — SIMULATED SIGNALS ONLY{RESET}')
    basic=bytes([0x02,0x12])+b'GS-SYNTHETIC-0001'.ljust(20,b'\x00')+bytes(3)
    loc=bytearray(25)
    loc[0],loc[1],loc[2],loc[3]=0x12,0,90,32
    struct.pack_into('<i',loc,5,400000000)
    struct.pack_into('<i',loc,9,-750000000)
    struct.pack_into('<H',loc,15,2080)
    packet=b'\xfa\x0b\xbc\x0d\x00\xf2\x19\x02'+basic+bytes(loc)
    r=decode_wifi_vendor(packet)
    assert len(r)==2 and r[0]['id']=='GS-SYNTHETIC-0001'
    assert r[1]['lat']==40 and r[1]['lon']==-75
    assert r[1]['heading_deg']==90 and r[1]['speed_mps']==8
    assert r[1]['alt_m']==40
    assert decode_wifi_vendor(b'not RID')==[]
    assert decode_ble_service(b'\x0d\x42'+basic)[0]['id']=='GS-SYNTHETIC-0001'
    assert classify('DJI-NEO-TEST')[2].startswith('Name')
    assert classify('TRAXXAS CAR')[3]==0
    assert classify('Office Printer')[3]==0
    assert split_nmcli(r'DJI-NEO:AA\:BB\:CC\:DD\:EE\:FF:6:2437:82')[1]=='AA:BB:CC:DD:EE:FF'
    observer=(40,-75.001)
    projected=projected_approach(r[1],observer)
    assert projected and projected['eta'] is None  # eastward from east of observer: moving away
    approaching=projected_approach(r[1],(40,-74.997))
    assert approaching and approaching['eta'] is not None and approaching['eta'] > 0
    closing=projected_approach(r[1],(40,-74.996))
    assert closing and 20<=closing['eta']<=40  # synthetic 340m distance, ~30s to 100m
    assert decode_scapy_vendor(0xfa0bbc,b'\x0d\x00'+packet[5:]) == r
    assert decode_scapy_vendor(None,packet) == r
    assert decode_scapy_vendor(0x123456,b'\x0d\x00'+packet[5:]) == []
    assert signal_index(100,'%')==100
    assert signal_advisory(100,'%')['level']=='red'
    assert signal_advisory(100,'%')['message'].startswith('DANGER: MAX')
    assert signal_advisory(90,'%')['level']=='red'
    assert signal_advisory(89,'%')['level']=='yellow'
    assert signal_advisory(50,'%')['level']=='yellow'
    assert signal_advisory(49,'%')['level']=='green'
    assert signal_advisory(-85,'dBm')['level']=='green'
    assert signal_advisory(-64,'dBm')['level']=='yellow'
    assert signal_advisory(-40,'dBm')['level']=='red'
    assert signal_advisory(None,'dBm')['level']=='unknown'
    print(f'{GREEN}PASS{RESET} Open Drone ID Wi-Fi Beacon message pack parser + Scapy vendor IE adaptation')
    print(f'{GREEN}PASS{RESET} Open Drone ID Bluetooth 0xFFFA service data parser')
    assert classify('BETAFPV-TEST')[1]=='drone'
    print(f'{GREEN}PASS{RESET} drone-only Wi-Fi and BLE heuristic labeling')
    print(f'{GREEN}PASS{RESET} NetworkManager MAC escape parser')
    print(f'{GREEN}PASS{RESET} Geometry-based projected 100 m arrival & no ETA from RSSI')
    print(f'{GREEN}PASS{RESET} Green/yellow/red signal index boundaries and missing-signal handling')
    print('All tests were synthetic: NO radio devices or drones were detected.')


def pcap_parse(filename,args):
    try:
        from scapy.all import PcapReader
    except ImportError:
        print('PCAP playback requires python3-scapy.');return 1
    if not filename or not Path(filename).is_file():
        print('Provide an existing PCAP filename after the pcap command.');return 1
    args.no_ble=True; args.no_wifi=True;args.duration=10
    m=Monitor(args)
    try:
        with PcapReader(filename) as packets:
            for pkt in packets:
                m.on_packet(pkt)
        while not m.q.empty():m.apply(m.q.get_nowait())
        print(f'{PURPLE}GS Drone Detector — recorded capture{RESET}')
        for item in sorted(m.devices.values(),key=lambda x:x['confidence'],reverse=True):
            if item['confidence']:
                print('\n'.join(m.format_item(item)))
        print(f'{len(m.rid_sources)} RID source(s) and {len(m.devices)} candidate(s) in capture')
    finally:
        m.close()
    return 0


def install():
    banner()
    print('Linux Mint / Debian/Ubuntu optional dependencies:')
    print('  sudo apt update')
    print('  sudo apt install network-manager bluez iw python3-scapy ieee-data')
    print('  sudo apt install python3-bleak    # if your distro provides it')
    print('If python3-bleak is unavailable, use a venv with system packages + pip bleak,')
    print('or keep using Wi-Fi scans only. No automatic package changes are made.')
    print('\nOptional vendor-name update: bash gs-drone-detector.sh update-db')
    return 0


def main():
    parser,args=make_args(sys.argv[1:])
    if args.command=='menu': args.command='scan'  # legacy alias; no submenu
    if args.command=='help':parser.print_help();return 0
    if args.command=='check':check();return 0
    if args.command=='update-db':return fetch_vendors()
    if args.command=='install':return install()
    if args.command=='test':offline_test();return 0
    if args.command=='pcap':return pcap_parse(args.pcapfile,args)
    if args.command in ('scan','demo'):
        if not sys.stdout.isatty() or args.plain:
            banner()
            if args.demo:print('DEMO: all displayed devices are simulated, not detected.')
            else:print('TURBO LIVE: drone-only Wi-Fi + BLE. Esc stops and returns home.')
        Monitor(args).run()
        return 0
    parser.print_help()
    return 0


if __name__=='__main__':
    try: sys.exit(main())
    except KeyboardInterrupt:
        print('\nStopped.')
        sys.exit(130)
GS_PYTHON_EOF
