import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'stereo_depth_service.dart';
import 'depth_map_service.dart';

/// Calibration parameters for converting MiDaS inverse depth to metric depth.
///
/// Model: 1/depth_metric = scale * d_midas + shift
/// Or equivalently: depth_metric = 1 / (scale * d_midas + shift)
class DepthCalibration {
  final double scale;
  final double shift;
  final int numPoints;       // Number of points used for calibration
  final double fitError;     // RMS error of the fit
  final DateTime timestamp;

  DepthCalibration({
    required this.scale,
    required this.shift,
    required this.numPoints,
    required this.fitError,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Convert MiDaS inverse depth to metric depth in meters.
  double toMetricDepth(double midasValue) {
    final inverseDepth = scale * midasValue + shift;
    if (inverseDepth <= 0) return double.infinity;
    return 1.0 / inverseDepth;
  }

  /// Check if calibration is valid and recent.
  bool get isValid => scale > 0 && numPoints >= 10 && fitError < 0.5;

  @override
  String toString() => 'DepthCalibration(s=$scale, t=$shift, n=$numPoints, err=$fitError)';
}

/// Service for calibrating MiDaS depth to metric scale using stereo depth.
///
/// Collects corresponding points from MiDaS and stereo depth, then solves
/// for scale and shift parameters using least squares regression.
///
/// The calibration model is:
///   1/depth_metric = scale * midas_inverse_depth + shift
///
/// This aligns MiDaS's smooth but relative depth map to the real-world
/// metric scale provided by stereo disparity.
class DepthCalibrationService {
  // Current calibration
  DepthCalibration? _calibration;

  // Running statistics for incremental updates
  final List<_CalibrationPoint> _recentPoints = [];
  static const int _maxRecentPoints = 200;
  static const int _minPointsForCalibration = 20;

  // Exponential moving average for smooth calibration updates
  double? _emaScale;
  double? _emaShift;
  static const double _emaAlpha = 0.1; // Smoothing factor

  /// Current calibration (null if not yet calibrated).
  DepthCalibration? get calibration => _calibration;

  /// Whether we have a valid calibration.
  bool get isCalibrated => _calibration?.isValid ?? false;

  /// Add calibration points from a frame's MiDaS and stereo depth.
  ///
  /// [midasDepth] - MiDaS depth map result
  /// [stereoPoints] - Sparse stereo depth points
  /// [minConfidence] - Minimum stereo confidence to use a point
  void addCalibrationPoints({
    required DepthMapResult midasDepth,
    required List<StereoDepthPoint> stereoPoints,
    double minConfidence = 0.6,
  }) {
    if (midasDepth.rawDepth.isEmpty || stereoPoints.isEmpty) return;

    final reliablePoints = stereoPoints.where((p) => p.confidence >= minConfidence).toList();
    if (reliablePoints.isEmpty) return;

    for (final stereoPoint in reliablePoints) {
      // Map stereo point coordinates to MiDaS depth map coordinates
      // Stereo and MiDaS may have different resolutions
      final midasX = (stereoPoint.x * midasDepth.width / stereoPoints.first.x.toDouble())
          .round()
          .clamp(0, midasDepth.width - 1);
      final midasY = (stereoPoint.y * midasDepth.height / stereoPoints.first.y.toDouble())
          .round()
          .clamp(0, midasDepth.height - 1);

      // Get MiDaS value at this location (sample a small region for robustness)
      final midasValue = _sampleMidasRegion(midasDepth, midasX, midasY);
      if (midasValue <= 0) continue;

      // Skip invalid stereo depths
      if (stereoPoint.depthMeters <= 0 || stereoPoint.depthMeters > 15) continue;

      _recentPoints.add(_CalibrationPoint(
        midasValue: midasValue,
        metricDepth: stereoPoint.depthMeters,
        confidence: stereoPoint.confidence,
      ));
    }

    // Trim old points
    while (_recentPoints.length > _maxRecentPoints) {
      _recentPoints.removeAt(0);
    }

    // Update calibration if we have enough points
    if (_recentPoints.length >= _minPointsForCalibration) {
      _updateCalibration();
    }
  }

  /// Sample MiDaS depth in a small region around a point (for robustness).
  double _sampleMidasRegion(DepthMapResult depth, int x, int y, {int radius = 2}) {
    double sum = 0;
    int count = 0;

    for (int dy = -radius; dy <= radius; dy++) {
      for (int dx = -radius; dx <= radius; dx++) {
        final px = (x + dx).clamp(0, depth.width - 1);
        final py = (y + dy).clamp(0, depth.height - 1);
        final idx = py * depth.width + px;
        if (idx < depth.rawDepth.length) {
          sum += depth.rawDepth[idx];
          count++;
        }
      }
    }

    return count > 0 ? sum / count : 0;
  }

  /// Update calibration using least squares on recent points.
  void _updateCalibration() {
    if (_recentPoints.length < _minPointsForCalibration) return;

    // Prepare data for linear regression
    // Model: y = s*x + t where y = 1/Z_metric, x = d_midas
    final n = _recentPoints.length;
    double sumX = 0, sumY = 0, sumXY = 0, sumX2 = 0;
    double sumW = 0; // For weighted regression

    for (final point in _recentPoints) {
      final x = point.midasValue;
      final y = 1.0 / point.metricDepth; // Inverse depth
      final w = point.confidence; // Weight by confidence

      sumX += w * x;
      sumY += w * y;
      sumXY += w * x * y;
      sumX2 += w * x * x;
      sumW += w;
    }

    // Solve normal equations (weighted least squares)
    final denom = sumW * sumX2 - sumX * sumX;
    if (denom.abs() < 1e-10) {
      debugPrint('DepthCalibrationService: Degenerate case, cannot solve');
      return;
    }

    final scale = (sumW * sumXY - sumX * sumY) / denom;
    final shift = (sumY - scale * sumX) / sumW;

    // Validate the result
    if (scale <= 0) {
      debugPrint('DepthCalibrationService: Invalid scale $scale, skipping');
      return;
    }

    // Compute fit error (RMS)
    double sumSqError = 0;
    for (final point in _recentPoints) {
      final predicted = scale * point.midasValue + shift;
      final actual = 1.0 / point.metricDepth;
      sumSqError += pow(predicted - actual, 2);
    }
    final rmsError = sqrt(sumSqError / n);

    // Apply exponential moving average for smooth updates
    if (_emaScale == null || _emaShift == null) {
      _emaScale = scale;
      _emaShift = shift;
    } else {
      _emaScale = _emaAlpha * scale + (1 - _emaAlpha) * _emaScale!;
      _emaShift = _emaAlpha * shift + (1 - _emaAlpha) * _emaShift!;
    }

    _calibration = DepthCalibration(
      scale: _emaScale!,
      shift: _emaShift!,
      numPoints: n,
      fitError: rmsError,
    );

    debugPrint('DepthCalibrationService: Updated calibration - $_calibration');
  }

  /// Convert a full MiDaS depth map to metric depth.
  ///
  /// Returns a new Float32List with metric depths in meters.
  /// Pixels where conversion fails return infinity.
  Float32List convertToMetricDepth(DepthMapResult midasDepth) {
    final result = Float32List(midasDepth.rawDepth.length);

    if (_calibration == null) {
      // No calibration - return raw MiDaS values (won't be metric)
      for (int i = 0; i < result.length; i++) {
        result[i] = midasDepth.rawDepth[i];
      }
      return result;
    }

    final cal = _calibration!;
    for (int i = 0; i < midasDepth.rawDepth.length; i++) {
      result[i] = cal.toMetricDepth(midasDepth.rawDepth[i]);
    }

    return result;
  }

  /// Get metric depth at a specific point in the depth map.
  double getMetricDepthAt(DepthMapResult midasDepth, int x, int y) {
    if (x < 0 || x >= midasDepth.width || y < 0 || y >= midasDepth.height) {
      return double.infinity;
    }

    final idx = y * midasDepth.width + x;
    if (idx >= midasDepth.rawDepth.length) return double.infinity;

    final midasValue = midasDepth.rawDepth[idx];
    return _calibration?.toMetricDepth(midasValue) ?? midasValue;
  }

  /// Reset calibration and clear all points.
  void reset() {
    _calibration = null;
    _recentPoints.clear();
    _emaScale = null;
    _emaShift = null;
    debugPrint('DepthCalibrationService: Reset');
  }

  /// Force recalibration with current points.
  void recalibrate() {
    if (_recentPoints.length >= _minPointsForCalibration) {
      _emaScale = null; // Reset EMA to use fresh values
      _emaShift = null;
      _updateCalibration();
    }
  }
}

class _CalibrationPoint {
  final double midasValue;
  final double metricDepth;
  final double confidence;

  _CalibrationPoint({
    required this.midasValue,
    required this.metricDepth,
    required this.confidence,
  });
}
