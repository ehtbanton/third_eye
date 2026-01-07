import 'package:flutter/foundation.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;
import 'stereo_video_source.dart';
import 'turbo_colormap.dart';

/// Result from depth map estimation.
class DepthMapResult {
  /// Raw depth values (float32 as bytes, row-major)
  final Float32List rawDepth;

  /// Colorized depth map as RGBA bytes (ready for display)
  final Uint8List colorizedRgba;

  /// Width of the depth map
  final int width;

  /// Height of the depth map
  final int height;

  /// Processing time in milliseconds
  final double processingTimeMs;

  DepthMapResult({
    required this.rawDepth,
    required this.colorizedRgba,
    required this.width,
    required this.height,
    required this.processingTimeMs,
  });
}

/// Service for generating depth maps from images using MiDaS.
///
/// MiDaS (Mixing Datasets for Zero-shot Cross-dataset Transfer) is a
/// monocular depth estimation network that produces depth maps from
/// single RGB images.
///
/// Model: MiDaS v2.1 optimized
/// Input: RGB image, shape (1, H, W, 3), normalized to [0, 1]
/// Output: Depth map, shape (1, H, W)
class DepthMapService {
  Interpreter? _interpreter;
  bool _isInitialized = false;
  String _accelerator = 'cpu';

  // Model configuration (MiDaS v2.1 - 384x384 or auto-detected)
  static const int defaultInputWidth = 384;
  static const int defaultInputHeight = 384;

  int _inputWidth = defaultInputWidth;
  int _inputHeight = defaultInputHeight;

  // Output scale factor (1.0 = full resolution, 0.5 = half, etc.)
  double _outputScale = 1.0;

  /// Whether the service is initialized
  bool get isInitialized => _isInitialized;

  /// Which accelerator is being used (nnapi, gpu, cpu)
  String get accelerator => _accelerator;

  /// Whether GPU delegate is enabled (legacy getter)
  bool get isUsingGpu => _accelerator == 'gpu' || _accelerator == 'nnapi';

  /// Model input width
  int get inputWidth => _inputWidth;

  /// Model input height
  int get inputHeight => _inputHeight;

  /// Output scale factor (1.0 = full resolution, 0.5 = half)
  double get outputScale => _outputScale;
  set outputScale(double value) {
    _outputScale = value.clamp(0.25, 1.0);
  }

  /// Initialize the depth map service with MiDaS model.
  ///
  /// [modelPath] - Path to the TFLite model file in assets
  /// [useGpuDelegate] - Whether to use hardware acceleration
  Future<void> initialize({
    String modelPath = 'assets/models/midas_v21_small_256.tflite',
    bool useGpuDelegate = true,
  }) async {
    if (_isInitialized) {
      dispose();
    }

    debugPrint('DepthMapService: Initializing with model: $modelPath');

    if (useGpuDelegate) {
      // Try GPU delegate (fastest for this model)
      try {
        await _initializeWithAccelerator(modelPath, accelerator: 'gpu');
        debugPrint('DepthMapService: Successfully initialized with GPU');
        return;
      } catch (e) {
        debugPrint('DepthMapService: GPU initialization failed: $e');
        _interpreter?.close();
        _interpreter = null;
      }
    }

    // Fall back to CPU
    try {
      await _initializeWithAccelerator(modelPath, accelerator: 'cpu');
      debugPrint('DepthMapService: Successfully initialized with CPU');
    } catch (e, stack) {
      debugPrint('DepthMapService: CPU initialization also failed: $e');
      debugPrint('DepthMapService: Stack: $stack');
      _isInitialized = false;
      rethrow;
    }
  }

  Future<void> _initializeWithAccelerator(String modelPath, {required String accelerator}) async {
    InterpreterOptions options = InterpreterOptions();

    if (accelerator == 'nnapi') {
      // NNAPI - uses NPU/DSP on Android devices (Samsung NPU, Qualcomm DSP, etc.)
      options.useNnApiForAndroid = true;
      _accelerator = 'nnapi';
      debugPrint('DepthMapService: NNAPI enabled for Android');
    } else if (accelerator == 'gpu') {
      final gpuDelegate = GpuDelegateV2();
      options.addDelegate(gpuDelegate);
      _accelerator = 'gpu';
      debugPrint('DepthMapService: GPU delegate added');
    } else {
      // CPU with multiple threads
      options.threads = 4;
      _accelerator = 'cpu';
      debugPrint('DepthMapService: Using CPU with 4 threads');
    }

    debugPrint('DepthMapService: Loading model from asset: $modelPath');
    _interpreter = await Interpreter.fromAsset(modelPath, options: options);

    // Print model info for debugging
    final inputTensors = _interpreter!.getInputTensors();
    final outputTensors = _interpreter!.getOutputTensors();

    debugPrint('DepthMapService: Model loaded successfully');
    debugPrint('DepthMapService: Input tensors:');
    for (var i = 0; i < inputTensors.length; i++) {
      final tensor = inputTensors[i];
      debugPrint('  [$i]: shape=${tensor.shape}, type=${tensor.type}');
    }
    debugPrint('DepthMapService: Output tensors:');
    for (var i = 0; i < outputTensors.length; i++) {
      final tensor = outputTensors[i];
      debugPrint('  [$i]: shape=${tensor.shape}, type=${tensor.type}');
    }

    // Infer input dimensions from model
    if (inputTensors.isNotEmpty) {
      final inputShape = inputTensors[0].shape;
      // Shape is typically (1, H, W, C) or (1, H, W, 6)
      if (inputShape.length >= 3) {
        _inputHeight = inputShape[1];
        _inputWidth = inputShape[2];
        debugPrint('DepthMapService: Input size: ${_inputWidth}x$_inputHeight');
      }
    }

    _isInitialized = true;
  }

