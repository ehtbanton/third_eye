import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../services/turbo_colormap.dart';

/// CustomPainter for rendering depth map overlay on the right half of stereo video.
///
/// The depth map is displayed only on the right half of the canvas,
/// overlaying the right camera view in an SBS (side-by-side) stereo video.
class DepthMapPainter extends CustomPainter {
  /// The depth map image to render (as ui.Image)
  final ui.Image? depthMapImage;

  /// Whether to show the overlay
  final bool showOverlay;

  /// Opacity of the depth map overlay (0.0 - 1.0)
  final double opacity;

  /// Whether to draw a vertical divider line between halves
  final bool showDivider;

  /// Color of the divider line
  final Color dividerColor;

  /// Whether to show the metric scale legend
  final bool showScale;

  /// Maximum distance for the scale (in meters)
  final double maxDistanceM;

  /// Whether the depth is calibrated to metric scale
  final bool isMetricCalibrated;

  DepthMapPainter({
    required this.depthMapImage,
    this.showOverlay = true,
    this.opacity = 0.7,
    this.showDivider = true,
    this.dividerColor = Colors.white,
    this.showScale = true,
    this.maxDistanceM = 6.0,
    this.isMetricCalibrated = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (!showOverlay || depthMapImage == null) {
      if (showDivider) {
        _drawDivider(canvas, size);
      }
      return;
    }

    final paint = Paint()
      ..filterQuality = FilterQuality.low
      ..color = Color.fromRGBO(255, 255, 255, opacity);

    // Source rectangle (full depth map image)
    final srcRect = Rect.fromLTWH(
      0,
      0,
      depthMapImage!.width.toDouble(),
      depthMapImage!.height.toDouble(),
    );

    // Calculate destination rectangle with BoxFit.contain logic
    // to match the camera frame's aspect ratio
    final imageAspect = depthMapImage!.width / depthMapImage!.height;
    final canvasAspect = size.width / size.height;

    double destWidth, destHeight, destX, destY;
    if (canvasAspect > imageAspect) {
      // Canvas is wider - fit to height, center horizontally
      destHeight = size.height;
      destWidth = destHeight * imageAspect;
      destX = (size.width - destWidth) / 2;
      destY = 0;
    } else {
      // Canvas is taller - fit to width, center vertically
      destWidth = size.width;
      destHeight = destWidth / imageAspect;
      destX = 0;
      destY = (size.height - destHeight) / 2;
    }

    final destRect = Rect.fromLTWH(destX, destY, destWidth, destHeight);

    canvas.drawImageRect(depthMapImage!, srcRect, destRect, paint);

    if (showDivider) {
      _drawDivider(canvas, size);
    }

    // Draw metric scale legend
    if (showScale) {
      _drawScaleLegend(canvas, size, destRect);
    }
  }

  /// Draw a vertical color scale legend with distance labels
  void _drawScaleLegend(Canvas canvas, Size size, Rect depthRect) {
    final legendWidth = 20.0;
    final legendHeight = depthRect.height * 0.6;
    final legendX = depthRect.right - legendWidth - 12;
    final legendY = depthRect.top + (depthRect.height - legendHeight) / 2;

    // Background for legend
    final bgPaint = Paint()
      ..color = Colors.black.withOpacity(0.6)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(legendX - 30, legendY - 20, legendWidth + 50, legendHeight + 40),
        const Radius.circular(8),
      ),
      bgPaint,
    );

    // Draw color gradient bar
    final numSteps = 50;
    final stepHeight = legendHeight / numSteps;

    for (int i = 0; i < numSteps; i++) {
      // Top = close (red), bottom = far (blue)
      final normalized = i / numSteps; // 0 = top (close), 1 = bottom (far)
      final color = TurboColormap.getMetricColor(
        normalized * maxDistanceM,
        maxDistanceM: maxDistanceM,
      );

      final stepPaint = Paint()
        ..color = Color.fromRGBO(color[0], color[1], color[2], 1.0)
        ..style = PaintingStyle.fill;

      canvas.drawRect(
        Rect.fromLTWH(legendX, legendY + i * stepHeight, legendWidth, stepHeight + 1),
        stepPaint,
      );
    }

