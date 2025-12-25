#!/bin/bash
# Complete CM4 Setup - WiFi AP + Cameras + Full BLE Service
# Place on boot partition, will run automatically via cloud-init

LOG="/boot/firmware/thirdeye-complete-setup.log"
FLAG="/home/anton/.thirdeye-complete"

# Exit if already done
[ -f "$FLAG" ] && exit 0

exec > "$LOG" 2>&1

echo "=========================================="
echo "Third Eye Complete Setup: $(date)"
echo "=========================================="

# Install all packages
echo "Installing packages..."
apt-get update -qq
apt-get install -y python3-dbus python3-gi python3-picamera2 python3-flask bluez

# 1. WiFi AP Configuration
echo "Configuring WiFi Access Point..."

# NetworkManager: ignore wlan0
mkdir -p /etc/NetworkManager/conf.d/
cat > /etc/NetworkManager/conf.d/unmanaged-wlan0.conf << 'EOF'
[keyfile]
unmanaged-devices=interface-name:wlan0
EOF

# hostapd config
cat > /etc/hostapd/hostapd.conf << 'EOF'
interface=wlan0
driver=nl80211
ssid=StereoPi_5G
hw_mode=a
channel=36
country_code=GB
ieee80211n=1
ht_capab=[HT40+][SHORT-GI-20][SHORT-GI-40]
ieee80211ac=1
vht_oper_chwidth=1
vht_oper_centr_freq_seg0_idx=42
wmm_enabled=1
auth_algs=1
wpa=2
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
wpa_passphrase=5maltesers
EOF
echo 'DAEMON_CONF="/etc/hostapd/hostapd.conf"' > /etc/default/hostapd

# dnsmasq config
cat > /etc/dnsmasq.conf << 'EOF'
interface=wlan0
dhcp-range=192.168.50.10,192.168.50.250,255.255.255.0,24h
bind-interfaces
no-resolv
EOF

# wlan0 setup service
cat > /etc/systemd/system/wlan0-ap.service << 'EOF'
[Unit]
Description=Configure wlan0 for Access Point
Before=hostapd.service dnsmasq.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/bash -c 'rfkill unblock wifi && sleep 1 && ip link set wlan0 down && ip addr flush dev wlan0 && ip addr add 192.168.50.1/24 dev wlan0 && ip link set wlan0 up'

[Install]
WantedBy=multi-user.target
EOF

# 2. Camera Server (controlled by BLE)
echo "Creating camera server..."
cat > /home/anton/camera_server.py << 'EOFPY'
#!/usr/bin/env python3
import io, time, threading, logging
from flask import Flask, Response
from picamera2 import Picamera2
from PIL import Image

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class CameraStream:
    def __init__(self, idx):
        self.frame, self.lock = None, threading.Lock()
        try:
            self.cam = Picamera2(idx)
            cfg = self.cam.create_still_configuration(main={"size": (1920, 1080), "format": "RGB888"})
            self.cam.configure(cfg)
            self.cam.start()
            logger.info(f"Camera {idx} started")
        except Exception as e:
            self.cam = None
            logger.error(f"Camera {idx} failed: {e}")

    def capture_loop(self):
        while self.cam:
            try:
                arr = self.cam.capture_array()
                buf = io.BytesIO()
                Image.fromarray(arr).save(buf, format='JPEG', quality=80)
                with self.lock:
                    self.frame = buf.getvalue()
                time.sleep(0.1)
            except:
                time.sleep(0.1)

    def get_frame(self):
        with self.lock:
            return self.frame

streams = {n: CameraStream(i) for i, n in enumerate(['left', 'right', 'eye'])}
for s in streams.values():
    threading.Thread(target=s.capture_loop, daemon=True).start()

