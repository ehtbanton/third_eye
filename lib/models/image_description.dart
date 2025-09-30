class ImageDescription {
  final String description;
  final DateTime timestamp;

  ImageDescription({
    required this.description,
    required this.timestamp,
  });

  factory ImageDescription.fromJson(Map<String, dynamic> json) {
    return ImageDescription(
      description: json['description'] as String,
      timestamp: DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'description': description,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}

class LlamaRequest {
  final String prompt;
  final String imageData;
  final int maxTokens;
  final double temperature;

  LlamaRequest({
    required this.prompt,
    required this.imageData,
    this.maxTokens = 512,
    this.temperature = 0.7,
  });

  Map<String, dynamic> toJson() {
    return {
      'prompt': prompt,
      'image_data': [
        {'data': imageData, 'id': 10}
      ],
      'n_predict': maxTokens,
      'temperature': temperature,
      'stream': false,
    };
  }
}

class LlamaResponse {
  final String content;
  final bool success;
  final String? error;

  LlamaResponse({
    required this.content,
    required this.success,
    this.error,
  });

  factory LlamaResponse.fromJson(Map<String, dynamic> json) {
    return LlamaResponse(
      content: json['content'] as String? ?? '',
      success: true,
    );
  }

  factory LlamaResponse.error(String errorMessage) {
    return LlamaResponse(
      content: '',
      success: false,
      error: errorMessage,
    );
  }
}
