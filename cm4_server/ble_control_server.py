#!/usr/bin/env python3
"""
CM4 BLE Control Server - Bluetooth LE GATT Server for Third Eye
Provides configuration, SSH access, and audio uplink via BLE
"""

import sys
import subprocess
import logging
import threading
import queue
import time
from typing import Optional

# Import bluez GATT libraries
try:
    import dbus
    import dbus.exceptions
    import dbus.mainloop.glib
    import dbus.service
    from gi.repository import GLib
except ImportError:
    print("ERROR: Required BLE libraries not installed")
    print("Run: sudo apt install -y python3-dbus python3-gi")
    sys.exit(1)

# Logging setup
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# UUIDs for Third Eye BLE Service
SERVICE_UUID = '12345678-1234-5678-1234-56789abcdef0'
COMMAND_CHAR_UUID = '12345678-1234-5678-1234-56789abcdef1'
RESPONSE_CHAR_UUID = '12345678-1234-5678-1234-56789abcdef2'
TERMINAL_IN_UUID = '12345678-1234-5678-1234-56789abcdef3'
TERMINAL_OUT_UUID = '12345678-1234-5678-1234-56789abcdef4'
AUDIO_DATA_UUID = '12345678-1234-5678-1234-56789abcdef5'
CONFIG_CHAR_UUID = '12345678-1234-5678-1234-56789abcdef6'

# D-Bus constants
BLUEZ_SERVICE_NAME = 'org.bluez'
GATT_MANAGER_IFACE = 'org.bluez.GattManager1'
DBUS_OM_IFACE = 'org.freedesktop.DBus.ObjectManager'
DBUS_PROP_IFACE = 'org.freedesktop.DBus.Properties'
GATT_SERVICE_IFACE = 'org.bluez.GattService1'
GATT_CHRC_IFACE = 'org.bluez.GattCharacteristic1'
GATT_DESC_IFACE = 'org.bluez.GattDescriptor1'
LE_ADVERTISING_MANAGER_IFACE = 'org.bluez.LEAdvertisingManager1'
LE_ADVERTISEMENT_IFACE = 'org.bluez.LEAdvertisement1'


class InvalidArgsException(dbus.exceptions.DBusException):
    _dbus_error_name = 'org.freedesktop.DBus.Error.InvalidArgs'


class NotSupportedException(dbus.exceptions.DBusException):
    _dbus_error_name = 'org.bluez.Error.NotSupported'


class NotPermittedException(dbus.exceptions.DBusException):
    _dbus_error_name = 'org.bluez.Error.NotPermitted'


class Application(dbus.service.Object):
    """Main GATT Application"""

    def __init__(self, bus):
        self.path = '/'
        self.services = []
        dbus.service.Object.__init__(self, bus, self.path)

    def get_path(self):
        return dbus.ObjectPath(self.path)

    def add_service(self, service):
        self.services.append(service)

    @dbus.service.method(DBUS_OM_IFACE, out_signature='a{oa{sa{sv}}}')
    def GetManagedObjects(self):
        response = {}
        for service in self.services:
            response[service.get_path()] = service.get_properties()
            chrcs = service.get_characteristics()
            for chrc in chrcs:
                response[chrc.get_path()] = chrc.get_properties()
        return response


class Service(dbus.service.Object):
    """GATT Service"""

    PATH_BASE = '/org/bluez/thirdeye/service'

    def __init__(self, bus, index, uuid, primary):
        self.path = self.PATH_BASE + str(index)
        self.bus = bus
        self.uuid = uuid
        self.primary = primary
        self.characteristics = []
        dbus.service.Object.__init__(self, bus, self.path)

    def get_properties(self):
        return {
            GATT_SERVICE_IFACE: {
                'UUID': self.uuid,
                'Primary': self.primary,
                'Characteristics': dbus.Array(
                    self.get_characteristic_paths(),
                    signature='o')
            }
        }

    def get_path(self):
        return dbus.ObjectPath(self.path)

    def add_characteristic(self, characteristic):
        self.characteristics.append(characteristic)

    def get_characteristic_paths(self):
        result = []
        for chrc in self.characteristics:
            result.append(chrc.get_path())
        return result

    def get_characteristics(self):
        return self.characteristics

    @dbus.service.method(DBUS_PROP_IFACE,
                         in_signature='s',
                         out_signature='a{sv}')
    def GetAll(self, interface):
        if interface != GATT_SERVICE_IFACE:
            raise InvalidArgsException()
        return self.get_properties()[GATT_SERVICE_IFACE]


