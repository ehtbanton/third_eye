import 'dart:async';
import 'cellular_gemini_service.dart';

class LocalLlmService {
  final CellularGeminiService _cellularGemini = CellularGeminiService();
  bool _isInitialized = false;

  /// Initialize the Gemini API service (now using cellular network)
  Future<bool> initialize(String modelPath, String mmprojPath) async {
    try {
      print('Initializing Gemini API with cellular routing...');
      _isInitialized = await _cellularGemini.initialize();

      if (_isInitialized) {
        print('✓ Gemini API initialized successfully (cellular routing enabled)');
      } else {
        print('✗ Failed to initialize Gemini API with cellular routing');
      }

      return _isInitialized;
    } catch (e) {
      print('Failed to initialize Gemini API: $e');
      return false;
    }
  }

  /// Generate a description for an image using Gemini (via cellular network)
  Future<String> describeImage(String imagePath) async {
    print('describeImage called with: $imagePath');

    if (!_isInitialized) {
      print('ERROR: Service not initialized');
      throw Exception('Service not initialized. Please initialize first.');
    }

    try {
      return await _cellularGemini.describeImage(imagePath);
    } catch (e) {
      print('ERROR in describeImage: $e');
      throw Exception('Failed to generate description: $e');
    }
  }

  /// Extract text from an image using Gemini (via cellular network)
  Future<String> extractText(String imagePath) async {
    print('extractText called with: $imagePath');

    if (!_isInitialized) {
      print('ERROR: Service not initialized');
      throw Exception('Service not initialized. Please initialize first.');
    }

    try {
      return await _cellularGemini.extractText(imagePath);
    } catch (e) {
      print('ERROR in extractText: $e');
      throw Exception('Failed to extract text: $e');
    }
  }

  /// Recognize face in an image using ML Kit and embeddings
  /// This method is now a wrapper that maintains backward compatibility
  /// The actual recognition is handled by FaceRecognitionService
  /// Returns: 'no_face' if no clear single face, person name if matched, or 'unknown' if new face
  Future<String> recognizeFace(String imagePath, List<String> knownFacePaths, Map<String, String> faceNameMap) async {
    print('recognizeFace called with: $imagePath (using ML Kit pipeline)');

    // Note: This method is kept for backward compatibility
    // The new approach uses FaceRecognitionService.recognizeFace() directly
    // which provides better quality feedback and uses embeddings-based matching

    // For backward compatibility, we'll return simple strings
    // But the UI should use FaceRecognitionService.recognizeFace() directly for better results
    return 'deprecated_use_FaceRecognitionService';
  }

  /// Check if the service is initialized
  bool get isInitialized => _isInitialized;

  /// Check if cellular network is available for Gemini requests
  Future<bool> isCellularAvailable() async {
    return await _cellularGemini.isCellularAvailable();
  }

  /// Dispose of resources
  Future<void> dispose() async {
    await _cellularGemini.dispose();
    _isInitialized = false;
    print('Gemini service disposed');
  }
}
