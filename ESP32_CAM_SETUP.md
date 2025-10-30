# ESP32 CAM Bluetooth Setup Guide

This guide will help you set up your ESP32 CAM module to stream images via Bluetooth to the Third Eye app.

## Hardware Requirements

- ESP32-CAM module (AI Thinker model recommended)
- FTDI programmer or ESP32-CAM-MB (USB programmer board)
- Micro USB cable
- Jumper wires (if using FTDI)

## Software Requirements

- Arduino IDE (version 1.8.x or 2.x)
- ESP32 board support for Arduino

## Step 1: Install Arduino IDE and ESP32 Support

1. Download and install Arduino IDE from https://www.arduino.cc/en/software
2. Open Arduino IDE
3. Go to **File > Preferences**
4. Add this URL to "Additional Board Manager URLs":
   ```
   https://raw.githubusercontent.com/espressif/arduino-esp32/gh-pages/package_esp32_index.json
   ```
5. Go to **Tools > Board > Boards Manager**
6. Search for "esp32" and install "esp32 by Espressif Systems"

## Step 2: Hardware Connection

### Option A: Using ESP32-CAM-MB Programmer Board
1. Insert ESP32-CAM into the MB programmer board
2. Connect via USB to your computer
3. No additional wiring needed

### Option B: Using FTDI Programmer
Connect the following pins:
- ESP32-CAM 5V → FTDI VCC (5V)
- ESP32-CAM GND → FTDI GND
- ESP32-CAM U0R → FTDI TX
- ESP32-CAM U0T → FTDI RX
- ESP32-CAM IO0 → GND (for programming mode)

## Step 3: Upload the Code

1. Open the file `esp32_cam_bluetooth.ino` in Arduino IDE
2. Select the correct board:
   - Go to **Tools > Board > ESP32 Arduino**
   - Select **AI Thinker ESP32-CAM**
3. Select the correct port:
   - Go to **Tools > Port**
   - Select the COM port for your ESP32-CAM
4. Configure board settings:
   - **Upload Speed**: 115200
   - **Flash Frequency**: 80MHz
   - **Flash Mode**: QIO
   - **Partition Scheme**: Huge APP (3MB No OTA/1MB SPIFFS)
5. Click **Upload** button
6. Wait for "Done uploading" message

**Important**: If using FTDI programmer, disconnect IO0 from GND after uploading to run the code.

## Step 4: Pair ESP32 CAM with Your Phone

1. Power on your ESP32-CAM (disconnect IO0 from GND if using FTDI)
2. On your Android phone:
   - Go to **Settings > Bluetooth**
   - Turn on Bluetooth
   - Look for a device named **ESP32_CAM**
   - Tap to pair (PIN is usually 1234 or 0000 if asked)
3. The ESP32-CAM is now paired and ready to use

## Step 5: Using with Third Eye App

1. Run the Third Eye Flutter app
2. The app will automatically show a device selection dialog
3. Select **ESP32_CAM** from the list
4. Wait for connection (green Bluetooth icon will appear)
5. The ESP32 CAM will start streaming at 1 FPS
6. Tap the camera button to capture a snapshot and get AI description

## Bluetooth Commands

The ESP32-CAM accepts the following commands via Bluetooth:

- `START\n` - Start continuous streaming (1 FPS)
- `STOP\n` - Stop streaming
- `SNAPSHOT\n` - Capture and send a single frame

## Troubleshooting

### Camera fails to initialize
- Check that your ESP32-CAM has PSRAM
- Try reducing the frame size in the code (change FRAMESIZE_VGA to FRAMESIZE_QVGA)

### Bluetooth not visible
- Make sure the code uploaded successfully
- Check Serial Monitor (115200 baud) for "Bluetooth started" message
- Reset the ESP32-CAM

### Upload fails
- Make sure IO0 is connected to GND during upload
- Try reducing upload speed to 115200
- Press the reset button on ESP32-CAM right before uploading

### Poor image quality
- Adjust `jpeg_quality` in the code (lower number = better quality, 10-63 range)
- Change frame size (QVGA, VGA, SVGA, etc.)
- Ensure good lighting conditions

### Slow streaming
- Default is 1 FPS (1000ms). You can modify `FRAME_INTERVAL` in the code
- Note: Bluetooth SPP has limited bandwidth (~100 KB/s)
- Smaller frame sizes and lower quality will stream faster

## Camera Frame Sizes

Available frame sizes (edit in code):
- `FRAMESIZE_QQVGA` - 160x120
- `FRAMESIZE_QVGA` - 320x240
- `FRAMESIZE_VGA` - 640x480 (default)
- `FRAMESIZE_SVGA` - 800x600
- `FRAMESIZE_XGA` - 1024x768
- `FRAMESIZE_SXGA` - 1280x1024

## Power Requirements

- ESP32-CAM requires stable 5V power supply
- USB power is usually sufficient
- For portable use, consider a power bank or battery pack
- Current draw: ~200-300mA during operation

## Notes

- The ESP32-CAM Bluetooth name is **ESP32_CAM** (can be changed in code)
- Streaming is at 1 FPS by default to maintain stable Bluetooth connection
- JPEG compression is used to reduce data size
- The app automatically handles image buffering and display
