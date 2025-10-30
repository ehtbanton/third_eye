# Bluetooth Clicker Integration Guide

## Overview
This guide explains how to use a Bluetooth clicker (remote shutter button) with the Third Eye application to take pictures hands-free and send them to the Gemini API for image analysis.

## Features
- Connect any Bluetooth clicker to your Android phone
- Take pictures hands-free by pressing the clicker button
- Automatically sends captured images to Gemini API for description
- Works with both ESP32 CAM (via Bluetooth) and phone's built-in camera
- Supports multiple clicker types and button protocols

## Setup Instructions

### 1. Pair Your Bluetooth Clicker
Before using the clicker with the app, you need to pair it with your phone:

1. Turn on your Bluetooth clicker (usually by pressing and holding the power/pairing button)
2. On your Android phone:
   - Go to **Settings** → **Bluetooth**
   - Turn on Bluetooth if it's not already on
   - Look for your clicker in the list of available devices (common names: "AB Shutter", "Bluetooth Remote", "BT Shutter", etc.)
   - Tap on the device name to pair
   - If prompted for a PIN, try: `0000`, `1234`, or `1111`
3. Wait for the pairing to complete (you should see "Paired" or "Connected")

### 2. Launch Third Eye App
1. Open the Third Eye application
2. Grant Bluetooth permissions if prompted
3. Select your camera source (ESP32 CAM or Phone Camera)

### 3. Connect Bluetooth Clicker
1. Look for the clicker button in the **top-left corner** of the camera view
2. Tap the gamepad icon that says "Connect Clicker"
3. Select your paired clicker from the list of Bluetooth devices
4. Wait for the connection to complete (the icon will turn green)

### 4. Take Pictures with Clicker
1. Point your camera at the subject
2. Press any button on your Bluetooth clicker
3. The app will automatically:
   - Capture the current frame/photo
   - Send it to Gemini API for analysis
   - Speak the description aloud via text-to-speech
   - Display the captured image and description on screen

## Supported Clicker Types

The app supports various Bluetooth clicker protocols:

### Common Bluetooth Clickers
- **Android Camera Shutter Buttons** (e.g., AB Shutter3, Bluetooth Camera Remote)
- **Volume Button Controllers** (sends volume up/down signals)
- **Presentation Remotes** (PowerPoint clickers that send space/enter keys)
- **Generic Bluetooth HID devices** (keyboards, game controllers)

### Button Mappings
By default, any button press triggers the "Describe Image" function. You can customize this behavior in the code:

```dart
// In image_picker_screen.dart, _setupClickerListener() method
if (event.buttonType == ButtonType.volumeUp) {
  _captureAndDescribe();  // Describe the image
} else if (event.buttonType == ButtonType.volumeDown) {
  _captureAndExtractText();  // Extract text from image
}
```

## Troubleshooting

### Clicker Not Appearing in List
- Make sure your clicker is paired in Android Settings → Bluetooth
- Ensure Bluetooth permissions are granted to the app
- Try restarting the app
- Verify your clicker is powered on

### Clicker Connects But Doesn't Trigger Capture
- Check that your camera is connected (ESP32 CAM or phone camera)
- Verify the Gemini API is initialized (green checkmark in top-right)
- Look for button press logs in the console
- Try different buttons on your clicker

### Custom Clicker Not Working
Your clicker might use a different protocol. To add support:

1. Connect the clicker via Bluetooth
2. Check the console logs when pressing buttons
3. Note the byte codes being received
4. Update `bluetooth_clicker_service.dart` in the `_detectButtonPress()` method:

```dart
// Add your custom byte code
if (byte == 0xYOUR_CODE) {
  return ClickerEvent(buttonType: ButtonType.primary, timestamp: DateTime.now());
}
```

### Multiple Clickers
The app currently supports one clicker at a time. To switch clickers:
1. Tap the clicker button (top-left) to disconnect
2. Select a different paired device from the list

## Technical Details

### Architecture
- **BluetoothClickerService**: Manages Bluetooth connection and button event detection
- **ImagePickerScreen**: Listens to clicker events and triggers image capture
- **ESP32BluetoothService**: Handles ESP32 CAM image streaming (independent connection)

### Multiple Bluetooth Connections
The app can maintain two simultaneous Bluetooth connections:
1. **ESP32 CAM** - Streams live video feed over Bluetooth
2. **Bluetooth Clicker** - Receives button press events

This is possible because Flutter Bluetooth Serial supports multiple independent connections.

### Button Detection Protocols
The clicker service detects various protocols:
- Single-byte commands (0x01, 0x81)
- Android media buttons (Volume Up: 0xE9, Volume Down: 0xEA)
- HID camera shutter (0x58, 0xB1)
- Keyboard codes (Enter: 0x0D, Space: 0x20)
- HID keyboard reports (8-byte format)

## Use Cases

### Accessibility
- Hands-free operation for users with mobility limitations
- Remote triggering for users who mount the camera on their head/glasses

### Vision Assistance
- Blind or low-vision users can trigger image capture by touch (feeling the clicker button)
- Voice feedback provides immediate scene description

### Convenience
- Take photos from a distance
- Avoid camera shake from touching the screen
- Capture images while keeping hands free for other tasks

## Code Locations

Key files modified/created:
- `lib/services/bluetooth_clicker_service.dart` - New clicker service
- `lib/screens/image_picker_screen.dart` - Updated with clicker integration
- `lib/services/esp32_bluetooth_service.dart` - Unchanged (handles ESP32 CAM)

## Future Enhancements

Potential improvements:
- Support multiple actions (describe, extract text, save image) mapped to different buttons
- Add clicker battery status indicator
- Support for clicker LED feedback
- Configurable button mappings via settings UI
- Multi-click gestures (double-click, long-press)

## Credits

Integration developed for the Third Eye vision assistance application.
Uses the `flutter_bluetooth_serial` package for Bluetooth connectivity.
