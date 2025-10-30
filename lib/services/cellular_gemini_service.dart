import 'dart:convert';
import 'dart:io';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'cellular_http_service.dart';

/// Gemini API service that routes all requests through cellular network
/// Uses Gemini REST API directly via CellularHttpService
class CellularGeminiService {
  final CellularHttpService _cellularHttp = CellularHttpService();
  String? _apiKey;
  bool _isInitialized = false;

  static const String _geminiApiBaseUrl = 'https://generativelanguage.googleapis.com/v1beta';
  static const String _modelName = 'gemini-2.0-flash-exp';

  /// Initialize the service
  /// Must be called before making any API requests
  Future<bool> initialize() async {
    try {
      // Load API key from environment
      _apiKey = dotenv.env['GEMINI_API_KEY'];
      if (_apiKey == null || _apiKey!.isEmpty || _apiKey == 'your_api_key_here') {
        print('ERROR: GEMINI_API_KEY not set in .env file');
        return false;
      }

      // Initialize cellular network
      print('Initializing cellular network for Gemini API...');
      final cellularAvailable = await _cellularHttp.initialize();

      if (!cellularAvailable) {
        print('ERROR: Cellular network not available. Make sure mobile data is enabled.');
        print('Gemini API requests will fail without cellular data.');
        return false; // Changed: return false if cellular is not available
      }

      _isInitialized = true;
      print('✓ Cellular Gemini service initialized with cellular network bound');
      return true;
    } catch (e) {
      print('Failed to initialize Cellular Gemini service: $e');
      return false;
    }
  }

  /// Generate image description using Gemini API over cellular
  Future<String> describeImage(String imagePath) async {
    print('describeImage called with: $imagePath');

    if (!_isInitialized || _apiKey == null) {
      throw Exception('Service not initialized. Call initialize() first.');
    }

    // Check if cellular network is still available
    final cellularAvailable = await _cellularHttp.isCellularAvailable();
    if (!cellularAvailable) {
      print('ERROR: Cellular network not available when trying to make request');
      print('Attempting to reinitialize cellular network...');

      // Try to reinitialize cellular network (force a new network request)
      final reinitialized = await _cellularHttp.initialize(forceReinitialize: true);
      if (!reinitialized) {
        throw Exception('Cellular network unavailable. Please ensure mobile data is enabled and you have cellular signal.');
      }
      print('✓ Cellular network reinitialized successfully');
    }

    try {
      // Read image file and encode as base64
      print('Reading image file: $imagePath');
      final imageFile = File(imagePath);
      if (!await imageFile.exists()) {
        throw Exception('Image file not found: $imagePath');
      }

      final imageBytes = await imageFile.readAsBytes();
      final base64Image = base64Encode(imageBytes);
      print('Image encoded: ${base64Image.length} base64 chars');

      // Build Gemini API request
      final url = '$_geminiApiBaseUrl/models/$_modelName:generateContent?key=$_apiKey';

      final requestBody = {
        'contents': [
          {
            'parts': [
              {'text': 'Describe this image in one sentence.'},
              {
                'inline_data': {
                  'mime_type': 'image/jpeg',
                  'data': base64Image,
                }
              }
            ]
          }
        ],
        'generationConfig': {
          'temperature': 0.4,
          'topK': 32,
          'topP': 1,
          'maxOutputTokens': 1024,
        }
      };

      print('Sending request to Gemini API via cellular...');
      print('URL: $url');

      // Make POST request over cellular with retry logic
      String? responseJson;
      int retryCount = 0;
      const maxRetries = 2;

      while (retryCount <= maxRetries) {
        try {
          responseJson = await _cellularHttp.post(
            url: url,
            headers: {'Content-Type': 'application/json'},
            body: requestBody,
            contentType: 'application/json',
          );
          break; // Success, exit retry loop
        } catch (e) {
          retryCount++;
          if (retryCount > maxRetries) {
            rethrow; // Max retries reached, throw the error
          }
          print('Request failed (attempt $retryCount/$maxRetries): $e');
          print('Retrying in ${retryCount * 2} seconds...');
          await Future.delayed(Duration(seconds: retryCount * 2));
        }
      }

      if (responseJson == null) {
        throw Exception('Failed to get response after $maxRetries retries');
      }

      // Parse response
      final response = jsonDecode(responseJson);

      if (response['candidates'] == null || response['candidates'].isEmpty) {
        throw Exception('No response from Gemini API');
      }

      final text = response['candidates'][0]['content']['parts'][0]['text'] as String?;
      print('Gemini response: $text');

      return text?.trim().isNotEmpty == true ? text!.trim() : 'No description generated';
    } catch (e) {
      print('ERROR in describeImage: $e');
      throw Exception('Failed to generate description: $e');
    }
  }

