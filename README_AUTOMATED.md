# Third Eye - Fully Automated Setup

## One Command Does Everything

```powershell
# Windows (PowerShell)
.\build_and_deploy.ps1

# Linux/Mac
./build_and_deploy.sh
```

This script automatically:
1. ✅ Finds CM4 boot partition
2. ✅ Copies setup script to CM4
3. ✅ Installs Flutter dependencies
4. ✅ Builds and runs the app

---

## Complete Workflow

### First Time Setup

1. **Enable Developer Mode (Windows only)**
   ```powershell
   # Run this once
   start ms-settings:developers
   # Toggle ON, then close
   ```

2. **Insert CM4 SD Card**
   - Insert CM4 SD card into your computer
   - Should appear as D: (or E:, F:, etc.)

3. **Run Build Script**
   ```powershell
   .\build_and_deploy.ps1
   ```

   The script will:
   - Find the CM4 boot partition
   - Copy `firstrun.sh` to boot partition
   - Install Flutter packages
   - Build and run the app

4. **Boot CM4**
   - Eject SD card
   - Insert into CM4
   - Power on
   - **Wait 10 minutes** (first boot only)

5. **Open App**
   - Open Third Eye app on your phone
   - Cameras appear automatically!

---

## What Happens Automatically

### On CM4 First Boot (10 minutes)

The `firstrun.sh` script runs and:
1. Installs Python, BLE libraries, camera libraries
2. Removes all old network configs
3. Creates WiFi AP: **StereoPi_5G**
4. Creates BLE server: **ThirdEye_CM4**
5. Creates 3 camera streams (ports 8081, 8082, 8083)
6. Sets up auto-start for all services
7. Starts everything

### On Every Boot After

Services auto-start:
- **wlan0-ap** - WiFi interface setup
- **hostapd** - WiFi Access Point
- **dnsmasq** - DHCP server
- **cm4-camera** - 3 camera streams
- **cm4-ble** - Bluetooth control

### When You Open the App

The app automatically:
1. Scans for "ThirdEye_CM4" Bluetooth
2. Connects via BLE
3. Sends WiFi start command
4. Sends camera start command
5. Connects to video streams
6. **Shows cameras!**

---

## Network Details

**WiFi:**
- SSID: `StereoPi_5G`
- Password: `5maltesers`
- CM4 IP: `192.168.50.1`

**Bluetooth:**
- Name: `ThirdEye_CM4`
- Service UUID: `12345678-1234-5678-1234-56789abcdef0`

**Cameras:**
- Left: `http://192.168.50.1:8081/stream`
- Right: `http://192.168.50.1:8082/stream`
- Eye: `http://192.168.50.1:8083/stream`

---

## Troubleshooting

### Developer Mode Issue (Windows)

```
Error: Building with plugins requires symlink support
```

**Fix:**
1. Run: `start ms-settings:developers`
2. Toggle "Developer Mode" ON
3. Close settings
4. Run build script again

### CM4 Boot Partition Not Found

```
⚠ CM4 boot partition not found
```

**Fix:**
- Insert CM4 SD card into computer
- Should appear as D: drive (Windows) or /media/boot (Linux)
- Run build script again

### App Can't Find CM4

**Check:**
1. Is CM4 powered on?
2. Did you wait 10 minutes after first boot?
3. Is Bluetooth enabled on phone?
4. Are app permissions granted? (Bluetooth, Location)

**Verify CM4 is ready:**
```bash
# On phone, look for WiFi "StereoPi_5G"
# If visible, CM4 is ready

# SSH to CM4
ssh anton@192.168.50.1

# Check services
systemctl status cm4-ble cm4-camera hostapd

# Check setup log
cat /boot/firmware/setup-complete.log
```

### No Video in App

**Check:**
1. Is phone connected to `StereoPi_5G` WiFi?
2. Can you ping CM4? `ping 192.168.50.1`
3. Test camera streams:
   - Open browser on phone
   - Go to: `http://192.168.50.1:8081/stream`
   - Should see video

---

## Files Created

### In Project
- `build_and_deploy.ps1` - Windows build script
- `build_and_deploy.sh` - Linux/Mac build script
- `firstrun_complete.sh` - CM4 setup script
- `lib/screens/camera_view_screen.dart` - Auto-connecting UI
- `lib/services/cm4_ble_service.dart` - BLE control
- `lib/services/cm4_stream_service.dart` - Video streaming

### On CM4 (created by firstrun.sh)
- `/home/anton/camera_server.py` - Camera server
- `/home/anton/ble_server.py` - BLE server
- `/etc/systemd/system/cm4-camera.service` - Camera auto-start
- `/etc/systemd/system/cm4-ble.service` - BLE auto-start
- `/etc/systemd/system/wlan0-ap.service` - WiFi setup
- `/etc/hostapd/hostapd.conf` - WiFi AP config
- `/etc/dnsmasq.conf` - DHCP config

---

## Advanced: Manual Steps (If Needed)

If the automated script doesn't work, you can run steps manually:

### Manual CM4 Setup
```bash
# Copy firstrun.sh manually
copy firstrun_complete.sh D:\firstrun.sh

# Boot CM4 with SD card
# Wait 10 minutes
```

### Manual App Build
```bash
flutter pub get
flutter run
```

---

## That's It!

**Normal workflow:**
1. Run `.\build_and_deploy.ps1` (once)
2. Boot CM4 (wait 10 min first time)
3. Open app → See cameras

**Every subsequent time:**
1. Power on CM4
2. Open app → See cameras

Fully automated. No configuration needed.
