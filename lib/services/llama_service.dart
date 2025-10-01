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
      // Check if both model files are already downloaded
      final isDownloaded = await _downloader.isModelDownloaded();

      Map<String, String> modelPaths;
      if (!isDownloaded) {
        // Download both model files with progress callback
        modelPaths = await _downloader.downloadModel(
          onProgress: onDownloadProgress ?? (progress) {},
        );
      } else {
        modelPaths = await _downloader.getModelPaths();
      }

      // Initialize the LLM with both model paths
      _isInitialized = await _localLlm.initialize(
        modelPaths['model']!,
        modelPaths['mmproj']!,
      );
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
