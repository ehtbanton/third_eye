import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'stereo_video_source.dart';
import 'depth_map_service.dart';
import 'stereo_depth_service.dart';
import 'depth_calibration_service.dart';

/// Result from metric depth estimation.
class MetricDepthResult {
  /// Calibrated metric depth values in meters (row-major).
  /// Lower value = closer. Infinity = unknown/far.
  final Float32List metricDepth;

  /// Original MiDaS inverse depth (for visualization).
  final Float32List midasDepth;

  /// Colorized depth map as RGBA bytes.
  final Uint8List colorizedRgba;

  /// Width of the depth map.
  final int width;

  /// Height of the depth map.
  final int height;

  /// Whether the depth is calibrated to metric scale.
  final bool isCalibrated;

  /// Current calibration parameters (null if not calibrated).
  final DepthCalibration? calibration;

  /// Processing time in milliseconds.
  final double processingTimeMs;

  MetricDepthResult({
    required this.metricDepth,
    required this.midasDepth,
    required this.colorizedRgba,
    required this.width,
    required this.height,
    required this.isCalibrated,
    this.calibration,
    required this.processingTimeMs,
  });

  /// Get metric depth at a normalized coordinate (0-1 range).
  double getDepthAtNormalized(double nx, double ny) {
    final x = (nx * width).round().clamp(0, width - 1);
    final y = (ny * height).round().clamp(0, height - 1);
    return metricDepth[y * width + x];
  }

  /// Get metric depth at pixel coordinate.
  double getDepthAt(int x, int y) {
    if (x < 0 || x >= width || y < 0 || y >= height) return double.infinity;
    return metricDepth[y * width + x];
  }
}

/// Service that combines MiDaS smooth depth with stereo calibration
/// to produce metric depth estimates.
///
/// How it works:
/// 1. MiDaS provides smooth, dense relative depth (fast, runs every frame)
/// 2. Stereo matching provides sparse but accurate metric depth (slower, runs periodically)
/// 3. Calibration service aligns MiDaS to stereo scale using: depth = 1/(s*midas + t)
/// 4. Result: smooth MiDaS depth in actual meters
///
/// Usage:
/// ```dart
/// final service = MetricDepthService();
/// await service.initialize();
///
/// // Process frames
/// final result = await service.estimateDepth(stereoPair);
/// if (result != null && result.isCalibrated) {
///   final depthMeters = result.getDepthAtNormalized(0.5, 0.5);
///   print('Center depth: ${depthMeters}m');
/// }
/// ```
class MetricDepthService {
  final DepthMapService _midasService = DepthMapService();
  final StereoDepthService _stereoService;
  final DepthCalibrationService _calibrationService = DepthCalibrationService();

  bool _isInitialized = false;
  int _frameCount = 0;

  // How often to run stereo calibration (every N frames)
  final int _stereoCalibrationInterval;

  // Whether to run stereo calibration in parallel (faster but uses more CPU)
  final bool _parallelCalibration;

  /// Create a MetricDepthService configured for StereoPi with Pi Camera v2 modules.
  ///
  /// Default parameters are for:
  /// - Pi Camera Module v2 (Sony IMX219, 3.04mm focal length)
  /// - 65mm stereo baseline
  /// - 720p streaming resolution (focal length ~1057px)
  ///
  /// The focal length will auto-configure on first stereo frame based on
  /// actual image resolution.
  MetricDepthService({
    double baselineMeters = 0.065,      // 65mm camera baseline
    double focalLengthPixels = 1057.0,  // Pi Cam v2 at 720p, auto-configured on first frame
    int stereoCalibrationInterval = 5,  // Run stereo every 5 frames
    bool parallelCalibration = false,
  }) : _stereoService = StereoDepthService(
         baselineMeters: baselineMeters,
         focalLengthPixels: focalLengthPixels,
       ),
       _stereoCalibrationInterval = stereoCalibrationInterval,
       _parallelCalibration = parallelCalibration;

  /// Whether the service is initialized.
  bool get isInitialized => _isInitialized;

  /// Whether depth is calibrated to metric scale.
  bool get isCalibrated => _calibrationService.isCalibrated;

  /// Current calibration (null if not calibrated).
  DepthCalibration? get calibration => _calibrationService.calibration;

  /// Access to underlying services for advanced use.
  DepthMapService get midasService => _midasService;
  StereoDepthService get stereoService => _stereoService;
  DepthCalibrationService get calibrationService => _calibrationService;

  /// Initialize the metric depth service.
  Future<void> initialize({
    String midasModelPath = 'assets/models/midas_v21_small_256.tflite',
    bool useGpuDelegate = true,
  }) async {
    if (_isInitialized) {
      dispose();
    }

    debugPrint('MetricDepthService: Initializing...');
    await _midasService.initialize(
      modelPath: midasModelPath,
      useGpuDelegate: useGpuDelegate,
    );

    _isInitialized = true;
    debugPrint('MetricDepthService: Initialized');
  }

