import 'dart:io';
import 'dart:isolate';
import 'dart:ui';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

class ModelDownloader {
  final Dio _dio = Dio();

  // Moondream2 vision model - requires BOTH files:
  // 1. mmproj (910 MB) - image encoder
  // 2. text model (2.84 GB) - text generator
  static const String mmprojUrl =
      'https://huggingface.co/ggml-org/moondream2-20250414-GGUF/resolve/main/moondream2-mmproj-f16-20250414.gguf';
  static const String mmprojFileName = 'moondream2-mmproj.gguf';

  static const String modelUrl =
      'https://huggingface.co/ggml-org/moondream2-20250414-GGUF/resolve/main/moondream2-text-model-f16_ct-vicuna.gguf';
  static const String modelFileName = 'moondream2-text.gguf';

  static const String downloadPortName = 'model_download_port';

  /// Get the model storage directory (ThirdEye/models on external storage)
  Future<Directory> _getModelDirectory() async {
    final externalDir = await getExternalStorageDirectory();
    if (externalDir == null) {
      throw Exception('External storage not available');
    }

    // Remove /Android/data/... to get to root, then add ThirdEye/models
    final pathParts = externalDir.path.split('/');
    final rootIndex = pathParts.indexOf('Android');
    final rootPath = pathParts.sublist(0, rootIndex).join('/');

    final modelDir = Directory('$rootPath/ThirdEye/models');
    if (!await modelDir.exists()) {
      await modelDir.create(recursive: true);
    }
    return modelDir;
  }

  /// Download both model files if not already present
  /// Returns a map with 'mmproj' and 'model' paths
  Future<Map<String, String>> downloadModel({
    required Function(double) onProgress,
  }) async {
    final modelDir = await _getModelDirectory();
    final mmprojPath = '${modelDir.path}/$mmprojFileName';
    final modelPath = '${modelDir.path}/$modelFileName';
    final mmprojFile = File(mmprojPath);
    final modelFile = File(modelPath);

    // Check if both files already exist with valid sizes
    bool mmprojExists = false;
    bool modelExists = false;

    if (await mmprojFile.exists()) {
      final fileSize = await mmprojFile.length();
      if (fileSize > 100 * 1024 * 1024) {
        print('Mmproj already exists at: $mmprojPath');
        mmprojExists = true;
      }
    }

    if (await modelFile.exists()) {
      final fileSize = await modelFile.length();
      if (fileSize > 100 * 1024 * 1024) {
        print('Model already exists at: $modelPath');
        modelExists = true;
      }
    }

    if (mmprojExists && modelExists) {
      return {'mmproj': mmprojPath, 'model': modelPath};
    }

    // Download mmproj if needed (910 MB)
    if (!mmprojExists) {
      print('Downloading mmproj to: $mmprojPath');
      await _dio.download(
        mmprojUrl,
        mmprojPath,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            // mmproj is ~25% of total download
            final progress = (received / total) * 0.25;
            onProgress(progress);
          }
        },
      );
    }

    // Download text model if needed (2.84 GB)
    if (!modelExists) {
      print('Downloading text model to: $modelPath');
      await _dio.download(
        modelUrl,
        modelPath,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            // text model is ~75% of total download, starts after mmproj
            final progress = 0.25 + (received / total) * 0.75;
            onProgress(progress);
          }
        },
      );
    }

    return {'mmproj': mmprojPath, 'model': modelPath};
  }

  /// Check if both model files are already downloaded
  Future<bool> isModelDownloaded() async {
    try {
      final modelDir = await _getModelDirectory();
      final mmprojPath = '${modelDir.path}/$mmprojFileName';
      final modelPath = '${modelDir.path}/$modelFileName';
      final mmprojFile = File(mmprojPath);
      final modelFile = File(modelPath);

      if (await mmprojFile.exists() && await modelFile.exists()) {
        final mmprojSize = await mmprojFile.length();
        final modelSize = await modelFile.length();
        return mmprojSize > 100 * 1024 * 1024 && modelSize > 100 * 1024 * 1024;
      }
    } catch (e) {
      print('Error checking model: $e');
    }
    return false;
  }

  /// Get both model file paths
  Future<Map<String, String>> getModelPaths() async {
    final modelDir = await _getModelDirectory();
    return {
      'mmproj': '${modelDir.path}/$mmprojFileName',
      'model': '${modelDir.path}/$modelFileName',
    };
  }

  /// Delete both downloaded model files
  Future<void> deleteModel() async {
    final modelDir = await _getModelDirectory();
    final mmprojPath = '${modelDir.path}/$mmprojFileName';
    final modelPath = '${modelDir.path}/$modelFileName';
    final mmprojFile = File(mmprojPath);
    final modelFile = File(modelPath);

    if (await mmprojFile.exists()) {
      await mmprojFile.delete();
    }
    if (await modelFile.exists()) {
      await modelFile.delete();
    }
  }
}
