import 'package:flutter/services.dart';
import '../models/depth_result.dart';

class DepthService {
  static const MethodChannel _channel = MethodChannel('com.example.third_eye/depth');

  Future<DepthResult> computeDepthFromPng({
    required Uint8List pngBytes,
    required bool assumeSbs,
    int numDisparities = 96,
    int blockSize = 15,
  }) async {
    final res = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'computeDepthFromPng',
      {
        'pngBytes': pngBytes,
        'assumeSbs': assumeSbs,
        'numDisparities': numDisparities,
        'blockSize': blockSize,
      },
    );

    if (res == null) {
      throw Exception('DepthService: null response from native');
    }

    final depthPng = res['depthPng'] as Uint8List?;
    final centerDisp = res['centerDisparity'] as double?;

    if (depthPng == null) {
      throw Exception('DepthService: missing depthPng in response');
    }

    return DepthResult(depthPng: depthPng, centerDisparity: centerDisp);
  }
}
