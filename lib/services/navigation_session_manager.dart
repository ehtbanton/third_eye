import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

// Services
import 'navigation_guidance_service.dart';
import 'location_service.dart';
import 'tts_service.dart';
import 'heading_service.dart';
import 'audio_priority_service.dart';
import 'object_detection_service.dart';
import 'depth_map_service.dart';
import 'obstacle_fusion_service.dart';
import 'safe_path_service.dart';
import 'guidance_synthesizer.dart';
import 'cellular_azure_openai_service.dart' as azure;

// Models
import '../models/route_info.dart';
import '../models/detected_object.dart';

enum SessionState {
  idle,
  initializing,
  navigating,
  error
}

/// The brain of the Blind Navigation System.
/// Coordinates Sensor Fusion, Navigation, Heading, and Safety Warnings.
class NavigationSessionManager extends ChangeNotifier {
  // Singleton pattern
  static final NavigationSessionManager _instance = NavigationSessionManager._internal();
  factory NavigationSessionManager() => _instance;
  NavigationSessionManager._internal();

  // Core Services
  late final TtsService _ttsService;
  late final HeadingService _headingService;
  late final LocationService _locationService;
  late final AudioPriorityService _audioService;
  late final NavigationGuidanceService _guidanceService;

  // Vision Services
  final ObjectDetectionService _objectDetectionService = ObjectDetectionService();
  final DepthMapService _depthMapService = DepthMapService();
  final ObstacleFusionService _obstacleFusionService = ObstacleFusionService();
  final SafePathService _safePathService = SafePathService();

  // LLM Services (Azure OpenAI as default)
  late final azure.CellularAzureOpenAIService _visionLlmService;

  // Synthesis
  late final GuidanceSynthesizer _guidanceSynthesizer;

  // State
  SessionState _state = SessionState.idle;
  SessionState get state => _state;

  bool _isVisionEnabled = false;
  bool _isLlmEnabled = false;
  bool _servicesInitialized = false;

  // Processing Timers
  Timer? _llmTimer;
  Timer? _headingTimer;
  DateTime _lastVisionProcessTime = DateTime.fromMillisecondsSinceEpoch(0);

  // Timing Configuration
  static const Duration visionInterval = Duration(milliseconds: 300); // ~3 FPS
  static const Duration headingInterval = Duration(milliseconds: 100); // 10 Hz
  static const Duration safePathInterval = Duration(milliseconds: 500); // 2 Hz
  static const Duration llmInterval = Duration(seconds: 20); // Scene description

  // Current Data
  GuidanceState? currentGuidanceState;
  List<ObstacleWarning> currentWarnings = [];
  SafePathResult? currentSafePathResult;
  SynthesizedGuidance? currentSynthesizedGuidance;
  DepthMapResult? currentDepthMap;

  // Frame buffer for LLM analysis
  Uint8List? _lastFrameBytes;

  /// Initialize all services
  Future<void> initialize() async {
    if (_servicesInitialized) return;

    _state = SessionState.initializing;
    notifyListeners();

    try {
      // Initialize core services
      _ttsService = TtsService();
      await _ttsService.initialize();

      _headingService = HeadingService();
      await _headingService.initialize();

      _locationService = LocationService();
      await _locationService.initialize();

      // Audio priority wraps TTS
      _audioService = AudioPriorityService(ttsService: _ttsService);

      // Navigation guidance with heading support
      _guidanceService = NavigationGuidanceService(
        ttsService: _ttsService,
        locationService: _locationService,
        headingService: _headingService,
      );

      // Guidance synthesizer
      _guidanceSynthesizer = GuidanceSynthesizer(audioService: _audioService);

      // Vision services
      await _objectDetectionService.initialize();
      await _depthMapService.initialize(
        modelPath: 'assets/models/hitnet_middlebury_480x640.tflite',
        useGpuDelegate: false,
      );


      // Placeholder value for focal length in pixels xyz    --------->                     v CHANGE THIS THING
      _depthMapService.setStereoCalibration(baselineMeters: 0.065, focalLengthPx: 700.0);

      // LLM service (Azure OpenAI)
      _visionLlmService = azure.CellularAzureOpenAIService();
      await _visionLlmService.initialize();

      // Wire up guidance state callback
      _guidanceService.onGuidanceStateChanged = (state) {
        currentGuidanceState = state;
        _updateSynthesizedGuidance();
        notifyListeners();
      };

      _servicesInitialized = true;
      _state = SessionState.idle;
      notifyListeners();

      _audioService.speak("System initialized. Ready for navigation.", AudioPriority.ambient);
    } catch (e) {
      debugPrint("Error initializing NavigationSessionManager: $e");
      _state = SessionState.error;
      notifyListeners();
    }
  }

