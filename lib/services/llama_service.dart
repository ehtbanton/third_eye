import '../models/image_description.dart';
import 'local_llm_service.dart';
import 'model_downloader.dart';

class LlamaService {
  final LocalLlmService _localLlm = LocalLlmService();
  final ModelDownloader _downloader = ModelDownloader();
  bool _isInitialized = false;

  /// Initialize the local LLM service
  Future<bool> initialize({Function(double)? onDownloadProgress}) async {
    try {
      // Check if model is already downloaded
      final isDownloaded = await _downloader.isModelDownloaded();

      String modelPath;
      if (!isDownloaded) {
        // Download model with progress callback
        modelPath = await _downloader.downloadModel(
          onProgress: onDownloadProgress ?? (progress) {},
        );
      } else {
        modelPath = await _downloader.getModelPath();
      }

      // Initialize the LLM with model path (mmproj only for vision)
      _isInitialized = await _localLlm.initialize(modelPath);
      return _isInitialized;
    } catch (e) {
      print('Failed to initialize LlamaService: $e');
      return false;
    }
  }

  /// Send image file path to local LLM for description
  Future<LlamaResponse> describeImage(String imagePath) async {
    if (!_isInitialized) {
      return LlamaResponse.error(
        'LLM not initialized. Please initialize the service first.',
      );
    }

    try {
      final description = await _localLlm.describeImage(imagePath);
      return LlamaResponse(
        content: description,
        success: true,
      );
    } catch (e) {
      return LlamaResponse.error('Failed to generate description: $e');
    }
  }

  /// Check if the local LLM is ready
  Future<bool> checkServerHealth() async {
    return _isInitialized && _localLlm.isInitialized;
  }

  /// Check if model needs to be downloaded
  Future<bool> isModelDownloaded() async {
    return await _downloader.isModelDownloaded();
  }

  void dispose() {
    _localLlm.dispose();
  }
}