def make_app(name, stream):
    app = Flask(name)
    @app.route('/stream')
    def stream_route():
        def gen():
            while True:
                f = stream.get_frame()
                if f:
                    yield b'--frame\r\nContent-Type: image/jpeg\r\n\r\n' + f + b'\r\n'
                time.sleep(0.1)
        return Response(gen(), mimetype='multipart/x-mixed-replace; boundary=frame')
    @app.route('/health')
    def health():
        return 'OK'
    return app

if __name__ == '__main__':
    for (n, s), p in zip(streams.items(), [8081, 8082, 8083]):
        threading.Thread(target=lambda: make_app(n, s).run(host='0.0.0.0', port=p, threaded=True), daemon=True).start()
    while True:
        time.sleep(1)
EOFPY

chown anton:anton /home/anton/camera_server.py
chmod +x /home/anton/camera_server.py

cat > /etc/systemd/system/cm4-camera.service << 'EOF'
[Unit]
Description=Third Eye Camera Server
After=wlan0-ap.service

[Service]
Type=simple
User=anton
ExecStart=/usr/bin/python3 /home/anton/camera_server.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# 3. Full BLE GATT Server with ALL characteristics
echo "Creating complete BLE server..."
cat > /home/anton/ble_server.py << 'EOFPY'
#!/usr/bin/env python3
import logging, dbus, dbus.service, dbus.mainloop.glib, subprocess
from gi.repository import GLib

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

SVC = '12345678-1234-5678-1234-56789abcdef0'
CMD = '12345678-1234-5678-1234-56789abcdef1'
RSP = '12345678-1234-5678-1234-56789abcdef2'
TERM_IN = '12345678-1234-5678-1234-56789abcdef3'
TERM_OUT = '12345678-1234-5678-1234-56789abcdef4'
AUDIO = '12345678-1234-5678-1234-56789abcdef5'
CFG = '12345678-1234-5678-1234-56789abcdef6'

wifi_running = True  # Auto-start
camera_running = True  # Auto-start

class App(dbus.service.Object):
    def __init__(self, bus):
        self.path, self.svcs = '/', []
        dbus.service.Object.__init__(self, bus, self.path)
    def add(self, s):
        self.svcs.append(s)
    @dbus.service.method('org.freedesktop.DBus.ObjectManager', out_signature='a{oa{sa{sv}}}')
    def GetManagedObjects(self):
        r = {}
        for s in self.svcs:
            r[s.path] = {'org.bluez.GattService1': {'UUID': s.uuid, 'Primary': True, 'Characteristics': dbus.Array([c.path for c in s.chars], signature='o')}}
            for c in s.chars:
                r[c.path] = {'org.bluez.GattCharacteristic1': {'Service': s.path, 'UUID': c.uuid, 'Flags': c.flags, 'Value': dbus.Array([], signature='y')}}
        return r

class Svc:
    def __init__(self, bus, uuid):
        self.path, self.uuid, self.chars = dbus.ObjectPath('/org/bluez/thirdeye/s0'), uuid, []

class Char(dbus.service.Object):
    def __init__(self, bus, idx, uuid, flags, svc):
        self.path = dbus.ObjectPath(str(svc.path) + '/c' + str(idx))
        self.uuid, self.flags = uuid, flags
        dbus.service.Object.__init__(self, bus, self.path)

    @dbus.service.method('org.freedesktop.DBus.Properties', in_signature='s', out_signature='a{sv}')
    def GetAll(self, i):
        return {}

    @dbus.service.method('org.bluez.GattCharacteristic1', out_signature='ay')
    def ReadValue(self, o):
        global wifi_running, camera_running
        # Response char - send status
        if self.uuid == RSP:
            status = f"WiFi:{wifi_running},Camera:{camera_running}"
            return dbus.Array([dbus.Byte(ord(c)) for c in status], signature='y')
        return []

    @dbus.service.method('org.bluez.GattCharacteristic1', in_signature='aya{sv}')
    def WriteValue(self, v, o):
        global wifi_running, camera_running
        cmd = bytes(v).decode().strip()
        logger.info(f"BLE Command: {cmd}")

        # Command handler
        if self.uuid == CMD:
            if cmd == 'WIFI_START':
                if not wifi_running:
                    subprocess.run(['systemctl', 'start', 'wlan0-ap', 'hostapd', 'dnsmasq'])
                    wifi_running = True
                logger.info("WiFi started")
            elif cmd == 'WIFI_STOP':
                if wifi_running:
                    subprocess.run(['systemctl', 'stop', 'hostapd', 'dnsmasq'])
                    wifi_running = False
                logger.info("WiFi stopped")
            elif cmd == 'CAMERA_START':
                if not camera_running:
                    subprocess.run(['systemctl', 'start', 'cm4-camera'])
                    camera_running = True
                logger.info("Cameras started")
            elif cmd == 'CAMERA_STOP':
                if camera_running:
                    subprocess.run(['systemctl', 'stop', 'cm4-camera'])
                    camera_running = False
                logger.info("Cameras stopped")
            elif cmd == 'STATUS':
                logger.info(f"Status: WiFi={wifi_running}, Camera={camera_running}")
            elif cmd == 'REBOOT':
                logger.info("Rebooting...")
                subprocess.run(['reboot'])

