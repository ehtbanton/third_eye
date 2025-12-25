import 'dart:io';
import 'dart:typed_data';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;
import 'dart:math' as math;

enum HandGesture {
  pointing, // Index finger pointing up
  none,
}

class HandDetectionResult {
  final HandGesture gesture;
  final HandLandmarks? landmarks;

  HandDetectionResult({
    required this.gesture,
    this.landmarks,
  });
}

class HandLandmarks {
  final List<Point> landmarks;

  HandLandmarks(this.landmarks);

  // MediaPipe hand landmark indices
  static const int thumbTip = 4;
  static const int indexTip = 8;
  static const int indexDip = 7;
  static const int indexPip = 6;
  static const int indexMcp = 5;
  static const int middleTip = 12;
  static const int middlePip = 10;
  static const int ringTip = 16;
  static const int ringPip = 14;
  static const int pinkyTip = 20;
  static const int pinkyPip = 18;
  static const int wrist = 0;
}

class Point {
  final double x;
  final double y;
  final double z;

  Point(this.x, this.y, this.z);
}

class HandGestureService {
  Interpreter? _palmDetector;
  Interpreter? _handLandmarker;
  bool _isInitialized = false;

  // Model configuration
  static const int _palmInputSize = 192;
  static const int _landmarkInputSize = 224;

  Future<void> initialize() async {
    try {
      // Load palm detection model
      _palmDetector = await Interpreter.fromAsset('assets/models/palm_detection_full.tflite');
      print('Palm detection model loaded successfully');

      // Load hand landmark model
      _handLandmarker = await Interpreter.fromAsset('assets/models/hand_landmark_full.tflite');
      print('Hand landmark model loaded successfully');

      // Print model input/output tensor info for debugging
      print('=== Hand Landmark Model Info ===');
      print('Input tensors: ${_handLandmarker!.getInputTensors()}');
      print('Output tensors: ${_handLandmarker!.getOutputTensors()}');

      // Get detailed tensor info
      final inputTensors = _handLandmarker!.getInputTensors();
      final outputTensors = _handLandmarker!.getOutputTensors();

      for (var i = 0; i < inputTensors.length; i++) {
        final tensor = inputTensors[i];
        print('Input[$i]: shape=${tensor.shape}, type=${tensor.type}');
      }

      for (var i = 0; i < outputTensors.length; i++) {
        final tensor = outputTensors[i];
        print('Output[$i]: shape=${tensor.shape}, type=${tensor.type}');
      }

      _isInitialized = true;
    } catch (e) {
      print('ERROR: Failed to initialize hand gesture service: $e');
      print('Make sure palm_detection_full.tflite and hand_landmark_full.tflite are in assets/models/');
      _isInitialized = false;
      throw Exception('Failed to load hand gesture models: $e');
    }
  }

  /// Detect hand gesture from camera frame
  Future<HandDetectionResult> detectGesture(Uint8List imageBytes) async {
    if (!_isInitialized || _handLandmarker == null) {
      throw Exception('Hand gesture service not initialized');
    }

    try {
      // Decode image
      img.Image? image = img.decodeImage(imageBytes);
      if (image == null) {
        return HandDetectionResult(gesture: HandGesture.none);
      }

      // Get hand landmarks directly (skip palm detection for simplicity)
      final landmarks = await _detectLandmarks(image);
      if (landmarks == null) {
        return HandDetectionResult(gesture: HandGesture.none);
      }

      // Classify gesture based on landmarks
      final gesture = _classifyGesture(landmarks);
      return HandDetectionResult(
        gesture: gesture,
        landmarks: landmarks,
      );
    } catch (e) {
      print('Error detecting gesture: $e');
      return HandDetectionResult(gesture: HandGesture.none);
    }
  }

  /// Detect gesture from image file
  Future<HandDetectionResult> detectGestureFromFile(File imageFile) async {
    final imageBytes = await imageFile.readAsBytes();
    return detectGesture(imageBytes);
  }

  /// Detect palm in image (simplified - just check if model runs)
  Future<bool> _detectPalm(img.Image image) async {
    try {
      // Resize image for palm detection
      final resized = img.copyResize(image, width: _palmInputSize, height: _palmInputSize);

      // Convert to input tensor
      final input = _imageToFloat32List(resized, _palmInputSize);

      // Run palm detection
      // Output format: [1, 2016, 18] for palm detection
      final output = List.generate(1, (_) => List.generate(2016, (_) => List.filled(18, 0.0)));
      _palmDetector!.run(input, output);

      print('Palm detection completed, checking for detections...');
      // Check if any detection has high confidence (score > 0.5)
      // The scores are typically in the last element of each detection
      int highConfidenceDetections = 0;
      for (var detection in output[0]) {
        if (detection.isNotEmpty && detection[0] > 0.5) {
          highConfidenceDetections++;
        }
      }

      print('Found $highConfidenceDetections high-confidence palm detections');
      // Simplified: if we got here without errors, assume palm might be present
      // A real implementation would parse the detection boxes and scores
      return true;
    } catch (e) {
      print('Palm detection error: $e');
      return false;
    }
  }

