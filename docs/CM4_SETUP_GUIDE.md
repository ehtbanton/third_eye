# CM4 Triple Camera Setup Guide

Complete guide to setting up a Raspberry Pi Compute Module 4 (CM4) for streaming 3 camera feeds to the Third Eye Flutter app.

---

## Table of Contents

1. [Hardware Requirements](#hardware-requirements)
2. [Initial CM4 Setup](#initial-cm4-setup)
3. [Configure 5GHz WiFi Hotspot](#configure-5ghz-wifi-hotspot)
4. [Install Camera Server Software](#install-camera-server-software)
5. [Configure Cameras](#configure-cameras)
6. [Run the Camera Server](#run-the-camera-server)
7. [Connect from Flutter App](#connect-from-flutter-app)
8. [Troubleshooting](#troubleshooting)
9. [Performance Tuning](#performance-tuning)

---

## Hardware Requirements

### Required Components

- **Raspberry Pi CM4** (any variant with WiFi)
  - Recommended: CM4 with at least 2GB RAM
  - Must have WiFi module (not CM4 Lite without WiFi)

- **CM4 IO Board** or compatible carrier board

- **3x Camera Modules** connected to CM4:
  - Official Raspberry Pi Camera Modules (v1, v2, or HQ Camera)
  - Or compatible CSI cameras
  - Note: CM4 has 2 CSI ports, you'll need a multiplexer or USB cameras for 3 feeds

- **Power Supply**: 5V 3A USB-C (recommended for CM4 with cameras)

- **MicroSD Card**: 16GB minimum (if using CM4 without eMMC)

### Camera Connection Options

**Option 1: 2 CSI + 1 USB Camera**
- Camera 0 (Left): CSI port 0
- Camera 1 (Right): CSI port 1
- Camera 2 (Eye): USB camera

**Option 2: CSI Multiplexer** (Advanced)
- Use Arducam Multi-Camera Adapter for 3+ CSI cameras
- Requires additional configuration

---

## Initial CM4 Setup

### 1. Install Raspberry Pi OS

```bash
# Use Raspberry Pi Imager to flash Raspberry Pi OS (64-bit recommended)
# Enable SSH during imaging (Settings → Services → SSH)
# Set username: pi
# Set password: (your choice)
```

### 2. Boot and SSH Access

```bash
# Connect CM4 to your network via Ethernet initially
# Find CM4 IP address (check your router or use nmap)
ssh pi@<cm4-ip-address>
```

### 3. Update System

```bash
sudo apt update && sudo apt upgrade -y
sudo reboot
```

---

## Configure 5GHz WiFi Hotspot

### 1. Install Required Packages

```bash
sudo apt install -y hostapd dnsmasq iptables-persistent
```

### 2. Configure Static IP for WiFi Interface

```bash
sudo nano /etc/dhcpcd.conf
```

Add at the end:

```
interface wlan0
    static ip_address=192.168.50.1/24
    nohook wpa_supplicant
```

### 3. Configure DHCP Server (dnsmasq)

```bash
sudo mv /etc/dnsmasq.conf /etc/dnsmasq.conf.orig
sudo nano /etc/dnsmasq.conf
```

Add:

```
interface=wlan0
dhcp-range=192.168.50.10,192.168.50.100,255.255.255.0,24h
domain=local
address=/cm4.local/192.168.50.1
```

### 4. Configure Access Point (hostapd)

```bash
sudo nano /etc/hostapd/hostapd.conf
```

Add:

```
# Interface and driver
interface=wlan0
driver=nl80211

# WiFi configuration
ssid=CM4-ThirdEye
hw_mode=a
channel=36
ieee80211n=1
ieee80211ac=1
wmm_enabled=1

# Security
wpa=2
wpa_passphrase=thirdeye123
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP

# Country code (change to your country)
country_code=US
```

**Important Notes:**
- `hw_mode=a` enables 5GHz
- `channel=36` is a common 5GHz channel (use 36, 40, 44, or 48 for compatibility)
- Change `country_code` to your country (US, GB, etc.)
- Change `wpa_passphrase` if desired

### 5. Enable hostapd

```bash
sudo nano /etc/default/hostapd
```

Find and set:

```
DAEMON_CONF="/etc/hostapd/hostapd.conf"
```

### 6. Enable IP Forwarding (Optional - for internet sharing)

```bash
sudo nano /etc/sysctl.conf
```

Uncomment:

```
net.ipv4.ip_forward=1
```

Apply:

```bash
sudo sysctl -p
```

### 7. Configure NAT (Optional - for internet sharing)

```bash
sudo iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
sudo netfilter-persistent save
```

### 8. Enable and Start Services

```bash
sudo systemctl unmask hostapd
sudo systemctl enable hostapd
sudo systemctl enable dnsmasq
sudo reboot
```

### 9. Verify Hotspot

After reboot, you should see the WiFi network **CM4-ThirdEye** on your phone/computer.

---

## Install Camera Server Software

### 1. Install Python Dependencies

```bash
sudo apt install -y python3-pip python3-picamera2 python3-flask
pip3 install flask pillow --break-system-packages
```

**Note:** `--break-system-packages` is needed on newer Raspberry Pi OS. Alternatively, use a virtual environment.

### 2. Copy Camera Server Script

Transfer the `camera_server.py` file to your CM4:

```bash
# On your computer (from the third_eye project directory):
scp cm4_server/camera_server.py pi@192.168.50.1:~/
```

Or create it manually:

```bash
nano ~/camera_server.py
# Paste the contents of cm4_server/camera_server.py
```

### 3. Make Script Executable

```bash
chmod +x ~/camera_server.py
```

---

## Configure Cameras

### 1. Enable Camera Interface

```bash
sudo raspi-config
# Navigate to: Interface Options → Camera → Enable
# Reboot
```

### 2. Test Camera Detection

```bash
# List available cameras
libcamera-hello --list-cameras
```

You should see your connected cameras listed (e.g., 0, 1, 2).

### 3. Update Camera Indices (if needed)

If your physical cameras don't match the expected indices (left=0, right=1, eye=2), edit `camera_server.py`:

```bash
nano ~/camera_server.py
```

Find and modify the `CAMERAS` dictionary:

```python
CAMERAS = {
    'left': {'port': 8081, 'camera_index': 0},   # Change index as needed
    'right': {'port': 8082, 'camera_index': 1},  # Change index as needed
    'eye': {'port': 8083, 'camera_index': 2}     # Change index as needed
}
```

### 4. Test Individual Camera

```bash
# Test camera 0
libcamera-still -t 2000 --camera 0 -o test0.jpg

# Test camera 1
libcamera-still -t 2000 --camera 1 -o test1.jpg

# Test camera 2
libcamera-still -t 2000 --camera 2 -o test2.jpg
```

---

## Run the Camera Server

### 1. Manual Test Run

```bash
python3 ~/camera_server.py
```

You should see output like:

```
============================================================
CM4 Triple Camera MJPEG Streaming Server
Resolution: 1920x1080
Target FPS: 10 (adaptive down to 5)
JPEG Quality: 80
============================================================
Camera 'left' starting on port 8081
Camera 'right' starting on port 8082
Camera 'eye' starting on port 8083

All camera servers started. Press Ctrl+C to stop.

Stream URLs:
  Left:  http://192.168.50.1:8081/stream
  Right: http://192.168.50.1:8082/stream
  Eye:   http://192.168.50.1:8083/stream
...
```

### 2. Test Stream in Browser

On a device connected to the **CM4-ThirdEye** WiFi:

```
http://192.168.50.1:8081/stream  (Left camera)
http://192.168.50.1:8082/stream  (Right camera)
http://192.168.50.1:8083/stream  (Eye camera)
```

You should see live MJPEG video.

### 3. Check Stats

```
http://192.168.50.1:8081/stats
http://192.168.50.1:8082/stats
http://192.168.50.1:8083/stats
```

### 4. Setup Auto-Start (systemd service)

Create a systemd service file:

```bash
sudo nano /etc/systemd/system/cm4-camera.service
```

Add:

```ini
[Unit]
Description=CM4 Triple Camera MJPEG Streaming Server
After=network.target

[Service]
Type=simple
User=pi
WorkingDirectory=/home/pi
ExecStart=/usr/bin/python3 /home/pi/camera_server.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

Enable and start:

```bash
sudo systemctl daemon-reload
sudo systemctl enable cm4-camera.service
sudo systemctl start cm4-camera.service
```

Check status:

```bash
sudo systemctl status cm4-camera.service
```

View logs:

```bash
sudo journalctl -u cm4-camera.service -f
```

---

## Connect from Flutter App

### 1. Connect Phone to CM4 WiFi

- WiFi Network: **CM4-ThirdEye**
- Password: **thirdeye123**

### 2. Launch Third Eye App

1. Open the Third Eye Flutter app
2. When prompted for camera source, select **"CM4 Triple Camera (192.168.50.1)"**
3. Wait for connection (~2-5 seconds)

### 3. Using Triple Camera

- You'll see 3 vertical camera feeds:
  - **Top**: Left camera
  - **Middle**: Right camera
  - **Bottom**: Eye camera

- **Tap any feed to select it** (green border indicates selected)
- Capture buttons use the selected camera
- FPS is displayed on each feed

### 4. Testing Features

- **Describe Image**: Tap camera button (or Volume Up on Bluetooth clicker)
- **Extract Text**: Tap text button (or Volume Down)
- **Face Recognition**: Tap face button

---

## Troubleshooting

### WiFi Hotspot Issues

**Problem: CM4-ThirdEye network not visible**

```bash
# Check hostapd status
sudo systemctl status hostapd

# Check hostapd logs
sudo journalctl -u hostapd -n 50

# Verify configuration
sudo hostapd -dd /etc/hostapd/hostapd.conf
```

**Problem: Can't connect to WiFi**

- Verify password is correct (thirdeye123)
- Check if 5GHz is supported on your device
- Try changing channel in `hostapd.conf` (36, 40, 44, 48)

### Camera Issues

**Problem: Camera not detected**

```bash
# Check camera cable connections
# Verify camera is enabled
sudo raspi-config
# Interface Options → Camera → Enable

# Check for camera devices
vcgencmd get_camera

# List cameras
libcamera-hello --list-cameras
```

**Problem: Camera server crashes**

```bash
# Check logs
sudo journalctl -u cm4-camera.service -n 100

# Test manually
python3 ~/camera_server.py
```

**Problem: Low FPS**

- Check CPU usage: `htop`
- Reduce resolution in `camera_server.py` (change RESOLUTION)
- Reduce JPEG quality (change JPEG_QUALITY from 80 to 60)
- Close other programs

### Streaming Issues

**Problem: Streams lag or buffer**

- Move closer to CM4
- Reduce number of active streams
- Check WiFi signal strength
- Restart camera server: `sudo systemctl restart cm4-camera.service`

**Problem: Can't connect from app**

- Verify phone is connected to **CM4-ThirdEye** WiFi
- Ping CM4: `ping 192.168.50.1`
- Check if ports are accessible: `curl http://192.168.50.1:8081/health`
- Check firewall: `sudo ufw status` (should be inactive or allow ports 8081-8083)

---

## Performance Tuning

### Optimize for Battery Life (CM4)

Reduce resolution and FPS in `camera_server.py`:

```python
RESOLUTION = (1280, 720)  # 720p instead of 1080p
TARGET_FPS = 5            # Lower FPS
JPEG_QUALITY = 60         # Lower quality
```

### Optimize for Quality

```python
RESOLUTION = (1920, 1080)  # Full 1080p
TARGET_FPS = 15            # Higher FPS (if your CM4 can handle it)
JPEG_QUALITY = 85          # Higher quality
```

### Monitor Performance

```bash
# CPU temperature
vcgencmd measure_temp

# CPU frequency
vcgencmd measure_clock arm

# System resources
htop

# Network bandwidth
iftop -i wlan0
```

### Camera-Specific Settings

Edit `camera_server.py` to add custom camera settings:

```python
config = self.picam.create_still_configuration(
    main={"size": RESOLUTION, "format": "RGB888"},
    controls={"Brightness": 0.0, "Contrast": 1.0}  # Adjust as needed
)
```

---

## Quick Reference

### Useful Commands

```bash
# Restart camera server
sudo systemctl restart cm4-camera.service

# View camera server logs
sudo journalctl -u cm4-camera.service -f

# Restart WiFi hotspot
sudo systemctl restart hostapd

# Check connected WiFi clients
arp -a

# Test camera
libcamera-still -t 2000 --camera 0 -o test.jpg

# Monitor system
htop
vcgencmd measure_temp
```

### Default Configuration

- **WiFi SSID**: CM4-ThirdEye
- **WiFi Password**: thirdeye123
- **CM4 IP**: 192.168.50.1
- **Left Camera Stream**: http://192.168.50.1:8081/stream
- **Right Camera Stream**: http://192.168.50.1:8082/stream
- **Eye Camera Stream**: http://192.168.50.1:8083/stream
- **Resolution**: 1920x1080 @ 10fps
- **Adaptive FPS Range**: 10fps → 5fps

---

## Next Steps

1. Configure camera angles and positions for your use case
2. Mount CM4 and cameras on wearable frame/headset
3. Add portable battery pack for mobile use
4. Test in real-world scenarios
5. Fine-tune FPS and quality based on your network conditions

---

## Support

For issues or questions:
- Check the [Troubleshooting](#troubleshooting) section
- Review system logs: `sudo journalctl -u cm4-camera.service`
- Test individual components (WiFi, cameras, streams)
- Verify all cables and connections

---

**Setup Complete!** Your CM4 is now streaming 3 camera feeds to the Third Eye app.
