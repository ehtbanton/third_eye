# CM4 Simplified Setup Guide

## Architecture Overview

The simplified architecture removes all BLE complexity:

```
┌─────────────────────┐
│   Flutter Phone     │
│  (WiFi Hotspot)     │
│  192.168.43.1       │
└──────────┬──────────┘
           │ WiFi
           │ 5GHz
           │
┌──────────▼──────────┐
│   CM4 Device        │
│  Static IP:         │
│  192.168.43.100     │
│                     │
│  Port 8081: Left    │
│  Port 8082: Right   │
│  Port 8083: Eye     │
└─────────────────────┘
```

## Phone Configuration

**Hotspot Settings:**
- SSID: `ThirdEye_Hotspot`
- Password: `thirdeye123`
- IP Range: `192.168.43.x`
- Phone IP: `192.168.43.1` (automatic)

**The app automatically:**
1. Enables hotspot on startup
2. Waits for CM4 to connect
3. Performs health check at `http://192.168.43.100:8081/health`
4. Connects to all 3 camera streams

## CM4 Configuration

### 1. WiFi Client Configuration

Edit `/etc/wpa_supplicant/wpa_supplicant.conf`:

```bash
sudo nano /etc/wpa_supplicant/wpa_supplicant.conf
```

Add:

```
country=US
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1

network={
    ssid="ThirdEye_Hotspot"
    psk="thirdeye123"
    key_mgmt=WPA-PSK
    priority=10
}
```

### 2. Static IP Configuration

Edit `/etc/dhcpcd.conf`:

```bash
sudo nano /etc/dhcpcd.conf
```

Add at the end:

```bash
# Static IP for Third Eye phone hotspot connection
interface wlan0
static ip_address=192.168.43.100/24
static routers=192.168.43.1
static domain_name_servers=192.168.43.1 8.8.8.8
```

### 3. Camera Server Setup

The Python camera server (`cm4_server/camera_server.py`) needs no changes.
It already serves on ports 8081, 8082, 8083.

Create systemd service `/etc/systemd/system/cm4-camera.service`:

```ini
[Unit]
Description=CM4 Triple Camera Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=pi
WorkingDirectory=/home/pi/third_eye/cm4_server
ExecStart=/usr/bin/python3 /home/pi/third_eye/cm4_server/camera_server.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

Enable and start:

```bash
sudo systemctl daemon-reload
sudo systemctl enable cm4-camera
sudo systemctl start cm4-camera
```

### 4. Auto-Connect on Boot

Ensure WiFi auto-connects:

```bash
sudo systemctl enable wpa_supplicant
sudo systemctl enable dhcpcd
```

### 5. Testing

Reboot CM4:

```bash
sudo reboot
```

After reboot, verify:

```bash
# Check WiFi connection
ip addr show wlan0
# Should show: inet 192.168.43.100/24

# Check camera server
systemctl status cm4-camera
# Should show: active (running)

# Test camera endpoint
curl http://localhost:8081/health
# Should return: {"status": "ok", "camera": "left"}
```

## Network Flow

1. **Power on CM4** → Boots and connects to `ThirdEye_Hotspot`
2. **CM4 gets IP** → Static IP `192.168.43.100`
3. **Camera server starts** → Serves on ports 8081-8083
4. **Phone app starts** → Enables hotspot, waits for CM4
5. **Phone health check** → Pings `http://192.168.43.100:8081/health`
6. **Stream connection** → HTTP GET to `/stream` on each port
7. **MJPEG streaming** → 3 simultaneous 1080p @ 10fps streams

## 5GHz WiFi Optimization

For best performance with 3 simultaneous 1080p streams:

Edit `/etc/hostapd/hostapd.conf` on phone (if accessible) or use router:

```
# Use 5GHz band
hw_mode=a
channel=36

# Enable 802.11ac
ieee80211ac=1

# Use 80MHz channel width for maximum throughput
vht_oper_chwidth=1
vht_oper_centr_freq_seg0_idx=42

# Max bandwidth
wmm_enabled=1
```

**Expected bandwidth:**
- Each stream: ~10 Mbps (1080p MJPEG @ 10fps, quality 80)
- Total: ~30 Mbps
- 5GHz 802.11ac provides: 433-867 Mbps (plenty of headroom)

## Troubleshooting

### CM4 not connecting to hotspot

```bash
# Check WiFi status
sudo systemctl status wpa_supplicant
sudo wpa_cli status

# Scan for networks
sudo iwlist wlan0 scan | grep "ThirdEye_Hotspot"

# Check logs
journalctl -u wpa_supplicant -n 50
```

### Phone can't reach CM4

```bash
# On CM4, check if network is up
ip addr show wlan0

# Verify static IP
ping 192.168.43.100  # Should respond

# Check if camera server is listening
sudo netstat -tlnp | grep python3
# Should show ports 8081, 8082, 8083
```

### Streams not working

```bash
# Check camera server status
systemctl status cm4-camera

# View camera server logs
journalctl -u cm4-camera -f

# Test streams locally
curl -I http://localhost:8081/stream
# Should return: Content-Type: multipart/x-mixed-replace
```

## What We Removed

❌ **BLE control server** - No longer needed
❌ **CM4 WiFi AP mode** - Phone is now the hotspot
❌ **hostapd/dnsmasq** - Not needed on CM4
❌ **BLE discovery/pairing** - Direct IP connection
❌ **Command/response protocol** - Cameras auto-start

## What We Kept

✅ **3 camera MJPEG streams** - Same streaming protocol
✅ **Adaptive FPS** - Server adjusts based on load
✅ **Port-per-camera design** - Independent stream control
✅ **Health check endpoint** - For connectivity testing

## Benefits of Simplified Architecture

1. **Fewer moving parts** - No BLE, no AP mode
2. **Faster startup** - Phone hotspot is instant
3. **More reliable** - WiFi client mode is simpler than AP
4. **Better range** - Phone antennas often better than CM4
5. **Less power** - No BLE radio needed
6. **Easier debugging** - Standard WiFi tools work
7. **Known network** - Fixed IPs, no discovery needed
