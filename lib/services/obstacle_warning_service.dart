import 'package:flutter/foundation.dart';
import 'depth_map_service.dart';
import 'metric_depth_service.dart';
import '../models/detected_object.dart';
import 'tts_service.dart';

/// Angular sector for obstacle positioning
enum ObstacleSector {
  farLeft,    // -60° to -40°
  left,       // -40° to -20°
  centerLeft, // -20° to -7°
  center,     // -7° to +7°
  centerRight,// +7° to +20°
  right,      // +20° to +40°
  farRight,   // +40° to +60°
}

extension ObstacleSectorExtension on ObstacleSector {
  String get announcement {
    switch (this) {
      case ObstacleSector.farLeft:
        return 'far left';
      case ObstacleSector.left:
        return 'to your left';
      case ObstacleSector.centerLeft:
        return 'ahead left';
      case ObstacleSector.center:
        return 'directly ahead';
      case ObstacleSector.centerRight:
        return 'ahead right';
      case ObstacleSector.right:
        return 'to your right';
      case ObstacleSector.farRight:
        return 'far right';
    }
  }

  /// Approximate angle from center (degrees)
  double get approximateAngle {
    switch (this) {
      case ObstacleSector.farLeft:
        return -50;
      case ObstacleSector.left:
        return -30;
      case ObstacleSector.centerLeft:
        return -13;
      case ObstacleSector.center:
        return 0;
      case ObstacleSector.centerRight:
        return 13;
      case ObstacleSector.right:
        return 30;
      case ObstacleSector.farRight:
        return 50;
    }
  }
}

/// Proximity level for obstacles
enum ProximityLevel {
  touching,   // < 1m - STOP!
  veryClose,  // 1-2m - Warning
  close,      // 2-4m - Caution
  moderate,   // 4-6m - Info
  far,        // > 6m - No warning
}

extension ProximityLevelExtension on ProximityLevel {
  /// Only warn for obstacles < 1 meter (touching level)
  bool get requiresWarning => this == ProximityLevel.touching;

  /// Only touching (< 1m) is considered critical
  bool get isCritical => this == ProximityLevel.touching;

  String get prefix {
    switch (this) {
      case ProximityLevel.touching:
        return 'Stop!';
      case ProximityLevel.veryClose:
        return ''; // No warning spoken for 1-2m
      case ProximityLevel.close:
        return ''; // No warning spoken for 2-4m
      case ProximityLevel.moderate:
        return '';
      case ProximityLevel.far:
        return '';
    }
  }
}

/// A detected obstacle with position and identity
class SpatialObstacle {
  final ObstacleSector sector;
  final ProximityLevel proximity;
  final String? objectName; // From YOLO, null if unknown
  final double normalizedDepth; // 0.0 = far, 1.0 = touching (relative mode)
  final double? distanceMeters; // Actual distance in meters (metric mode)
  final double confidence;

  SpatialObstacle({
    required this.sector,
    required this.proximity,
    this.objectName,
    required this.normalizedDepth,
    this.distanceMeters,
    this.confidence = 1.0,
  });

  /// Human-friendly announcement of the obstacle.
  /// Includes distance in meters when available (metric mode).
  String get announcement {
    final prefix = proximity.prefix;
    final name = objectName ?? 'obstacle';
    final position = sector.announcement;

    // Include distance if we have metric depth
    String distanceStr = '';
    if (distanceMeters != null && distanceMeters! < 10) {
      final meters = distanceMeters!;
      if (meters < 1) {
        distanceStr = ' ${(meters * 100).round()} centimeters';
      } else {
        distanceStr = ' ${meters.toStringAsFixed(1)} meters';
      }
    }

    if (prefix.isNotEmpty) {
      return '$prefix $name$distanceStr $position';
    }
    return '$name$distanceStr $position';
  }

  @override
  String toString() => 'SpatialObstacle($objectName @ $sector, $proximity, '
      'depth=$normalizedDepth${distanceMeters != null ? ", ${distanceMeters!.toStringAsFixed(2)}m" : ""})';
}

/// Result of obstacle analysis
class ObstacleAnalysisResult {
  final List<SpatialObstacle> obstacles;
  final bool pathBlocked;
  final String? suggestedAction;
  final List<double> sectorDepths; // Closest depth per sector (7 values)
  final List<double>? sectorDistancesMeters; // Metric distances per sector (null if uncalibrated)
  final bool isMetricCalibrated; // Whether depths are in real meters