class Characteristic(dbus.service.Object):
    """GATT Characteristic"""

    def __init__(self, bus, index, uuid, flags, service):
        self.path = service.path + '/char' + str(index)
        self.bus = bus
        self.uuid = uuid
        self.service = service
        self.flags = flags
        self.value = []
        dbus.service.Object.__init__(self, bus, self.path)

    def get_properties(self):
        return {
            GATT_CHRC_IFACE: {
                'Service': self.service.get_path(),
                'UUID': self.uuid,
                'Flags': self.flags,
                'Value': dbus.Array(self.value, signature='y')
            }
        }

    def get_path(self):
        return dbus.ObjectPath(self.path)

    @dbus.service.method(DBUS_PROP_IFACE,
                         in_signature='s',
                         out_signature='a{sv}')
    def GetAll(self, interface):
        if interface != GATT_CHRC_IFACE:
            raise InvalidArgsException()
        return self.get_properties()[GATT_CHRC_IFACE]

    @dbus.service.method(GATT_CHRC_IFACE, out_signature='ay')
    def ReadValue(self, options):
        logger.info(f'Read request on {self.uuid}')
        return self.value

    @dbus.service.method(GATT_CHRC_IFACE, in_signature='aya{sv}')
    def WriteValue(self, value, options):
        logger.info(f'Write request on {self.uuid}: {bytes(value)}')
        self.value = value


class CommandCharacteristic(Characteristic):
    """Characteristic for receiving commands from phone"""

    def __init__(self, bus, index, service, command_handler):
        Characteristic.__init__(
            self, bus, index,
            COMMAND_CHAR_UUID,
            ['write', 'write-without-response'],
            service)
        self.command_handler = command_handler

    def WriteValue(self, value, options):
        command = bytes(value).decode('utf-8')
        logger.info(f'Received command: {command}')
        response = self.command_handler(command)
        logger.info(f'Command response: {response}')


class ResponseCharacteristic(Characteristic):
    """Characteristic for sending responses to phone"""

    def __init__(self, bus, index, service):
        Characteristic.__init__(
            self, bus, index,
            RESPONSE_CHAR_UUID,
            ['read', 'notify'],
            service)
        self.notifying = False

    def send_response(self, message: str):
        """Send a response notification to the phone"""
        if self.notifying:
            value = [dbus.Byte(c) for c in message.encode('utf-8')]
            self.PropertiesChanged(GATT_CHRC_IFACE, {'Value': value}, [])
            logger.info(f'Sent response: {message}')

    @dbus.service.method(GATT_CHRC_IFACE)
    def StartNotify(self):
        if self.notifying:
            return
        self.notifying = True
        logger.info('Response notifications enabled')

    @dbus.service.method(GATT_CHRC_IFACE)
    def StopNotify(self):
        if not self.notifying:
            return
        self.notifying = False
        logger.info('Response notifications disabled')


class ThirdEyeService(Service):
    """Main Third Eye BLE GATT Service"""

    def __init__(self, bus, index):
        Service.__init__(self, bus, index, SERVICE_UUID, True)

        # Command handler
        self.response_char = ResponseCharacteristic(bus, 1, self)
        self.add_characteristic(CommandCharacteristic(bus, 0, self, self.handle_command))
        self.add_characteristic(self.response_char)

        # Add more characteristics for terminal, audio, etc.
        # TODO: Add terminal and audio characteristics

    def handle_command(self, command: str) -> str:
        """Handle incoming commands from phone"""
        try:
            parts = command.strip().split(':', 1)
            cmd = parts[0].upper()

            if cmd == 'WIFI_STATUS':
                # Check WiFi AP status
                result = subprocess.run(['systemctl', 'is-active', 'hostapd'],
                                      capture_output=True, text=True)
                status = result.stdout.strip()
                self.response_char.send_response(f'WIFI:{status}')
                return status

            elif cmd == 'WIFI_START':
                # Start WiFi AP
                subprocess.run(['sudo', 'systemctl', 'start', 'hostapd'])
                subprocess.run(['sudo', 'systemctl', 'start', 'dnsmasq'])
                self.response_char.send_response('WIFI:started')
                return 'started'

            elif cmd == 'WIFI_STOP':
                # Stop WiFi AP
                subprocess.run(['sudo', 'systemctl', 'stop', 'hostapd'])
                subprocess.run(['sudo', 'systemctl', 'stop', 'dnsmasq'])
                self.response_char.send_response('WIFI:stopped')
                return 'stopped'

            elif cmd == 'CAMERA_START':
                # Start camera server
                subprocess.run(['sudo', 'systemctl', 'start', 'cm4-camera'])
                self.response_char.send_response('CAMERA:started')
                return 'started'

            elif cmd == 'CAMERA_STOP':
                # Stop camera server
                subprocess.run(['sudo', 'systemctl', 'stop', 'cm4-camera'])
                self.response_char.send_response('CAMERA:stopped')
                return 'stopped'

            elif cmd == 'REBOOT':
                # Reboot the CM4
                self.response_char.send_response('REBOOTING')
                subprocess.run(['sudo', 'reboot'])
                return 'rebooting'

            elif cmd == 'STATUS':
                # Get system status
                wifi = subprocess.run(['systemctl', 'is-active', 'hostapd'],
                                    capture_output=True, text=True).stdout.strip()
                camera = subprocess.run(['systemctl', 'is-active', 'cm4-camera'],
                                       capture_output=True, text=True).stdout.strip()
                response = f'STATUS:wifi={wifi},camera={camera}'
                self.response_char.send_response(response)
                return response

            else:
                self.response_char.send_response(f'ERROR:Unknown command: {cmd}')
                return 'error'

        except Exception as e:
            logger.error(f'Command handler error: {e}')
            self.response_char.send_response(f'ERROR:{str(e)}')
            return 'error'


