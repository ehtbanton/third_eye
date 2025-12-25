import 'package:flutter/material.dart';
import '../services/hand_gesture_service.dart';

class HandLandmarksPainter extends CustomPainter {
  final HandLandmarks? landmarks;
  final Size imageSize;

  HandLandmarksPainter({
    required this.landmarks,
    required this.imageSize,
  });

  // MediaPipe hand connections (which landmarks connect to which)
  static const List<List<int>> connections = [
    // Thumb
    [0, 1], [1, 2], [2, 3], [3, 4],
    // Index finger
    [0, 5], [5, 6], [6, 7], [7, 8],
    // Middle finger
    [0, 9], [9, 10], [10, 11], [11, 12],
    // Ring finger
    [0, 13], [13, 14], [14, 15], [15, 16],
    // Pinky
    [0, 17], [17, 18], [18, 19], [19, 20],
    // Palm connections
    [5, 9], [9, 13], [13, 17],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (landmarks == null || landmarks!.landmarks.isEmpty) {
      return;
    }

    final paint = Paint()
      ..color = Colors.green
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    final pointPaint = Paint()
      ..color = Colors.red
      ..strokeWidth = 8
      ..style = PaintingStyle.fill;

    final indexFingerPaint = Paint()
      ..color = Colors.yellow
      ..strokeWidth = 10
      ..style = PaintingStyle.fill;

    // Draw connections
    for (final connection in connections) {
      final startIdx = connection[0];
      final endIdx = connection[1];

      if (startIdx < landmarks!.landmarks.length &&
          endIdx < landmarks!.landmarks.length) {
        final start = landmarks!.landmarks[startIdx];
        final end = landmarks!.landmarks[endIdx];

        // Convert normalized coordinates (0-1) to screen coordinates
        final startPos = Offset(
          start.x * size.width,
          start.y * size.height,
        );
        final endPos = Offset(
          end.x * size.width,
          end.y * size.height,
        );

        canvas.drawLine(startPos, endPos, paint);
      }
    }

    // Draw landmark points
    for (int i = 0; i < landmarks!.landmarks.length; i++) {
      final point = landmarks!.landmarks[i];
      final pos = Offset(
        point.x * size.width,
        point.y * size.height,
      );

      // Highlight index finger tip (landmark 8)
      if (i == HandLandmarks.indexTip) {
        canvas.drawCircle(pos, 6, indexFingerPaint);
      } else {
        canvas.drawCircle(pos, 4, pointPaint);
      }
    }

    // Draw debug text
    final indexTip = landmarks!.landmarks[HandLandmarks.indexTip];
    final wrist = landmarks!.landmarks[HandLandmarks.wrist];

    final textPainter = TextPainter(
      text: TextSpan(
        children: [
          TextSpan(
            text: '✋ Hand Detected!\n',
            style: const TextStyle(
              color: Colors.green,
              fontSize: 18,
              fontWeight: FontWeight.bold,
              backgroundColor: Colors.black87,
            ),
          ),
          TextSpan(
            text: '${landmarks!.landmarks.length} landmarks\n',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              backgroundColor: Colors.black87,
            ),
          ),
          TextSpan(
            text: 'Index: ${indexTip.y.toStringAsFixed(2)}\n',
            style: const TextStyle(
              color: Colors.yellow,
              fontSize: 12,
              backgroundColor: Colors.black87,
            ),
          ),
          TextSpan(
            text: 'Wrist: ${wrist.y.toStringAsFixed(2)}',
            style: const TextStyle(
              color: Colors.cyan,
              fontSize: 12,
              backgroundColor: Colors.black87,
            ),
          ),
        ],
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, const Offset(10, 10));
  }

  @override
  bool shouldRepaint(covariant HandLandmarksPainter oldDelegate) {
    return oldDelegate.landmarks != landmarks;
  }
}
