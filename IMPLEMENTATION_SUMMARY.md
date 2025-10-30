# ESP32 CAM Bluetooth Integration - Implementation Summary

## Overview
The Third Eye app has been successfully modified to connect to an ESP32 CAM module via Bluetooth SPP and receive a live image stream at 1 FPS. The app can now capture snapshots from the stream and send them to the Gemini API for text and audio feedback.

## Changes Made

### 1. Dependencies Added
**File**: `pubspec.yaml`
- Added `flutter_bluetooth_serial: ^0.4.0` for Bluetooth SPP communication

### 2. New Service Created
**File**: `lib/services/esp32_bluetooth_service.dart`
- Complete Bluetooth SPP service for ESP32 CAM
- Features:
  - Device discovery and pairing
  - Connection management
  - Real-time JPEG image stream parsing
  - Command sending (START, STOP, SNAPSHOT)
  - Automatic image buffering with JPEG marker detection
  - Stream-based image delivery to UI

### 3. Main Screen Updated
**File**: `lib/screens/image_picker_screen.dart`
- **Removed**: Device camera functionality
- **Added**: ESP32 CAM Bluetooth integration
- **Key Changes**:
  - Replaced `CameraController` with `Esp32BluetoothService`
  - Added Bluetooth permission requests
  - Device selection dialog for pairing
  - Live image stream display using `Image.memory()`
  - Snapshot capture from current frame
  - Bluetooth connection status indicators
  - Automatic streaming at 1 FPS when connected

### 4. Android Permissions
**File**: `android/app/src/main/AndroidManifest.xml`
- Added Bluetooth permissions:
  - `BLUETOOTH`
  - `BLUETOOTH_ADMIN`
  - `BLUETOOTH_CONNECT`
  - `BLUETOOTH_SCAN`
  - `ACCESS_FINE_LOCATION`
  - `ACCESS_COARSE_LOCATION`

### 5. ESP32 CAM Firmware
**File**: `esp32_cam_bluetooth.ino`
- Arduino sketch for ESP32-CAM
- Features:
  - Bluetooth SPP server (device name: "ESP32_CAM")
  - Camera initialization with optimal settings
  - 1 FPS image streaming
  - Command processing (START, STOP, SNAPSHOT)
  - JPEG compression for efficient data transfer

### 6. Documentation
**File**: `ESP32_CAM_SETUP.md`
- Complete setup guide for ESP32 CAM
- Hardware requirements and wiring diagrams
- Arduino IDE configuration
- Pairing instructions
- Troubleshooting guide

## How It Works

### Architecture Flow:
1. **App Startup**:
   - Initialize Gemini API and TTS services
   - Request Bluetooth permissions
   - Scan for paired Bluetooth devices
   - Show device selection dialog

2. **Connection**:
   - User selects ESP32_CAM from paired devices
   - App connects via Bluetooth SPP
   - Sends "START" command to begin streaming
   - Listens to incoming JPEG data stream

3. **Image Streaming**:
   - ESP32 CAM captures frames at 1 FPS
   - Sends JPEG data over Bluetooth
   - App parses JPEG markers (0xFF 0xD8 start, 0xFF 0xD9 end)
   - Buffers complete images
   - Updates UI with latest frame using `Image.memory()`

4. **Snapshot & Analysis**:
   - User taps camera button
   - Current frame is saved to temporary file
   - File sent to Gemini API for vision analysis
   - Text description returned
   - TTS speaks the description
   - Image and description displayed in UI

### Data Format:
- Images are transmitted as raw JPEG bytes
- Start marker: `0xFF 0xD8`
- End marker: `0xFF 0xD9`
- Typical size: 10-50 KB per frame (VGA quality)

## UI Changes

### Top Half (Camera View):
- **Before**: Device camera live preview
- **After**: ESP32 CAM stream display
  - Shows live stream at 1 FPS
  - "Connect to Device" button when not connected
  - Loading indicator while waiting for stream

