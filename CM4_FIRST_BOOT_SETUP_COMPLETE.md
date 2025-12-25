# CM4 First Boot Setup - COMPLETE ✓

## Overview
The CM4 boot partition (D:\) has been configured for fully automated first-boot setup. No SSH access required!

## What's Been Configured

### 1. Boot Partition Files (D:\)
- ✓ `user-data` - Cloud-init configuration for automated setup
- ✓ `camera_server.py` - Triple camera streaming server (full implementation)
- ✓ `ble_server.py` - BLE GATT control server (full implementation)
- ✓ `THIRDEYE_SETUP_README.txt` - Deployment instructions

### 2. Automated First Boot Process
The CM4 will automatically execute these steps on first boot:

**Phase 1: Package Installation (via cloud-init)**
1. Update hostname to `thirdeye-cm4`
2. Run apt update & upgrade
3. Install required packages:
   - python3-dbus, python3-gi, python3-picamera2
   - python3-flask, python3-pil
   - bluez, hostapd, dnsmasq, network-manager

**Phase 2: Network Setup**
4. Connect to "Antonet" phone hotspot (for internet access)
5. Wait for connection (up to 60 seconds)
6. Download any additional packages
7. Disconnect from Antonet

**Phase 3: WiFi AP Configuration**
8. Configure NetworkManager to ignore wlan0
9. Set up hostapd for 5GHz AP:
   - SSID: `StereoPi_5G`
   - Password: `5maltesers`
   - IP: `192.168.50.1`
   - Channel: 36 (5GHz)
10. Configure dnsmasq for DHCP (192.168.50.10-250)

**Phase 4: Service Creation**
11. Copy camera_server.py and ble_server.py from boot partition
12. Create systemd services:
    - `wlan0-ap.service` - Configure wlan0 interface
    - `cm4-camera.service` - Camera streaming server
    - `cm4-ble.service` - BLE control server
13. Enable all services for auto-start

**Phase 5: Service Launch**
14. Start wlan0-ap → hostapd → dnsmasq (in sequence)
15. Start camera server (ports 8081, 8082, 8083)
16. Start BLE server (device name: ThirdEye_CM4)
17. Mark setup as complete (`/var/lib/thirdeye-setup-complete`)

## Deployment Instructions

### Prerequisites
- Phone hotspot "Antonet" with password "5maltesers" **must be running**
- CM4 must have WiFi and Bluetooth hardware
- Three cameras should be connected (camera_server handles missing cameras gracefully)

### Steps
1. **Insert SD card** into CM4
2. **Turn on phone hotspot** "Antonet"
3. **Power on CM4**
4. **Wait 3-5 minutes** for first boot setup to complete
5. **Connect to "StereoPi_5G"** WiFi network (password: 5maltesers)
6. **Test camera streams**:
   - Left: http://192.168.50.1:8081/stream
   - Right: http://192.168.50.1:8082/stream
   - Eye: http://192.168.50.1:8083/stream
7. **Test BLE connection** from the ThirdEye Flutter app
   - Device name: ThirdEye_CM4
   - Service UUID: 12345678-1234-5678-1234-56789abcdef0

## Services Overview

### Camera Server (`cm4-camera.service`)
- **Ports**: 8081 (left), 8082 (right), 8083 (eye)
- **Endpoints**:
  - `/stream` - MJPEG stream
  - `/stats` - Server statistics
  - `/health` - Health check
- **Resolution**: 1920x1080
- **FPS**: Adaptive 5-10 FPS
- **User**: ubuntu
- **Auto-restart**: Yes

### BLE Server (`cm4-ble.service`)
- **Device Name**: ThirdEye_CM4
- **Service UUID**: 12345678-1234-5678-1234-56789abcdef0
- **Characteristics**:
  - Command (write): Control WiFi, cameras, reboot
  - Response (read, notify): Status responses
  - Terminal In/Out (write/notify): SSH-like access
  - Audio (write): Audio uplink
  - Config (read/write): Configuration
- **User**: root (required for BLE and system control)
- **Auto-restart**: Yes

