# Quick Start - Simplified Architecture

## TL;DR

**Phone** creates hotspot → **CM4** connects with static IP → **Stream video** over WiFi

## 30-Second Setup

### Phone Side (Already Done)

The Flutter app now automatically:
1. Enables hotspot `ThirdEye_Hotspot` (password: `thirdeye123`)
2. Waits for CM4 at `192.168.43.100`
3. Connects to camera streams

### CM4 Side (One-Time Setup)

```bash
# 1. Configure WiFi client
sudo tee -a /etc/wpa_supplicant/wpa_supplicant.conf > /dev/null <<EOF

network={
    ssid="ThirdEye_Hotspot"
    psk="thirdeye123"
    key_mgmt=WPA-PSK
    priority=10
}
EOF

# 2. Set static IP
sudo tee -a /etc/dhcpcd.conf > /dev/null <<EOF

# Third Eye static IP
interface wlan0
static ip_address=192.168.43.100/24
static routers=192.168.43.1
static domain_name_servers=192.168.43.1 8.8.8.8
EOF

# 3. Enable camera server (if not already)
sudo systemctl enable cm4-camera
sudo systemctl start cm4-camera

# 4. Reboot
sudo reboot
```

## Usage Flow

1. **Open app** on phone
2. **App enables hotspot** automatically
3. **CM4 connects** (within 10 seconds)
4. **Cameras stream** instantly

That's it!

## Files Created

### Flutter App
- `lib/services/phone_hotspot_service.dart` - Manages phone hotspot
- `lib/services/cm4_stream_service_simple.dart` - Connects to CM4 cameras
- `lib/screens/cm4_camera_screen.dart` - UI for camera viewing

### Documentation
- `CM4_SIMPLIFIED_SETUP.md` - Complete setup guide
- `QUICK_START_SIMPLIFIED.md` - This file

## Testing

### Test CM4 is ready:

```bash
# On CM4
ip addr show wlan0  # Should show 192.168.43.100
systemctl status cm4-camera  # Should be active
curl http://localhost:8081/health  # Should return {"status": "ok"}
```

### Test from phone:

```bash
# In app, you'll see:
# "Waiting for CM4..." → "CM4 ready!" → "Connected! Streaming..."
```

## Network Map

```
Phone: 192.168.43.1
  ↓
CM4: 192.168.43.100
  ├─ Port 8081 → Left camera
  ├─ Port 8082 → Right camera
  └─ Port 8083 → Eye camera
```

## What Changed From Old Architecture

| Old (Complex) | New (Simple) |
|---------------|--------------|
| BLE discovery | Static IP |
| CM4 creates WiFi AP | Phone creates hotspot |
| BLE commands to start cameras | Cameras auto-start on boot |
| Phone connects to CM4's WiFi | CM4 connects to phone's WiFi |
| Complex multi-protocol setup | Pure WiFi |

## Next Steps

1. Update `pubspec.yaml` dependencies:
   ```bash
   flutter pub get
   ```

2. Use the new screen in your app:
   ```dart
   import 'package:third_eye/screens/cm4_camera_screen.dart';

   // Navigate to it:
   Navigator.push(
     context,
     MaterialPageRoute(builder: (context) => Cm4CameraScreen()),
   );
   ```

3. Configure CM4 (see commands above)

4. Test!
