import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:camera/camera.dart';
import '../services/llama_service.dart';
import '../services/tts_service.dart';
import '../services/esp32_bluetooth_service.dart';
import '../services/hardware_key_service.dart';

class ImagePickerScreen extends StatefulWidget {
  const ImagePickerScreen({super.key});

  @override
  State<ImagePickerScreen> createState() => _ImagePickerScreenState();
}

class _ImagePickerScreenState extends State<ImagePickerScreen> {
  final LlamaService _llamaService = LlamaService();
  final TtsService _ttsService = TtsService();
  final Esp32BluetoothService _bluetoothService = Esp32BluetoothService();
  final HardwareKeyService _hardwareKeyService = HardwareKeyService();

  Uint8List? _currentFrame;
  Uint8List? _snapshotImage;
  File? _capturedImage;
  String _description = '';
  bool _isLoading = false;
  bool _serverAvailable = false;
  bool _isInitializing = false;
  bool _isConnectedToBluetooth = false;
  bool _hardwareKeysActive = false;
  List<BluetoothDevice> _pairedDevices = [];

  // Phone camera fallback
  CameraController? _cameraController;
  bool _usePhoneCamera = false;
  List<CameraDescription>? _cameras;

  @override
  void initState() {
    super.initState();
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    setState(() {
      _isInitializing = true;
    });

    try {
      // Request camera permissions
      final cameraPermission = await Permission.camera.request();
      print('Camera permission: $cameraPermission');

      // Request Bluetooth permissions for Android 12+ (API 31+)
      if (Platform.isAndroid) {
        final btPermission = await Permission.bluetooth.request();
        final btConnectPermission = await Permission.bluetoothConnect.request();
        final btScanPermission = await Permission.bluetoothScan.request();

        print('Bluetooth permission: $btPermission');
        print('Bluetooth Connect permission: $btConnectPermission');
        print('Bluetooth Scan permission: $btScanPermission');

        // Check if all required Bluetooth permissions are granted
        if (!btConnectPermission.isGranted) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Bluetooth Connect permission is required to connect to devices'),
                duration: Duration(seconds: 5),
                backgroundColor: Colors.orange,
              ),
            );
          }
        }
      }

      // Initialize Gemini API and TTS
      final success = await _llamaService.initialize();
      await _ttsService.initialize();

      // Get available cameras
      _cameras = await availableCameras();

      // Check if Bluetooth is enabled
      final btEnabled = await _bluetoothService.isBluetoothEnabled();
      if (!btEnabled) {
        final enabled = await _bluetoothService.requestEnableBluetooth();
        if (!enabled && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Bluetooth must be enabled to connect to devices'),
              duration: Duration(seconds: 5),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }

      // Get paired devices - only after permissions are granted
      _pairedDevices = await _bluetoothService.getPairedDevices();
      print('Found ${_pairedDevices.length} paired Bluetooth devices');

      // Setup hardware key listener for Bluetooth clickers and volume buttons
      _setupHardwareKeyListener();

      if (mounted) {
        setState(() {
          _isInitializing = false;
          _serverAvailable = success;
        });

        if (!success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to initialize: Check your API key in .env'),
              duration: Duration(seconds: 5),
              backgroundColor: Colors.red,
            ),
          );
        }

        // Show dialog to select ESP32 device or use phone camera
        if (_pairedDevices.isNotEmpty) {
          _showCameraSourceDialog();
        } else {
          // No Bluetooth devices, fallback to phone camera
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No Bluetooth devices found. Using phone camera.'),
              duration: Duration(seconds: 3),
              backgroundColor: Colors.blue,
            ),
          );
          await _initializePhoneCamera();
        }
      }
    } catch (e) {
      setState(() {
        _isInitializing = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Initialization failed: $e'),
            duration: const Duration(seconds: 5),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Setup listener for hardware key presses (volume buttons from Bluetooth clicker)
  void _setupHardwareKeyListener() {
    // Start listening to hardware keys
    _hardwareKeyService.startListening();

    setState(() {
      _hardwareKeysActive = _hardwareKeyService.isListening;
    });

    // Listen to key events
    _hardwareKeyService.keyStream.listen((event) {
      print('Hardware key pressed: ${event.keyType}');

      // Trigger capture on any key press if camera is available
      if (!_isLoading && _serverAvailable && (_isConnectedToBluetooth || _usePhoneCamera)) {
        // Volume Up: Describe image
        if (event.keyType == HardwareKeyType.volumeUp) {
          _captureAndDescribe();
        }
        // Volume Down: Extract text
        else if (event.keyType == HardwareKeyType.volumeDown) {
          _captureAndExtractText();
        }
        // Other buttons: Default to describe
        else {
          _captureAndDescribe();
        }
      }
    });
  }

  Future<void> _showCameraSourceDialog() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Camera Source'),
        content: const Text('Choose which camera to use:'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'bluetooth'),
            child: const Text('ESP32 Bluetooth Camera'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'phone'),
            child: const Text('Phone Camera'),
          ),
        ],
      ),
    );

    if (choice == 'bluetooth') {
      _showDeviceSelectionDialog();
    } else if (choice == 'phone') {
      await _initializePhoneCamera();
    }
  }

  Future<void> _initializePhoneCamera() async {
    if (_cameras == null || _cameras!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No cameras found on device'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Find back camera
    final backCamera = _cameras!.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.back,
      orElse: () => _cameras!.first,
    );

    _cameraController = CameraController(
      backCamera,
      ResolutionPreset.high,
      enableAudio: false,
    );

    try {
      await _cameraController!.initialize();
      if (mounted) {
        setState(() {
          _usePhoneCamera = true;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to initialize phone camera: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _showDeviceSelectionDialog() async {
    final device = await showDialog<BluetoothDevice>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select ESP32 CAM'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _pairedDevices.length,
            itemBuilder: (context, index) {
              final device = _pairedDevices[index];
              return ListTile(
                title: Text(device.name ?? 'Unknown Device'),
                subtitle: Text(device.address),
                onTap: () => Navigator.pop(context, device),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (device != null) {
      await _connectToDevice(device);
    }
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    setState(() {
      _isLoading = true;
    });

    final success = await _bluetoothService.connect(device.address);

    if (success) {
      // Listen to image stream
      _bluetoothService.imageStream.listen((imageData) {
        if (mounted) {
          setState(() {
            _currentFrame = imageData;
          });
        }
      });

      // Start streaming
      await _bluetoothService.startStreaming();

      if (mounted) {
        setState(() {
          _isConnectedToBluetooth = true;
          _isLoading = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connected to ${device.name}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } else {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to connect to ESP32 CAM'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }


  Future<void> _captureAndDescribe() async {
    File? imageFile;

    // Capture from phone camera
    if (_usePhoneCamera && _cameraController != null && _cameraController!.value.isInitialized) {
      try {
        setState(() {
          _isLoading = true;
          _description = '';
        });

        final XFile image = await _cameraController!.takePicture();
        imageFile = File(image.path);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to capture from phone camera: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
        setState(() {
          _isLoading = false;
        });
        return;
      }
    }
    // Capture from Bluetooth camera
    else if (_isConnectedToBluetooth && _currentFrame != null) {
      try {
        setState(() {
          _isLoading = true;
          _description = '';
          _snapshotImage = _currentFrame;
        });

        // Save current frame to a temporary file
        final tempDir = await getTemporaryDirectory();
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final tempFile = File('${tempDir.path}/snapshot_$timestamp.jpg');
        await tempFile.writeAsBytes(_currentFrame!);
        imageFile = tempFile;
      } catch (e) {
        setState(() {
          _description = 'Error: $e';
          _isLoading = false;
        });
        return;
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No camera available'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    try {
      setState(() {
        _capturedImage = imageFile;
      });

      // Get description from LLM
      final response = await _llamaService.describeImage(imageFile.path);

      setState(() {
        if (response.success) {
          _description = response.content;
          // Speak the description immediately
          _ttsService.speak(_description);
        } else {
          _description = 'Error: ${response.error}';
        }
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _description = 'Error: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _captureAndExtractText() async {
    File? imageFile;

    // Capture from phone camera
    if (_usePhoneCamera && _cameraController != null && _cameraController!.value.isInitialized) {
      try {
        setState(() {
          _isLoading = true;
          _description = '';
        });

        final XFile image = await _cameraController!.takePicture();
        imageFile = File(image.path);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to capture from phone camera: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
        setState(() {
          _isLoading = false;
        });
        return;
      }
    }
    // Capture from Bluetooth camera
    else if (_isConnectedToBluetooth && _currentFrame != null) {
      try {
        setState(() {
          _isLoading = true;
          _description = '';
          _snapshotImage = _currentFrame;
        });

        // Save current frame to a temporary file
        final tempDir = await getTemporaryDirectory();
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final tempFile = File('${tempDir.path}/snapshot_$timestamp.jpg');
        await tempFile.writeAsBytes(_currentFrame!);
        imageFile = tempFile;
      } catch (e) {
        setState(() {
          _description = 'Error: $e';
          _isLoading = false;
        });
        return;
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No camera available'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    try {
      setState(() {
        _capturedImage = imageFile;
      });

      // Extract text from LLM
      final response = await _llamaService.extractText(imageFile.path);

      setState(() {
        if (response.success) {
          _description = response.content;
          // Speak the extracted text immediately
          _ttsService.speak(_description);
        } else {
          _description = 'Error: ${response.error}';
        }
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _description = 'Error: $e';
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _bluetoothService.dispose();
    _hardwareKeyService.dispose();
    _llamaService.dispose();
    _ttsService.dispose();
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _isInitializing
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 16),
                  Text(
                    'Initializing camera...',
                    style: TextStyle(color: Colors.white),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                // Top half: Camera preview with capture button
                Expanded(
                  flex: 1,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Phone camera preview
                      if (_usePhoneCamera && _cameraController != null && _cameraController!.value.isInitialized)
                        Center(
                          child: CameraPreview(_cameraController!),
                        )
                      // ESP32 CAM stream preview
                      else if (_isConnectedToBluetooth && _currentFrame != null)
                        Center(
                          child: Image.memory(
                            _currentFrame!,
                            fit: BoxFit.contain,
                            gaplessPlayback: true,
                          ),
                        )
                      else if (_isConnectedToBluetooth)
                        const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CircularProgressIndicator(color: Colors.white),
                              SizedBox(height: 16),
                              Text(
                                'Waiting for ESP32 CAM stream...',
                                style: TextStyle(color: Colors.white),
                              ),
                            ],
                          ),
                        )
                      else if (_usePhoneCamera)
                        const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CircularProgressIndicator(color: Colors.white),
                              SizedBox(height: 16),
                              Text(
                                'Initializing phone camera...',
                                style: TextStyle(color: Colors.white),
                              ),
                            ],
                          ),
                        )
                      else
                        Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.camera_alt,
                                color: Colors.white,
                                size: 64,
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'No camera connected',
                                style: TextStyle(color: Colors.white),
                              ),
                              const SizedBox(height: 8),
                              ElevatedButton(
                                onPressed: () => _pairedDevices.isNotEmpty
                                    ? _showCameraSourceDialog()
                                    : _initializePhoneCamera(),
                                child: Text(_pairedDevices.isNotEmpty
                                    ? 'Select Camera'
                                    : 'Use Phone Camera'),
                              ),
                            ],
                          ),
                        ),

                      // Status indicators (top right)
                      Positioned(
                        top: 40,
                        right: 16,
                        child: Column(
                          children: [
                            Icon(
                              _serverAvailable ? Icons.check_circle : Icons.error,
                              color: _serverAvailable ? Colors.green : Colors.red,
                              size: 32,
                            ),
                            const SizedBox(height: 8),
                            Icon(
                              _isConnectedToBluetooth
                                  ? Icons.bluetooth_connected
                                  : _usePhoneCamera
                                      ? Icons.camera
                                      : Icons.bluetooth_disabled,
                              color: _isConnectedToBluetooth
                                  ? Colors.blue
                                  : _usePhoneCamera
                                      ? Colors.green
                                      : Colors.grey,
                              size: 32,
                            ),
                          ],
                        ),
                      ),

                      // Hardware key status indicator (top left)
                      Positioned(
                        top: 40,
                        left: 16,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.5),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            children: [
                              Icon(
                                _hardwareKeysActive ? Icons.keyboard : Icons.keyboard_outlined,
                                color: _hardwareKeysActive ? Colors.green : Colors.grey,
                                size: 32,
                              ),
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  _hardwareKeysActive ? 'Clicker\nReady' : 'No Clicker',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Capture buttons (bottom center)
                      Positioned(
                        bottom: 20,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              // Describe button
                              FloatingActionButton(
                                onPressed: _isLoading || !_serverAvailable ||
                                        (!_isConnectedToBluetooth && !_usePhoneCamera)
                                    ? null
                                    : _captureAndDescribe,
                                backgroundColor: _serverAvailable &&
                                        (_isConnectedToBluetooth || _usePhoneCamera)
                                    ? Colors.white
                                    : Colors.grey,
                                child: const Icon(
                                  Icons.camera_alt,
                                  color: Colors.black,
                                  size: 32,
                                ),
                              ),
                              const SizedBox(width: 16),
                              // Extract text button
                              FloatingActionButton(
                                onPressed: _isLoading || !_serverAvailable ||
                                        (!_isConnectedToBluetooth && !_usePhoneCamera)
                                    ? null
                                    : _captureAndExtractText,
                                backgroundColor: _serverAvailable &&
                                        (_isConnectedToBluetooth || _usePhoneCamera)
                                    ? Colors.white
                                    : Colors.grey,
                                child: const Icon(
                                  Icons.text_fields,
                                  color: Colors.black,
                                  size: 32,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Bottom half: Image preview (left) and description (right)
                Expanded(
                  flex: 1,
                  child: Container(
                    color: Colors.grey[900],
                    child: Row(
                      children: [
                        // Left: Image preview
                        Expanded(
                          flex: 1,
                          child: Container(
                            padding: const EdgeInsets.all(8.0),
                            child: _capturedImage != null
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.file(
                                      _capturedImage!,
                                      fit: BoxFit.contain,
                                    ),
                                  )
                                : Center(
                                    child: Icon(
                                      Icons.image_outlined,
                                      size: 64,
                                      color: Colors.grey[700],
                                    ),
                                  ),
                          ),
                        ),

                        // Right: Description
                        Expanded(
                          flex: 1,
                          child: Container(
                            padding: const EdgeInsets.all(16.0),
                            child: _isLoading
                                ? const Center(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        CircularProgressIndicator(
                                            color: Colors.white),
                                        SizedBox(height: 16),
                                        Text(
                                          'Analyzing...',
                                          style: TextStyle(color: Colors.white),
                                        ),
                                      ],
                                    ),
                                  )
                                : _description.isNotEmpty
                                    ? SingleChildScrollView(
                                        child: Text(
                                          _description,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 14,
                                          ),
                                        ),
                                      )
                                    : Center(
                                        child: Text(
                                          'Tap the button to capture',
                                          style: TextStyle(
                                            color: Colors.grey[600],
                                            fontSize: 14,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
