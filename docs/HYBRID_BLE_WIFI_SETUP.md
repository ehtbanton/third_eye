# Third Eye - Hybrid BLE + 5GHz WiFi Architecture

**Professional Camera Wearable Architecture (GoPro/DJI Style)**

## Overview

This document describes the hybrid communication architecture:
- **Bluetooth LE**: Control, configuration, SSH access, audio uplink (phone → CM4)
- **5GHz WiFi**: Video streaming, high-bandwidth data (CM4 → phone)

##Architecture

```
┌─────────────────────────────────────────┐
│         Samsung S24 (Android)           │
│                                         │
│  ┌───────────────┐  ┌────────────────┐ │
│  │  BLE Client   │  │  WiFi Client   │ │
│  │               │  │                │ │
│  │  • Commands   │  │  • Video RX    │ │
│  │  • Config     │  │  • HTTP        │ │
│  │  • Audio TX   │  │                │ │
│  └───────┬───────┘  └────────┬───────┘ │
└──────────┼──────────────────┬┼─────────┘
           │                  ││
      BLE  │                  ││ 5GHz WiFi
           │                  ││
┌──────────┼──────────────────┼┼─────────┐
│          │   CM4 Module     ││         │
│  ┌───────▼───────┐  ┌───────▼▼──────┐ │
│  │  BLE Server   │  │  WiFi AP      │ │
│  │  GATT Service │  │  hostapd      │ │
│  │               │  │               │ │
│  │ • Commands    │  │ • Video TX    │ │
│  │ • Status      │  │ • HTTP Server │ │
│  │ • Audio RX    │  │               │ │
│  └───────┬───────┘  └───────┬───────┘ │
│          │                  │         │
│          ▼                  ▼         │
│    ┌─────────────────────────────┐   │
│    │   Application Logic         │   │
│    │   • Camera control          │   │
│    │   • Audio processing        │   │
│    └─────────────────────────────┘   │
└─────────────────────────────────────────┘
```

## Communication Channels

### Bluetooth LE (Control Channel)
- **Device Name**: `ThirdEye_CM4`
- **Service UUID**: `12345678-1234-5678-1234-56789abcdef0`
- **Characteristics**:
  - Command (Write): `..def1` - Send commands
  - Response (Notify): `..def2` - Receive responses
  - Terminal In (Write): `..def3` - SSH input
  - Terminal Out (Notify): `..def4` - SSH output
  - Audio Data (Write): `..def5` - Audio uplink
  - Config (Read/Write): `..def6` - Configuration

### 5GHz WiFi (Data Channel)
- **SSID**: `StereoPi_5G`
- **Password**: `5maltesers`
- **CM4 IP**: `192.168.50.1`
- **Frequency**: 5GHz (channel 36)
- **Video Streams**:
  - Left camera: `http://192.168.50.1:8081/stream`
  - Right camera: `http://192.168.50.1:8082/stream`
  - Eye camera: `http://192.168.50.1:8083/stream`

## User Flow

1. **Power On**: CM4 boots and starts BLE advertising
2. **BLE Discovery**: Phone app scans and finds `ThirdEye_CM4`
3. **BLE Connect**: App connects to BLE service
4. **Configuration**: App sends config commands via BLE
5. **WiFi Start**: App sends `WIFI_START` command
6. **WiFi Connect**: Phone auto-connects to `StereoPi_5G`
7. **Video Streaming**: App connects to video streams over WiFi
8. **Operation**:
   - Control/config via BLE
   - Video streaming via WiFi
   - Audio uplink via BLE

## CM4 Setup

### 1. Copy Files to CM4

```bash
# From your computer, copy server files
scp cm4_server/ble_control_server.py anton@192.168.50.1:~/
scp cm4_server/camera_server.py anton@192.168.50.1:~/
```

### 2. Install Dependencies

```bash
# SSH to CM4
ssh anton@192.168.50.1

# Install BLE dependencies
sudo apt update
sudo apt install -y python3-dbus python3-gi bluez

# Install camera dependencies
sudo apt install -y python3-pip python3-picamera2 python3-flask
pip3 install flask pillow --break-system-packages
```

### 3. Create Systemd Services

**BLE Control Service** (`/etc/systemd/system/cm4-ble.service`):
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

**Camera Server Service** (`/etc/systemd/system/cm4-camera.service`):
```ini
[Unit]
Description=CM4 Triple Camera Server
After=network-online.target wlan0-ap.service
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

### 4. Enable and Start Services

```bash
# Enable services
sudo systemctl daemon-reload
sudo systemctl enable cm4-ble.service
sudo systemctl enable cm4-camera.service

# Start services
sudo systemctl start cm4-ble.service
sudo systemctl start cm4-camera.service

# Check status
sudo systemctl status cm4-ble.service
sudo systemctl status cm4-camera.service
```

### 5. Verify BLE Advertisement

```bash
# Check if BLE is advertising
sudo bluetoothctl
> scan on
# Should see "ThirdEye_CM4" appear
> exit
```

## Flutter App Integration

### 1. Add Dependencies

Add to `pubspec.yaml`:
```yaml
dependencies:
  # BLE support
  flutter_blue_plus: ^1.32.0

  # Audio recording
  record: ^5.0.0
  path_provider: ^2.1.2

  # Permissions
  permission_handler: ^11.3.0
