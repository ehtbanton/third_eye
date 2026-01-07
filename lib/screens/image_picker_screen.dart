import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import '../services/llama_service.dart';
import '../services/tts_service.dart';
import '../services/hardware_key_service.dart';
import '../services/face_recognition_service.dart';
import '../services/foreground_service.dart';
import '../services/location_service.dart';
import '../services/azure_maps_service.dart';
import '../services/navigation_guidance_service.dart';
import '../services/video_source.dart';
import '../services/depth_map_service.dart';
import '../widgets/depth_map_painter.dart';
import '../models/route_info.dart';
import 'map_screen.dart';
import 'dart:ui' as ui;

class ImagePickerScreen extends StatefulWidget {
  const ImagePickerScreen({super.key});

  @override
  State<ImagePickerScreen> createState() => _ImagePickerScreenState();
}

class _ImagePickerScreenState extends State<ImagePickerScreen> with WidgetsBindingObserver {
  final LlamaService _llamaService = LlamaService();
  final TtsService _ttsService = TtsService();
  final HardwareKeyService _hardwareKeyService = HardwareKeyService();
  final FaceRecognitionService _faceRecognitionService = FaceRecognitionService();
  final ForegroundService _foregroundService = ForegroundService();
  final LocationService _locationService = LocationService();
  final AzureMapsService _azureMapsService = AzureMapsService();
  late final NavigationGuidanceService _navigationService;
  StreamSubscription<Map<String, dynamic>>? _foregroundTriggerSubscription;
  bool _backgroundServiceRunning = false;

  // PageView for swipe navigation between map and camera
  final PageController _pageController = PageController(initialPage: 1);
  int _currentPage = 1; // 0 = Map, 1 = Camera

  RouteInfo? _activeRoute;

  // ignore: unused_field
  Uint8List? _snapshotImage;
  File? _capturedImage;
  String _description = '';
  bool _isLoading = false;
  bool _serverAvailable = false;
  bool _isInitializing = false;
  bool _hardwareKeysActive = false;
  bool _isDialogOpen = false;

  // Unified video source
  CameraSource _selectedSource = CameraSource.slp2Udp;
  VideoSource? _currentSource;
  StreamSubscription<bool>? _sourceConnectionSubscription;

  // LLM provider selection
  LlmProvider _selectedLlmProvider = LlmProvider.gemini;

  // Depth map overlay
  final DepthMapService _depthMapService = DepthMapService();
  bool _showDepthOverlay = false;
  ui.Image? _depthMapImage;
  bool _isProcessingDepth = false;
  Timer? _depthProcessingTimer;
  double _lastDepthProcessingTime = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeServices();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    debugPrint('App lifecycle state changed: $state');