    // Border around color bar
    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawRect(
      Rect.fromLTWH(legendX, legendY, legendWidth, legendHeight),
      borderPaint,
    );

    // Draw distance labels
    final textStyle = ui.TextStyle(
      color: Colors.white,
      fontSize: 10,
      fontWeight: ui.FontWeight.bold,
    );

    // Labels at key distances
    final distances = isMetricCalibrated
        ? [0.0, 1.0, 2.0, 4.0, maxDistanceM]
        : [0.0, maxDistanceM * 0.25, maxDistanceM * 0.5, maxDistanceM * 0.75, maxDistanceM];

    for (final distance in distances) {
      final normalized = distance / maxDistanceM;
      final y = legendY + normalized * legendHeight;

      // Format label
      String label;
      if (isMetricCalibrated) {
        if (distance < 1) {
          label = '${(distance * 100).round()}cm';
        } else {
          label = '${distance.toStringAsFixed(1)}m';
        }
      } else {
        label = '${(normalized * 100).round()}%';
      }

      final paragraphBuilder = ui.ParagraphBuilder(ui.ParagraphStyle(
        textAlign: TextAlign.left,
        fontSize: 10,
      ))
        ..pushStyle(textStyle)
        ..addText(label);

      final paragraph = paragraphBuilder.build()
        ..layout(const ui.ParagraphConstraints(width: 40));

      canvas.drawParagraph(paragraph, Offset(legendX - 28, y - 5));

      // Tick mark
      canvas.drawLine(
        Offset(legendX - 2, y),
        Offset(legendX, y),
        borderPaint,
      );
    }

    // Title
    final titleBuilder = ui.ParagraphBuilder(ui.ParagraphStyle(
      textAlign: TextAlign.center,
      fontSize: 9,
    ))
      ..pushStyle(ui.TextStyle(
        color: Colors.white70,
        fontSize: 9,
      ))
      ..addText(isMetricCalibrated ? 'DEPTH' : 'REL');

    final titleParagraph = titleBuilder.build()
      ..layout(const ui.ParagraphConstraints(width: 40));

    canvas.drawParagraph(titleParagraph, Offset(legendX - 10, legendY - 16));
  }

  void _drawDivider(Canvas canvas, Size size) {
    final dividerPaint = Paint()
      ..color = dividerColor
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    canvas.drawLine(
      Offset(size.width / 2, 0),
      Offset(size.width / 2, size.height),
      dividerPaint,
    );
  }

  @override
  bool shouldRepaint(covariant DepthMapPainter oldDelegate) {
    return oldDelegate.depthMapImage != depthMapImage ||
           oldDelegate.showOverlay != showOverlay ||
           oldDelegate.opacity != opacity ||
           oldDelegate.showDivider != showDivider ||
           oldDelegate.showScale != showScale ||
           oldDelegate.maxDistanceM != maxDistanceM ||
           oldDelegate.isMetricCalibrated != isMetricCalibrated;
  }
}

/// Helper to convert RGBA bytes to ui.Image for use with DepthMapPainter.
class DepthMapImageHelper {
  /// Convert RGBA bytes to ui.Image.
  ///
  /// [rgbaBytes] - RGBA pixel data (4 bytes per pixel)
  /// [width] - Image width in pixels
  /// [height] - Image height in pixels
  static Future<ui.Image> rgbaToImage(
    List<int> rgbaBytes,
    int width,
    int height,
  ) async {
    final completer = Completer<ui.Image>();

    ui.decodeImageFromPixels(
      Uint8List.fromList(rgbaBytes),
      width,
      height,
      ui.PixelFormat.rgba8888,
      (ui.Image image) {
        completer.complete(image);
      },
    );

    return completer.future;
  }
}
