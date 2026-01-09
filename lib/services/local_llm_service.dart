import 'dart:async';
import 'cellular_azure_openai_service.dart';
import 'cellular_gemini_service.dart';

enum LlmProvider {
  azureOpenAI,
  gemini,
}

class LocalLlmService {
  final CellularAzureOpenAIService _azureOpenAI = CellularAzureOpenAIService();
  final CellularGeminiService _gemini = CellularGeminiService();

  LlmProvider _currentProvider = LlmProvider.azureOpenAI;
  bool _azureInitialized = false;
  bool _geminiInitialized = false;

  /// Get current provider
  LlmProvider get currentProvider => _currentProvider;

  /// Set the LLM provider to use
  Future<bool> setProvider(LlmProvider provider) async {
    _currentProvider = provider;
    print('Switched LLM provider to: ${provider.name}');

    // Initialize the selected provider if not already done
    if (provider == LlmProvider.azureOpenAI && !_azureInitialized) {
      return await _initializeAzure();
    } else if (provider == LlmProvider.gemini && !_geminiInitialized) {
      return await _initializeGemini();
    }

    return true;
  }

  Future<bool> _initializeAzure() async {
    try {
      print('Initializing Azure OpenAI with cellular routing...');
      _azureInitialized = await _azureOpenAI.initialize();
      if (_azureInitialized) {
        print('✓ Azure OpenAI initialized successfully');
      } else {
        print('✗ Failed to initialize Azure OpenAI');
      }
      return _azureInitialized;
    } catch (e) {
      print('Failed to initialize Azure OpenAI: $e');
      return false;
    }
  }

  Future<bool> _initializeGemini() async {
    try {
      print('Initializing Gemini with cellular routing...');
      _geminiInitialized = await _gemini.initialize();
      if (_geminiInitialized) {
        print('✓ Gemini initialized successfully');
      } else {
        print('✗ Failed to initialize Gemini');
      }
      return _geminiInitialized;
    } catch (e) {
      print('Failed to initialize Gemini: $e');
      return false;
    }
  }

  /// Initialize the default LLM provider (Azure OpenAI)
  Future<bool> initialize(String modelPath, String mmprojPath) async {
    // Initialize the default provider (Azure OpenAI)
    return await _initializeAzure();
  }

  /// Generate a description for an image using the selected provider
  Future<String> describeImage(String imagePath) async {
    print('describeImage called with: $imagePath (provider: ${_currentProvider.name})');

    if (_currentProvider == LlmProvider.azureOpenAI) {
      if (!_azureInitialized) {
        throw Exception('Azure OpenAI not initialized. Please initialize first.');
      }
      return await _azureOpenAI.describeImage(imagePath);
    } else {
      if (!_geminiInitialized) {
        throw Exception('Gemini not initialized. Please initialize first.');
      }
      return await _gemini.describeImage(imagePath);
    }
  }

  /// Extract text from an image using the selected provider
  Future<String> extractText(String imagePath) async {
    print('extractText called with: $imagePath (provider: ${_currentProvider.name})');

    if (_currentProvider == LlmProvider.azureOpenAI) {
      if (!_azureInitialized) {
        throw Exception('Azure OpenAI not initialized. Please initialize first.');
      }
      return await _azureOpenAI.extractText(imagePath);
    } else {
      if (!_geminiInitialized) {
        throw Exception('Gemini not initialized. Please initialize first.');
      }
      return await _gemini.extractText(imagePath);
    }
  }

  /// Recognize face in an image using ML Kit and embeddings
  /// This method is kept for backward compatibility
  Future<String> recognizeFace(String imagePath, List<String> knownFacePaths, Map<String, String> faceNameMap) async {
    print('recognizeFace called with: $imagePath (using ML Kit pipeline)');
    return 'deprecated_use_FaceRecognitionService';
  }

  /// Check if the current provider is initialized
  bool get isInitialized {
    if (_currentProvider == LlmProvider.azureOpenAI) {
      return _azureInitialized;
    } else {
      return _geminiInitialized;
    }
  }

  /// Check if cellular network is available
  Future<bool> isCellularAvailable() async {
    if (_currentProvider == LlmProvider.azureOpenAI) {
      return await _azureOpenAI.isCellularAvailable();
    } else {
      return await _gemini.isCellularAvailable();
    }
  }

  /// Dispose of resources
  Future<void> dispose() async {
    await _azureOpenAI.dispose();
    await _gemini.dispose();
    _azureInitialized = false;
    _geminiInitialized = false;
    print('LLM services disposed');
  }
}
