import 'dart:async';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../services/navigation_session_manager.dart';
import '../services/navigation_guidance_service.dart';
import '../services/guidance_synthesizer.dart';
import '../services/safe_path_service.dart';
import '../models/route_info.dart';
import '../models/navigation_checkpoint.dart';

class BlindNavigationScreen extends StatefulWidget {
  const BlindNavigationScreen({super.key});

  @override
  State<BlindNavigationScreen> createState() => _BlindNavigationScreenState();
}

class _BlindNavigationScreenState extends State<BlindNavigationScreen> {
  final NavigationSessionManager _sessionManager = NavigationSessionManager();
  CameraController? _cameraController;
  bool _isCameraInitialized = false;
  bool _isProcessingFrame = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    await _sessionManager.initialize();
    await _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    final cameras = await availableCameras();
    final firstCamera = cameras.first;

    _cameraController = CameraController(
      firstCamera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg, // Critical for consistent bytes
    );

    await _cameraController!.initialize();
    
    // Start Stream
    await _cameraController!.startImageStream((CameraImage image) {
      if (_isProcessingFrame) return;
      _isProcessingFrame = true;
      
      // Convert CameraImage to Uint8List (JPEG)
      // Note: This is complex in Flutter (YUV -> RGB -> JPEG).
      // For simplicity in this architecture demo, we might skip actual conversion 
      // if the services expect specific formats.
      // However, our services expect Uint8List (JPEG bytes).
      // Converting YUV to JPEG in Dart is slow.
      // Better approach: Use a specific plugin or assume the services handle YUV?
      // DetectionService uses flutter_vision which takes YUV/Bytes.
      // DepthMapService uses Image package decode.
      
      // For this prototype, we will just simulate the "Process" call 
      // if we can't easily convert fast enough without blocking.
      // OR, we assume the camera returns a format we can handle.
      
      // OPTIMIZATION: Just pass the raw bytes if the service supports it.
      // But for now, we'll placeholder the conversion to keep the UI responsive.
      // In a real app, use `image_conversion` package or native code.
      
       _isProcessingFrame = false;
    });

