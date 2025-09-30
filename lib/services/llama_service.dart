import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/image_description.dart';

class LlamaService {
  final String baseUrl;
  final http.Client _client;

  LlamaService({
    this.baseUrl = 'http://localhost:8080',
    http.Client? client,
  }) : _client = client ?? http.Client();

  /// Send image to llama.cpp server for description
  Future<LlamaResponse> describeImage(String base64Image) async {
    try {
      final request = LlamaRequest(
        prompt:
            'USER: [img-10]Describe this image in detail.\nASSISTANT:',
        imageData: base64Image,
        maxTokens: 512,
        temperature: 0.7,
      );

      final response = await _client
          .post(
            Uri.parse('$baseUrl/completion'),
            headers: {
              'Content-Type': 'application/json',
            },
            body: jsonEncode(request.toJson()),
          )
          .timeout(
            const Duration(seconds: 60),
            onTimeout: () {
              throw Exception('Request timeout - server took too long to respond');
            },
          );

      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(response.body) as Map<String, dynamic>;
        return LlamaResponse.fromJson(jsonResponse);
      } else {
        return LlamaResponse.error(
          'Server error: ${response.statusCode} - ${response.body}',
        );
      }
    } catch (e) {
      return LlamaResponse.error('Failed to connect to LLM server: $e');
    }
  }

  /// Check if the llama.cpp server is running and accessible
  Future<bool> checkServerHealth() async {
    try {
      final response = await _client
          .get(Uri.parse('$baseUrl/health'))
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// Update server URL
  void updateServerUrl(String newUrl) {
    // This would require creating a new instance in production
    // Kept simple for this implementation
  }

  void dispose() {
    _client.close();
  }
}
