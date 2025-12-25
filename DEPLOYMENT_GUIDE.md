# Third Eye - Hybrid BLE + WiFi Deployment Guide

## Overview

Your CM4 camera wearable now has a **professional GoPro/DJI-style architecture**:

- **Bluetooth LE** → Control, configuration, SSH, audio uplink
- **5GHz WiFi** → Video streaming, high-bandwidth data

## What's Been Created

###CM4 Side
✅ `cm4_server/ble_control_server.py` - BLE GATT server for control
✅ `cm4_server/camera_server.py` - Video streaming server (existing)
✅ WiFi AP configured (StereoPi_5G @ 192.168.50.1)

### Flutter App Side
✅ `lib/services/cm4_ble_service.dart` - BLE control service
✅ `lib/services/cm4_stream_service.dart` - Video streaming (existing)
✅ `pubspec.yaml` updated with BLE + audio packages

### Documentation
✅ `docs/HYBRID_BLE_WIFI_SETUP.md` - Complete architecture guide

## Quick Start Deployment

### Step 1: Update Flutter Dependencies

```bash
flutter pub get
```

This will install:
- `flutter_blue_plus` (BLE)
- `record` (audio recording)

### Step 2: Copy Files to CM4

```bash
# Make sure you're connected to StereoPi_5G WiFi
# CM4 IP: 192.168.50.1

# Copy BLE server
scp cm4_server/ble_control_server.py anton@192.168.50.1:~/

# Verify camera server is already there
ssh anton@192.168.50.1 "ls -la ~/camera_server.py"
```

### Step 3: Install CM4 Dependencies

```bash
# SSH to CM4
ssh anton@192.168.50.1

# Install BLE dependencies
sudo apt update
sudo apt install -y python3-dbus python3-gi bluez

# Make scripts executable
chmod +x ~/ble_control_server.py
chmod +x ~/camera_server.py
```

### Step 4: Create Systemd Services

**Create BLE service:**
```bash
sudo nano /etc/systemd/system/cm4-ble.service
```

Paste this:
```ini
[Unit]
Description=Third Eye BLE Control Server
After=bluetooth.target
Requires=bluetooth.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/python3 /home/anton/ble_control_server.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

**Create Camera service (if not exists):**
```bash
sudo nano /etc/systemd/system/cm4-camera.service
```

Paste this:
```ini
[Unit]
Description=CM4 Triple Camera Server
After=network-online.target wlan0-ap.service hostapd.service
Wants=network-online.target

[Service]
Type=simple
User=anton
WorkingDirectory=/home/anton
ExecStart=/usr/bin/python3 /home/anton/camera_server.py
Restart=always
RestartSec=5
Environment="PYTHONUNBUFFERED=1"

[Install]
WantedBy=multi-user.target
```

**Enable and start services:**
```bash
sudo systemctl daemon-reload
sudo systemctl enable cm4-ble.service cm4-camera.service
sudo systemctl start cm4-ble.service cm4-camera.service

# Check status
sudo systemctl status cm4-ble.service
sudo systemctl status cm4-camera.service
```

### Step 5: Verify BLE Advertisement

```bash
# On CM4, check if BLE is working
sudo bluetoothctl
> scan on
# Should see "ThirdEye_CM4" appear within 10 seconds
> exit

# Check logs
sudo journalctl -u cm4-ble.service -f
```

### Step 6: Test from Flutter App

Create a simple test in your app:

```dart
import 'package:third_eye/services/cm4_ble_service.dart';

// Test BLE connection
final bleService = Cm4BleService();

// Scan for CM4
final devices = await bleService.scanForCM4();
print('Found ${devices.length} devices');

// Connect to first device
if (devices.isNotEmpty) {
  final success = await bleService.connect(devices.first.device);
  print('Connected: $success');

  // Test commands
  await bleService.getStatus();
  await bleService.startCamera();
  await bleService.startWiFi();
}
```

## Usage Flow

### 1. Power On Sequence
1. CM4 boots
2. WiFi AP starts (StereoPi_5G)
3. BLE server starts (ThirdEye_CM4)
4. Camera server starts

### 2. App Connection Flow
1. App scans for BLE devices
2. Finds "ThirdEye_CM4"
3. Connects via BLE
4. Sends commands via BLE
5. Phone connects to StereoPi_5G WiFi
6. App connects to video streams

### 3. Operation
- **Control** → BLE commands
- **Video** → WiFi streams
- **Audio uplink** → BLE (future feature)

## Available BLE Commands

```dart
// WiFi Control
await bleService.startWiFi();      // Start WiFi AP
await bleService.stopWiFi();       // Stop WiFi AP
await bleService.getWiFiStatus();  // Get status

// Camera Control
await bleService.startCamera();    // Start camera server
await bleService.stopCamera();     // Stop camera server

// System
await bleService.getStatus();      // Get full status
await bleService.reboot();         // Reboot CM4
```

## Video Streaming (Already Working)

```dart
import 'package:third_eye/services/cm4_stream_service.dart';

final streamService = Cm4StreamService();

// Connect to camera streams
await streamService.connectAll();

// Get image stream for a camera
final leftStream = streamService.getImageStream(CameraFeed.left);

