import 'dart:typed_data';
import 'depth_map_service.dart';

enum PathSafety { clear, caution, blocked }

class WalkableCorridor {
  final double centerX; // 0.0-1.0 in frame (0.5 = center)
  final double widthRatio; // Corridor width as fraction of frame
  final double clearDistance; // Relative clear distance (0-1, higher = clearer)
  final int startColumn; // First clear column index
  final int endColumn; // Last clear column index

  WalkableCorridor({
    required this.centerX,
    required this.widthRatio,
    required this.clearDistance,
    required this.startColumn,
    required this.endColumn,
  });

  /// Is the corridor centered (within tolerance)?
  bool get isCentered => (centerX - 0.5).abs() < 0.15;

  /// Direction to veer: negative = left, positive = right, 0 = centered
  double get veerDirection => centerX - 0.5;
}

class SafePathResult {
  final WalkableCorridor? corridor;
  final PathSafety safety;
  final String? suggestedAction;
  final List<int> blockedColumns; // Indices of blocked columns
  final double overallClearance; // 0-1, how much of path is clear

  SafePathResult({
    this.corridor,
    required this.safety,
    this.suggestedAction,
    required this.blockedColumns,
    required this.overallClearance,
  });
}

class SafePathService {
  // Configuration
  static const int numColumns = 12; // Divide image into 12 vertical slices
  static const double groundPlaneRatio = 0.6; // Use bottom 60% for ground detection
  static const double obstacleThreshold = 0.7; // Depth > 70% of max = obstacle
  static const double criticalThreshold = 0.85; // Depth > 85% = critical obstacle
  static const double minCorridorWidth = 0.2; // Minimum 20% width to be walkable

  /// Analyze depth map to find walkable corridor
  SafePathResult analyzePath(DepthMapResult depthMap) {
    if (depthMap.rawDepth.isEmpty) {
      return SafePathResult(
        safety: PathSafety.blocked,
        suggestedAction: 'No depth data',
        blockedColumns: List.generate(numColumns, (i) => i),
        overallClearance: 0.0,
      );
    }

    // Find max depth in scene (closest object)
    double maxDepth = 0;
    for (var val in depthMap.rawDepth) {
      if (val > maxDepth) maxDepth = val;
    }

    if (maxDepth == 0) {
      return SafePathResult(
        safety: PathSafety.blocked,
        suggestedAction: 'Invalid depth data',
        blockedColumns: List.generate(numColumns, (i) => i),
        overallClearance: 0.0,
      );
    }

    // Analyze each column
    final columnClearance = <double>[];
    final blockedColumns = <int>[];
    final columnWidth = depthMap.width ~/ numColumns;

    // Only analyze ground plane (bottom 60%)
    final groundStartY = (depthMap.height * (1 - groundPlaneRatio)).round();

    for (int col = 0; col < numColumns; col++) {
      final startX = col * columnWidth;
      final endX = (col + 1) * columnWidth;

      // Sample depth values in this column's ground region
      double totalDepth = 0;
      int sampleCount = 0;
      double maxColDepth = 0;

      for (int y = groundStartY; y < depthMap.height; y += 2) {
        for (int x = startX; x < endX; x += 2) {
          final idx = y * depthMap.width + x;
          if (idx < depthMap.rawDepth.length) {
            final depth = depthMap.rawDepth[idx];
            totalDepth += depth;
            sampleCount++;
            if (depth > maxColDepth) maxColDepth = depth;
          }
        }
      }

      // Normalize: higher values mean closer obstacles
      final normalizedDepth = sampleCount > 0 ? maxColDepth / maxDepth : 0.0;

      // Clearance is inverse of obstacle proximity
      final clearance = 1.0 - normalizedDepth;
      columnClearance.add(clearance);

      if (normalizedDepth > obstacleThreshold) {
        blockedColumns.add(col);
      }
    }

    // Find widest contiguous clear region
    WalkableCorridor? bestCorridor;
    int maxWidth = 0;
    int currentStart = -1;
    int currentWidth = 0;

    for (int col = 0; col < numColumns; col++) {
      if (!blockedColumns.contains(col)) {
        if (currentStart == -1) currentStart = col;
        currentWidth++;
      } else {
        if (currentWidth > maxWidth) {
          maxWidth = currentWidth;
          bestCorridor = _createCorridor(
            currentStart,
            currentStart + currentWidth - 1,
            columnClearance,
          );
        }
        currentStart = -1;
        currentWidth = 0;
      }
    }

    // Check final segment
    if (currentWidth > maxWidth) {
      maxWidth = currentWidth;
      bestCorridor = _createCorridor(
        currentStart,
        currentStart + currentWidth - 1,
        columnClearance,
      );
    }

    // Calculate overall clearance
    final overallClearance = columnClearance.reduce((a, b) => a + b) / numColumns;

    // Determine safety level and action
    PathSafety safety;
    String? action;

    if (bestCorridor == null || bestCorridor.widthRatio < minCorridorWidth) {
      safety = PathSafety.blocked;
      action = 'Stop, path blocked';
    } else if (blockedColumns.length > numColumns * 0.5) {
      safety = PathSafety.caution;
      if (bestCorridor.veerDirection < -0.15) {
        action = 'Caution, veer left';
      } else if (bestCorridor.veerDirection > 0.15) {
        action = 'Caution, veer right';
      } else {
        action = 'Caution, narrow path ahead';
      }
    } else {
      safety = PathSafety.clear;
      if (!bestCorridor.isCentered) {
        if (bestCorridor.veerDirection < -0.1) {
          action = 'Veer left';
        } else if (bestCorridor.veerDirection > 0.1) {
          action = 'Veer right';
        }
      } else {
        action = 'Clear ahead';
      }
    }

    return SafePathResult(
      corridor: bestCorridor,
      safety: safety,
      suggestedAction: action,
      blockedColumns: blockedColumns,
      overallClearance: overallClearance,
    );
  }