  /// Detect hand landmarks
  Future<HandLandmarks?> _detectLandmarks(img.Image image) async {
    try {
      // Resize image for landmark detection
      final resized = img.copyResize(image, width: _landmarkInputSize, height: _landmarkInputSize);

      // Convert to input tensor
      final input = _imageToFloat32List(resized, _landmarkInputSize);

      // Get actual output tensor shape from model
      final outputTensors = _handLandmarker!.getOutputTensors();
      final outputShape = outputTensors[0].shape;

      // Create output based on actual model output shape
      dynamic output;

      if (outputShape.length == 2) {
        // Shape like [1, 63] or [batch, features]
        output = List.generate(outputShape[0], (_) => List.filled(outputShape[1], 0.0));
      } else if (outputShape.length == 3) {
        // Shape like [1, 21, 3]
        output = List.generate(
          outputShape[0],
          (_) => List.generate(
            outputShape[1],
            (_) => List.filled(outputShape[2], 0.0),
          ),
        );
      } else {
        print('Unexpected output shape: $outputShape');
        return null;
      }

      try {
        _handLandmarker!.run(input, output);
        print('TFLite run succeeded! Output shape: $outputShape');
      } catch (e) {
        print('TFLite run error: $e');
        print('Input type: ${input.runtimeType}');
        print('Output type: ${output.runtimeType}');
        return null;
      }

      // Parse output based on shape
      List<double> flatOutput;
      if (outputShape.length == 2) {
        flatOutput = output[0].cast<double>();
      } else if (outputShape.length == 3) {
        // Flatten [1, 21, 3] to [63]
        flatOutput = [];
        for (var landmarks in output[0]) {
          flatOutput.addAll(landmarks.cast<double>());
        }
      } else {
        return null;
      }

      // Check if we got valid output (not all zeros)
      bool hasNonZero = flatOutput.any((v) => v.abs() > 0.01);

      if (!hasNonZero) {
        // No hand detected
        return null;
      }

      print('✋ Hand landmark detection completed');
      print('First landmark: x=${flatOutput[0].toStringAsFixed(3)}, y=${flatOutput[1].toStringAsFixed(3)}');
      print('Index tip (8): x=${flatOutput[24].toStringAsFixed(3)}, y=${flatOutput[25].toStringAsFixed(3)}');

      // Parse landmarks
      final landmarks = <Point>[];
      for (int i = 0; i < 21; i++) {
        landmarks.add(Point(
          flatOutput[i * 3],
          flatOutput[i * 3 + 1],
          flatOutput[i * 3 + 2],
        ));
      }

      return HandLandmarks(landmarks);
    } catch (e) {
      print('Landmark detection error: $e');
      return null;
    }
  }

  /// Classify gesture based on hand landmarks
  HandGesture _classifyGesture(HandLandmarks landmarks) {
    // Check if index finger is pointing up
    if (_isPointingUp(landmarks)) {
      return HandGesture.pointing;
    }

    return HandGesture.none;
  }

  /// Check if index finger is pointing up
  bool _isPointingUp(HandLandmarks landmarks) {
    final points = landmarks.landmarks;

    // Safety check
    if (points.length < 21) {
      print('Not enough landmarks: ${points.length}');
      return false;
    }

    // Get relevant landmarks
    final indexTip = points[HandLandmarks.indexTip];
    final indexDip = points[HandLandmarks.indexDip];
    final indexPip = points[HandLandmarks.indexPip];
    final indexMcp = points[HandLandmarks.indexMcp];
    final middleTip = points[HandLandmarks.middleTip];
    final middlePip = points[HandLandmarks.middlePip];
    final ringTip = points[HandLandmarks.ringTip];
    final ringPip = points[HandLandmarks.ringPip];
    final pinkyTip = points[HandLandmarks.pinkyTip];
    final pinkyPip = points[HandLandmarks.pinkyPip];
    final wrist = points[HandLandmarks.wrist];

    // Index finger should be extended (tip higher than base joints)
    final indexExtended = indexTip.y < indexDip.y &&
                          indexDip.y < indexPip.y &&
                          indexPip.y < indexMcp.y;

    // Index finger should be pointing upward (tip significantly above wrist)
    final indexPointingUp = indexTip.y < wrist.y - 0.1;

    // Other fingers should be curled (tips not extended)
    final middleCurled = middleTip.y > middlePip.y;
    final ringCurled = ringTip.y > ringPip.y;
    final pinkyCurled = pinkyTip.y > pinkyPip.y;

    print('Gesture check: indexExt=$indexExtended, indexUp=$indexPointingUp, '
          'middleCurl=$middleCurled, ringCurl=$ringCurled, pinkyCurl=$pinkyCurled');
    print('Index tip Y: ${indexTip.y}, Wrist Y: ${wrist.y}');

    // All conditions must be true
    return indexExtended && indexPointingUp && middleCurled && ringCurled && pinkyCurled;
  }

  /// Convert image to float32 list for model input
  List<List<List<List<double>>>> _imageToFloat32List(img.Image image, int size) {
    final input = List.generate(
      1,
      (_) => List.generate(
        size,
        (y) => List.generate(
          size,
          (x) {
            final pixel = image.getPixel(x, y);
            // Normalize to [0, 1]
            return [
              pixel.r / 255.0,
              pixel.g / 255.0,
              pixel.b / 255.0,
            ];
          },
        ),
      ),
    );
    return input;
  }

  bool get isInitialized => _isInitialized;

  void dispose() {
    _palmDetector?.close();
    _handLandmarker?.close();
    _isInitialized = false;
  }
}
