import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;
import 'stereo_video_source.dart';
import 'turbo_colormap.dart';

class DepthMapResult {
  final Float32List rawDepth;

  final Uint8List colorizedRgba;

  final int width;

  final int height;

  final double processingTimeMs;

  DepthMapResult({
    required this.rawDepth,
    required this.colorizedRgba,
    required this.width,
    required this.height,
    required this.processingTimeMs,
  });
}

enum _DepthBackend { midas, hitnet }

class DepthMapService {
  Interpreter? _interpreter;
  bool _isInitialized = false;
  String _accelerator = 'cpu';

  int _inputWidth = 256;
  int _inputHeight = 256;
  int _inputChannels = 3;

  int _inputTensorCount = 1;

  _DepthBackend _backend = _DepthBackend.midas;

  double _outputScale = 1.0;

  double? _stereoBaselineMeters;
  double? _stereoFocalLengthPx;

  bool get isInitialized => _isInitialized;

  String get accelerator => _accelerator;

  bool get isUsingGpu => _accelerator == 'gpu' || _accelerator == 'nnapi';

  int get inputWidth => _inputWidth;

  int get inputHeight => _inputHeight;

  double get outputScale => _outputScale;
  set outputScale(double value) {
    _outputScale = value.clamp(0.25, 1.0);
  }

  void setStereoCalibration({
    required double baselineMeters,
    required double focalLengthPx,
  }) {
    _stereoBaselineMeters = baselineMeters;
    _stereoFocalLengthPx = focalLengthPx;
    debugPrint('DepthMapService: Stereo calibration set: baseline=$baselineMeters m, fx=$focalLengthPx px');
  }

  void clearStereoCalibration() {
    _stereoBaselineMeters = null;
    _stereoFocalLengthPx = null;
    debugPrint('DepthMapService: Stereo calibration cleared');
  }

  Future<void> initialize({
    String modelPath = 'assets/models/hitnet_middlebury_480x640.tflite',
    bool useGpuDelegate = true,
  }) async {
    if (_isInitialized) {
      dispose();
    }

    debugPrint('DepthMapService: Initializing with model: $modelPath');

    if (useGpuDelegate) {
      try {
        await _initializeWithAccelerator(modelPath, accelerator: 'gpu');
        debugPrint('DepthMapService: Successfully initialized with GPU');
        return;
      } catch (e) {
        debugPrint('DepthMapService: GPU init failed: $e');
      }

      try {
        await _initializeWithAccelerator(modelPath, accelerator: 'nnapi');
        debugPrint('DepthMapService: Successfully initialized with NNAPI');
        return;
      } catch (e) {
        debugPrint('DepthMapService: NNAPI init failed: $e');
      }
    }

    await _initializeWithAccelerator(modelPath, accelerator: 'cpu');
    debugPrint('DepthMapService: Successfully initialized with CPU');
  }

  Future<void> _initializeWithAccelerator(String modelPath, {required String accelerator}) async {
    final options = InterpreterOptions();

    if (accelerator == 'nnapi') {
      options.useNnApiForAndroid = true;
      options.threads = 2;
      _accelerator = 'nnapi';
      debugPrint('DepthMapService: NNAPI enabled for Android');
    } else if (accelerator == 'gpu') {
      final gpuDelegate = GpuDelegateV2();
      options.addDelegate(gpuDelegate);
      options.threads = 2;
      _accelerator = 'gpu';
      debugPrint('DepthMapService: GPU delegate added');
    } else {
      options.threads = 4;
      _accelerator = 'cpu';
      debugPrint('DepthMapService: Using CPU with 4 threads');
    }

    _interpreter = await Interpreter.fromAsset(modelPath, options: options);

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

    _inputTensorCount = inputTensors.length;
    if (inputTensors.isNotEmpty) {
      final inputShape = inputTensors[0].shape;
      if (inputShape.length >= 4) {
        _inputHeight = inputShape[1];
        _inputWidth = inputShape[2];
        _inputChannels = inputShape[3];
      } else if (inputShape.length >= 3) {
        _inputHeight = inputShape[1];
        _inputWidth = inputShape[2];
        _inputChannels = 1;
      }
      debugPrint('DepthMapService: Input size: ${_inputWidth}x$_inputHeight, channels=$_inputChannels, inputs=$_inputTensorCount');
    }

    final looksLikeHitnet = modelPath.toLowerCase().contains('hitnet') ||
        _inputTensorCount == 2 ||
        (_inputTensorCount == 1 && _inputChannels == 6);
    _backend = looksLikeHitnet ? _DepthBackend.hitnet : _DepthBackend.midas;

    debugPrint('DepthMapService: Backend selected: ${_backend.name}');
    _isInitialized = true;
  }

  Future<DepthMapResult?> estimateDepth(StereoFramePair stereoPair) async {
    if (_backend == _DepthBackend.hitnet) {
      return estimateStereoDepthFromPair(stereoPair.leftImage, stereoPair.rightImage);
    }
    return estimateDepthFromImage(stereoPair.leftImage);
  }

