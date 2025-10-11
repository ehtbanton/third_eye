import '../models/image_description.dart';
import 'local_llm_service.dart';

class LlamaService {
  final LocalLlmService _localLlm = LocalLlmService();
  bool _isInitialized = false;

  /// Initialize the Gemini API service
  Future<bool> initialize({Function(double)? onDownloadProgress}) async {
    try {
      // Initialize Gemini API (no downloads needed)
      _isInitialized = await _localLlm.initialize('', '');
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

  /// Extract text from image using local LLM
  Future<LlamaResponse> extractText(String imagePath) async {
    if (!_isInitialized) {
      return LlamaResponse.error(
        'LLM not initialized. Please initialize the service first.',
      );
    }

    try {
      final text = await _localLlm.extractText(imagePath);
      return LlamaResponse(
        content: text,
        success: true,
      );
    } catch (e) {
      return LlamaResponse.error('Failed to extract text: $e');
    }
  }

  /// Check if the local LLM is ready
  Future<bool> checkServerHealth() async {
    return _isInitialized && _localLlm.isInitialized;
  }

  /// Check if model needs to be downloaded (always true for API)
  Future<bool> isModelDownloaded() async {
    return true; // API doesn't need downloads
  }

  void dispose() {
    _localLlm.dispose();
  }
}
