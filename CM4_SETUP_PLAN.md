# Third Eye CM4 Setup Plan
## Fresh Raspberry Pi OS Lite Installation

### Prerequisites
- Raspberry Pi Imager installed
- CM4 in boot mode (rpiboot to access eMMC)

### Step 1: Flash Fresh OS
1. Download **Raspberry Pi OS Lite (64-bit)** using Raspberry Pi Imager
2. Flash to CM4 eMMC
3. Configure in Imager settings (⚙️):
   - Hostname: `stereopi`
   - Username: `anton` / Password: `<your-password>`
   - Enable SSH
   - **Do NOT configure WiFi** (we need custom AP)

### Step 2: Configure Boot Partition
After flashing, the boot partition will be mounted. Create these files:

**File: `user-data` (cloud-init config)**
```yaml
#cloud-config

hostname: stereopi

users:
  - default
  - name: anton
    gecos: Anton
    groups: users,adm,dialout,audio,video,plugdev,games,input,render,netdev,gpio,i2c,spi
    sudo: ALL=(ALL) NOPASSWD:ALL
    lock_passwd: false
    passwd: <hashed-password>

ssh_pwauth: true

runcmd:
  - [ bash, /boot/firmware/cm4_setup_complete.sh ]
```

**File: `cm4_setup_complete.sh`**
- Copy the complete setup script to boot partition
- Make executable: `chmod +x cm4_setup_complete.sh`

### Step 3: First Boot
1. Eject SD card / eMMC
2. Boot CM4
3. Wait 10-15 minutes for complete setup
4. CM4 will:
   - Install all packages
   - Configure WiFi AP (StereoPi_5G)
   - Start camera servers
   - Start BLE with ALL characteristics
   - Create completion flag

### Step 4: App Connection
1. Open Third Eye app on phone
2. App automatically:
   - Scans for "ThirdEye_CM4" BLE device
   - Connects via BLE
   - Sends WIFI_START command (already running)
   - Sends CAMERA_START command (already running)
   - Connects to WiFi streams
   - Displays cameras

### What's Auto-Configured
**BLE Service (Control Channel):**
- ✓ Command characteristic - send commands
- ✓ Response characteristic - get status
- ✓ Terminal In/Out - SSH over BLE (future)
- ✓ Audio characteristic - phone mic uplink (future)
- ✓ Config characteristic - settings (future)

**WiFi AP (Data Channel):**
- SSID: StereoPi_5G
- Password: 5maltesers
- IP: 192.168.50.1
- 5GHz 802.11ac

**Camera Servers:**
- Left: http://192.168.50.1:8081/stream
- Right: http://192.168.50.1:8082/stream
- Eye: http://192.168.50.1:8083/stream

### Workflow
```
Power On CM4
    ↓
BLE advertises "ThirdEye_CM4"
    ↓
App scans & finds device
    ↓
App connects via BLE
    ↓
App sends WIFI_START (already running)
    ↓
App sends CAMERA_START (already running)
    ↓
App connects to camera streams
    ↓
User sees cameras!
```

### Logs
Check `/boot/firmware/thirdeye-complete-setup.log` after first boot

### SSH Access
```bash
ssh anton@192.168.50.1
```

### Troubleshooting
If BLE doesn't work:
```bash
ssh anton@192.168.50.1
sudo systemctl status cm4-ble
sudo journalctl -u cm4-ble -f
```

If cameras don't work:
```bash
sudo systemctl status cm4-camera
```

If WiFi AP doesn't work:
```bash
sudo systemctl status wlan0-ap hostapd dnsmasq
```
