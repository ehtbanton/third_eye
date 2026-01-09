import 'dart:math';
import 'dart:ui';
import '../models/detected_object.dart';
import 'depth_map_service.dart';

enum ObstaclePosition { left, center, right }

class ObstacleWarning {
  final String objectName;
  final ObstaclePosition position;
  final double distanceScore; // 0.0 (far) to 1.0 (touching)
  final bool isCritical;

  ObstacleWarning({
    required this.objectName,
    required this.position,
    required this.distanceScore,
    required this.isCritical,
  });

  String get announcement {
    if (isCritical) {
      return "Stop! $objectName ahead.";
    }
    String posStr = position == ObstaclePosition.left ? "on your left" : 
                    position == ObstaclePosition.right ? "on your right" : "ahead";
    return "$objectName $posStr.";
  }
}

class ObstacleFusionService {
  
  // Heuristic: If object depth is in the top 20% of the scene's max depth, it's "close".
  // This avoids calibration issues with MiDaS.
  static const double relativeDepthThreshold = 0.8;
  
  List<ObstacleWarning> detectHazards(List<DetectedObject> detections, DepthMapResult depthMap) {
    List<ObstacleWarning> warnings = [];

    if (depthMap.rawDepth.isEmpty) return warnings;

    // 1. Find the maximum depth value in the scene (closest point)
    double maxSceneDepth = 0;
    for (var val in depthMap.rawDepth) {
      if (val > maxSceneDepth) maxSceneDepth = val;
    }
    
    if (maxSceneDepth == 0) return warnings; // Invalid map

    // 2. Analyze each object
    for (var object in detections) {
      double objectDepth = _calculateObjectDepth(object.boundingBox, depthMap);
      
      // Normalize score: how close is this object relative to the closest thing seen?
      double distanceScore = objectDepth / maxSceneDepth;

      if (distanceScore > relativeDepthThreshold) {
        // It is close!
        ObstaclePosition pos = _determinePosition(object.boundingBox);
        bool isCritical = (pos == ObstaclePosition.center) && (distanceScore > 0.9); // Very close and centered

        // Filter out common background things if needed (e.g., "sky" if YOLO detects it, though standard YOLO doesn't)
        
        warnings.add(ObstacleWarning(
          objectName: object.className,
          position: pos,
          distanceScore: distanceScore,
          isCritical: isCritical
        ));
      }
    }
    
    // Sort by criticality and closeness
    warnings.sort((a, b) => b.distanceScore.compareTo(a.distanceScore));
    
    return warnings;
  }

  double _calculateObjectDepth(Rect bbox, DepthMapResult depthMap) {
    // Map normalized Rect to depth map coordinates
    int x1 = (bbox.left * depthMap.width).floor().clamp(0, depthMap.width - 1);
    int x2 = (bbox.right * depthMap.width).floor().clamp(0, depthMap.width - 1);
    int y1 = (bbox.top * depthMap.height).floor().clamp(0, depthMap.height - 1);
    int y2 = (bbox.bottom * depthMap.height).floor().clamp(0, depthMap.height - 1);

    if (x2 <= x1 || y2 <= y1) return 0.0;

    // Sample the center region of the box to avoid background edges
    // We'll take the median of the center 50% of the box
    List<double> samples = [];
    int stride = 2; // Optimization: skip pixels
    
    int cx1 = x1 + ((x2 - x1) * 0.25).floor();
    int cx2 = x2 - ((x2 - x1) * 0.25).floor();
    int cy1 = y1 + ((y2 - y1) * 0.25).floor();
    int cy2 = y2 - ((y2 - y1) * 0.25).floor();

    for (int y = cy1; y < cy2; y += stride) {
      for (int x = cx1; x < cx2; x += stride) {
        int idx = y * depthMap.width + x;
        if (idx < depthMap.rawDepth.length) {
          samples.add(depthMap.rawDepth[idx]);
        }
      }
    }

    if (samples.isEmpty) return 0.0;
    
    // Return the 90th percentile (closest parts of the object)
    // Sorting small list is fast enough
    samples.sort();
    return samples[(samples.length * 0.9).floor()];
  }

  ObstaclePosition _determinePosition(Rect bbox) {
    double centerX = bbox.center.dx;
    if (centerX < 0.35) return ObstaclePosition.left;
    if (centerX > 0.65) return ObstaclePosition.right;
    return ObstaclePosition.center;
  }
}
