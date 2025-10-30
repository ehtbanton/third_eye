import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:camera/camera.dart';
import '../services/llama_service.dart';
import '../services/tts_service.dart';
import '../services/esp32_wifi_service.dart';
import '../services/hardware_key_service.dart';
import '../services/face_recognition_service.dart';

class ImagePickerScreen extends StatefulWidget {
  const ImagePickerScreen({super.key});

  @override
  State<ImagePickerScreen> createState() => _ImagePickerScreenState();
}

class _ImagePickerScreenState extends State<ImagePickerScreen> {
  final LlamaService _llamaService = LlamaService();
  final TtsService _ttsService = TtsService();
  final Esp32WifiService _wifiService = Esp32WifiService();
  final HardwareKeyService _hardwareKeyService = HardwareKeyService();
  final FaceRecognitionService _faceRecognitionService = FaceRecognitionService();

  Uint8List? _currentFrame;
  Uint8List? _snapshotImage;
  File? _capturedImage;
  String _description = '';
  bool _isLoading = false;
  bool _serverAvailable = false;
  bool _isInitializing = false;
  bool _isConnectedToWifi = false;
  bool _hardwareKeysActive = false;
  bool _isDialogOpen = false;

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
      // Initialize face recognition service early
      print('Initializing face recognition service...');
      try {
        await _faceRecognitionService.initialize();
        print('Face recognition service initialized with ${_faceRecognitionService.cachedFaceCount} known faces');
      } catch (e) {
        // Show error but continue - face recognition won't work but other features will
        print('WARNING: Face recognition initialization failed: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Face recognition unavailable: Missing TFLite model. See assets/models/README.md'),
              duration: const Duration(seconds: 8),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }

      // Request camera permissions
      print('Requesting camera permission...');
      final cameraPermission = await Permission.camera.request();
      print('Camera permission status: $cameraPermission');

      if (!cameraPermission.isGranted) {
        print('WARNING: Camera permission not granted');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Camera permission is required to use the camera'),
              duration: Duration(seconds: 5),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }

      // No Bluetooth permissions needed for WiFi connection

      // Initialize Gemini API and TTS
      final success = await _llamaService.initialize();
      await _ttsService.initialize();

      // Get available cameras
      print('Querying available cameras...');
      try {
        _cameras = await availableCameras();
        print('Found ${_cameras?.length ?? 0} cameras:');
        if (_cameras != null) {
          for (var i = 0; i < _cameras!.length; i++) {
            print('  Camera $i: ${_cameras![i].name} (${_cameras![i].lensDirection})');
          }
        }
      } catch (e) {
        print('ERROR: Failed to get available cameras: $e');
        _cameras = null;
      }

