import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:fllama/fllama.dart';

class LocalLlmService {
  bool _isInitialized = false;
  String? _mmprojPath;
  String? _modelPath;

  /// Initialize the LLM service with both model paths
  Future<bool> initialize(String modelPath, String mmprojPath) async {
    try {
      if (!await File(modelPath).exists()) {
        print('Warning: Model file not found at: $modelPath');
        print('Download will start on first use.');
        return false;
      }

      if (!await File(mmprojPath).exists()) {
        print('Warning: Mmproj file not found at: $mmprojPath');
        print('Download will start on first use.');
        return false;
      }

      _modelPath = modelPath;
      _mmprojPath = mmprojPath;
      _isInitialized = true;
      return true;
    } catch (e) {
      print('Failed to initialize LLM: $e');
      return false;
    }
  }

  /// Generate a description for an image using Moondream2
  Future<String> describeImage(String imagePath) async {
    print('describeImage called with: $imagePath');

    if (_modelPath == null || _mmprojPath == null) {
      print('ERROR: Model not initialized. _modelPath=$_modelPath, _mmprojPath=$_mmprojPath');
      throw Exception('Model not initialized. Please initialize first.');
    }

    print('Using modelPath: $_modelPath');
    print('Using mmprojPath: $_mmprojPath');

    try {
      final completer = Completer<String>();
      String result = '';

      // Read image and convert to base64
      print('Reading image file: $imagePath');
      final imageFile = File(imagePath);
      var imageBytes = await imageFile.readAsBytes();
      print('Original image size: ${imageBytes.length} bytes');

      // Limit image size to 200KB to avoid memory issues
      // The image is already scaled by image_picker, but let's be extra safe
      if (imageBytes.length > 200 * 1024) {
        print('Image too large, using first 200KB only');
        imageBytes = imageBytes.sublist(0, 200 * 1024);
      }

      final base64Image = base64Encode(imageBytes);
      print('Base64 encoded, length: ${base64Image.length} chars');

      // Create message with base64-encoded image (HTML img tag format)
      final messageText = '<img src="data:image/jpeg;base64,$base64Image">\n\nDescribe this image in one sentence.';

      print('Creating OpenAiRequest...');
      final request = OpenAiRequest(
        maxTokens: 50, // Short for one sentence
        messages: [
          Message(Role.user, messageText),
        ],
        modelPath: _modelPath!,
        mmprojPath: _mmprojPath!,
        temperature: 0.7,
        topP: 0.9,
        numGpuLayers: 0,
        contextSize: 2048,
      );

      print('Calling fllamaChat...');
      fllamaChat(request, (response, partialResponse, done) {
        print('fllamaChat callback: response="$response", done=$done');
        result = response;
        if (done) {
          print('Generation complete! Final result: $result');
          completer.complete(result);
        }
      });

      // Wait for generation to complete
      final finalResult = await completer.future;
      print('fllamaChat completed. Result: $finalResult');
      return finalResult.trim().isNotEmpty ? finalResult.trim() : 'No description generated';
    } catch (e) {
      print('ERROR in describeImage: $e');
      throw Exception('Failed to generate description: $e');
    }
  }

  /// Check if the service is initialized
  bool get isInitialized => _isInitialized;

  /// Dispose of resources
  Future<void> dispose() async {
    _modelPath = null;
    _mmprojPath = null;
    _isInitialized = false;
  }
}
