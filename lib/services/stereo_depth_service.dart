import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'stereo_video_source.dart';

/// A sparse depth point from stereo matching.
class StereoDepthPoint {
  final int x;              // X coordinate in image
  final int y;              // Y coordinate in image
  final double disparity;   // Disparity in pixels (left - right x position)
  final double depthMeters; // Computed depth in meters
  final double confidence;  // Match confidence (0-1, higher is better)

  StereoDepthPoint({
    required this.x,
    required this.y,
    required this.disparity,
    required this.depthMeters,
    required this.confidence,
  });

  @override
  String toString() => 'StereoDepthPoint($x,$y d=$disparity z=${depthMeters.toStringAsFixed(2)}m conf=${confidence.toStringAsFixed(2)})';
}

/// Result from stereo depth computation.
class StereoDepthResult {
  final List<StereoDepthPoint> points;
  final int imageWidth;
  final int imageHeight;
  final double processingTimeMs;

  StereoDepthResult({
    required this.points,
    required this.imageWidth,
    required this.imageHeight,
    required this.processingTimeMs,
  });

  /// Get reliable points (above confidence threshold).
  List<StereoDepthPoint> getReliablePoints({double minConfidence = 0.7}) {
    return points.where((p) => p.confidence >= minConfidence).toList();
  }
}

/// Service for computing metric depth from stereo image pairs.
///
/// Uses block matching to find correspondences between left and right images,
/// then converts disparity to metric depth using:
///   depth = (focal_length * baseline) / disparity
///
/// Camera parameters:
/// - baseline: Distance between cameras (default 65mm = 0.065m)
/// - focalLengthPixels: Focal length in pixels (depends on camera/resolution)
///
/// Pi Camera Module v2 specifications (for reference):
/// - Sensor: Sony IMX219 (3.68mm × 2.76mm)
/// - Focal length: 3.04mm
/// - To compute focal length in pixels: (3.04 * image_width) / 3.68
class StereoDepthService {
  // Pi Camera Module v2 constants
  static const double piCamV2FocalLengthMm = 3.04;
  static const double piCamV2SensorWidthMm = 3.68;

  // Camera parameters (configurable)
  double _baselineMeters;
  double _focalLengthPixels;

  // Block matching parameters
  final int _blockSize;
  final int _searchRange;  // Max disparity to search (pixels)
  final int _gridSpacing;  // Spacing between sample points

  // Minimum disparity threshold (to filter out infinite depths)
  final double _minDisparity;

  StereoDepthService({
    double baselineMeters = 0.065,    // 65mm
    double focalLengthPixels = 500.0, // Approximate for 720p, will be calibrated
    int blockSize = 15,               // Block size for matching
    int searchRange = 64,             // Max disparity search range
    int gridSpacing = 20,             // Sample every N pixels
    double minDisparity = 2.0,        // Minimum valid disparity
  }) : _baselineMeters = baselineMeters,
       _focalLengthPixels = focalLengthPixels,
       _blockSize = blockSize,
       _searchRange = searchRange,
       _gridSpacing = gridSpacing,
       _minDisparity = minDisparity;

  /// Get/set baseline in meters
  double get baselineMeters => _baselineMeters;
  set baselineMeters(double value) => _baselineMeters = value;

  /// Get/set focal length in pixels
  double get focalLengthPixels => _focalLengthPixels;
  set focalLengthPixels(double value) => _focalLengthPixels = value;

  /// Compute focal length in pixels for Pi Camera Module v2 at given image width.
  ///
  /// Common values:
  /// - 1920px width → ~1586 pixels
  /// - 1280px width → ~1057 pixels
  /// - 640px width  → ~529 pixels
  static double computePiCamV2FocalLength(int imageWidth) {
    return (piCamV2FocalLengthMm * imageWidth) / piCamV2SensorWidthMm;
  }

  /// Auto-configure focal length based on image width (assumes Pi Camera v2).
  void autoConfigureFocalLength(int imageWidth) {
    _focalLengthPixels = computePiCamV2FocalLength(imageWidth);
    debugPrint('StereoDepthService: Auto-configured focal length to $_focalLengthPixels px for ${imageWidth}px width');
  }

  // Track if we've auto-configured focal length
  bool _focalLengthAutoConfigured = false;

