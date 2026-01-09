import 'dart:convert';
import 'dart:io';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'cellular_http_service.dart';

/// Azure OpenAI service that routes all requests through cellular network
/// Uses Azure OpenAI REST API directly via CellularHttpService
class CellularAzureOpenAIService {
  final CellularHttpService _cellularHttp = CellularHttpService();
  String? _endpoint;
  String? _apiKey;
  String? _deploymentName;
  String? _apiVersion;
  bool _isInitialized = false;

  /// Initialize the service
  /// Must be called before making any API requests
  Future<bool> initialize() async {
    try {
      // Load configuration from environment
      _endpoint = dotenv.env['AZURE_OPENAI_ENDPOINT'];
      _apiKey = dotenv.env['AZURE_OPENAI_API_KEY'];
      _deploymentName = dotenv.env['AZURE_OPENAI_DEPLOYMENT_NAME'];
      _apiVersion = dotenv.env['AZURE_OPENAI_API_VERSION'] ?? '2024-02-15-preview';

      if (_endpoint == null || _endpoint!.isEmpty || _endpoint!.contains('your-resource')) {
        print('ERROR: AZURE_OPENAI_ENDPOINT not set in .env file');
        return false;
      }
      if (_apiKey == null || _apiKey!.isEmpty || _apiKey!.contains('your-api-key')) {
        print('ERROR: AZURE_OPENAI_API_KEY not set in .env file');
        return false;
      }
      if (_deploymentName == null || _deploymentName!.isEmpty) {
        print('ERROR: AZURE_OPENAI_DEPLOYMENT_NAME not set in .env file');
        return false;
      }

      // Initialize cellular network
      print('Initializing cellular network for Azure OpenAI...');
      final cellularAvailable = await _cellularHttp.initialize();

      if (!cellularAvailable) {
        print('ERROR: Cellular network not available. Make sure mobile data is enabled.');
        print('Azure OpenAI requests will fail without cellular data.');
        return false;
      }

      _isInitialized = true;
      print('✓ Cellular Azure OpenAI service initialized with cellular network bound');
      return true;
    } catch (e) {
      print('Failed to initialize Cellular Azure OpenAI service: $e');
      return false;
    }
  }

  /// Build the Azure OpenAI API URL
  String _buildApiUrl() {
    // Remove trailing slash from endpoint if present
    final baseUrl = _endpoint!.endsWith('/')
        ? _endpoint!.substring(0, _endpoint!.length - 1)
        : _endpoint!;
    return '$baseUrl/openai/deployments/$_deploymentName/chat/completions?api-version=$_apiVersion';
  }

  /// Ensure cellular network is available, reinitialize if needed
  Future<void> _ensureCellularAvailable() async {
    final cellularAvailable = await _cellularHttp.isCellularAvailable();
    if (!cellularAvailable) {
      print('ERROR: Cellular network not available when trying to make request');
      print('Attempting to reinitialize cellular network...');

      final reinitialized = await _cellularHttp.initialize(forceReinitialize: true);
      if (!reinitialized) {
        throw Exception('Cellular network unavailable. Please ensure mobile data is enabled and you have cellular signal.');
      }
      print('✓ Cellular network reinitialized successfully');
    }
  }