  /// Start navigation to a route
  void startNavigation(RouteInfo route) {
    if (_state == SessionState.error || !_servicesInitialized) return;

    _guidanceService.startGuidance(route);
    _guidanceSynthesizer.reset();
    _isVisionEnabled = true;
    _isLlmEnabled = true;

    // Start periodic LLM scene analysis
    _llmTimer?.cancel();
    _llmTimer = Timer.periodic(llmInterval, (_) => _triggerLlmSceneAnalysis());

    _state = SessionState.navigating;
    notifyListeners();

    _audioService.speak(
      "Navigation started. Follow voice guidance.",
      AudioPriority.navigation,
    );
  }

  /// Stop navigation
  void stopNavigation() {
    _guidanceService.stopGuidance();
    _isVisionEnabled = false;
    _isLlmEnabled = false;
    _llmTimer?.cancel();
    _headingTimer?.cancel();
    currentWarnings = [];
    currentSafePathResult = null;
    currentDepthMap = null;
    _state = SessionState.idle;
    notifyListeners();

    _audioService.speak("Navigation stopped.", AudioPriority.navigation);
  }

  /// Process a camera frame through the vision pipeline
  /// Called by the UI camera stream
  Future<void> processFrame(Uint8List frameBytes, {int? width, int? height}) async {
    if (!_isVisionEnabled || _state != SessionState.navigating) return;

    final now = DateTime.now();
    if (now.difference(_lastVisionProcessTime) < visionInterval) return;
    _lastVisionProcessTime = now;

    try {
      // Run Object Detection & Depth in parallel
      final detectionFuture = _objectDetectionService.detectObjects(
        frameBytes,
        imageWidth: width ?? 640,
        imageHeight: height ?? 480,
      );
      final depthFuture = _depthMapService.estimateDepthFromBytes(frameBytes);

      final results = await Future.wait([detectionFuture, depthFuture]);

      final detectionResult = results[0] as ObjectDetectionResult?;
      final depthResult = results[1] as DepthMapResult?;

      if (depthResult != null) {
        currentDepthMap = depthResult;

        // Analyze safe path from depth
        currentSafePathResult = _safePathService.analyzePath(depthResult);
      }

      if (detectionResult != null && depthResult != null) {
        // Fuse YOLO detections with depth for obstacle warnings
        currentWarnings = _obstacleFusionService.detectHazards(
          detectionResult.detections,
          depthResult
        );
      }

      // Update synthesized guidance
      _updateSynthesizedGuidance();

      // Announce via synthesizer (handles priority)
      _guidanceSynthesizer.synthesize(
        navigationState: currentGuidanceState,
        safePathResult: currentSafePathResult,
        obstacles: currentWarnings,
      );

      // Store frame for LLM analysis
      _lastFrameBytes = frameBytes;

      notifyListeners();

    } catch (e) {
      debugPrint("Vision Loop Error: $e");
    }
  }

  /// Update the synthesized guidance display state
  void _updateSynthesizedGuidance() {
    currentSynthesizedGuidance = _guidanceSynthesizer.getDisplayGuidance(
      navigationState: currentGuidanceState,
      safePathResult: currentSafePathResult,
      obstacles: currentWarnings,
    );
  }

  /// Trigger LLM scene analysis (Azure OpenAI)
  Future<void> _triggerLlmSceneAnalysis() async {
    if (_lastFrameBytes == null || !_isLlmEnabled) return;

    try {
      // Write frame to temp file
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/nav_scene_frame.jpg');
      await file.writeAsBytes(_lastFrameBytes!);

      // Analyze scene with Azure OpenAI
      final description = await _visionLlmService.analyzeNavigationScene(file.path);

      // Speak if meaningful
      if (description.isNotEmpty &&
          !description.toLowerCase().contains("error") &&
          !description.toLowerCase().contains("no description")) {
        _audioService.speak(description, AudioPriority.ambient);
      }

    } catch (e) {
      debugPrint("LLM Scene Analysis Error: $e");
    }
  }

  /// Manual request for detailed scene description
  Future<void> requestDetailedDescription() async {
    _audioService.speak("Analyzing scene...", AudioPriority.navigation);
    await _triggerLlmSceneAnalysis();
  }

  /// Get current heading to next waypoint
  double? get headingDelta => currentGuidanceState?.headingDelta;

  /// Get current compass heading
  double? get currentHeading => currentGuidanceState?.currentHeading;

  /// Is path currently safe?
  bool get isPathSafe =>
      currentSafePathResult?.safety != PathSafety.blocked;

  /// Are there critical obstacles?
  bool get hasCriticalObstacles =>
      currentWarnings.any((w) => w.isCritical);

  @override
  void dispose() {
    stopNavigation();
    _guidanceService.dispose();
    _headingService.dispose();
    _objectDetectionService.dispose();
    _depthMapService.dispose();
    _ttsService.dispose();
    _audioService.dispose();
    super.dispose();
  }
}