  Future<DepthMapResult?> estimateDepthFromImage(Uint8List imageBytes) async {
    if (!_isInitialized || _interpreter == null) {
      debugPrint('DepthMapService: Not initialized');
      return null;
    }

    if (_backend == _DepthBackend.hitnet) {
      final full = img.decodeImage(imageBytes);
      if (full == null) {
        debugPrint('DepthMapService: Failed to decode input image (HITNet)');
        return null;
      }

      final canSplit = full.width.isEven && (full.width / full.height) >= 1.6;
      if (!canSplit) {
        debugPrint(
          'DepthMapService: HITNet requires a stereo pair. The provided frame is ${full.width}x${full.height} '
          'and does not look like side-by-side stereo. Returning null.',
        );
        return null;
      }

      final halfW = full.width ~/ 2;
      final left = img.copyCrop(full, x: 0, y: 0, width: halfW, height: full.height);
      final right = img.copyCrop(full, x: halfW, y: 0, width: halfW, height: full.height);

      final leftJpeg = Uint8List.fromList(img.encodeJpg(left, quality: 90));
      final rightJpeg = Uint8List.fromList(img.encodeJpg(right, quality: 90));

      return estimateStereoDepthFromPair(leftJpeg, rightJpeg);
    }

    return _estimateMidasFromJpeg(imageBytes);
  }

  Future<DepthMapResult?> estimateDepthFromBytes(Uint8List imageBytes) async {
    return estimateDepthFromImage(imageBytes);
  }

  Future<DepthMapResult?> estimateStereoDepthFromPair(Uint8List leftJpeg, Uint8List rightJpeg) async {
    if (!_isInitialized || _interpreter == null) {
      debugPrint('DepthMapService: Not initialized');
      return null;
    }

    final stopwatch = Stopwatch()..start();

    try {
      final left = img.decodeImage(leftJpeg);
      final right = img.decodeImage(rightJpeg);
      if (left == null || right == null) {
        debugPrint('DepthMapService: Failed to decode stereo images');
        return null;
      }

      final leftResized = img.copyResize(left, width: _inputWidth, height: _inputHeight);
      final rightResized = img.copyResize(right, width: _inputWidth, height: _inputHeight);

      final inputTensor = _interpreter!.getInputTensors().first;
      final isUint8 = inputTensor.type == TfLiteType.uint8;

      Object makeRgbTensor(img.Image im) {
        if (isUint8) {
          return List.generate(
            1,
            (_) => List.generate(
              _inputHeight,
              (y) => List.generate(
                _inputWidth,
                (x) {
                  final p = im.getPixel(x, y);
                  return <int>[p.r.toInt(), p.g.toInt(), p.b.toInt()];
                },
              ),
            ),
          );
        } else {
          return List.generate(
            1,
            (_) => List.generate(
              _inputHeight,
              (y) => List.generate(
                _inputWidth,
                (x) {
                  final p = im.getPixel(x, y);
                  return <double>[p.r / 255.0, p.g / 255.0, p.b / 255.0];
                },
              ),
            ),
          );
        }
      }

      Object makeConcat6Tensor(img.Image leftIm, img.Image rightIm) {
        if (isUint8) {
          return List.generate(
            1,
            (_) => List.generate(
              _inputHeight,
              (y) => List.generate(
                _inputWidth,
                (x) {
                  final lp = leftIm.getPixel(x, y);
                  final rp = rightIm.getPixel(x, y);
                  return <int>[
                    lp.r.toInt(), lp.g.toInt(), lp.b.toInt(),
                    rp.r.toInt(), rp.g.toInt(), rp.b.toInt(),
                  ];
                },
              ),
            ),
          );
        } else {
          return List.generate(
            1,
            (_) => List.generate(
              _inputHeight,
              (y) => List.generate(
                _inputWidth,
                (x) {
                  final lp = leftIm.getPixel(x, y);
                  final rp = rightIm.getPixel(x, y);
                  return <double>[
                    lp.r / 255.0, lp.g / 255.0, lp.b / 255.0,
                    rp.r / 255.0, rp.g / 255.0, rp.b / 255.0,
                  ];
                },
              ),
            ),
          );
        }
      }

      final Object leftInput = makeRgbTensor(leftResized);
      final Object rightInput = makeRgbTensor(rightResized);

      final outShape = _interpreter!.getOutputTensors().first.shape;
      final outH = outShape.length >= 3 ? outShape[1] : _inputHeight;
      final outW = outShape.length >= 3 ? outShape[2] : _inputWidth;

      final output = List.generate(
        1,
        (_) => List.generate(
          outH,
          (_) => List.generate(outW, (_) => List.generate(1, (_) => 0.0)),
        ),
      );

      if (_inputTensorCount == 2) {
        _interpreter!.runForMultipleInputs([leftInput, rightInput], {0: output});
      } else {
        final input = (_inputChannels == 6) ? makeConcat6Tensor(leftResized, rightResized) : leftInput;
        _interpreter!.run(input, output);
      }

      final outScale = _outputScale.clamp(0.25, 1.0);
      final dispW = (outW * outScale).round().clamp(1, outW);
      final dispH = (outH * outScale).round().clamp(1, outH);

      final scaleX = outW / dispW;
      final scaleY = outH / dispH;

      final raw = Float32List(dispW * dispH);
      final viz = List<double>.filled(dispW * dispH, 0.0);

      final fx = _stereoFocalLengthPx;
      final b = _stereoBaselineMeters;
      const eps = 1e-6;

      for (int y = 0; y < dispH; y++) {
        for (int x = 0; x < dispW; x++) {
          final srcX = (x * scaleX).floor().clamp(0, outW - 1);
          final srcY = (y * scaleY).floor().clamp(0, outH - 1);

          final disparity = (output[0][srcY][srcX][0] as num).toDouble();

          double value;
          if (fx != null && b != null) {
            value = (fx * b) / math.max(disparity, eps);
            viz[y * dispW + x] = 1.0 / math.max(value, eps);
          } else {
            value = disparity;
            viz[y * dispW + x] = value;
          }

          raw[y * dispW + x] = value;
        }
      }

      final colorized = TurboColormap.apply(viz, dispW, dispH);

      stopwatch.stop();
      debugPrint(
        'DepthMapService(HITNet): ${stopwatch.elapsedMilliseconds}ms '
        '[in:${_inputWidth}x$_inputHeight out:${dispW}x$dispH] $_accelerator '
        '${(fx != null && b != null) ? "metric" : "disparity"}',
      );

      return DepthMapResult(
        rawDepth: raw,
        colorizedRgba: colorized,
        width: dispW,
        height: dispH,
        processingTimeMs: stopwatch.elapsedMilliseconds.toDouble(),
      );
    } catch (e, stack) {
      debugPrint('DepthMapService(HITNet): Inference failed: $e');
      debugPrint('DepthMapService(HITNet): Stack: $stack');
      return null;
    }
  }