  WalkableCorridor _createCorridor(
    int startCol,
    int endCol,
    List<double> columnClearance,
  ) {
    final width = endCol - startCol + 1;
    final widthRatio = width / numColumns;
    final centerCol = (startCol + endCol) / 2;
    final centerX = (centerCol + 0.5) / numColumns;

    // Average clearance in corridor
    double totalClearance = 0;
    for (int col = startCol; col <= endCol; col++) {
      totalClearance += columnClearance[col];
    }
    final avgClearance = totalClearance / width;

    return WalkableCorridor(
      centerX: centerX,
      widthRatio: widthRatio,
      clearDistance: avgClearance,
      startColumn: startCol,
      endColumn: endCol,
    );
  }

  /// Quick check if immediate path is blocked (center columns)
  bool isImmediatePathBlocked(DepthMapResult depthMap) {
    final result = analyzePath(depthMap);
    // Check if center columns (4-7 of 12) are blocked
    final centerBlocked = result.blockedColumns
        .where((col) => col >= 4 && col <= 7)
        .length;
    return centerBlocked >= 2; // At least 2 center columns blocked
  }

  /// Get quick safety assessment without full analysis
  PathSafety quickSafetyCheck(DepthMapResult depthMap) {
    if (depthMap.rawDepth.isEmpty) return PathSafety.blocked;

    // Sample center region only for speed
    final centerStartX = depthMap.width ~/ 3;
    final centerEndX = (depthMap.width * 2) ~/ 3;
    final groundStartY = (depthMap.height * 0.5).round();

    double maxDepth = 0;
    double centerMaxDepth = 0;

    // Find global max
    for (var val in depthMap.rawDepth) {
      if (val > maxDepth) maxDepth = val;
    }

    if (maxDepth == 0) return PathSafety.blocked;

    // Sample center ground region
    for (int y = groundStartY; y < depthMap.height; y += 4) {
      for (int x = centerStartX; x < centerEndX; x += 4) {
        final idx = y * depthMap.width + x;
        if (idx < depthMap.rawDepth.length) {
          final depth = depthMap.rawDepth[idx];
          if (depth > centerMaxDepth) centerMaxDepth = depth;
        }
      }
    }

    final normalizedCenter = centerMaxDepth / maxDepth;

    if (normalizedCenter > criticalThreshold) {
      return PathSafety.blocked;
    } else if (normalizedCenter > obstacleThreshold) {
      return PathSafety.caution;
    }
    return PathSafety.clear;
  }
}