```

### 2. Request Permissions

Add to `AndroidManifest.xml`:
```xml
<!-- Bluetooth permissions -->
<uses-permission android:name="android.permission.BLUETOOTH" />
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" />
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />

<!-- Audio permission -->
<uses-permission android:name="android.permission.RECORD_AUDIO" />
```

### 3. BLE Service Structure

See `lib/services/cm4_ble_service.dart` for complete implementation.

Key methods:
- `scanForCM4()` - Scan for ThirdEye_CM4
- `connect()` - Connect to BLE device
- `sendCommand(String cmd)` - Send commands
- `startAudioUplink()` - Start audio streaming
- `disconnect()` - Disconnect from device

## Commands via BLE

Send commands to Command characteristic (`..def1`):

| Command | Description | Response |
|---------|-------------|----------|
| `WIFI_STATUS` | Get WiFi AP status | `WIFI:active` or `WIFI:inactive` |
| `WIFI_START` | Start WiFi AP | `WIFI:started` |
| `WIFI_STOP` | Stop WiFi AP | `WIFI:stopped` |
| `CAMERA_START` | Start camera server | `CAMERA:started` |
| `CAMERA_STOP` | Stop camera server | `CAMERA:stopped` |
| `STATUS` | Get full system status | `STATUS:wifi=active,camera=active` |
| `REBOOT` | Reboot CM4 | `REBOOTING` |

## Audio Uplink Protocol

Audio is sent from phone to CM4 via BLE:

1. **Format**: PCM 16-bit, 16kHz mono
2. **Chunk Size**: 512 bytes per write
3. **Characteristic**: Audio Data (`..def5`)
4. **Flow**: Phone records → Encode → Send via BLE → CM4 processes

CM4 receives audio and can:
- Save to file
- Process with speech recognition
- Stream to another service

## Testing Checklist

### BLE Testing
- [ ] CM4 appears as "ThirdEye_CM4" in BLE scan
- [ ] Can connect to BLE service
- [ ] Can send commands and receive responses
- [ ] Commands execute correctly (WiFi, camera control)

### WiFi Testing
- [ ] Can connect to "StereoPi_5G" network
- [ ] Gets IP address 192.168.50.X
- [ ] Can access video streams
- [ ] Streams are smooth and low-latency

### Hybrid Testing
- [ ] BLE and WiFi work simultaneously
- [ ] Can control via BLE while viewing video
- [ ] Phone uses cellular for internet
- [ ] Audio uplink works over BLE

### Integration Testing
- [ ] App can discover and connect automatically
- [ ] Video display works in app
- [ ] Commands trigger appropriate actions
- [ ] Survives reconnection scenarios

## Troubleshooting

### BLE Issues

**Device not found in scan:**
```bash
# On CM4, check BLE service
sudo systemctl status cm4-ble.service
sudo journalctl -u cm4-ble.service -f

# Check Bluetooth
sudo bluetoothctl
> show
# Should see "Powered: yes" and "Discoverable: yes"
```

**Can't connect:**
- Ensure Bluetooth is enabled on phone
- Check distance (BLE has limited range)
- Restart BLE service: `sudo systemctl restart cm4-ble.service`

### WiFi Issues

**Can't see StereoPi_5G:**
- Check hostapd: `sudo systemctl status hostapd`
- Check wlan0: `ip addr show wlan0`
- Should show `192.168.50.1/24`

**Connected but no video:**
- Check camera service: `sudo systemctl status cm4-camera.service`
- Test streams: `curl http://192.168.50.1:8081/health`

### Performance Issues

**Video laggy:**
- Reduce resolution in `camera_server.py`
- Lower FPS (set TARGET_FPS = 5)
- Ensure only one camera stream is active

**BLE commands slow:**
- Check signal strength
- Reduce BLE distance
- Avoid interference (move away from WiFi routers)

## Security Notes

⚠️ **Important**: This is a development configuration. For production:

1. **WiFi Security**: Change password in `/etc/hostapd/hostapd.conf`
2. **BLE Security**: Implement pairing/bonding
3. **SSH**: Use key-based authentication
4. **Firewall**: Configure iptables to restrict access

## Next Steps

1. ✅ CM4 WiFi AP working
2. ✅ BLE server created
3. ⬜ Deploy BLE server to CM4
4. ⬜ Test BLE commands
5. ⬜ Implement Flutter BLE service
6. ⬜ Add audio uplink
7. ⬜ Integrate with existing app screens
8. ⬜ Test full hybrid system

## References

- [BlueZ D-Bus API](https://github.com/bluez/bluez/tree/master/doc)
- [Flutter Blue Plus](https://pub.dev/packages/flutter_blue_plus)
- [hostapd Documentation](https://w1.fi/hostapd/)
- [Raspberry Pi Camera Documentation](https://datasheets.raspberrypi.com/camera/picamera2-manual.pdf)

---

*Generated: 2025-12-04*
*Architecture: Hybrid BLE + 5GHz WiFi*
*Device: CM4 on StereoPi v2*
