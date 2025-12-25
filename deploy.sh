#!/bin/bash
# ONE COMMAND - Configure boot drive + Build app
# Run this when boot drive is attached

echo "=========================================="
echo "Third Eye - One Command Setup"
echo "=========================================="
echo ""

# Find boot drive
BOOT=""
for d in /mnt/d /d D: E: F: G: H:; do
    if [ -f "$d/bootcode.bin" ] 2>/dev/null; then
        BOOT="$d"
        echo "✓ Found boot drive: $BOOT"
        break
    fi
done

if [ -z "$BOOT" ]; then
    echo "✗ Boot drive not found!"
    echo "  Insert CM4 SD card and try again"
    exit 1
fi

echo ""
echo "[1/2] Creating boot-time BLE installer..."

# Create systemd oneshot service that runs on boot
cat > "$BOOT/cmdline.txt.bak" << 'EOF'
# Backup created by deploy.sh
EOF
cp "$BOOT/cmdline.txt" "$BOOT/cmdline.txt.original" 2>/dev/null || true

# Create the BLE install script on boot partition
cat > "$BOOT/install_ble_oneshot.sh" << 'EOFCM4'
#!/bin/bash
LOG="/boot/firmware/boot-stage2-ble-install.log"
FLAG="/home/anton/.ble-complete"

exec >> "$LOG" 2>&1

echo "=========================================="
echo "Stage 2: BLE Installation - $(date)"
echo "=========================================="

# Exit if already done
if [ -f "$FLAG" ]; then
    echo "BLE already installed (flag exists), exiting"
    exit 0
fi

echo "Starting BLE package installation..."
echo "Running apt-get update..."
apt-get update -qq
echo "Installing python3-dbus python3-gi bluez..."
apt-get install -y python3-dbus python3-gi bluez
echo "Packages installed"

# Create BLE server
cat > /home/anton/ble_server.py << 'EOFPY'
#!/usr/bin/env python3
import logging, dbus, dbus.service, dbus.mainloop.glib
from gi.repository import GLib

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

SVC = '12345678-1234-5678-1234-56789abcdef0'
CMD = '12345678-1234-5678-1234-56789abcdef1'

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
        return []
    @dbus.service.method('org.bluez.GattCharacteristic1', in_signature='aya{sv}')
    def WriteValue(self, v, o):
        logger.info(f"BLE: {bytes(v).decode()}")

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
svc.chars = [Char(bus, 0, CMD, ['write'], svc)]
app.add(svc)
adp = list(dbus.Interface(bus.get_object('org.bluez', '/'), 'org.freedesktop.DBus.ObjectManager').GetManagedObjects().keys())[0]
dbus.Interface(bus.get_object('org.bluez', adp), 'org.bluez.GattManager1').RegisterApplication(app.get_path(), {})
dbus.Interface(bus.get_object('org.bluez', adp), 'org.bluez.LEAdvertisingManager1').RegisterAdvertisement(Ad(bus).path, {})
logger.info("BLE: ThirdEye_CM4")
GLib.MainLoop().run()
EOFPY

chmod +x /home/anton/ble_server.py

cat > /etc/systemd/system/cm4-ble.service << 'EOF'
[Unit]
Description=BLE Server
After=bluetooth.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/python3 /home/anton/ble_server.py
Restart=always

[Install]
WantedBy=multi-user.target
EOF

echo "Setting ownership and permissions..."
chown anton:anton /home/anton/ble_server.py
chmod +x /home/anton/ble_server.py
ls -la /home/anton/ble_server.py

echo "Creating systemd service file..."
# Create systemd service
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

echo "Service file created"
ls -la /etc/systemd/system/cm4-ble.service

echo "Reloading systemd daemon..."
systemctl daemon-reload

echo "Enabling cm4-ble service..."
systemctl enable cm4-ble

echo "Starting cm4-ble service..."
systemctl start cm4-ble

sleep 3

