import 'dart:typed_data';

class DepthResult {
  final Uint8List depthPng;
  final double? centerDisparity;

  const DepthResult({
    required this.depthPng,
    this.centerDisparity,
  });
}