  ObstacleAnalysisResult({
    required this.obstacles,
    required this.pathBlocked,
    this.suggestedAction,
    required this.sectorDepths,
    this.sectorDistancesMeters,
    this.isMetricCalibrated = false,
  });
}

/// Service that analyzes depth map and YOLO detections to produce spatial obstacle warnings.
///
/// Key features:
/// - Squashes depth map vertically to get horizontal distance profile
/// - Divides view into 7 angular sectors
/// - Combines with YOLO to identify obstacle types
/// - Manages warning cooldowns to avoid spam
/// - Supports both relative (MiDaS) and metric (calibrated) depth modes
class ObstacleWarningService {
  final TtsService _ttsService;

  // Configuration
  static const int numSectors = 7;
  static const double fovDegrees = 120.0; // Assumed horizontal FOV
  static const double groundPlaneRatio = 0.7; // Use bottom 70% to avoid sky

  // Relative depth thresholds (for uncalibrated MiDaS)
  // Higher value = closer (MiDaS inverse depth, normalized 0-1)
  static const double touchingThreshold = 0.92;
  static const double veryCloseThreshold = 0.80;
  static const double closeThreshold = 0.65;
  static const double moderateThreshold = 0.50;

  // Metric distance thresholds (in meters, for calibrated depth)
  // Lower value = closer
  static const double touchingDistanceM = 1.0;    // < 1m - STOP!
  static const double veryCloseDistanceM = 2.0;   // 1-2m - Warning
  static const double closeDistanceM = 4.0;       // 2-4m - Caution
  static const double moderateDistanceM = 6.0;    // 4-6m - Info

  // Warning cooldowns per sector to avoid spam
  final Map<ObstacleSector, DateTime> _lastWarningTime = {};
  static const Duration criticalCooldown = Duration(seconds: 2);
  static const Duration normalCooldown = Duration(seconds: 5);
  static const Duration infoCooldown = Duration(seconds: 10);

  // Track last spoken warning to avoid exact repeats
  String? _lastWarningMessage;
  DateTime? _lastWarningMessageTime;

  ObstacleWarningService({required TtsService ttsService}) : _ttsService = ttsService;

  /// Analyze depth map and detections to find obstacles
  ObstacleAnalysisResult analyzeFrame({
    required DepthMapResult depthMap,
    List<DetectedObject>? detections,
  }) {
    if (depthMap.rawDepth.isEmpty) {
      return ObstacleAnalysisResult(
        obstacles: [],
        pathBlocked: false,
        sectorDepths: List.filled(numSectors, 0.0),
      );
    }

    // 1. Find max depth in scene (closest point in MiDaS)
    double maxSceneDepth = 0;
    for (var val in depthMap.rawDepth) {
      if (val > maxSceneDepth) maxSceneDepth = val;
    }

    if (maxSceneDepth == 0) {
      return ObstacleAnalysisResult(
        obstacles: [],
        pathBlocked: false,
        sectorDepths: List.filled(numSectors, 0.0),
      );
    }

    // 2. Squash depth map vertically - get max (closest) depth per column
    //    Only consider ground plane (bottom portion of image)
    final columnDepths = _squashDepthVertically(depthMap, maxSceneDepth);

    // 3. Aggregate columns into sectors
    final sectorDepths = _aggregateIntoSectors(columnDepths);

    // 4. Determine proximity level per sector
    final sectorProximities = sectorDepths.map(_depthToProximity).toList();

    // 5. Create obstacles from sectors with significant depth
    final obstacles = <SpatialObstacle>[];
    for (int i = 0; i < numSectors; i++) {
      final sector = ObstacleSector.values[i];
      final proximity = sectorProximities[i];

      if (proximity.requiresWarning) {
        // Try to find a YOLO detection in this sector
        String? objectName;
        double confidence = 1.0;

        if (detections != null && detections.isNotEmpty) {
          final detection = _findDetectionInSector(detections, sector);
          if (detection != null) {
            objectName = detection.className;
            confidence = detection.confidence;
          }
        }

        obstacles.add(SpatialObstacle(
          sector: sector,
          proximity: proximity,
          objectName: objectName,
          normalizedDepth: sectorDepths[i],
          confidence: confidence,
        ));
      }
    }

    // Sort by proximity (most critical first)
    obstacles.sort((a, b) => b.normalizedDepth.compareTo(a.normalizedDepth));

    // 6. Check if center path is blocked
    final centerProximity = sectorProximities[3]; // Center sector
    final centerLeftProximity = sectorProximities[2];
    final centerRightProximity = sectorProximities[4];

    final pathBlocked = centerProximity == ProximityLevel.touching ||
        (centerProximity == ProximityLevel.veryClose &&
         centerLeftProximity.isCritical &&
         centerRightProximity.isCritical);

    // 7. Suggest action
    String? suggestedAction;
    if (pathBlocked) {
      // Find clearest direction
      final leftClear = sectorDepths[0] + sectorDepths[1];
      final rightClear = sectorDepths[5] + sectorDepths[6];

      if (leftClear < rightClear - 0.1) {
        suggestedAction = 'Move left';
      } else if (rightClear < leftClear - 0.1) {
        suggestedAction = 'Move right';
      } else {
        suggestedAction = 'Stop and assess';
      }
    }

    return ObstacleAnalysisResult(
      obstacles: obstacles,
      pathBlocked: pathBlocked,
      suggestedAction: suggestedAction,
      sectorDepths: sectorDepths,
    );
  }

