# CM4 Camera Server

Python MJPEG streaming server for Raspberry Pi CM4 with 3 camera feeds.

## Quick Start

### On CM4:

```bash
# Install dependencies
sudo apt install -y python3-pip python3-picamera2 python3-flask
pip3 install flask pillow --break-system-packages

# Copy this file to CM4
scp camera_server.py pi@192.168.50.1:~/

# Run server
python3 ~/camera_server.py
```

### Test Streams:

```
http://192.168.50.1:8081/stream  (Left camera)
http://192.168.50.1:8082/stream  (Right camera)
http://192.168.50.1:8083/stream  (Eye camera)
```

## Configuration

Edit `camera_server.py` to change:

- **Resolution**: `RESOLUTION = (1920, 1080)` (default: 1080p)
- **FPS**: `TARGET_FPS = 10` (default: 10fps, adaptive down to 5fps)
- **Quality**: `JPEG_QUALITY = 80` (0-100, higher = better quality)
- **Camera Indices**: Modify `CAMERAS` dict to match your setup

## Features

- **3 simultaneous MJPEG streams** on ports 8081, 8082, 8083
- **Adaptive frame rate**: Automatically reduces from 10fps to 5fps under load
- **1080p @ 10fps** by default
- **Multi-threaded**: Separate thread per camera for smooth performance
- **Graceful degradation**: Shows placeholder if camera unavailable
- **Stats endpoint**: `/stats` on each port for monitoring

## Auto-Start Service

See [CM4_SETUP_GUIDE.md](../docs/CM4_SETUP_GUIDE.md) for complete systemd service setup.

Quick version:

```bash
sudo nano /etc/systemd/system/cm4-camera.service
# Paste service configuration
sudo systemctl enable cm4-camera.service
sudo systemctl start cm4-camera.service
```

## Troubleshooting

**No cameras detected:**
```bash
libcamera-hello --list-cameras
sudo raspi-config  # Enable camera interface
```

**Low FPS:**
- Reduce resolution to 720p
- Lower JPEG_QUALITY to 60
- Close other programs

**Connection issues:**
- Verify CM4 WiFi hotspot is running
- Check IP is 192.168.50.1: `ip addr show wlan0`
- Test with: `curl http://192.168.50.1:8081/health`

## Full Documentation

See [docs/CM4_SETUP_GUIDE.md](../docs/CM4_SETUP_GUIDE.md) for complete setup instructions.
