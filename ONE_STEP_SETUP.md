# Third Eye - ONE STEP SETUP

## What You Get

Boot CM4 → Build app → Open → See cameras. Fully automatic.

---

## Step 1: Setup CM4 (One Time)

### Copy Setup File to Boot Partition

1. **Insert CM4 SD card into your computer**

2. **Copy the setup file:**
   ```bash
   # On Windows: Copy from project to D:\ (boot partition)
   copy firstrun_complete.sh D:\firstrun.sh

   # On Linux/Mac:
   cp firstrun_complete.sh /path/to/boot/firstrun.sh
   chmod +x /path/to/boot/firstrun.sh
   ```

3. **Eject SD card and insert into CM4**

4. **Power on CM4 and wait 5-10 minutes**
   - First boot installs everything automatically
   - CM4 will create "StereoPi_5G" WiFi network
   - CM4 will advertise "ThirdEye_CM4" via Bluetooth

5. **Verify setup (optional):**
   - On your phone, look for "StereoPi_5G" WiFi (should appear)
   - Connect with password: `5maltesers`
   - SSH to CM4: `ssh anton@192.168.50.1`
   - Check logs: `cat /boot/firmware/setup-complete.log`

---

## Step 2: Build Android App

```bash
# Install dependencies
flutter pub get

# Build and install on phone
flutter run
# OR
flutter build apk
# Then install: build/app/outputs/flutter-apk/app-release.apk
```

---

## Step 3: Use the App

1. **Power on CM4** (if not already on)
2. **Open Third Eye app on phone**
3. **App automatically:**
   - Scans for CM4 via Bluetooth
   - Connects to "ThirdEye_CM4"
   - Starts WiFi AP
   - Starts cameras
   - Connects to video streams
   - **Shows cameras!**

---

## What Runs Automatically

### On CM4 (Auto-start on every boot):
- ✅ WiFi AP: `StereoPi_5G` @ 192.168.50.1
- ✅ BLE Server: `ThirdEye_CM4`
- ✅ Camera Server: 3 cameras @ ports 8081, 8082, 8083

### On App Open:
- ✅ Scans for CM4 Bluetooth
- ✅ Connects via BLE
- ✅ Connects to WiFi streams
- ✅ Displays cameras

---

## Troubleshooting

### CM4 Setup Issues

**StereoPi_5G WiFi doesn't appear:**
```bash
# SSH via ethernet or HDMI+keyboard
ssh anton@<cm4-ip>

# Check services
sudo systemctl status hostapd wlan0-ap cm4-camera cm4-ble

# Restart if needed
sudo systemctl restart hostapd wlan0-ap cm4-camera cm4-ble
```

**Check setup log:**
```bash
# On boot partition (D:\ on Windows)
cat D:\setup-complete.log

# Or via SSH
cat /boot/firmware/setup-complete.log
```

### App Issues

**App says "CM4 not found":**
- Ensure Bluetooth is enabled on phone
- Grant app all permissions (Bluetooth, Location)
- Ensure CM4 is powered on and booted
- Try restarting CM4

**App connects but no video:**
- Ensure phone is connected to `StereoPi_5G` WiFi
- Password is `5maltesers`
- Android should connect automatically after BLE handshake
- If not, manually connect to WiFi first

**Permissions denied:**
- Go to Android Settings → Apps → Third Eye → Permissions
- Enable: Bluetooth, Location, Camera (if using local camera)

---

## Network Details

**WiFi AP:**
- SSID: `StereoPi_5G`
- Password: `5maltesers`
- CM4 IP: `192.168.50.1`
- Your phone gets: `192.168.50.x`

**Bluetooth:**
- Device name: `ThirdEye_CM4`
- Service UUID: `12345678-1234-5678-1234-56789abcdef0`

**Camera Streams:**
- Left: `http://192.168.50.1:8081/stream`
- Right: `http://192.168.50.1:8082/stream`
- Eye: `http://192.168.50.1:8083/stream`

---

## Phone WiFi Configuration

**To use cellular for internet while connected to CM4:**

1. Connect to `StereoPi_5G`
2. Android Settings → WiFi → StereoPi_5G → ⚙️
3. Enable "Metered connection" or disable "Auto-switch to mobile data"
4. Android will:
   - Keep WiFi connected to CM4 for video
   - Use cellular for internet

---

## Files Created

**CM4 (created automatically by firstrun.sh):**
- `/home/anton/camera_server.py` - Camera MJPEG server
- `/home/anton/ble_server.py` - Bluetooth control server
- `/etc/systemd/system/cm4-camera.service` - Camera auto-start
- `/etc/systemd/system/cm4-ble.service` - BLE auto-start
- `/etc/systemd/system/wlan0-ap.service` - WiFi AP setup
- `/etc/hostapd/hostapd.conf` - WiFi AP config
- `/etc/dnsmasq.conf` - DHCP server config

**Flutter App:**
- `lib/screens/camera_view_screen.dart` - Auto-connecting camera view
- `lib/services/cm4_ble_service.dart` - BLE control
- `lib/services/cm4_stream_service.dart` - Video streaming

---

## That's It!

Three simple steps:
1. Copy `firstrun.sh` to boot partition → Boot CM4 (one time)
2. Build Flutter app
3. Open app → See cameras

No manual configuration. No SSH commands. Just works.

---

**Questions?** Check `/boot/firmware/setup-complete.log` on CM4 for detailed setup logs.