  /// Compute sparse stereo depth from a stereo frame pair.
  ///
  /// Returns a list of depth points at a sparse grid of locations
  /// where reliable matches were found.
  Future<StereoDepthResult?> computeDepth(StereoFramePair stereoPair) async {
    final stopwatch = Stopwatch()..start();

    try {
      // Decode images
      final leftImage = img.decodeImage(stereoPair.leftImage);
      final rightImage = img.decodeImage(stereoPair.rightImage);

      if (leftImage == null || rightImage == null) {
        debugPrint('StereoDepthService: Failed to decode images');
        return null;
      }

      // Auto-configure focal length on first frame (assumes Pi Camera v2)
      if (!_focalLengthAutoConfigured) {
        autoConfigureFocalLength(leftImage.width);
        _focalLengthAutoConfigured = true;
      }

      // Convert to grayscale for matching
      final leftGray = img.grayscale(leftImage);
      final rightGray = img.grayscale(rightImage);

      final width = leftGray.width;
      final height = leftGray.height;

      // Extract pixel arrays for fast access
      final leftPixels = _extractGrayscalePixels(leftGray);
      final rightPixels = _extractGrayscalePixels(rightGray);

      final points = <StereoDepthPoint>[];
      final halfBlock = _blockSize ~/ 2;

      // Sample on a sparse grid
      for (int y = halfBlock + _gridSpacing; y < height - halfBlock - _gridSpacing; y += _gridSpacing) {
        for (int x = halfBlock + _searchRange; x < width - halfBlock; x += _gridSpacing) {
          // Find best match in right image
          final match = _findBestMatch(
            leftPixels, rightPixels,
            width, height,
            x, y,
          );

          if (match != null && match.disparity >= _minDisparity) {
            // Convert disparity to depth
            final depth = (_focalLengthPixels * _baselineMeters) / match.disparity;

            // Filter unreasonable depths (0.1m to 20m)
            if (depth >= 0.1 && depth <= 20.0) {
              points.add(StereoDepthPoint(
                x: x,
                y: y,
                disparity: match.disparity,
                depthMeters: depth,
                confidence: match.confidence,
              ));
            }
          }
        }
      }

      stopwatch.stop();
      final reliablePoints = points.where((p) => p.confidence >= 0.6).toList();
      debugPrint('StereoDepthService: Found ${points.length} points (${reliablePoints.length} reliable, conf>=0.6) in ${stopwatch.elapsedMilliseconds}ms');
      if (reliablePoints.isNotEmpty) {
        final avgDepth = reliablePoints.map((p) => p.depthMeters).reduce((a, b) => a + b) / reliablePoints.length;
        final avgDisp = reliablePoints.map((p) => p.disparity).reduce((a, b) => a + b) / reliablePoints.length;
        debugPrint('StereoDepthService: Avg depth=${avgDepth.toStringAsFixed(2)}m, avg disp=${avgDisp.toStringAsFixed(1)}px, focal=${_focalLengthPixels.toStringAsFixed(0)}px');
      }

      return StereoDepthResult(
        points: points,
        imageWidth: width,
        imageHeight: height,
        processingTimeMs: stopwatch.elapsedMilliseconds.toDouble(),
      );
    } catch (e, stack) {
      debugPrint('StereoDepthService: Error computing depth: $e');
      debugPrint('StereoDepthService: Stack: $stack');
      return null;
    }
  }