### WiFi AP (`hostapd` + `dnsmasq`)
- **SSID**: StereoPi_5G
- **Password**: 5maltesers
- **IP**: 192.168.50.1
- **DHCP Range**: 192.168.50.10-250
- **Frequency**: 5GHz, Channel 36
- **Auto-restart**: Yes

## Troubleshooting

### Setup Doesn't Complete
- **Check**: Phone hotspot "Antonet" is on and broadcasting
- **Check**: Password is exactly "5maltesers" (case-sensitive)
- **Wait**: First boot can take 5-10 minutes for package downloads
- **Logs**: If you can SSH in, check `/var/log/thirdeye-setup.log`

### Can't Connect to StereoPi_5G
- **Wait**: Give it 5+ minutes after first boot
- **Check**: Your device supports 5GHz WiFi
- **Reboot**: Power cycle the CM4
- **Logs**: `systemctl status hostapd dnsmasq wlan0-ap`

### Camera Streams Don't Work
- **Check**: Cameras are properly connected to CM4
- **Check**: Camera server is running: `systemctl status cm4-camera`
- **Check**: Navigate to http://192.168.50.1:8081/health
- **Logs**: `journalctl -u cm4-camera -f`

### BLE Device Not Found
- **Check**: Bluetooth is enabled on CM4
- **Check**: BLE service is running: `systemctl status cm4-ble`
- **Try**: Restart BLE service: `sudo systemctl restart cm4-ble`
- **Logs**: `journalctl -u cm4-ble -f`

### Need to Re-run Setup
If setup fails and you need to re-run:
```bash
sudo rm /var/lib/thirdeye-setup-complete
sudo /usr/local/bin/thirdeye-setup.sh
```

## Architecture Alignment

This setup is fully aligned with the ThirdEye Flutter app architecture:

### Camera Integration
- ✓ Three camera streams on ports 8081, 8082, 8083
- ✓ MJPEG format compatible with Flutter video players
- ✓ Adaptive FPS for performance optimization
- ✓ Stats endpoint for monitoring

### BLE Integration
- ✓ Service UUID matches `lib/services/cm4_ble_service.dart`
- ✓ Command/Response characteristics for control
- ✓ Supports WIFI_START, WIFI_STOP, CAMERA_START, CAMERA_STOP, REBOOT, STATUS
- ✓ Device name "ThirdEye_CM4" for easy discovery

### Network Integration
- ✓ 5GHz WiFi AP for high-bandwidth camera streaming
- ✓ Fixed IP (192.168.50.1) for predictable connections
- ✓ DHCP for automatic phone configuration

## Files Summary

### On Boot Partition (D:\)
```
D:\
├── user-data                    # Cloud-init configuration (7.5 KB)
├── camera_server.py            # Camera streaming server (8.7 KB)
├── ble_server.py              # BLE control server (15.9 KB)
└── THIRDEYE_SETUP_README.txt  # Deployment instructions (3 KB)
```

### Created on CM4 During First Boot
```
/etc/
├── NetworkManager/conf.d/unmanaged-wlan0.conf
├── hostapd/hostapd.conf
├── default/hostapd
├── dnsmasq.conf
└── systemd/system/
    ├── wlan0-ap.service
    ├── cm4-camera.service
    └── cm4-ble.service

/home/ubuntu/
├── camera_server.py
└── ble_server.py

/usr/local/bin/
└── thirdeye-setup.sh

/var/log/
└── thirdeye-setup.log

/var/lib/
└── thirdeye-setup-complete (flag file)
```

## Next Steps

1. ✓ Boot partition is ready
2. → Insert SD card into CM4
3. → Turn on "Antonet" hotspot
4. → Power on CM4 and wait 5 minutes
5. → Connect to "StereoPi_5G" and test
6. → Launch ThirdEye Flutter app and test BLE connection

## Notes

- **No SSH required**: Everything is automated
- **Idempotent**: Setup script checks for completion flag
- **Robust**: Services auto-restart on failure
- **Logged**: All setup steps logged to `/var/log/thirdeye-setup.log`
- **User**: Default user is `ubuntu` (cloud-init default for Raspberry Pi OS)

---

**Setup completed**: 2025-12-05
**Ready for deployment**: YES ✓