  /// Analyze metric depth map and detections to find obstacles.
  ///
  /// This method uses calibrated metric depth in meters for accurate
  /// distance-based warnings. Falls back to relative mode if uncalibrated.
  ObstacleAnalysisResult analyzeMetricFrame({
    required MetricDepthResult depthResult,
    List<DetectedObject>? detections,
  }) {
    // If not calibrated, fall back to relative depth analysis
    if (!depthResult.isCalibrated) {
      // Create a DepthMapResult from the MiDaS data for backward compatibility
      final depthMap = DepthMapResult(
        rawDepth: depthResult.midasDepth,
        colorizedRgba: depthResult.colorizedRgba,
        width: depthResult.width,
        height: depthResult.height,
        processingTimeMs: depthResult.processingTimeMs,
      );
      return analyzeFrame(depthMap: depthMap, detections: detections);
    }

    if (depthResult.metricDepth.isEmpty) {
      return ObstacleAnalysisResult(
        obstacles: [],
        pathBlocked: false,
        sectorDepths: List.filled(numSectors, 0.0),
        isMetricCalibrated: true,
      );
    }

    // 1. Squash depth map vertically - get minimum (closest) metric depth per column
    //    Only consider ground plane (bottom portion of image)
    final columnDistances = _squashMetricDepthVertically(depthResult);

    // 2. Aggregate columns into sectors (get minimum distance per sector)
    final sectorDistances = _aggregateMetricIntoSectors(columnDistances);

    // 3. Determine proximity level per sector based on metric distance
    final sectorProximities = sectorDistances.map(_distanceToProximity).toList();

    // 4. Create obstacles from sectors with close objects
    final obstacles = <SpatialObstacle>[];
    for (int i = 0; i < numSectors; i++) {
      final sector = ObstacleSector.values[i];
      final proximity = sectorProximities[i];

      if (proximity.requiresWarning) {
        // Try to find a YOLO detection in this sector
        String? objectName;
        double confidence = 1.0;

        if (detections != null && detections.isNotEmpty) {
          final detection = _findDetectionInSector(detections, sector);
          if (detection != null) {
            objectName = detection.className;
            confidence = detection.confidence;
          }
        }

        // Convert distance to normalized depth for compatibility (inverse relationship)
        // Closer = higher normalized depth
        final normalizedDepth = sectorDistances[i] > 0
            ? (1.0 - (sectorDistances[i] / moderateDistanceM)).clamp(0.0, 1.0)
            : 1.0;

        obstacles.add(SpatialObstacle(
          sector: sector,
          proximity: proximity,
          objectName: objectName,
          normalizedDepth: normalizedDepth,
          distanceMeters: sectorDistances[i],
          confidence: confidence,
        ));
      }
    }

    // Sort by distance (closest first)
    obstacles.sort((a, b) => (a.distanceMeters ?? double.infinity)
        .compareTo(b.distanceMeters ?? double.infinity));

    // 5. Check if center path is blocked
    final centerProximity = sectorProximities[3]; // Center sector
    final centerLeftProximity = sectorProximities[2];
    final centerRightProximity = sectorProximities[4];

    final pathBlocked = centerProximity == ProximityLevel.touching ||
        (centerProximity == ProximityLevel.veryClose &&
         centerLeftProximity.isCritical &&
         centerRightProximity.isCritical);

    // 6. Suggest action based on which direction has more clearance
    String? suggestedAction;
    if (pathBlocked) {
      // Find direction with furthest obstacles (more clearance)
      final leftClearance = (sectorDistances[0] + sectorDistances[1]) / 2;
      final rightClearance = (sectorDistances[5] + sectorDistances[6]) / 2;

      if (leftClearance > rightClearance + 0.5) {
        suggestedAction = 'Move left';
      } else if (rightClearance > leftClearance + 0.5) {
        suggestedAction = 'Move right';
      } else {
        suggestedAction = 'Stop and assess';
      }
    }

    return ObstacleAnalysisResult(
      obstacles: obstacles,
      pathBlocked: pathBlocked,
      suggestedAction: suggestedAction,
      sectorDepths: sectorDistances, // In metric mode, these are distances
      sectorDistancesMeters: sectorDistances,
      isMetricCalibrated: true,
    );
  }