  /// Estimate depth from a stereo frame pair (uses left image for monocular depth).
  ///
  /// [stereoPair] - Left and right images as JPEG bytes (uses left image only)
  /// Returns [DepthMapResult] with depth and colorized depth map
  Future<DepthMapResult?> estimateDepth(StereoFramePair stereoPair) async {
    // Use the left image for monocular depth estimation
    return estimateDepthFromImage(stereoPair.leftImage);
  }

  /// Estimate depth from a single image.
  ///
  /// [imageBytes] - Image as JPEG bytes
  /// Returns [DepthMapResult] with depth and colorized depth map
  Future<DepthMapResult?> estimateDepthFromImage(Uint8List imageBytes) async {
    if (!_isInitialized || _interpreter == null) {
      debugPrint('DepthMapService: Not initialized');
      return null;
    }

    final stopwatch = Stopwatch()..start();

    try {
      // Decode JPEG image
      final image = img.decodeImage(imageBytes);
      final decodeTime = stopwatch.elapsedMilliseconds;

      if (image == null) {
        debugPrint('DepthMapService: Failed to decode input image');
        return null;
      }

      // Resize to model input size
      final resized = img.copyResize(image, width: _inputWidth, height: _inputHeight);
      final resizeTime = stopwatch.elapsedMilliseconds - decodeTime;

      // Prepare input tensor
      final input = List.generate(
        1,
        (_) => List.generate(
          _inputHeight,
          (y) => List.generate(
            _inputWidth,
            (x) {
              final pixel = resized.getPixel(x, y);
              return [pixel.r / 255.0, pixel.g / 255.0, pixel.b / 255.0];
            },
          ),
        ),
      );
      final prepTime = stopwatch.elapsedMilliseconds - resizeTime - decodeTime;

      // Prepare output tensor
      final output = List.generate(
        1,
        (_) => List.generate(
          _inputHeight,
          (_) => List.generate(_inputWidth, (_) => List.filled(1, 0.0)),
        ),
      );

      // Run inference
      _interpreter!.run(input, output);
      final inferTime = stopwatch.elapsedMilliseconds - prepTime - resizeTime - decodeTime;

      // Calculate output dimensions with downscaling
      final outWidth = (_inputWidth * _outputScale).round();
      final outHeight = (_inputHeight * _outputScale).round();

      // Extract and downsample depth values
      final depth = Float32List(outWidth * outHeight);
      final scaleX = _inputWidth / outWidth;
      final scaleY = _inputHeight / outHeight;

      for (int y = 0; y < outHeight; y++) {
        for (int x = 0; x < outWidth; x++) {
          final srcX = (x * scaleX).floor().clamp(0, _inputWidth - 1);
          final srcY = (y * scaleY).floor().clamp(0, _inputHeight - 1);
          depth[y * outWidth + x] = output[0][srcY][srcX][0].toDouble();
        }
      }

      // Colorize with TURBO colormap at reduced resolution
      final colorized = TurboColormap.apply(
        depth.toList(),
        outWidth,
        outHeight,
      );

      stopwatch.stop();
      final colorTime = stopwatch.elapsedMilliseconds - inferTime - prepTime - resizeTime - decodeTime;

      debugPrint('DepthMapService: ${stopwatch.elapsedMilliseconds}ms total [decode:$decodeTime resize:$resizeTime prep:$prepTime infer:$inferTime color:$colorTime] (${outWidth}x$outHeight) $_accelerator');

      return DepthMapResult(
        rawDepth: depth,
        colorizedRgba: colorized,
        width: outWidth,
        height: outHeight,
        processingTimeMs: stopwatch.elapsedMilliseconds.toDouble(),
      );
    } catch (e, stack) {
      debugPrint('DepthMapService: Inference failed: $e');
      debugPrint('DepthMapService: Stack: $stack');
      return null;
    }
  }

  /// Estimate depth from raw image bytes (convenience method).
  ///
  /// [imageBytes] - Image as JPEG bytes
  Future<DepthMapResult?> estimateDepthFromBytes(Uint8List imageBytes) async {
    return estimateDepthFromImage(imageBytes);
  }

  /// Dispose of resources.
  void dispose() {
    debugPrint('DepthMapService: Disposing...');
    _interpreter?.close();
    _interpreter = null;
    _isInitialized = false;
    _accelerator = 'cpu';
    debugPrint('DepthMapService: Disposed');
  }
}