class Advertisement(dbus.service.Object):
    """BLE Advertisement"""

    PATH_BASE = '/org/bluez/thirdeye/advertisement'

    def __init__(self, bus, index, advertising_type):
        self.path = self.PATH_BASE + str(index)
        self.bus = bus
        self.ad_type = advertising_type
        self.service_uuids = None
        self.manufacturer_data = None
        self.solicit_uuids = None
        self.service_data = None
        self.local_name = 'ThirdEye_CM4'
        self.include_tx_power = False
        dbus.service.Object.__init__(self, bus, self.path)

    def get_properties(self):
        properties = dict()
        properties['Type'] = self.ad_type
        if self.service_uuids is not None:
            properties['ServiceUUIDs'] = dbus.Array(self.service_uuids,
                                                     signature='s')
        if self.local_name is not None:
            properties['LocalName'] = dbus.String(self.local_name)
        if self.include_tx_power:
            properties['IncludeTxPower'] = dbus.Boolean(self.include_tx_power)

        return {LE_ADVERTISEMENT_IFACE: properties}

    def get_path(self):
        return dbus.ObjectPath(self.path)

    @dbus.service.method(DBUS_PROP_IFACE,
                         in_signature='s',
                         out_signature='a{sv}')
    def GetAll(self, interface):
        if interface != LE_ADVERTISEMENT_IFACE:
            raise InvalidArgsException()
        return self.get_properties()[LE_ADVERTISEMENT_IFACE]

    @dbus.service.method(LE_ADVERTISEMENT_IFACE,
                         in_signature='',
                         out_signature='')
    def Release(self):
        logger.info('Advertisement released')


def find_adapter(bus):
    """Find the first available Bluetooth adapter"""
    remote_om = dbus.Interface(bus.get_object(BLUEZ_SERVICE_NAME, '/'),
                                DBUS_OM_IFACE)
    objects = remote_om.GetManagedObjects()

    for o, props in objects.items():
        if GATT_MANAGER_IFACE in props.keys():
            return o

    return None


def main():
    """Main entry point"""
    logger.info("=" * 60)
    logger.info("Third Eye CM4 BLE Control Server")
    logger.info("=" * 60)

    # Set up D-Bus main loop
    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)

    bus = dbus.SystemBus()

    # Find Bluetooth adapter
    adapter_path = find_adapter(bus)
    if not adapter_path:
        logger.error('No Bluetooth adapter found')
        return

    logger.info(f'Using adapter: {adapter_path}')

    # Set adapter properties
    adapter_props = dbus.Interface(
        bus.get_object(BLUEZ_SERVICE_NAME, adapter_path),
        DBUS_PROP_IFACE)

    adapter_props.Set('org.bluez.Adapter1', 'Powered', dbus.Boolean(1))
    adapter_props.Set('org.bluez.Adapter1', 'Discoverable', dbus.Boolean(1))

    # Create and register GATT application
    app = Application(bus)
    service = ThirdEyeService(bus, 0)
    app.add_service(service)

    # Register GATT application
    service_manager = dbus.Interface(
        bus.get_object(BLUEZ_SERVICE_NAME, adapter_path),
        GATT_MANAGER_IFACE)

    try:
        service_manager.RegisterApplication(app.get_path(), {},
                                           reply_handler=lambda: logger.info('GATT application registered'),
                                           error_handler=lambda e: logger.error(f'Failed to register application: {e}'))
    except Exception as e:
        logger.error(f'Failed to register application: {e}')
        return

    # Create and register advertisement
    ad_manager = dbus.Interface(bus.get_object(BLUEZ_SERVICE_NAME, adapter_path),
                                 LE_ADVERTISING_MANAGER_IFACE)

    advertisement = Advertisement(bus, 0, 'peripheral')
    advertisement.service_uuids = [SERVICE_UUID]

    try:
        ad_manager.RegisterAdvertisement(advertisement.get_path(), {},
                                         reply_handler=lambda: logger.info('Advertisement registered'),
                                         error_handler=lambda e: logger.error(f'Failed to register advertisement: {e}'))
    except Exception as e:
        logger.error(f'Failed to register advertisement: {e}')
        return

    logger.info("\n" + "=" * 60)
    logger.info("BLE Server Ready!")
    logger.info(f"Device Name: ThirdEye_CM4")
    logger.info(f"Service UUID: {SERVICE_UUID}")
    logger.info("Waiting for connections...")
    logger.info("=" * 60 + "\n")

    # Run main loop
    mainloop = GLib.MainLoop()
    try:
        mainloop.run()
    except KeyboardInterrupt:
        logger.info('\nShutting down...')
    finally:
        ad_manager.UnregisterAdvertisement(advertisement.get_path())
        service_manager.UnregisterApplication(app.get_path())


if __name__ == '__main__':
    main()