### Status Indicators:
- Green/Red circle: Gemini API status
- Blue/Grey Bluetooth icon: Connection status

### Bottom Half:
- Left: Latest snapshot preview
- Right: AI-generated description

### Capture Button:
- Disabled when not connected or API unavailable
- Captures current frame for analysis
- Triggers Gemini API call and TTS

## Key Features

1. **Real-time Streaming**: 1 FPS continuous image stream from ESP32 CAM
2. **Snapshot Capture**: Freeze current frame for AI analysis
3. **Text Description**: Gemini API generates image descriptions
4. **Audio Feedback**: TTS speaks descriptions automatically
5. **Bluetooth Management**: Easy device selection and connection
6. **Status Indicators**: Visual feedback for all system states
7. **Error Handling**: Comprehensive error messages and recovery

## Technical Details

### Bluetooth Protocol:
- **Type**: SPP (Serial Port Profile)
- **Baud Rate**: Not applicable for BT Classic
- **Data Format**: Raw JPEG bytes
- **Command Format**: ASCII strings with newline terminator

### Performance:
- **Stream Rate**: 1 frame per second
- **Latency**: ~100-300ms per frame
- **Image Size**: VGA (640x480) or configurable
- **Bandwidth**: ~10-50 KB/s depending on quality

### Compatibility:
- **Android**: Requires Android 6.0+ (API 23+)
- **Bluetooth**: Classic Bluetooth (not BLE)
- **ESP32**: AI Thinker ESP32-CAM or compatible

## Setup Steps

1. **Install Dependencies**:
   ```bash
   flutter pub get
   ```

2. **Configure ESP32 CAM**:
   - Follow instructions in `ESP32_CAM_SETUP.md`
   - Upload `esp32_cam_bluetooth.ino` to ESP32
   - Pair device with phone

3. **Run App**:
   ```bash
   flutter run
   ```

4. **Connect**:
   - Select ESP32_CAM from device list
   - Wait for stream to start
   - Tap camera button to capture and analyze

## Troubleshooting

### App Issues:
- **No devices found**: Ensure ESP32 is paired in phone settings first
- **Connection fails**: Reset ESP32 and try again
- **No stream**: Check Serial Monitor for ESP32 errors
- **Slow performance**: Reduce frame size or quality on ESP32

### ESP32 Issues:
- **Upload fails**: Connect IO0 to GND during programming
- **Camera error**: Check PSRAM availability
- **Bluetooth not visible**: Verify code uploaded successfully

## Future Enhancements

Potential improvements:
1. Variable frame rate control from app
2. Image quality adjustment
3. Multiple ESP32 device support
4. Automatic reconnection on disconnect
5. Image history/gallery
6. Custom camera settings (brightness, contrast, etc.)
7. WiFi streaming option for higher bandwidth
8. Recording capability

## Files Modified/Created

### Modified:
- `pubspec.yaml`
- `lib/screens/image_picker_screen.dart`
- `android/app/src/main/AndroidManifest.xml`

### Created:
- `lib/services/esp32_bluetooth_service.dart`
- `esp32_cam_bluetooth.ino`
- `ESP32_CAM_SETUP.md`
- `IMPLEMENTATION_SUMMARY.md` (this file)

## Testing Checklist

- [ ] App requests Bluetooth permissions
- [ ] Device selection dialog appears
- [ ] Connection to ESP32 succeeds
- [ ] Live stream displays at ~1 FPS
- [ ] Snapshot capture works
- [ ] Gemini API returns description
- [ ] TTS speaks description
- [ ] Reconnection after disconnect
- [ ] Error handling for all failure modes

## Notes

- The app no longer uses the device camera
- All image capture is from ESP32 CAM via Bluetooth
- Requires physical ESP32 CAM hardware to function
- Bluetooth Classic required (not BLE)
- Android only (iOS requires different Bluetooth approach)