  /// Extract grayscale pixel values as a flat array for fast access.
  Uint8List _extractGrayscalePixels(img.Image image) {
    final pixels = Uint8List(image.width * image.height);
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        // For grayscale image, r=g=b
        pixels[y * image.width + x] = pixel.r.toInt();
      }
    }
    return pixels;
  }

  /// Find the best matching block in the right image using SAD (Sum of Absolute Differences).
  ///
  /// Returns null if no reliable match found.
  _MatchResult? _findBestMatch(
    Uint8List leftPixels,
    Uint8List rightPixels,
    int width,
    int height,
    int leftX,
    int leftY,
  ) {
    final halfBlock = _blockSize ~/ 2;

    // First check if the block has enough texture (variance)
    final leftVariance = _computeBlockVariance(leftPixels, width, leftX, leftY, halfBlock);
    if (leftVariance < 100) {
      // Low texture region - skip
      return null;
    }

    double bestSad = double.infinity;
    double secondBestSad = double.infinity;
    int bestDisparity = 0;

    // Search along epipolar line (same row, to the left in right image)
    // In a properly rectified stereo pair, matches are on the same row
    for (int d = 0; d <= _searchRange; d++) {
      final rightX = leftX - d;
      if (rightX < halfBlock) break;

      // Compute SAD for this disparity
      double sad = 0;
      for (int dy = -halfBlock; dy <= halfBlock; dy++) {
        for (int dx = -halfBlock; dx <= halfBlock; dx++) {
          final leftIdx = (leftY + dy) * width + (leftX + dx);
          final rightIdx = (leftY + dy) * width + (rightX + dx);
          sad += (leftPixels[leftIdx] - rightPixels[rightIdx]).abs();
        }
      }

      if (sad < bestSad) {
        secondBestSad = bestSad;
        bestSad = sad;
        bestDisparity = d;
      } else if (sad < secondBestSad) {
        secondBestSad = sad;
      }
    }

    // Check if match is reliable (best match significantly better than second best)
    if (bestDisparity == 0) return null;

    final uniquenessRatio = bestSad / secondBestSad;
    if (uniquenessRatio > 0.8) {
      // Match not unique enough
      return null;
    }

    // Sub-pixel refinement using parabola fitting
    double refinedDisparity = bestDisparity.toDouble();
    if (bestDisparity > 0 && bestDisparity < _searchRange) {
      final rightX = leftX - bestDisparity;

      // Get SAD at d-1, d, d+1
      final sadMinus = _computeSad(leftPixels, rightPixels, width, leftX, leftY, rightX + 1, halfBlock);
      final sadCenter = bestSad;
      final sadPlus = _computeSad(leftPixels, rightPixels, width, leftX, leftY, rightX - 1, halfBlock);

      // Parabola fitting for sub-pixel accuracy
      final denom = 2 * (sadMinus + sadPlus - 2 * sadCenter);
      if (denom.abs() > 0.001) {
        final offset = (sadMinus - sadPlus) / denom;
        refinedDisparity = bestDisparity + offset.clamp(-0.5, 0.5);
      }
    }

    // Compute confidence based on SAD and uniqueness
    final maxSad = _blockSize * _blockSize * 255.0;
    final normalizedSad = bestSad / maxSad;
    final sadConfidence = 1.0 - normalizedSad;
    final uniquenessConfidence = 1.0 - uniquenessRatio;
    final confidence = (sadConfidence * 0.5 + uniquenessConfidence * 0.5).clamp(0.0, 1.0);

    return _MatchResult(
      disparity: refinedDisparity,
      confidence: confidence,
    );
  }

  /// Compute variance of a block (to detect low-texture regions).
  double _computeBlockVariance(Uint8List pixels, int width, int x, int y, int halfBlock) {
    double sum = 0;
    double sumSq = 0;
    int count = 0;

    for (int dy = -halfBlock; dy <= halfBlock; dy++) {
      for (int dx = -halfBlock; dx <= halfBlock; dx++) {
        final idx = (y + dy) * width + (x + dx);
        final val = pixels[idx].toDouble();
        sum += val;
        sumSq += val * val;
        count++;
      }
    }

    final mean = sum / count;
    final variance = (sumSq / count) - (mean * mean);
    return variance;
  }

  /// Compute SAD between a block in left image and a position in right image.
  double _computeSad(
    Uint8List leftPixels,
    Uint8List rightPixels,
    int width,
    int leftX,
    int leftY,
    int rightX,
    int halfBlock,
  ) {
    double sad = 0;
    for (int dy = -halfBlock; dy <= halfBlock; dy++) {
      for (int dx = -halfBlock; dx <= halfBlock; dx++) {
        final leftIdx = (leftY + dy) * width + (leftX + dx);
        final rightIdx = (leftY + dy) * width + (rightX + dx);
        sad += (leftPixels[leftIdx] - rightPixels[rightIdx]).abs();
      }
    }
    return sad;
  }

  /// Estimate focal length from known object at known distance.
  ///
  /// If you have a calibration object at a known distance:
  ///   focal_length = disparity * distance / baseline
  void calibrateFocalLength({
    required double measuredDisparity,
    required double knownDistanceMeters,
  }) {
    _focalLengthPixels = (measuredDisparity * knownDistanceMeters) / _baselineMeters;
    debugPrint('StereoDepthService: Calibrated focal length to $_focalLengthPixels pixels');
  }
}

class _MatchResult {
  final double disparity;
  final double confidence;

  _MatchResult({required this.disparity, required this.confidence});
}