  /// Squash metric depth map vertically, returning minimum (closest) distance per column
  List<double> _squashMetricDepthVertically(MetricDepthResult depthResult) {
    final numColumns = depthResult.width;
    final columnDistances = List<double>.filled(numColumns, double.infinity);

    // Only look at ground plane (bottom portion)
    final startY = (depthResult.height * (1 - groundPlaneRatio)).round();

    for (int x = 0; x < numColumns; x++) {
      double minDistance = double.infinity;

      for (int y = startY; y < depthResult.height; y += 2) { // Skip every other row for speed
        final idx = y * depthResult.width + x;
        if (idx < depthResult.metricDepth.length) {
          final distance = depthResult.metricDepth[idx];
          if (distance > 0 && distance < minDistance) {
            minDistance = distance;
          }
        }
      }

      columnDistances[x] = minDistance;
    }

    return columnDistances;
  }

  /// Aggregate column distances into sector distances (minimum per sector)
  List<double> _aggregateMetricIntoSectors(List<double> columnDistances) {
    final numColumns = columnDistances.length;
    final sectorDistances = List<double>.filled(numSectors, double.infinity);

    final sectorBoundaries = [0.0, 0.12, 0.27, 0.42, 0.58, 0.73, 0.88, 1.0];

    for (int s = 0; s < numSectors; s++) {
      final startCol = (sectorBoundaries[s] * numColumns).round();
      final endCol = (sectorBoundaries[s + 1] * numColumns).round();

      double minSectorDistance = double.infinity;
      for (int c = startCol; c < endCol && c < numColumns; c++) {
        if (columnDistances[c] < minSectorDistance) {
          minSectorDistance = columnDistances[c];
        }
      }

      sectorDistances[s] = minSectorDistance;
    }

    return sectorDistances;
  }

  /// Convert metric distance to proximity level
  ProximityLevel _distanceToProximity(double distanceMeters) {
    if (distanceMeters <= touchingDistanceM) return ProximityLevel.touching;
    if (distanceMeters <= veryCloseDistanceM) return ProximityLevel.veryClose;
    if (distanceMeters <= closeDistanceM) return ProximityLevel.close;
    if (distanceMeters <= moderateDistanceM) return ProximityLevel.moderate;
    return ProximityLevel.far;
  }

  /// Squash depth map vertically, returning max (closest) depth per column
  List<double> _squashDepthVertically(DepthMapResult depthMap, double maxSceneDepth) {
    final numColumns = depthMap.width;
    final columnDepths = List<double>.filled(numColumns, 0.0);

    // Only look at ground plane (bottom portion)
    final startY = (depthMap.height * (1 - groundPlaneRatio)).round();

    for (int x = 0; x < numColumns; x++) {
      double maxColDepth = 0;

      for (int y = startY; y < depthMap.height; y += 2) { // Skip every other row for speed
        final idx = y * depthMap.width + x;
        if (idx < depthMap.rawDepth.length) {
          final depth = depthMap.rawDepth[idx];
          if (depth > maxColDepth) maxColDepth = depth;
        }
      }

      // Normalize to 0-1 range
      columnDepths[x] = maxColDepth / maxSceneDepth;
    }

    return columnDepths;
  }

  /// Aggregate column depths into sector depths
  List<double> _aggregateIntoSectors(List<double> columnDepths) {
    final numColumns = columnDepths.length;
    final sectorDepths = List<double>.filled(numSectors, 0.0);

    // Sector boundaries (as fractions of image width)
    // Maps to roughly: farLeft(-60 to -40), left(-40 to -20), centerLeft(-20 to -7),
    // center(-7 to +7), centerRight(+7 to +20), right(+20 to +40), farRight(+40 to +60)
    final sectorBoundaries = [0.0, 0.12, 0.27, 0.42, 0.58, 0.73, 0.88, 1.0];

    for (int s = 0; s < numSectors; s++) {
      final startCol = (sectorBoundaries[s] * numColumns).round();
      final endCol = (sectorBoundaries[s + 1] * numColumns).round();

      double maxSectorDepth = 0;
      for (int c = startCol; c < endCol && c < numColumns; c++) {
        if (columnDepths[c] > maxSectorDepth) {
          maxSectorDepth = columnDepths[c];
        }
      }

      sectorDepths[s] = maxSectorDepth;
    }

    return sectorDepths;
  }