    setState(() {
      _isCameraInitialized = true;
    });
  }
  
  // Alternative: Take picture periodically (Cleaner for JPEG requirements)
  Timer? _pictureTimer;
  
  void _startPictureLoop() {
    _pictureTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) async {
       if (_cameraController != null && _cameraController!.value.isInitialized && !_isProcessingFrame) {
         _isProcessingFrame = true;
         try {
           final file = await _cameraController!.takePicture();
           final bytes = await file.readAsBytes();
           await _sessionManager.processFrame(bytes);
         } catch (e) {
           print("Camera error: $e");
         } finally {
           _isProcessingFrame = false;
         }
       }
    });
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _pictureTimer?.cancel();
    _sessionManager.dispose();
    super.dispose();
  }
  
  void _startTestNavigation() {
    // Create a dummy route relative to current location (if known) or fixed
    // For demo, we'll just start the session logic
    final route = RouteInfo(
      routePoints: [const LatLng(0,0), const LatLng(0, 0.0001), const LatLng(0, 0.0002)],
      checkpoints: [
         NavigationCheckpoint(
             index: 0, 
             location: const LatLng(0,0), 
             instruction: "Walk forward 10 meters", 
             distanceMeters: 0,
             maneuver: "STRAIGHT"
         ),
         NavigationCheckpoint(
             index: 1, 
             location: const LatLng(0,0.0001), 
             instruction: "Turn left",
             distanceMeters: 10,
             maneuver: "TURN_LEFT"
         ),
      ], 
      destination: const LatLng(0, 0.0002), 
      distanceMeters: 100, 
      durationSeconds: 60,
      summary: "Test Route",
      timestamp: DateTime.now(),
    );
    
    _sessionManager.startNavigation(route);
    _startPictureLoop();
  }
  
  void _triggerCognitive() {
    _sessionManager.requestDetailedDescription();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. Camera Feed
          if (_isCameraInitialized && _cameraController != null)
             Center(child: CameraPreview(_cameraController!))
          else
             const Center(child: CircularProgressIndicator()),
             
          // 2. Overlays
          _buildGuidanceOverlay(),
          _buildWarningOverlay(),
          
          // 3. Controls
          Positioned(
            bottom: 30,
            left: 20,
            right: 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                FloatingActionButton(
                  heroTag: "start",
                  backgroundColor: Colors.green,
                  onPressed: _startTestNavigation,
                  child: const Icon(Icons.navigation),
                ),
                FloatingActionButton(
                  heroTag: "gemini",
                  backgroundColor: Colors.blue,
                  onPressed: _triggerCognitive,
                  child: const Icon(Icons.remove_red_eye),
                ),
                FloatingActionButton(
                  heroTag: "stop",
                  backgroundColor: Colors.red,
                  onPressed: () => _sessionManager.stopNavigation(),
                  child: const Icon(Icons.stop),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildGuidanceOverlay() {
    return ListenableBuilder(
      listenable: _sessionManager,
      builder: (context, child) {
        final synthesized = _sessionManager.currentSynthesizedGuidance;
        final navState = _sessionManager.currentGuidanceState;

        if (synthesized == null && navState == null) return const SizedBox.shrink();

        // Determine border color based on urgency
        Color borderColor;
        if (synthesized != null) {
          switch (synthesized.urgency) {
            case GuidanceUrgency.critical:
              borderColor = Colors.red;
              break;
            case GuidanceUrgency.warning:
              borderColor = Colors.orange;
              break;
            case GuidanceUrgency.caution:
              borderColor = Colors.yellow;
              break;
            case GuidanceUrgency.navigation:
              borderColor = Colors.blue;
              break;
            case GuidanceUrgency.clear:
              borderColor = Colors.green;
              break;
          }
        } else {
          borderColor = Colors.white24;
        }

        return Positioned(
          top: 50,
          left: 20,
          right: 20,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor, width: 3)
            ),
            child: Column(
              children: [
                // Primary guidance message
                Text(
                  synthesized?.primaryMessage ?? navState?.currentCheckpoint?.instruction ?? "Head to start",
                  style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),

                // Turn instruction with heading delta
                if (navState?.headingDelta != null && navState!.headingDelta!.abs() > 20)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.yellow.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          navState.headingDelta! > 0 ? Icons.turn_right : Icons.turn_left,
                          color: Colors.yellow,
                          size: 32,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          navState.turnInstruction ?? "Turn ${navState.headingDelta! > 0 ? 'Right' : 'Left'}",
                          style: const TextStyle(color: Colors.yellow, fontSize: 28, fontWeight: FontWeight.w900),
                        ),
                      ],
                    ),
                  ),

                // Secondary info (distance to checkpoint)
                if (synthesized?.secondaryMessage != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    synthesized!.secondaryMessage!,
                    style: const TextStyle(color: Colors.grey, fontSize: 16),
                  ),
                ],

                // Remaining distance
                if (navState != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    navState.formattedRemainingDistance,
                    style: const TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                ],

                // Safe path indicator
                if (_sessionManager.currentSafePathResult != null) ...[
                  const SizedBox(height: 8),
                  _buildSafePathIndicator(_sessionManager.currentSafePathResult!),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSafePathIndicator(SafePathResult pathResult) {
    Color safetyColor;
    IconData safetyIcon;
    String safetyText;

    switch (pathResult.safety) {
      case PathSafety.clear:
        safetyColor = Colors.green;
        safetyIcon = Icons.check_circle;
        safetyText = "Path Clear";
        break;
      case PathSafety.caution:
        safetyColor = Colors.orange;
        safetyIcon = Icons.warning;
        safetyText = pathResult.suggestedAction ?? "Caution";
        break;
      case PathSafety.blocked:
        safetyColor = Colors.red;
        safetyIcon = Icons.block;
        safetyText = pathResult.suggestedAction ?? "Path Blocked";
        break;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(safetyIcon, color: safetyColor, size: 20),
        const SizedBox(width: 6),
        Text(
          safetyText,
          style: TextStyle(color: safetyColor, fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _buildWarningOverlay() {
    return ListenableBuilder(
      listenable: _sessionManager,
      builder: (context, child) {
        if (_sessionManager.currentWarnings.isEmpty) return const SizedBox.shrink();
        
        final warning = _sessionManager.currentWarnings.first;
        final color = warning.isCritical ? Colors.red : Colors.orange;
        
        return Positioned(
          top: 200,
          left: 20,
          right: 20,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: color.withOpacity(0.8),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.white, size: 40),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    warning.announcement,
                    style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
