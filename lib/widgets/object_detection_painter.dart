import 'package:flutter/material.dart';
import '../models/detected_object.dart';

/// CustomPainter for rendering object detection bounding boxes and labels.
class ObjectDetectionPainter extends CustomPainter {
  final List<DetectedObject>? detections;
  final bool showOverlay;
  final bool showConfidence;

  ObjectDetectionPainter({
    required this.detections,
    this.showOverlay = true,
    this.showConfidence = true,
  });

  /// Color mapping for different object categories
  static Color _getColorForClass(int classId) {
    // Group classes by category for consistent coloring
    if (classId == 0) {
      // person
      return Colors.green;
    } else if (classId >= 1 && classId <= 8) {
      // vehicles: bicycle, car, motorcycle, airplane, bus, train, truck, boat
      return Colors.blue;
    } else if (classId >= 14 && classId <= 23) {
      // animals: bird, cat, dog, horse, sheep, cow, elephant, bear, zebra, giraffe
      return Colors.orange;
    } else if (classId >= 39 && classId <= 45) {
      // kitchen items: bottle, wine glass, cup, fork, knife, spoon, bowl
      return Colors.purple;
    } else if (classId >= 46 && classId <= 55) {
      // food: banana, apple, sandwich, orange, broccoli, carrot, hot dog, pizza, donut, cake
      return Colors.yellow;
    } else if (classId >= 56 && classId <= 61) {
      // furniture: chair, couch, potted plant, bed, dining table, toilet
      return Colors.brown;
    } else if (classId >= 62 && classId <= 72) {
      // electronics: tv, laptop, mouse, remote, keyboard, cell phone, microwave, oven, toaster, sink, refrigerator
      return Colors.cyan;
    } else {
      // other: traffic light, fire hydrant, stop sign, parking meter, bench, backpack, umbrella, etc.
      return Colors.red;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (!showOverlay || detections == null || detections!.isEmpty) {
      return;
    }

    for (final detection in detections!) {
      final color = _getColorForClass(detection.classId);

      // Draw bounding box
      final boxPaint = Paint()
        ..color = color
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke;

      // Convert normalized coordinates (0-1) to screen coordinates
      final rect = Rect.fromLTRB(
        detection.boundingBox.left * size.width,
        detection.boundingBox.top * size.height,
        detection.boundingBox.right * size.width,
        detection.boundingBox.bottom * size.height,
      );

      canvas.drawRect(rect, boxPaint);

      // Draw label background
      final labelText = showConfidence
          ? '${detection.className} ${(detection.confidence * 100).toStringAsFixed(0)}%'
          : detection.className;

      final textPainter = TextPainter(
        text: TextSpan(
          text: labelText,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();

      // Position label at top-left of bounding box
      final labelX = rect.left;
      final labelY = rect.top - textPainter.height - 4;

      // Draw label background
      final bgPaint = Paint()
        ..color = color.withOpacity(0.8)
        ..style = PaintingStyle.fill;

      final labelRect = Rect.fromLTWH(
        labelX,
        labelY.clamp(0, size.height - textPainter.height),
        textPainter.width + 8,
        textPainter.height + 4,
      );
      canvas.drawRect(labelRect, bgPaint);

      // Draw label text
      textPainter.paint(
        canvas,
        Offset(labelX + 4, labelY.clamp(0, size.height - textPainter.height) + 2),
      );
    }

    // Draw detection count in corner
    final countPainter = TextPainter(
      text: TextSpan(
        text: '${detections!.length} objects',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          backgroundColor: Colors.black54,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    countPainter.layout();
    countPainter.paint(canvas, Offset(size.width - countPainter.width - 8, 8));
  }

  @override
  bool shouldRepaint(covariant ObjectDetectionPainter oldDelegate) {
    return oldDelegate.detections != detections ||
        oldDelegate.showOverlay != showOverlay ||
        oldDelegate.showConfidence != showConfidence;
  }
}