  /// Make a request to Azure OpenAI with retry logic
  Future<String> _makeRequest(Map<String, dynamic> requestBody) async {
    final url = _buildApiUrl();
    print('Sending request to Azure OpenAI via cellular...');
    print('URL: $url');

    String? responseJson;
    int retryCount = 0;
    const maxRetries = 2;

    while (retryCount <= maxRetries) {
      try {
        responseJson = await _cellularHttp.post(
          url: url,
          headers: {
            'Content-Type': 'application/json',
            'api-key': _apiKey!,
          },
          body: requestBody,
          contentType: 'application/json',
        );
        break;
      } catch (e) {
        retryCount++;
        if (retryCount > maxRetries) {
          rethrow;
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

    // Check for errors
    if (response['error'] != null) {
      throw Exception('Azure OpenAI error: ${response['error']['message']}');
    }

    if (response['choices'] == null || response['choices'].isEmpty) {
      throw Exception('No response from Azure OpenAI');
    }

    final text = response['choices'][0]['message']['content'] as String?;
    print('Azure OpenAI response: $text');

    return text?.trim() ?? '';
  }

  /// Generate image description using Azure OpenAI over cellular
  Future<String> describeImage(String imagePath) async {
    print('describeImage called with: $imagePath');

    if (!_isInitialized || _apiKey == null) {
      throw Exception('Service not initialized. Call initialize() first.');
    }

    await _ensureCellularAvailable();

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

      // Build Azure OpenAI request
      final requestBody = {
        'messages': [
          {
            'role': 'user',
            'content': [
              {'type': 'text', 'text': 'Describe this image in one sentence.'},
              {
                'type': 'image_url',
                'image_url': {
                  'url': 'data:image/jpeg;base64,$base64Image',
                }
              }
            ]
          }
        ],
        'max_tokens': 1024,
        'temperature': 0.4,
      };

      final result = await _makeRequest(requestBody);
      return result.isNotEmpty ? result : 'No description generated';
    } catch (e) {
      print('ERROR in describeImage: $e');
      throw Exception('Failed to generate description: $e');
    }
  }

  /// Extract text from image using Azure OpenAI over cellular
  Future<String> extractText(String imagePath) async {
    print('extractText called with: $imagePath');

    if (!_isInitialized || _apiKey == null) {
      throw Exception('Service not initialized. Call initialize() first.');
    }

    await _ensureCellularAvailable();

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

      // Build Azure OpenAI request
      final requestBody = {
        'messages': [
          {
            'role': 'user',
            'content': [
              {'type': 'text', 'text': 'Write out any text that is visible on screen, and nothing else.'},
              {
                'type': 'image_url',
                'image_url': {
                  'url': 'data:image/jpeg;base64,$base64Image',
                }
              }
            ]
          }
        ],
        'max_tokens': 2048,
        'temperature': 0.1,
      };

      final result = await _makeRequest(requestBody);
      return result.isNotEmpty ? result : 'No text detected';
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

  /// Analyze navigation scene for blind navigation assistance
  /// Returns a brief, actionable description focused on safety
  Future<String> analyzeNavigationScene(String imagePath) async {
    print('analyzeNavigationScene called with: $imagePath');

    if (!_isInitialized || _apiKey == null) {
      throw Exception('Service not initialized. Call initialize() first.');
    }

    await _ensureCellularAvailable();

    try {
      // Read image file and encode as base64
      final imageFile = File(imagePath);
      if (!await imageFile.exists()) {
        throw Exception('Image file not found: $imagePath');
      }

      final imageBytes = await imageFile.readAsBytes();
      final base64Image = base64Encode(imageBytes);

      // Navigation-specific prompt
      final requestBody = {
        'messages': [
          {
            'role': 'system',
            'content': 'You are assisting a blind person navigating outdoors. '
                'Provide brief, actionable guidance. Focus on: '
                '1) Immediate path ahead (clear, obstructed, turns) '
                '2) Hazards (stairs, curbs, vehicles, holes) '
                '3) Useful landmarks (crosswalks, doors, signs). '
                'Keep response under 20 words. Be direct and safety-focused.'
          },
          {
            'role': 'user',
            'content': [
              {'type': 'text', 'text': 'Describe what I need to know to walk safely.'},
              {
                'type': 'image_url',
                'image_url': {
                  'url': 'data:image/jpeg;base64,$base64Image',
                }
              }
            ]
          }
        ],
        'max_tokens': 100,
        'temperature': 0.2,
      };

      final result = await _makeRequest(requestBody);
      return result.isNotEmpty ? result : 'Unable to analyze scene';
    } catch (e) {
      print('ERROR in analyzeNavigationScene: $e');
      return 'Scene analysis unavailable';
    }
  }

  /// Dispose of resources
  Future<void> dispose() async {
    await _cellularHttp.release();
    _isInitialized = false;
    _apiKey = null;
    _endpoint = null;
    _deploymentName = null;
    print('Cellular Azure OpenAI service disposed');
  }
}