class Ad(dbus.service.Object):
    def __init__(self, bus):
        self.path = dbus.ObjectPath('/org/bluez/thirdeye/ad0')
        dbus.service.Object.__init__(self, bus, self.path)
    @dbus.service.method('org.freedesktop.DBus.Properties', in_signature='s', out_signature='a{sv}')
    def GetAll(self, i):
        return {'Type': 'peripheral', 'ServiceUUIDs': dbus.Array([SVC], signature='s'), 'LocalName': 'ThirdEye_CM4'}
    @dbus.service.method('org.bluez.LEAdvertisement1')
    def Release(self):
        pass

dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
bus = dbus.SystemBus()
app, svc = App(bus), Svc(bus, SVC)

# Create ALL characteristics the app expects
svc.chars = [
    Char(bus, 0, CMD, ['write'], svc),           # Command
    Char(bus, 1, RSP, ['read', 'notify'], svc),  # Response
    Char(bus, 2, TERM_IN, ['write'], svc),       # Terminal In
    Char(bus, 3, TERM_OUT, ['read', 'notify'], svc),  # Terminal Out
    Char(bus, 4, AUDIO, ['write'], svc),         # Audio
    Char(bus, 5, CFG, ['read', 'write'], svc),   # Config
]

app.add(svc)
adp = list(dbus.Interface(bus.get_object('org.bluez', '/'), 'org.freedesktop.DBus.ObjectManager').GetManagedObjects().keys())[0]
dbus.Interface(bus.get_object('org.bluez', adp), 'org.bluez.GattManager1').RegisterApplication(app.get_path(), {})
dbus.Interface(bus.get_object('org.bluez', adp), 'org.bluez.LEAdvertisingManager1').RegisterAdvertisement(Ad(bus).path, {})
logger.info("BLE: ThirdEye_CM4 ready with all characteristics")
GLib.MainLoop().run()
EOFPY

chown anton:anton /home/anton/ble_server.py
chmod +x /home/anton/ble_server.py

cat > /etc/systemd/system/cm4-ble.service << 'EOF'
[Unit]
Description=Third Eye BLE Server
After=bluetooth.target
Requires=bluetooth.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/python3 /home/anton/ble_server.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Enable and start everything
echo "Enabling services..."
systemctl daemon-reload
systemctl enable wlan0-ap hostapd dnsmasq cm4-camera cm4-ble
systemctl restart NetworkManager || true

echo "Starting services..."
systemctl start wlan0-ap hostapd dnsmasq cm4-camera cm4-ble

# Mark complete
touch "$FLAG"

echo "=========================================="
echo "Setup Complete: $(date)"
echo "WiFi: StereoPi_5G @ 192.168.50.1"
echo "BLE: ThirdEye_CM4"
echo "Cameras: 8081, 8082, 8083"
echo "=========================================="