      // WiFi doesn't require manual enabling like Bluetooth

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
              content: Text('Failed to initialize Gemini API. Make sure:\n1. Your API key is set in .env\n2. Mobile data is enabled\n3. You have cellular signal'),
              duration: Duration(seconds: 8),
              backgroundColor: Colors.red,
            ),
          );
          _ttsService.speak('Failed to initialize. Please enable mobile data.');
        }

        // Show dialog to select camera source
        _showCameraSourceDialog();
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

    // Listen to key events from AB Shutter 3 Bluetooth clicker
    _hardwareKeyService.keyStream.listen((event) {
      print('=== AB Shutter 3 Button Press Detected ===');
      print('Button type: ${event.keyType}');
      print('Camera available: ${_isConnectedToWifi || _usePhoneCamera}');
      print('Server available: $_serverAvailable');
      print('Is loading: $_isLoading');
      print('Dialog open: $_isDialogOpen');

      // Trigger capture on any key press if camera is available and no dialog is open
      if (!_isLoading && !_isDialogOpen && _serverAvailable && (_isConnectedToWifi || _usePhoneCamera)) {
        // Button 1 (Volume Up): Take photo and describe image
        if (event.keyType == HardwareKeyType.volumeUp) {
          print('✓ Button 1 pressed - Taking photo and describing image');
          _captureAndDescribe();
        }
        // Button 2 (Volume Down): Take photo and extract text (test reading)
        else if (event.keyType == HardwareKeyType.volumeDown) {
          print('✓ Button 2 pressed - Taking photo and extracting text');
          _captureAndExtractText();
        }
        // Other buttons (if any): Face recognition
        else {
          print('✓ Other button pressed - Performing face recognition');
          _captureAndRecognizeFace();
        }
      } else {
        print('⚠ Button press ignored - conditions not met for capture');
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
            onPressed: () => Navigator.pop(context, 'wifi'),
            child: const Text('ESP32-CAM WiFi (192.168.4.1)'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'phone'),
            child: const Text('Phone Camera'),
          ),
        ],
      ),
    );

    if (choice == 'wifi') {
      await _connectToEsp32Wifi();
    } else if (choice == 'phone') {
      await _initializePhoneCamera();
    }
  }

  Future<void> _initializePhoneCamera() async {
    print('=== Phone Camera Initialization Started ===');
    print('Available cameras: ${_cameras?.length ?? 0}');

    if (_cameras == null || _cameras!.isEmpty) {
      final errorMsg = 'No cameras found on device. Camera permission may be denied.';
      print('ERROR: $errorMsg');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMsg),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
        _ttsService.speak('Camera not available. Please check permissions.');
      }
      return;
    }

    // Show loading state
    if (mounted) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      // Find back camera
      final backCamera = _cameras!.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras!.first,
      );

      print('Initializing phone camera: ${backCamera.name}');
      print('Camera direction: ${backCamera.lensDirection}');

      _cameraController = CameraController(
        backCamera,
        ResolutionPreset.high,
        enableAudio: false,
      );

      print('Starting camera controller initialization...');
      await _cameraController!.initialize();

      print('✓ Phone camera initialized successfully');

      if (mounted) {
        setState(() {
          _usePhoneCamera = true;
          _isLoading = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Phone camera ready'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );

        _ttsService.speak('Camera ready');
      }
    } catch (e, stackTrace) {
      print('✗ Failed to initialize phone camera');
      print('Error: $e');
      print('Stack trace: $stackTrace');

      // Provide more specific error messages
      String userMessage = 'Failed to initialize phone camera';
      String spokenMessage = 'Camera initialization failed';

      if (e.toString().contains('permission')) {
        userMessage = 'Camera permission denied. Please grant camera access in settings.';
        spokenMessage = 'Camera permission denied';
      } else if (e.toString().contains('in use')) {
        userMessage = 'Camera is being used by another app. Please close other camera apps.';
        spokenMessage = 'Camera is in use by another app';
      } else if (e.toString().contains('not available')) {
        userMessage = 'Camera not available. It may be disconnected or disabled.';
        spokenMessage = 'Camera not available';
      } else {
        userMessage = 'Failed to initialize camera: $e';
      }

      if (mounted) {
        setState(() {
          _isLoading = false;
          _usePhoneCamera = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(userMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 7),
          ),
        );

        _ttsService.speak(spokenMessage);
      }
    }
  }

  Future<void> _connectToEsp32Wifi() async {
    setState(() {
      _isLoading = true;
    });

    // Inform user to connect to ESP32-CAM WiFi network first
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Connecting to ESP32-CAM at 192.168.4.1...'),
        duration: Duration(seconds: 2),
        backgroundColor: Colors.blue,
      ),
    );

    final success = await _wifiService.connect(esp32Ip: '192.168.4.1');

    if (success) {
      // Listen to image stream
      _wifiService.imageStream.listen((imageData) {
        if (mounted) {
          setState(() {
            _currentFrame = imageData;
          });
        }
      });

      // Listen to connection state changes
      _wifiService.connectionStateStream.listen((connected) {
        if (mounted && !connected && _isConnectedToWifi) {
          setState(() {
            _isConnectedToWifi = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('ESP32-CAM disconnected'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      });

      if (mounted) {
        setState(() {
          _isConnectedToWifi = true;
          _isLoading = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Connected to ESP32-CAM WiFi'),
            backgroundColor: Colors.green,
          ),
        );

        _ttsService.speak('ESP32 camera connected');
      }
    } else {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to connect to ESP32-CAM. Make sure you are connected to ESP32-CAM-AP WiFi network.'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 5),
          ),
        );

        _ttsService.speak('Failed to connect to ESP32 camera');
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
    // Capture from WiFi camera
    else if (_isConnectedToWifi && _currentFrame != null) {
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
    // Capture from WiFi camera
    else if (_isConnectedToWifi && _currentFrame != null) {
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

  Future<void> _captureAndRecognizeFace() async {
    // Check if face recognition is available
    if (!_faceRecognitionService.isInitialized) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Face recognition unavailable. TFLite model not loaded.'),
            duration: Duration(seconds: 4),
            backgroundColor: Colors.red,
          ),
        );
        _ttsService.speak('Face recognition unavailable');
      }
      return;
    }

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
    // Capture from WiFi camera
    else if (_isConnectedToWifi && _currentFrame != null) {
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

      // Use new ML-based face recognition
      final result = await _faceRecognitionService.recognizeFace(imageFile);

      if (!mounted) return;

      // Check for quality issues first
      if (result.qualityIssue != null) {
        final issue = result.qualityIssue!;
        setState(() {
          _description = issue.message ?? 'Face quality check failed';
          _isLoading = false;
        });
        // Speak the issue immediately
        _ttsService.speak(_description);
        return;
      }

      // Check if we found a match
      if (result.match != null) {
        final match = result.match!;
        final confidence = (match.similarity * 100).toStringAsFixed(0);
        setState(() {
          _description = 'This is ${match.personName} ($confidence% match)';
          _isLoading = false;
        });
        _ttsService.speak('This is ${match.personName}');
      } else {
        // Unknown face - ask for name
        setState(() {
          _isLoading = false;
        });
        _showNameInputDialog(imageFile);
      }
    } catch (e) {
      setState(() {
        _description = 'Error: $e';
        _isLoading = false;
      });
      _ttsService.speak('Error during face recognition');
    }
  }

  Future<void> _showNameInputDialog(File imageFile) async {
    final TextEditingController nameController = TextEditingController();

    // Speak the prompt
    _ttsService.speak('Person not recognized. Please enter their name.');

    // Set dialog open flag to prevent hardware key triggers
    setState(() {
      _isDialogOpen = true;
    });

    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Person not recognized'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Please enter their name:'),
            const SizedBox(height: 16),
            TextField(
              controller: nameController,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Enter name',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (value) {
                Navigator.pop(context, value);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, nameController.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    // Clear dialog open flag
    setState(() {
      _isDialogOpen = false;
    });

    if (name != null && name.trim().isNotEmpty) {
      try {
        // Show loading state
        if (mounted) {
          setState(() {
            _isLoading = true;
            _description = 'Validating and saving face...';
          });
        }

        // Save face to bank (includes quality validation and embedding extraction)
        await _faceRecognitionService.addFace(imageFile, name.trim());

        if (mounted) {
          setState(() {
            _description = 'Saved ${name.trim()} to face bank.';
            _isLoading = false;
          });
          _ttsService.speak('Saved ${name.trim()} to face bank');

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${name.trim()} added to face bank'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        // Extract the actual error message
        final errorMessage = e.toString().replaceFirst('Exception: ', '').replaceFirst('Failed to add face: ', '');

        if (mounted) {
          setState(() {
            _description = errorMessage;
            _isLoading = false;
          });
          _ttsService.speak(errorMessage);

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorMessage),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    }
  }

  @override
  void dispose() {
    _wifiService.dispose();
    _hardwareKeyService.dispose();
    _llamaService.dispose();
    _ttsService.dispose();
    _faceRecognitionService.dispose();
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
                      // ESP32-CAM WiFi stream preview
                      else if (_isConnectedToWifi && _currentFrame != null)
                        Center(
                          child: Image.memory(
                            _currentFrame!,
                            fit: BoxFit.contain,
                            gaplessPlayback: true,
                          ),
                        )
                      else if (_isConnectedToWifi)
                        const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CircularProgressIndicator(color: Colors.white),
                              SizedBox(height: 16),
                              Text(
                                'Waiting for ESP32-CAM WiFi stream...',
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
                                onPressed: _showCameraSourceDialog,
                                child: const Text('Select Camera'),
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
                              _isConnectedToWifi
                                  ? Icons.wifi
                                  : _usePhoneCamera
                                      ? Icons.camera
                                      : Icons.wifi_off,
                              color: _isConnectedToWifi
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
                                        (!_isConnectedToWifi && !_usePhoneCamera)
                                    ? null
                                    : _captureAndDescribe,
                                backgroundColor: _serverAvailable &&
                                        (_isConnectedToWifi || _usePhoneCamera)
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
                                        (!_isConnectedToWifi && !_usePhoneCamera)
                                    ? null
                                    : _captureAndExtractText,
                                backgroundColor: _serverAvailable &&
                                        (_isConnectedToWifi || _usePhoneCamera)
                                    ? Colors.white
                                    : Colors.grey,
                                child: const Icon(
                                  Icons.text_fields,
                                  color: Colors.black,
                                  size: 32,
                                ),
                              ),
                              const SizedBox(width: 16),
                              // Face recognition button
                              FloatingActionButton(
                                onPressed: _isLoading || !_serverAvailable ||
                                        (!_isConnectedToWifi && !_usePhoneCamera)
                                    ? null
                                    : _captureAndRecognizeFace,
                                backgroundColor: _serverAvailable &&
                                        (_isConnectedToWifi || _usePhoneCamera)
                                    ? Colors.white
                                    : Colors.grey,
                                child: const Icon(
                                  Icons.face,
                                  color: Colors.black,
                                  size: 32,
                                ),
                              ),
                              const SizedBox(width: 16),
                              // Repeat last description button
                              FloatingActionButton(
                                onPressed: _description.isEmpty
                                    ? null
                                    : () => _ttsService.speak(_description),
                                backgroundColor: _description.isNotEmpty
                                    ? Colors.white
                                    : Colors.grey,
                                child: const Icon(
                                  Icons.replay,
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
