#!/bin/bash
# Manual BLE installation script
# Run this on the CM4 via: ssh anton@192.168.50.1 'bash -s' < install_ble_manual.sh

echo "=== Installing BLE on CM4 ==="

# Install packages
sudo apt-get update -qq
sudo apt-get install -y python3-dbus python3-gi bluez

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
logger.info("BLE: ThirdEye_CM4 ready")
GLib.MainLoop().run()
EOFPY

chmod +x /home/anton/ble_server.py

# Create systemd service
sudo tee /etc/systemd/system/cm4-ble.service > /dev/null << 'EOF'
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

# Start service
sudo systemctl daemon-reload
sudo systemctl enable cm4-ble.service
sudo systemctl start cm4-ble.service

echo ""
echo "=== BLE Installation Complete ==="
echo ""
echo "Checking service status..."
sudo systemctl status cm4-ble.service --no-pager -l | head -15
