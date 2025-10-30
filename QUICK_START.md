# Quick Start Guide - Third Eye ESP32 CAM

This is a quick reference for getting your Third Eye app working with ESP32 CAM.

## Prerequisites Checklist

- [ ] ESP32-CAM module (AI Thinker)
- [ ] USB programmer (ESP32-CAM-MB or FTDI)
- [ ] Arduino IDE installed
- [ ] ESP32 board support added to Arduino
- [ ] Android phone with Bluetooth
- [ ] Gemini API key in `.env` file

## 5-Minute Setup

### 1. Flash ESP32 CAM (5 minutes)
```
1. Open esp32_cam_bluetooth.ino in Arduino IDE
2. Select Board: AI Thinker ESP32-CAM
3. Select correct COM port
4. Click Upload
5. Wait for "Done uploading"
```

### 2. Pair Device (1 minute)
```
1. Power on ESP32-CAM
2. Phone Settings → Bluetooth
3. Find "ESP32_CAM"
4. Tap to pair (PIN: 1234 or 0000)
```

### 3. Install Flutter App (2 minutes)
```bash
cd third_eye
flutter pub get
flutter run
```

### 4. Connect & Use (30 seconds)
```
1. App shows device selection
2. Select "ESP32_CAM"
3. Wait for green checkmark
4. Tap camera button to analyze
```

## Troubleshooting (30 seconds each)

| Problem | Solution |
|---------|----------|
| Can't upload to ESP32 | Connect IO0 to GND |
| No Bluetooth device | Check ESP32 powered on |
| Connection fails | Reset ESP32 |
| No stream | Wait 5 seconds, check BT icon |
| Poor quality | Change `jpeg_quality = 10` in .ino |

## App Controls

**Status Icons (Top Right):**
- 🟢 Green circle = API ready
- 🔴 Red circle = API failed
- 🔵 Bluetooth icon = Connected
- ⚪ Gray icon = Disconnected

**Main Button:**
- Camera icon = Capture snapshot for AI analysis
- Disabled when not connected

**Screens:**
- Top half = Live stream (1 FPS)
- Bottom left = Last snapshot
- Bottom right = AI description

## ESP32 Commands

The ESP32 accepts these commands via Bluetooth:
- `START` - Begin streaming
- `STOP` - Stop streaming
- `SNAPSHOT` - Take single photo

## Key Settings

**Frame Rate:** 1 FPS (1000ms in .ino file)
**Image Size:** VGA (640x480)
**Quality:** 10 (lower = better)

To change:
```cpp
// In esp32_cam_bluetooth.ino
const unsigned long FRAME_INTERVAL = 1000; // Change to 500 for 2 FPS
config.frame_size = FRAMESIZE_VGA;          // Change to FRAMESIZE_QVGA for smaller
config.jpeg_quality = 10;                   // Change to 15 for faster, lower quality
```

## File Structure

```
third_eye/
├── lib/
│   ├── services/
│   │   └── esp32_bluetooth_service.dart  ← Bluetooth handler
│   └── screens/
│       └── image_picker_screen.dart      ← Main UI
├── esp32_cam_bluetooth.ino               ← ESP32 code
├── ESP32_CAM_SETUP.md                    ← Detailed setup
└── IMPLEMENTATION_SUMMARY.md             ← Technical docs
```

## Next Steps

1. Test basic connection
2. Verify 1 FPS stream
3. Test snapshot capture
4. Try different lighting
5. Adjust settings as needed

## Support

**Detailed Setup:** See `ESP32_CAM_SETUP.md`
**Technical Details:** See `IMPLEMENTATION_SUMMARY.md`
**ESP32 Issues:** Check Serial Monitor at 115200 baud

---

**That's it! You should now have a working Third Eye vision assistant with ESP32 CAM streaming.**