    if (state == AppLifecycleState.resumed) {
      _handleAppResumed();
    }
  }

  Future<void> _handleAppResumed() async {
    debugPrint('App resumed - reconnecting to stream');
    // Sources handle their own reconnection
  }

  Future<void> _initializeServices() async {
    setState(() {
      _isInitializing = true;
    });

    try {
      // Initialize face recognition service early
      debugPrint('Initializing face recognition service...');
      try {
        await _faceRecognitionService.initialize();
        debugPrint('Face recognition service initialized with ${_faceRecognitionService.cachedFaceCount} known faces');
      } catch (e) {
        debugPrint('WARNING: Face recognition initialization failed: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Face recognition unavailable: Missing TFLite model. See assets/models/README.md'),
              duration: Duration(seconds: 8),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }

      // Request camera permissions
      debugPrint('Requesting camera permission...');
      final cameraPermission = await Permission.camera.request();
      debugPrint('Camera permission status: $cameraPermission');

      if (!cameraPermission.isGranted) {
        debugPrint('WARNING: Camera permission not granted');
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

      // Initialize Gemini API and TTS
      final success = await _llamaService.initialize();
      await _ttsService.initialize();

      // Initialize navigation guidance service
      _navigationService = NavigationGuidanceService(
        ttsService: _ttsService,
        locationService: _locationService,
      );

      // Initialize map services (async, non-blocking)
      _azureMapsService.initialize().then((success) {
        if (!success) {
          debugPrint('WARNING: Azure Maps service not configured - add AZURE_MAPS_SUBSCRIPTION_KEY to .env');
        }
      });
      _locationService.initialize().then((success) {
        if (!success) {
          debugPrint('WARNING: Location service failed to initialize');
        }
      });

      // Initialize depth map service
      try {
        await _depthMapService.initialize();
        debugPrint('Depth map service initialized');
      } catch (e) {
        debugPrint('WARNING: Depth map service failed to initialize: $e');
      }

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

        // Auto-start background service for persistent operation
        await _startBackgroundService();

        // Auto-connect to default source (SLP2 UDP)
        _switchSource(CameraSource.slp2Udp);
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

  void _setupHardwareKeyListener() {
    _hardwareKeyService.startListening();

    setState(() {
      _hardwareKeysActive = _hardwareKeyService.isListening;
    });

    _hardwareKeyService.keyStream.listen((event) {
      debugPrint('=== Hardware Button Press Detected ===');
      debugPrint('Button type: ${event.keyType}');
      debugPrint('Source connected: ${_currentSource?.isConnected}');
      debugPrint('Server available: $_serverAvailable');
      debugPrint('Is loading: $_isLoading');
      debugPrint('Dialog open: $_isDialogOpen');

      if (!_isLoading && !_isDialogOpen && _serverAvailable && _currentSource?.isConnected == true) {
        if (event.keyType == HardwareKeyType.volumeUp) {
          debugPrint('Button 1 pressed - Taking photo and describing image');
          _captureAndDescribe();
        } else if (event.keyType == HardwareKeyType.volumeDown) {
          debugPrint('Button 2 pressed - Taking photo and extracting text');
          _captureAndExtractText();
        } else {
          debugPrint('Other button pressed - Performing face recognition');
          _captureAndRecognizeFace();
        }
      } else {
        debugPrint('Button press ignored - conditions not met for capture');
      }
    });

    _setupForegroundServiceListener();
  }

  void _setupForegroundServiceListener() {
    _foregroundTriggerSubscription = _foregroundService.triggerStream.listen((event) {
      debugPrint('=== Background Service Trigger ===');
      debugPrint('Source: ${event['source']}');
      debugPrint('Source connected: ${_currentSource?.isConnected}');
      debugPrint('Server available: $_serverAvailable');
      debugPrint('Is loading: $_isLoading');

      if (!_isLoading && _serverAvailable && _currentSource?.isConnected == true) {
        debugPrint('Background trigger - Taking photo and describing image');
        _captureAndDescribe();
      } else {
        debugPrint('Background trigger ignored - conditions not met for capture');
        _ttsService.speak('Cannot capture. Camera or server not ready.');
      }
    });
  }

  Future<void> _startBackgroundService() async {
    if (_backgroundServiceRunning) {
      debugPrint('Background service already running');
      return;
    }

    if (!await _foregroundService.hasNotificationPermission()) {
      await _foregroundService.requestNotificationPermission();
    }

    await _foregroundService.requestBatteryOptimizationExemption();

    final success = await _foregroundService.startService(port: 5000);
    if (success) {
      setState(() {
        _backgroundServiceRunning = true;
      });
      debugPrint('Background service started successfully');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Background service started. Clicker works even with screen off.'),
            duration: Duration(seconds: 3),
            backgroundColor: Colors.green,
          ),
        );
      }
    } else {
      debugPrint('Failed to start background service');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to start background service'),
            duration: Duration(seconds: 3),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _stopBackgroundService() async {
    await _foregroundService.stopService();
    setState(() {
      _backgroundServiceRunning = false;
    });
    debugPrint('Background service stopped');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Background service stopped'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  /// Switch to a different camera source
  Future<void> _switchSource(CameraSource source) async {
    if (_selectedSource == source && _currentSource != null) return;

    // Stop depth processing
    _stopDepthProcessing();
    setState(() {
      _showDepthOverlay = false;
      _selectedSource = source;
    });

    // Disconnect from current source
    await _sourceConnectionSubscription?.cancel();
    await _currentSource?.disconnect();

    // Create new source
    _currentSource = VideoSourceFactory.create(source);

    // Listen to connection state changes
    _sourceConnectionSubscription = _currentSource!.connectionStateStream.listen((connected) {
      if (mounted) {
        setState(() {}); // Trigger rebuild to update UI
        if (connected) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${source.label} connected'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    });

    // Update UI immediately to show the source widget
    setState(() {});

    // Start connection in background - don't block UI
    _currentSource!.connect(context).then((success) {
      if (mounted && !success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to connect to ${source.label}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    });
  }

  /// Switch to a different LLM provider
  Future<void> _switchLlmProvider(LlmProvider provider) async {
    if (_selectedLlmProvider == provider) return;

    setState(() {
      _selectedLlmProvider = provider;
    });

    final success = await _llamaService.setProvider(provider);
    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to initialize ${_getLlmProviderLabel(provider)}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  String _getLlmProviderLabel(LlmProvider provider) {
    switch (provider) {
      case LlmProvider.azureOpenAI:
        return 'Azure GPT-4o';
      case LlmProvider.gemini:
        return 'Gemini Flash';
    }
  }

  /// Toggle depth map overlay
  void _toggleDepthOverlay() {
    setState(() {
      _showDepthOverlay = !_showDepthOverlay;
    });

    if (_showDepthOverlay) {
      _startDepthProcessing();
    } else {
      _stopDepthProcessing();
    }
  }

  /// Start depth map processing loop
  void _startDepthProcessing() {
    if (_depthProcessingTimer != null) return;
    if (!_depthMapService.isInitialized) {
      debugPrint('Depth map service not initialized - cannot start processing');
      return;
    }
    if (_currentSource?.isConnected != true) {
      debugPrint('No source connected - cannot start depth processing');
      return;
    }

    debugPrint('Starting depth processing timer');
    _depthProcessingTimer = Timer.periodic(
      const Duration(milliseconds: 200), // ~5 FPS
      (_) => _processDepthFrame(),
    );
  }

  /// Stop depth map processing
  void _stopDepthProcessing() {
    _depthProcessingTimer?.cancel();
    _depthProcessingTimer = null;
  }

  /// Process a single depth frame
  Future<void> _processDepthFrame() async {
    if (_isProcessingDepth || _currentSource?.isConnected != true) return;
    _isProcessingDepth = true;

    try {
      final frame = await _currentSource!.captureFrame();
      if (frame == null) {
        _isProcessingDepth = false;
        return;
      }

      if (!_depthMapService.isInitialized) {
        _isProcessingDepth = false;
        return;
      }

      final result = await _depthMapService.estimateDepthFromImage(frame);
      if (result == null) {
        _isProcessingDepth = false;
        return;
      }

      // Validate RGBA data
      final expectedSize = result.width * result.height * 4;
      if (result.colorizedRgba.length != expectedSize) {
        debugPrint('RGBA size mismatch! Got ${result.colorizedRgba.length}, expected $expectedSize');
        _isProcessingDepth = false;
        return;
      }

      // Convert colorized RGBA to ui.Image
      final image = await DepthMapImageHelper.rgbaToImage(
        result.colorizedRgba.toList(),
        result.width,
        result.height,
      );

      if (mounted) {
        setState(() {
          _depthMapImage = image;
          _lastDepthProcessingTime = result.processingTimeMs;
        });
      }
    } catch (e, stack) {
      debugPrint('Depth processing error: $e');
      debugPrint('Stack: $stack');
    } finally {
      _isProcessingDepth = false;
    }
  }

  /// Capture frame and get description from LLM
  Future<void> _captureAndDescribe() async {
    if (_currentSource?.isConnected != true) {
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

    setState(() {
      _isLoading = true;
      _description = '';
    });

    try {
      final frameBytes = await _currentSource!.captureFrame();
      if (frameBytes == null) {
        throw Exception('Failed to capture frame');
      }

      _snapshotImage = frameBytes;

      // Save to temporary file
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final tempFile = File('${tempDir.path}/snapshot_$timestamp.jpg');
      await tempFile.writeAsBytes(frameBytes);

      setState(() {
        _capturedImage = tempFile;
      });

      // Get description from LLM
      final response = await _llamaService.describeImage(tempFile.path);

      setState(() {
        if (response.success) {
          _description = response.content;
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

  /// Capture frame and extract text from LLM
  Future<void> _captureAndExtractText() async {
    if (_currentSource?.isConnected != true) {
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

    setState(() {
      _isLoading = true;
      _description = '';
    });

    try {
      final frameBytes = await _currentSource!.captureFrame();
      if (frameBytes == null) {
        throw Exception('Failed to capture frame');
      }

      _snapshotImage = frameBytes;

      // Save to temporary file
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final tempFile = File('${tempDir.path}/snapshot_$timestamp.jpg');
      await tempFile.writeAsBytes(frameBytes);

      setState(() {
        _capturedImage = tempFile;
      });

      // Extract text from LLM
      final response = await _llamaService.extractText(tempFile.path);

      setState(() {
        if (response.success) {
          _description = response.content;
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

  /// Capture frame and recognize face
  Future<void> _captureAndRecognizeFace() async {
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

    if (_currentSource?.isConnected != true) {
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

    setState(() {
      _isLoading = true;
      _description = '';
    });

    try {
      final frameBytes = await _currentSource!.captureFrame();
      if (frameBytes == null) {
        throw Exception('Failed to capture frame');
      }

      _snapshotImage = frameBytes;

      // Save to temporary file
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final tempFile = File('${tempDir.path}/snapshot_$timestamp.jpg');
      await tempFile.writeAsBytes(frameBytes);

      setState(() {
        _capturedImage = tempFile;
      });

      // Use ML-based face recognition
      final result = await _faceRecognitionService.recognizeFace(tempFile);

      if (!mounted) return;

      // Check for quality issues first
      if (result.qualityIssue != null) {
        final issue = result.qualityIssue!;
        setState(() {
          _description = issue.message ?? 'Face quality check failed';
          _isLoading = false;
        });
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
        _showNameInputDialog(tempFile);
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

    _ttsService.speak('Person not recognized. Please enter their name.');

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

    setState(() {
      _isDialogOpen = false;
    });

    if (name != null && name.trim().isNotEmpty) {
      try {
        if (mounted) {
          setState(() {
            _isLoading = true;
            _description = 'Validating and saving face...';
          });
        }

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
    WidgetsBinding.instance.removeObserver(this);
    _foregroundService.stopService();
    _foregroundTriggerSubscription?.cancel();
    _sourceConnectionSubscription?.cancel();
    _currentSource?.disconnect();
    _hardwareKeyService.dispose();
    _llamaService.dispose();
    _ttsService.dispose();
    _faceRecognitionService.dispose();
    _navigationService.dispose();
    _locationService.dispose();
    _pageController.dispose();
    _depthMapService.dispose();
    _stopDepthProcessing();
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
          : Stack(
              children: [
                PageView(
                  controller: _pageController,
                  onPageChanged: (index) {
                    setState(() => _currentPage = index);
                  },
                  children: [
                    // Page 0: Map view
                    MapScreen(
                      locationService: _locationService,
                      azureMapsService: _azureMapsService,
                      navigationService: _navigationService,
                      activeRoute: _activeRoute,
                      onRouteChanged: (route) {
                        setState(() => _activeRoute = route);
                      },
                    ),
                    // Page 1: Camera view
                    _buildCameraView(),
                  ],
                ),
                // Page indicator dots
                Positioned(
                  bottom: 8,
                  left: 0,
                  right: 0,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _currentPage == 0 ? Colors.white : Colors.white38,
                        ),
                      ),
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _currentPage == 1 ? Colors.white : Colors.white38,
                        ),
                      ),
                    ],
                  ),
                ),
                // Swipe handle on right edge (map view) or left edge (camera view)
                Positioned(
                  right: _currentPage == 0 ? 0 : null,
                  left: _currentPage == 1 ? 0 : null,
                  top: 0,
                  bottom: 0,
                  child: GestureDetector(
                    onHorizontalDragEnd: (details) {
                      if (_currentPage == 0 && (details.primaryVelocity ?? 0) > 0) {
                        _pageController.animateToPage(1,
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut);
                      } else if (_currentPage == 1 && (details.primaryVelocity ?? 0) < 0) {
                        _pageController.animateToPage(0,
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut);
                      }
                    },
                    child: Container(
                      width: 24,
                      color: Colors.transparent,
                      child: Center(
                        child: Container(
                          width: 4,
                          height: 48,
                          decoration: BoxDecoration(
                            color: Colors.white54,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildCameraView() {
    return Column(
      children: [
        // Top half: Camera preview with capture button
        Expanded(
          flex: 1,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Camera preview from current source
              // Show the widget even while connecting - the widget handles its own loading state
              if (_currentSource != null)
                _currentSource!.buildPreview(
                  overlay: _showDepthOverlay && _currentSource!.isConnected ? _buildDepthOverlay() : null,
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
                      Text(
                        'Select a source from the dropdown above',
                        style: TextStyle(color: Colors.grey[400], fontSize: 12),
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
                      _getSourceIcon(),
                      color: _getSourceColor(),
                      size: 32,
                    ),
                    // Depth map toggle (show for any connected source with depth service)
                    if (_currentSource?.isConnected == true && _depthMapService.isInitialized) ...[
                      const SizedBox(height: 8),
                      GestureDetector(
                        onTap: _toggleDepthOverlay,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: _showDepthOverlay ? Colors.green.withOpacity(0.8) : Colors.black54,
                            borderRadius: BorderRadius.circular(8),
                            border: _showDepthOverlay
                                ? Border.all(color: Colors.greenAccent, width: 2)
                                : null,
                          ),
                          child: Icon(
                            Icons.layers,
                            color: _showDepthOverlay ? Colors.white : Colors.white70,
                            size: 28,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // Source and LLM selection dropdowns (top left)
              Positioned(
                top: 40,
                left: 16,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Camera source dropdown
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Hardware key status icon
                          Icon(
                            _hardwareKeysActive ? Icons.keyboard : Icons.keyboard_outlined,
                            color: _hardwareKeysActive ? Colors.green : Colors.grey,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          // Source dropdown
                          DropdownButton<CameraSource>(
                            value: _selectedSource,
                            dropdownColor: Colors.grey[900],
                            underline: const SizedBox(),
                            icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
                            style: const TextStyle(color: Colors.white, fontSize: 14),
                            items: CameraSource.values.map((source) {
                              return DropdownMenuItem<CameraSource>(
                                value: source,
                                child: Text(source.label),
                              );
                            }).toList(),
                            onChanged: _isLoading ? null : (source) {
                              if (source != null) {
                                _switchSource(source);
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    // LLM provider dropdown
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: DropdownButton<LlmProvider>(
                        value: _selectedLlmProvider,
                        dropdownColor: Colors.grey[900],
                        underline: const SizedBox(),
                        icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        items: LlmProvider.values.map((provider) {
                          return DropdownMenuItem<LlmProvider>(
                            value: provider,
                            child: Text(_getLlmProviderLabel(provider)),
                          );
                        }).toList(),
                        onChanged: _isLoading ? null : (provider) {
                          if (provider != null) {
                            _switchLlmProvider(provider);
                          }
                        },
                      ),
                    ),
                  ],
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
                        onPressed: _isLoading || !_serverAvailable || _currentSource?.isConnected != true
                            ? null
                            : _captureAndDescribe,
                        backgroundColor: _serverAvailable && _currentSource?.isConnected == true
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
                        onPressed: _isLoading || !_serverAvailable || _currentSource?.isConnected != true
                            ? null
                            : _captureAndExtractText,
                        backgroundColor: _serverAvailable && _currentSource?.isConnected == true
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
                        onPressed: _isLoading || !_serverAvailable || _currentSource?.isConnected != true
                            ? null
                            : _captureAndRecognizeFace,
                        backgroundColor: _serverAvailable && _currentSource?.isConnected == true
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
    );
  }

  Widget _buildDepthOverlay() {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Depth map overlay
        CustomPaint(
          painter: DepthMapPainter(
            depthMapImage: _depthMapImage,
            showOverlay: _showDepthOverlay,
            opacity: 0.7,
            showDivider: false,
          ),
          size: Size.infinite,
        ),
        // Depth processing indicator
        Positioned(
          right: 8,
          bottom: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_isProcessingDepth)
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                if (_isProcessingDepth) const SizedBox(width: 6),
                Text(
                  '${_lastDepthProcessingTime.toStringAsFixed(0)}ms',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
                if (_depthMapService.isUsingGpu) ...[
                  const SizedBox(width: 4),
                  const Icon(Icons.memory, size: 12, color: Colors.greenAccent),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  IconData _getSourceIcon() {
    if (_currentSource?.isConnected != true) return Icons.wifi_off;

    switch (_selectedSource) {
      case CameraSource.esp32:
        return Icons.wifi;
      case CameraSource.slp2Rtsp:
        return Icons.videocam;
      case CameraSource.slp2Udp:
        return Icons.stream;
      case CameraSource.phone:
        return Icons.camera;
      case CameraSource.stereoSim:
        return Icons.threed_rotation;
    }
  }

  Color _getSourceColor() {
    if (_currentSource?.isConnected != true) return Colors.grey;

    switch (_selectedSource) {
      case CameraSource.esp32:
        return Colors.blue;
      case CameraSource.slp2Rtsp:
        return Colors.purple;
      case CameraSource.slp2Udp:
        return Colors.cyan;
      case CameraSource.phone:
        return Colors.green;
      case CameraSource.stereoSim:
        return Colors.orange;
    }
  }
}
