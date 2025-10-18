import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class FaceEmbedding {
  final List<double> embedding;
  final String personName;
  final String imageFilename;

  FaceEmbedding({
    required this.embedding,
    required this.personName,
    required this.imageFilename,
  });

  Map<String, dynamic> toJson() => {
        'embedding': embedding,
        'personName': personName,
        'imageFilename': imageFilename,
      };

  factory FaceEmbedding.fromJson(Map<String, dynamic> json) {
    return FaceEmbedding(
      embedding: (json['embedding'] as List).map((e) => e as double).toList(),
      personName: json['personName'] as String,
      imageFilename: json['imageFilename'] as String,
    );
  }
}

class FaceMatch {
  final String personName;
  final double similarity;
  final String imageFilename;

  FaceMatch({
    required this.personName,
    required this.similarity,
    required this.imageFilename,
  });
}

class FaceEmbeddingService {
  Interpreter? _interpreter;
  bool _isInitialized = false;

  // Model input/output dimensions (for MobileFaceNet: 112x112x3 -> 192-dim embedding)
  // For FaceNet: 160x160x3 -> 512-dim embedding
  static const int _inputSize = 112; // MobileFaceNet uses 112x112
  static const int _embeddingSize = 192; // MobileFaceNet outputs 192-dim embeddings
  static const double _matchThreshold = 0.8; // Cosine similarity threshold

  Future<void> initialize() async {
    try {
      // Load the FaceNet/MobileFaceNet model from assets
      // Download MobileFaceNet from: https://github.com/sirius-ai/MobileFaceNet_TF
      // Place model file in assets/models/mobilefacenet.tflite

      _interpreter = await Interpreter.fromAsset('assets/models/mobilefacenet.tflite');
      print('TFLite face recognition model loaded successfully');
      _isInitialized = true;
    } catch (e) {
      print('ERROR: Failed to initialize face embedding service: $e');
      print('Make sure mobilefacenet.tflite model is in assets/models/');
      _isInitialized = false;
      throw Exception('Failed to load face recognition model. Please add mobilefacenet.tflite to assets/models/');
    }
  }

  /// Extract face embedding from image
  /// If face bounds are provided, crop to face region first
  Future<List<double>> extractEmbedding(String imagePath, {Face? face}) async {
    if (!_isInitialized || _interpreter == null) {
      throw Exception('Face embedding service not initialized. TFLite model must be loaded.');
    }

    try {
      // Load and preprocess image
      final imageFile = File(imagePath);
      final imageBytes = await imageFile.readAsBytes();
      img.Image? image = img.decodeImage(imageBytes);

      if (image == null) {
        throw Exception('Failed to decode image');
      }

      // Crop to face region if bounds provided
      if (face != null) {
        final bounds = face.boundingBox;
        image = img.copyCrop(
          image,
          x: bounds.left.toInt(),
          y: bounds.top.toInt(),
          width: bounds.width.toInt(),
          height: bounds.height.toInt(),
        );
      }

      // Resize to model input size
      image = img.copyResize(image, width: _inputSize, height: _inputSize);

      // Convert to normalized float array
      final input = _imageToByteListFloat32(image);

      // Prepare output buffer
      final output = List.generate(1, (_) => List.filled(_embeddingSize, 0.0));

      // Run inference
      _interpreter!.run(input, output);

      // Extract and normalize embedding
      final embedding = output[0];
      return _normalizeEmbedding(embedding);
    } catch (e) {
      print('Error extracting embedding: $e');
      throw Exception('Failed to extract face embedding: $e');
    }
  }

  /// Convert image to normalized float array for model input
  List<List<List<List<double>>>> _imageToByteListFloat32(img.Image image) {
    // Create a 4D list: [1, height, width, channels]
    final input = List.generate(
      1,
      (_) => List.generate(
        _inputSize,
        (y) => List.generate(
          _inputSize,
          (x) {
            final pixel = image.getPixel(x, y);
            // Normalize to [-1, 1]
            return [
              (pixel.r - 127.5) / 127.5,
              (pixel.g - 127.5) / 127.5,
              (pixel.b - 127.5) / 127.5,
            ];
          },
        ),
      ),
    );

    return input;
  }

  /// Normalize embedding vector (L2 normalization)
  List<double> _normalizeEmbedding(List<double> embedding) {
    final norm = math.sqrt(embedding.fold(0.0, (sum, val) => sum + val * val));
    if (norm == 0) return embedding;
    return embedding.map((v) => v / norm).toList();
  }

  /// Calculate cosine similarity between two embeddings
  double calculateSimilarity(List<double> embedding1, List<double> embedding2) {
    if (embedding1.length != embedding2.length) {
      throw Exception('Embeddings must have same length');
    }

    double dotProduct = 0.0;
    for (int i = 0; i < embedding1.length; i++) {
      dotProduct += embedding1[i] * embedding2[i];
    }

    // Since embeddings are normalized, dot product = cosine similarity
    return dotProduct;
  }

  /// Find best match for a face embedding from a list of known embeddings
  FaceMatch? findBestMatch(
    List<double> queryEmbedding,
    List<FaceEmbedding> knownEmbeddings,
  ) {
    if (knownEmbeddings.isEmpty) {
      return null;
    }

    FaceMatch? bestMatch;
    double bestSimilarity = -1.0;

    for (final knownEmbedding in knownEmbeddings) {
      final similarity = calculateSimilarity(queryEmbedding, knownEmbedding.embedding);

      if (similarity > bestSimilarity && similarity >= _matchThreshold) {
        bestSimilarity = similarity;
        bestMatch = FaceMatch(
          personName: knownEmbedding.personName,
          similarity: similarity,
          imageFilename: knownEmbedding.imageFilename,
        );
      }
    }

    return bestMatch;
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _isInitialized = false;
    print('Face embedding service disposed');
  }

  bool get isInitialized => _isInitialized;
  double get matchThreshold => _matchThreshold;
}