echo "Checking service status..."
systemctl status cm4-ble --no-pager -l || echo "Service status check failed"

echo "Checking if BLE is advertising..."
hciconfig || echo "hciconfig not available"

# Mark complete
echo "Creating completion flag..."
touch "$FLAG"
ls -la "$FLAG"

echo "=========================================="
echo "Stage 2 Complete: $(date)"
echo "BLE Server should be running as ThirdEye_CM4"
echo "=========================================="
EOFCM4

chmod +x "$BOOT/install_ble_oneshot.sh"

# Copy the install script to a location that will persist
cat > "$BOOT/copy_ble_installer.sh" << 'EOFCOPY'
#!/bin/bash
# This script copies the BLE installer from boot partition to root filesystem
# and creates a systemd service to run it

LOG="/boot/firmware/boot-stage1.log"
exec >> "$LOG" 2>&1

echo "=========================================="
echo "Stage 1: Copy BLE Installer - $(date)"
echo "=========================================="

INSTALLER_SRC="/boot/firmware/install_ble_oneshot.sh"
INSTALLER_DST="/usr/local/bin/install_ble_oneshot.sh"
SERVICE_FILE="/etc/systemd/system/ble-oneshot-install.service"

echo "Checking if installer source exists..."
ls -la "$INSTALLER_SRC" || echo "ERROR: Installer source not found!"

# Exit if already copied
if [ -f "$INSTALLER_DST" ]; then
    echo "Installer already copied, exiting"
    exit 0
fi

echo "Copying installer to $INSTALLER_DST..."
cp "$INSTALLER_SRC" "$INSTALLER_DST"
chmod +x "$INSTALLER_DST"
echo "Installer copied successfully"

echo "Creating systemd service..."
# Create systemd service
cat > "$SERVICE_FILE" << 'EOFSVC'
[Unit]
Description=One-time BLE Installation
After=network-online.target
Wants=network-online.target
ConditionPathExists=!/home/anton/.ble-complete

[Service]
Type=oneshot
ExecStart=/usr/local/bin/install_ble_oneshot.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOFSVC

# Enable and start
echo "Reloading systemd..."
systemctl daemon-reload
echo "Enabling service..."
systemctl enable ble-oneshot-install.service
echo "Starting service..."
systemctl start ble-oneshot-install.service --no-block

echo "Stage 1 complete - $(date)"
echo "Checking service status..."
systemctl status ble-oneshot-install.service --no-pager -l || echo "Service status check failed"
echo "=========================================="
EOFCOPY

chmod +x "$BOOT/copy_ble_installer.sh"

# Modify cmdline.txt to run the copy script on boot
CURRENT_CMDLINE=$(cat "$BOOT/cmdline.txt" | tr -d '\n')
if [[ ! "$CURRENT_CMDLINE" =~ "copy_ble_installer" ]]; then
    echo "$CURRENT_CMDLINE systemd.run=/boot/firmware/copy_ble_installer.sh systemd.run_success_action=none" > "$BOOT/cmdline.txt"
    echo "  ✓ Added BLE installer to boot cmdline"
else
    echo "  ✓ BLE installer already in cmdline"
fi

echo "  ✓ Boot-time BLE installer configured"

echo ""
echo "[2/2] Building Flutter app..."
flutter pub get && flutter run

echo ""
echo "=========================================="
echo "Setup Complete!"
echo "=========================================="
echo ""
echo "Next steps:"
echo "  1. Eject SD card from PC"
echo "  2. Insert into CM4 and boot"
echo "  3. Wait 5-10 min for BLE install"
echo "  4. App will auto-connect!"
echo ""
echo "Troubleshooting logs (on boot drive):"
echo "  /boot/firmware/boot-stage1.log - cmdline.txt execution"
echo "  /boot/firmware/boot-stage2-ble-install.log - BLE installation"
echo ""
echo "After boot, reconnect SD card to check logs"
