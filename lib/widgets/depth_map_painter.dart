import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

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

  DepthMapPainter({
    required this.depthMapImage,
    this.showOverlay = true,
    this.opacity = 0.7,
    this.showDivider = true,
    this.dividerColor = Colors.white,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (!showOverlay || depthMapImage == null) {
      // Still draw divider if enabled
      if (showDivider) {
        _drawDivider(canvas, size);
      }
      return;
    }

    // Calculate right half region
    final rightHalfRect = Rect.fromLTWH(
      size.width / 2,  // Start at horizontal midpoint
      0,
      size.width / 2,  // Half width
      size.height,
    );

    // Draw depth map scaled to right half with opacity
    final paint = Paint()
      ..filterQuality = FilterQuality.medium
      ..color = Color.fromRGBO(255, 255, 255, opacity);

    canvas.save();
    canvas.clipRect(rightHalfRect);

    // Scale depth map to fill right half
    final srcRect = Rect.fromLTWH(
      0,
      0,
      depthMapImage!.width.toDouble(),
      depthMapImage!.height.toDouble(),
    );

    canvas.drawImageRect(depthMapImage!, srcRect, rightHalfRect, paint);
    canvas.restore();

    // Draw divider line between halves
    if (showDivider) {
      _drawDivider(canvas, size);
    }
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
           oldDelegate.showDivider != showDivider;
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
