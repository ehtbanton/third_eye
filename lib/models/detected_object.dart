import 'dart:ui';

/// Represents a single detected object from YOLO inference.
class DetectedObject {
  /// Bounding box in normalized coordinates [0, 1]
  final Rect boundingBox;

  /// COCO class name (e.g., "person", "car")
  final String className;

  /// COCO class index (0-79)
  final int classId;

  /// Detection confidence score [0, 1]
  final double confidence;

  const DetectedObject({
    required this.boundingBox,
    required this.className,
    required this.classId,
    required this.confidence,
  });

  @override
  String toString() {
    return 'DetectedObject($className: ${(confidence * 100).toStringAsFixed(1)}%)';
  }
}

/// Result from object detection inference.
class ObjectDetectionResult {
  /// List of detected objects
  final List<DetectedObject> detections;

  /// Processing time in milliseconds
  final double processingTimeMs;

  /// Original image width
  final int imageWidth;

  /// Original image height
  final int imageHeight;

  const ObjectDetectionResult({
    required this.detections,
    required this.processingTimeMs,
    required this.imageWidth,
    required this.imageHeight,
  });
}