// Display in widget
StreamBuilder<Uint8List>(
  stream: leftStream,
  builder: (context, snapshot) {
    if (snapshot.hasData) {
      return Image.memory(snapshot.data!);
    }
    return CircularProgressIndicator();
  },
)
```

## Troubleshooting

### BLE Not Working

**Device not found:**
```bash
# On CM4
sudo systemctl status cm4-ble.service
sudo journalctl -u cm4-ble.service -n 50

# Check Bluetooth
sudo hciconfig hci0 up
sudo bluetoothctl
> show
```

**Can't connect:**
- Ensure Bluetooth is enabled on phone
- Check permissions in AndroidManifest.xml
- Try rebooting CM4: `sudo reboot`

### WiFi Not Working

**StereoPi_5G not visible:**
```bash
# Check hostapd
sudo systemctl status hostapd
sudo systemctl restart hostapd

# Check wlan0
ip addr show wlan0
# Should show 192.168.50.1/24
```

**Connected but no video:**
```bash
# Check camera service
sudo systemctl status cm4-camera.service
sudo journalctl -u cm4-camera.service -n 50

# Test manually
curl http://192.168.50.1:8081/health
```

### App Issues

**BLE permissions:**
Add to `android/app/src/main/AndroidManifest.xml`:
```xml
<uses-permission android:name="android.permission.BLUETOOTH" />
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" />
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
```

**Runtime permissions:**
```dart
import 'package:permission_handler/permission_handler.dart';

// Request permissions
await Permission.bluetooth.request();
await Permission.bluetoothScan.request();
await Permission.bluetoothConnect.request();
await Permission.location.request();
```

## Next Steps

### Phase 1: Basic Control ✅
- [x] WiFi AP working
- [x] BLE server created
- [x] Flutter BLE service created
- [ ] Deploy to CM4
- [ ] Test BLE commands
- [ ] Test video + BLE simultaneously

### Phase 2: Integration
- [ ] Add BLE control to main app screen
- [ ] Auto-connect to CM4 on app start
- [ ] Show connection status
- [ ] Add camera control buttons

### Phase 3: Audio Uplink
- [ ] Implement audio recording in Flutter
- [ ] Send audio chunks via BLE
- [ ] Receive and process audio on CM4
- [ ] Add speech recognition (optional)

### Phase 4: Advanced Features
- [ ] BLE SSH/terminal access
- [ ] Configuration persistence
- [ ] Firmware updates via BLE
- [ ] Battery monitoring

## Architecture Diagram

```
┌─────────────────────────────────────────┐
│         Samsung S24 Ultra               │
│                                         │
│  Flutter App (third_eye)                │
│  ┌───────────────┐  ┌────────────────┐ │
│  │  BLE Client   │  │  WiFi Client   │ │
│  │               │  │                │ │
│  │  Commands →   │  │  ← Video       │ │
│  │  ← Responses  │  │  ← HTTP        │ │
│  │  Audio →      │  │                │ │
│  └───────┬───────┘  └────────┬───────┘ │
└──────────┼──────────────────┬┼─────────┘
           │                  ││
      BLE  │                  ││ 5GHz WiFi
    (Control)                 ││ (Data)
           │                  ││
┌──────────┼──────────────────┼┼─────────┐
│   Raspberry Pi CM4          ││         │
│   (StereoPi v2)             ││         │
│  ┌────────▼──────┐  ┌───────▼▼──────┐ │
│  │  BLE Server   │  │  WiFi AP      │ │
│  │  ble_control  │  │  hostapd      │ │
│  │  _server.py   │  │  dnsmasq      │ │
│  │               │  │               │ │
│  │  Commands     │  │  Video Srv    │ │
│  │  Responses    │  │  camera_      │ │
│  │  Audio RX     │  │  server.py    │ │
│  └───────┬───────┘  └───────┬───────┘ │
│          │                  │         │
│          ▼                  ▼         │
│    ┌──────────────────────────────┐  │
│    │   Cameras (Picamera2)        │  │
│    │   • Left  (1080p)            │  │
│    │   • Right (1080p)            │  │
│    │   • Eye   (1080p)            │  │
│    └──────────────────────────────┘  │
└─────────────────────────────────────────┘
```

## Service UUIDs Reference

```
Service:      12345678-1234-5678-1234-56789abcdef0
Command:      12345678-1234-5678-1234-56789abcdef1 (Write)
Response:     12345678-1234-5678-1234-56789abcdef2 (Notify)
Terminal In:  12345678-1234-5678-1234-56789abcdef3 (Write)
Terminal Out: 12345678-1234-5678-1234-56789abcdef4 (Notify)
Audio Data:   12345678-1234-5678-1234-56789abcdef5 (Write)
Config:       12345678-1234-5678-1234-56789abcdef6 (Read/Write)
```

## Support

For detailed technical documentation, see:
- `docs/HYBRID_BLE_WIFI_SETUP.md` - Complete architecture guide
- `cm4_server/README.md` - Camera server documentation
- Flutter service files in `lib/services/`

---

**Status**: WiFi ✅ | BLE Server ✅ | Flutter BLE ✅ | Ready for deployment!

*Generated: 2025-12-04*
*Architecture: Hybrid BLE + 5GHz WiFi (GoPro/DJI style)*