  /// Extract text from image using Gemini API over cellular
  Future<String> extractText(String imagePath) async {
    print('extractText called with: $imagePath');

    if (!_isInitialized || _apiKey == null) {
      throw Exception('Service not initialized. Call initialize() first.');
    }

    // Check if cellular network is still available
    final cellularAvailable = await _cellularHttp.isCellularAvailable();
    if (!cellularAvailable) {
      print('ERROR: Cellular network not available when trying to make request');
      print('Attempting to reinitialize cellular network...');

      // Try to reinitialize cellular network (force a new network request)
      final reinitialized = await _cellularHttp.initialize(forceReinitialize: true);
      if (!reinitialized) {
        throw Exception('Cellular network unavailable. Please ensure mobile data is enabled and you have cellular signal.');
      }
      print('✓ Cellular network reinitialized successfully');
    }

    try {
      // Read image file and encode as base64
      print('Reading image file: $imagePath');
      final imageFile = File(imagePath);
      if (!await imageFile.exists()) {
        throw Exception('Image file not found: $imagePath');
      }

      final imageBytes = await imageFile.readAsBytes();
      final base64Image = base64Encode(imageBytes);
      print('Image encoded: ${base64Image.length} base64 chars');

      // Build Gemini API request
      final url = '$_geminiApiBaseUrl/models/$_modelName:generateContent?key=$_apiKey';

      final requestBody = {
        'contents': [
          {
            'parts': [
              {'text': 'Write out any text that is visible on screen, and nothing else.'},
              {
                'inline_data': {
                  'mime_type': 'image/jpeg',
                  'data': base64Image,
                }
              }
            ]
          }
        ],
        'generationConfig': {
          'temperature': 0.1,
          'topK': 32,
          'topP': 1,
          'maxOutputTokens': 2048,
        }
      };

      print('Sending request to Gemini API via cellular...');
      print('URL: $url');

      // Make POST request over cellular with retry logic
      String? responseJson;
      int retryCount = 0;
      const maxRetries = 2;

      while (retryCount <= maxRetries) {
        try {
          responseJson = await _cellularHttp.post(
            url: url,
            headers: {'Content-Type': 'application/json'},
            body: requestBody,
            contentType: 'application/json',
          );
          break; // Success, exit retry loop
        } catch (e) {
          retryCount++;
          if (retryCount > maxRetries) {
            rethrow; // Max retries reached, throw the error
          }
          print('Request failed (attempt $retryCount/$maxRetries): $e');
          print('Retrying in ${retryCount * 2} seconds...');
          await Future.delayed(Duration(seconds: retryCount * 2));
        }
      }

      if (responseJson == null) {
        throw Exception('Failed to get response after $maxRetries retries');
      }

      // Parse response
      final response = jsonDecode(responseJson);

      if (response['candidates'] == null || response['candidates'].isEmpty) {
        throw Exception('No response from Gemini API');
      }

      final text = response['candidates'][0]['content']['parts'][0]['text'] as String?;
      print('Gemini response: $text');

      return text?.trim().isNotEmpty == true ? text!.trim() : 'No text detected';
    } catch (e) {
      print('ERROR in extractText: $e');
      throw Exception('Failed to extract text: $e');
    }
  }

  /// Check if the service is initialized
  bool get isInitialized => _isInitialized;

  /// Check if cellular network is available
  Future<bool> isCellularAvailable() async {
    return await _cellularHttp.isCellularAvailable();
  }

  /// Dispose of resources
  Future<void> dispose() async {
    await _cellularHttp.release();
    _isInitialized = false;
    _apiKey = null;
    print('Cellular Gemini service disposed');
  }
}