  Future<DepthMapResult?> _estimateMidasFromJpeg(Uint8List imageBytes) async {
    final stopwatch = Stopwatch()..start();

    try {
      final image = img.decodeImage(imageBytes);
      if (image == null) {
        debugPrint('DepthMapService: Failed to decode input image');
        return null;
      }
      final decodeTime = stopwatch.elapsedMilliseconds;

      final resized = img.copyResize(image, width: _inputWidth, height: _inputHeight);
      final resizeTime = stopwatch.elapsedMilliseconds - decodeTime;

      final input = List.generate(
        1,
        (_) => List.generate(
          _inputHeight,
          (y) => List.generate(
            _inputWidth,
            (x) {
              final p = resized.getPixel(x, y);
              return <double>[p.r / 255.0, p.g / 255.0, p.b / 255.0];
            },
          ),
        ),
      );
      final prepTime = stopwatch.elapsedMilliseconds - resizeTime - decodeTime;

      final output = List.generate(
        1,
        (_) => List.generate(
          _inputHeight,
          (_) => List.generate(_inputWidth, (_) => List.generate(1, (_) => 0.0)),
        ),
      );

      _interpreter!.run(input, output);
      final inferTime = stopwatch.elapsedMilliseconds;

      final outScale = _outputScale.clamp(0.25, 1.0);
      final outWidth = (_inputWidth * outScale).round().clamp(1, _inputWidth);
      final outHeight = (_inputHeight * outScale).round().clamp(1, _inputHeight);

      final scaleX = _inputWidth / outWidth;
      final scaleY = _inputHeight / outHeight;

      final depth = Float32List(outWidth * outHeight);

      for (int y = 0; y < outHeight; y++) {
        for (int x = 0; x < outWidth; x++) {
          final srcX = (x * scaleX).floor().clamp(0, _inputWidth - 1);
          final srcY = (y * scaleY).floor().clamp(0, _inputHeight - 1);
          depth[y * outWidth + x] = (output[0][srcY][srcX][0] as num).toDouble();
        }
      }

      final colorized = TurboColormap.apply(depth.toList(), outWidth, outHeight);

      stopwatch.stop();
      final colorTime = stopwatch.elapsedMilliseconds - inferTime - prepTime - resizeTime - decodeTime;

      debugPrint(
        'DepthMapService(MiDaS): ${stopwatch.elapsedMilliseconds}ms '
        '[decode:$decodeTime resize:$resizeTime prep:$prepTime infer:${inferTime - prepTime - resizeTime - decodeTime} color:$colorTime] '
        '(${outWidth}x$outHeight) $_accelerator',
      );

      return DepthMapResult(
        rawDepth: depth,
        colorizedRgba: colorized,
        width: outWidth,
        height: outHeight,
        processingTimeMs: stopwatch.elapsedMilliseconds.toDouble(),
      );
    } catch (e, stack) {
      debugPrint('DepthMapService(MiDaS): Inference failed: $e');
      debugPrint('DepthMapService(MiDaS): Stack: $stack');
      return null;
    }
  }

  void dispose() {
    debugPrint('DepthMapService: Disposing...');
    _interpreter?.close();
    _interpreter = null;
    _isInitialized = false;
    _accelerator = 'cpu';
    debugPrint('DepthMapService: Disposed');
  }
}
