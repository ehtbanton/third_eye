import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_vision/flutter_vision.dart';

import '../models/detected_object.dart';

/// Service for running YOLO object detection using flutter_vision package.
///
/// Supports YOLOv5, YOLOv8, and YOLO11 models.
class ObjectDetectionService {
  FlutterVision? _vision;
  bool _isInitialized = false;
  String _accelerator = 'cpu';

  /// Whether the service is initialized
  bool get isInitialized => _isInitialized;

  /// Which accelerator is being used
  String get accelerator => _accelerator;

  /// Initialize the object detection service.
  ///
  /// [modelPath] - Path to the TFLite model in assets
  /// [labelsPath] - Path to the labels file in assets
  /// [modelVersion] - YOLO version: 'yolov5', 'yolov8', or 'yolo11'
  Future<void> initialize({
    String modelPath = 'assets/models/yolov8n.tflite',
    String labelsPath = 'assets/models/labels.txt',
    String modelVersion = 'yolov8',
    bool useGpu = true,
  }) async {
    if (_isInitialized) {
      dispose();
    }

    debugPrint('ObjectDetectionService: Initializing with model: $modelPath');

    try {
      _vision = FlutterVision();

      await _vision!.loadYoloModel(
        labels: labelsPath,
        modelPath: modelPath,
        modelVersion: modelVersion,
        quantization: false,
        numThreads: 4,
        useGpu: useGpu,
      );

      _accelerator = useGpu ? 'gpu' : 'cpu';
      _isInitialized = true;
      debugPrint('ObjectDetectionService: Successfully initialized with $_accelerator');
    } catch (e, stack) {
      debugPrint('ObjectDetectionService: GPU initialization failed: $e');

      // Try CPU fallback
      if (useGpu) {
        try {
          _vision = FlutterVision();
          await _vision!.loadYoloModel(
            labels: labelsPath,
            modelPath: modelPath,
            modelVersion: modelVersion,
            quantization: false,
            numThreads: 4,
            useGpu: false,
          );
          _accelerator = 'cpu';
          _isInitialized = true;
          debugPrint('ObjectDetectionService: Successfully initialized with CPU');
        } catch (e2, stack2) {
          debugPrint('ObjectDetectionService: CPU initialization also failed: $e2');
          debugPrint('ObjectDetectionService: Stack: $stack2');
          _isInitialized = false;
          rethrow;
        }
      } else {
        debugPrint('ObjectDetectionService: Stack: $stack');
        _isInitialized = false;
        rethrow;
      }
    }
  }

  /// Detect objects in an image.
  ///
  /// [imageBytes] - Image as JPEG bytes
  /// [imageWidth] - Width of the image
  /// [imageHeight] - Height of the image
  /// Returns [ObjectDetectionResult] with detected objects
  Future<ObjectDetectionResult?> detectObjects(
    Uint8List imageBytes, {
    int imageWidth = 640,
    int imageHeight = 640,
  }) async {
    if (!_isInitialized || _vision == null) {
      debugPrint('ObjectDetectionService: Not initialized');
      return null;
    }

    final stopwatch = Stopwatch()..start();

    try {
      // Run detection on image bytes
      final results = await _vision!.yoloOnImage(
        bytesList: imageBytes,
        imageHeight: imageHeight,
        imageWidth: imageWidth,
        iouThreshold: 0.4,
        confThreshold: 0.4,
        classThreshold: 0.5,
      );

      stopwatch.stop();

      // Convert results to our DetectedObject format
      final detections = <DetectedObject>[];

      for (final result in results) {
        // flutter_vision returns: {"box": [x1, y1, x2, y2, confidence], "tag": "class_name"}
        final box = result['box'] as List<dynamic>;
        final tag = result['tag'] as String;

        // Normalize coordinates to [0, 1] range
        final x1 = (box[0] as num).toDouble() / imageWidth;
        final y1 = (box[1] as num).toDouble() / imageHeight;
        final x2 = (box[2] as num).toDouble() / imageWidth;
        final y2 = (box[3] as num).toDouble() / imageHeight;
        final confidence = (box[4] as num).toDouble();

        detections.add(DetectedObject(
          boundingBox: Rect.fromLTRB(
            x1.clamp(0.0, 1.0),
            y1.clamp(0.0, 1.0),
            x2.clamp(0.0, 1.0),
            y2.clamp(0.0, 1.0),
          ),
          classId: 0, // flutter_vision doesn't return class ID, just tag
          className: tag,
          confidence: confidence,
        ));
      }

      debugPrint(
        'ObjectDetectionService: ${stopwatch.elapsedMilliseconds}ms '
        '${detections.length} objects $_accelerator',
      );

      return ObjectDetectionResult(
        detections: detections,
        processingTimeMs: stopwatch.elapsedMilliseconds.toDouble(),
        imageWidth: imageWidth,
        imageHeight: imageHeight,
      );
    } catch (e, stack) {
      debugPrint('ObjectDetectionService: Detection failed: $e');
      debugPrint('ObjectDetectionService: Stack: $stack');
      return null;
    }
  }

  /// Dispose of resources.
  void dispose() {
    debugPrint('ObjectDetectionService: Disposing...');
    _vision?.closeYoloModel();
    _vision = null;
    _isInitialized = false;
    _accelerator = 'cpu';
    debugPrint('ObjectDetectionService: Disposed');
  }
}