  /// Convert normalized depth to proximity level
  ProximityLevel _depthToProximity(double normalizedDepth) {
    if (normalizedDepth >= touchingThreshold) return ProximityLevel.touching;
    if (normalizedDepth >= veryCloseThreshold) return ProximityLevel.veryClose;
    if (normalizedDepth >= closeThreshold) return ProximityLevel.close;
    if (normalizedDepth >= moderateThreshold) return ProximityLevel.moderate;
    return ProximityLevel.far;
  }

  /// Find a YOLO detection that falls within the given sector
  DetectedObject? _findDetectionInSector(List<DetectedObject> detections, ObstacleSector sector) {
    // Sector boundaries (as fractions of image width)
    final sectorBoundaries = [0.0, 0.12, 0.27, 0.42, 0.58, 0.73, 0.88, 1.0];
    final sectorIndex = sector.index;
    final startX = sectorBoundaries[sectorIndex];
    final endX = sectorBoundaries[sectorIndex + 1];

    // Find detection whose center falls in this sector
    for (final detection in detections) {
      final centerX = detection.boundingBox.center.dx;
      if (centerX >= startX && centerX < endX) {
        return detection;
      }
    }

    return null;
  }

  /// Speak warnings for detected obstacles (with cooldown management)
  void speakWarnings(ObstacleAnalysisResult result) {
    if (result.obstacles.isEmpty && !result.pathBlocked) return;

    final now = DateTime.now();

    // Priority 1: Path blocked - always warn
    if (result.pathBlocked) {
      final message = result.suggestedAction != null
          ? 'Path blocked! ${result.suggestedAction}'
          : 'Stop! Path blocked';
      _speakWithCooldown(message, criticalCooldown, now);
      return;
    }

    // Priority 2: Critical obstacles (touching/very close)
    final criticalObstacles = result.obstacles.where((o) => o.proximity.isCritical).toList();
    if (criticalObstacles.isNotEmpty) {
      final obstacle = criticalObstacles.first;
      if (_canWarnForSector(obstacle.sector, criticalCooldown, now)) {
        _speak(obstacle.announcement);
        _lastWarningTime[obstacle.sector] = now;
      }
      return;
    }

    // Priority 3: Close obstacles
    final closeObstacles = result.obstacles.where((o) => o.proximity == ProximityLevel.close).toList();
    if (closeObstacles.isNotEmpty) {
      final obstacle = closeObstacles.first;
      if (_canWarnForSector(obstacle.sector, normalCooldown, now)) {
        _speak(obstacle.announcement);
        _lastWarningTime[obstacle.sector] = now;
      }
      return;
    }

    // Priority 4: Moderate obstacles (only if center)
    final centerObstacles = result.obstacles.where(
      (o) => o.proximity == ProximityLevel.moderate &&
             (o.sector == ObstacleSector.center ||
              o.sector == ObstacleSector.centerLeft ||
              o.sector == ObstacleSector.centerRight)
    ).toList();

    if (centerObstacles.isNotEmpty) {
      final obstacle = centerObstacles.first;
      if (_canWarnForSector(obstacle.sector, infoCooldown, now)) {
        _speak(obstacle.announcement);
        _lastWarningTime[obstacle.sector] = now;
      }
    }
  }

  bool _canWarnForSector(ObstacleSector sector, Duration cooldown, DateTime now) {
    final lastTime = _lastWarningTime[sector];
    if (lastTime == null) return true;
    return now.difference(lastTime) >= cooldown;
  }

  void _speakWithCooldown(String message, Duration cooldown, DateTime now) {
    if (_lastWarningMessage == message &&
        _lastWarningMessageTime != null &&
        now.difference(_lastWarningMessageTime!) < cooldown) {
      return;
    }
    _speak(message);
    _lastWarningMessage = message;
    _lastWarningMessageTime = now;
  }

  void _speak(String message) {
    debugPrint('ObstacleWarning: $message');
    _ttsService.speak(message);
  }

  /// Reset cooldowns (e.g., when navigation restarts)
  void reset() {
    _lastWarningTime.clear();
    _lastWarningMessage = null;
    _lastWarningMessageTime = null;
  }
}
