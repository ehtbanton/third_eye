import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import '../services/llama_service.dart';
import '../services/tts_service.dart';
import '../services/esp32_bluetooth_service.dart';

class ImagePickerScreen extends StatefulWidget {
  const ImagePickerScreen({super.key});

  @override
  State<ImagePickerScreen> createState() => _ImagePickerScreenState();
}

class _ImagePickerScreenState extends State<ImagePickerScreen> {
  final LlamaService _llamaService = LlamaService();
  final TtsService _ttsService = TtsService();
  final Esp32BluetoothService _bluetoothService = Esp32BluetoothService();

  Uint8List? _currentFrame;
  Uint8List? _snapshotImage;
  File? _capturedImage;
  String _description = '';
  bool _isLoading = false;
  bool _serverAvailable = false;
  bool _isInitializing = false;
  bool _isConnectedToBluetooth = false;
  List<BluetoothDevice> _pairedDevices = [];

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
      // Request Bluetooth permissions
      if (Platform.isAndroid) {
        await Permission.bluetooth.request();
        await Permission.bluetoothConnect.request();
        await Permission.bluetoothScan.request();
      }

      // Initialize Gemini API and TTS
      final success = await _llamaService.initialize();
      await _ttsService.initialize();

      // Check if Bluetooth is enabled
      final btEnabled = await _bluetoothService.isBluetoothEnabled();
      if (!btEnabled) {
        await _bluetoothService.requestEnableBluetooth();
      }

      // Get paired devices
      _pairedDevices = await _bluetoothService.getPairedDevices();

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

        // Show dialog to select ESP32 device
        if (_pairedDevices.isNotEmpty) {
          _showDeviceSelectionDialog();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No paired Bluetooth devices found. Please pair your ESP32 CAM first.'),
              duration: Duration(seconds: 5),
              backgroundColor: Colors.orange,
            ),
          );
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
    if (!_isConnectedToBluetooth || _currentFrame == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Not connected to ESP32 CAM or no image available'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

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

      setState(() {
        _capturedImage = tempFile;
      });

      // Get description from LLM
      final response = await _llamaService.describeImage(tempFile.path);

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

  @override
  void dispose() {
    _bluetoothService.dispose();
    _llamaService.dispose();
    _ttsService.dispose();
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
                // Top half: ESP32 CAM stream preview with capture button
                Expanded(
                  flex: 1,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // ESP32 CAM stream preview
                      if (_isConnectedToBluetooth && _currentFrame != null)
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
                      else
                        Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.bluetooth_disabled,
                                color: Colors.white,
                                size: 64,
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'Not connected to ESP32 CAM',
                                style: TextStyle(color: Colors.white),
                              ),
                              const SizedBox(height: 8),
                              ElevatedButton(
                                onPressed: () => _showDeviceSelectionDialog(),
                                child: const Text('Connect to Device'),
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
                              _isConnectedToBluetooth ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                              color: _isConnectedToBluetooth ? Colors.blue : Colors.grey,
                              size: 32,
                            ),
                          ],
                        ),
                      ),

                      // Capture button (bottom center)
                      Positioned(
                        bottom: 20,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: FloatingActionButton(
                            onPressed: _isLoading || !_serverAvailable || !_isConnectedToBluetooth
                                ? null
                                : _captureAndDescribe,
                            backgroundColor: _serverAvailable && _isConnectedToBluetooth
                                ? Colors.white
                                : Colors.grey,
                            child: const Icon(
                              Icons.camera_alt,
                              color: Colors.black,
                              size: 32,
                            ),
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