  /// Estimate metric depth from a stereo frame pair.
  ///
  /// Returns calibrated metric depth if calibration is available,
  /// otherwise returns uncalibrated MiDaS depth.
  Future<MetricDepthResult?> estimateDepth(StereoFramePair stereoPair) async {
    if (!_isInitialized) {
      debugPrint('MetricDepthService: Not initialized');
      return null;
    }

    final stopwatch = Stopwatch()..start();
    _frameCount++;

    // 1. Run MiDaS on left image (always)
    final midasResult = await _midasService.estimateDepth(stereoPair);
    if (midasResult == null) {
      debugPrint('MetricDepthService: MiDaS failed');
      return null;
    }

    // 2. Periodically run stereo for calibration
    final shouldRunStereo = _frameCount % _stereoCalibrationInterval == 0;

    if (shouldRunStereo) {
      debugPrint('MetricDepthService: Running stereo calibration (frame $_frameCount)');
      if (_parallelCalibration) {
        // Run stereo in parallel (don't await, let it update calibration async)
        _runStereoCalibration(stereoPair, midasResult);
      } else {
        // Run stereo synchronously
        await _runStereoCalibration(stereoPair, midasResult);
      }
    }

    // 3. Convert MiDaS to metric depth using calibration
    final metricDepth = _calibrationService.convertToMetricDepth(midasResult);

    stopwatch.stop();

    return MetricDepthResult(
      metricDepth: metricDepth,
      midasDepth: midasResult.rawDepth,
      colorizedRgba: midasResult.colorizedRgba,
      width: midasResult.width,
      height: midasResult.height,
      isCalibrated: _calibrationService.isCalibrated,
      calibration: _calibrationService.calibration,
      processingTimeMs: stopwatch.elapsedMilliseconds.toDouble(),
    );
  }

  /// Run stereo depth and update calibration.
  Future<void> _runStereoCalibration(StereoFramePair stereoPair, DepthMapResult midasResult) async {
    try {
      debugPrint('MetricDepthService: Computing stereo depth (pair: ${stereoPair.width}x${stereoPair.height})');
      final stereoResult = await _stereoService.computeDepth(stereoPair);
      if (stereoResult == null) {
        debugPrint('MetricDepthService: Stereo computation returned null');
        return;
      }
      if (stereoResult.points.isEmpty) {
        debugPrint('MetricDepthService: Stereo found 0 points');
        return;
      }

      debugPrint('MetricDepthService: Stereo found ${stereoResult.points.length} points, scaling to MiDaS ${midasResult.width}x${midasResult.height}');

      // Scale stereo coordinates to match MiDaS resolution
      final scaledPoints = stereoResult.points.map((p) => StereoDepthPoint(
        x: (p.x * midasResult.width / stereoResult.imageWidth).round(),
        y: (p.y * midasResult.height / stereoResult.imageHeight).round(),
        disparity: p.disparity,
        depthMeters: p.depthMeters,
        confidence: p.confidence,
      )).toList();

      _calibrationService.addCalibrationPoints(
        midasDepth: midasResult,
        stereoPoints: scaledPoints,
      );
    } catch (e, stack) {
      debugPrint('MetricDepthService: Stereo calibration error: $e');
      debugPrint('MetricDepthService: Stack: $stack');
    }
  }

  /// Estimate metric depth from a single image (no stereo calibration update).
  ///
  /// Uses existing calibration if available.
  Future<MetricDepthResult?> estimateDepthFromImage(Uint8List imageBytes) async {
    if (!_isInitialized) return null;

    final stopwatch = Stopwatch()..start();

    final midasResult = await _midasService.estimateDepthFromImage(imageBytes);
    if (midasResult == null) return null;

    final metricDepth = _calibrationService.convertToMetricDepth(midasResult);

    stopwatch.stop();

    return MetricDepthResult(
      metricDepth: metricDepth,
      midasDepth: midasResult.rawDepth,
      colorizedRgba: midasResult.colorizedRgba,
      width: midasResult.width,
      height: midasResult.height,
      isCalibrated: _calibrationService.isCalibrated,
      calibration: _calibrationService.calibration,
      processingTimeMs: stopwatch.elapsedMilliseconds.toDouble(),
    );
  }

  /// Force a stereo calibration update on next frame.
  void triggerCalibration() {
    // Set frame count to trigger calibration on next estimateDepth call
    _frameCount = _stereoCalibrationInterval - 1;
  }

  /// Reset calibration (e.g., when camera setup changes).
  void resetCalibration() {
    _calibrationService.reset();
    _frameCount = 0;
  }

  /// Update stereo camera parameters.
  void updateCameraParameters({
    double? baselineMeters,
    double? focalLengthPixels,
  }) {
    if (baselineMeters != null) {
      _stereoService.baselineMeters = baselineMeters;
    }
    if (focalLengthPixels != null) {
      _stereoService.focalLengthPixels = focalLengthPixels;
    }
    // Reset calibration since camera parameters changed
    resetCalibration();
  }

  /// Dispose of resources.
  void dispose() {
    debugPrint('MetricDepthService: Disposing...');
    _midasService.dispose();
    _calibrationService.reset();
    _isInitialized = false;
    _frameCount = 0;
    debugPrint('MetricDepthService: Disposed');
  }
}
