import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'face_detection_service.dart';
import 'face_embedding_service.dart';

class FaceRecognitionService {
  static const String _faceBankFolder = 'face_bank';
  static const String _metadataFile = 'faces.json';
  static const String _embeddingsFile = 'embeddings.json';

  final FaceDetectionService _faceDetector = FaceDetectionService();
  final FaceEmbeddingService _embeddingService = FaceEmbeddingService();

  // Cache embeddings in memory for fast lookups
  List<FaceEmbedding>? _cachedEmbeddings;
  bool _isInitialized = false;

  /// Get the face bank directory path
  Future<Directory> _getFaceBankDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final faceBank = Directory('${appDir.path}/$_faceBankFolder');

    // Create directory if it doesn't exist
    if (!await faceBank.exists()) {
      await faceBank.create(recursive: true);
    }

    return faceBank;
  }

  /// Get the metadata file
  Future<File> _getMetadataFile() async {
    final faceBank = await _getFaceBankDirectory();
    return File('${faceBank.path}/$_metadataFile');
  }

  /// Get the embeddings file
  Future<File> _getEmbeddingsFile() async {
    final faceBank = await _getFaceBankDirectory();
    return File('${faceBank.path}/$_embeddingsFile');
  }

  /// Initialize the face recognition services
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      print('Initializing face detection...');
      await _faceDetector.initialize();

      print('Initializing face embedding service...');
      await _embeddingService.initialize();

      print('Loading embeddings cache...');
      await _loadEmbeddingsCache();

      _isInitialized = true;
      print('Face recognition service initialized successfully');
    } catch (e) {
      print('ERROR: Failed to initialize face recognition service: $e');
      _isInitialized = false;
      throw Exception('Failed to initialize face recognition: $e');
    }
  }

  /// Load face metadata (maps image filenames to person names)
  Future<Map<String, String>> loadFaceMetadata() async {
    try {
      final metadataFile = await _getMetadataFile();

      if (!await metadataFile.exists()) {
        return {};
      }

      final content = await metadataFile.readAsString();
      final Map<String, dynamic> json = jsonDecode(content);

      // Convert to Map<String, String>
      return json.map((key, value) => MapEntry(key, value.toString()));
    } catch (e) {
      print('Error loading face metadata: $e');
      return {};
    }
  }

  /// Save face metadata
  Future<void> saveFaceMetadata(Map<String, String> metadata) async {
    try {
      final metadataFile = await _getMetadataFile();
      final json = jsonEncode(metadata);
      await metadataFile.writeAsString(json);
    } catch (e) {
      print('Error saving face metadata: $e');
      throw Exception('Failed to save face metadata: $e');
    }
  }

  /// Load face embeddings
  Future<List<FaceEmbedding>> loadEmbeddings() async {
    try {
      final embeddingsFile = await _getEmbeddingsFile();

      if (!await embeddingsFile.exists()) {
        return [];
      }

      final content = await embeddingsFile.readAsString();
      final List<dynamic> jsonList = jsonDecode(content);

      return jsonList.map((json) => FaceEmbedding.fromJson(json)).toList();
    } catch (e) {
      print('Error loading embeddings: $e');
      return [];
    }
  }

  /// Save face embeddings
  Future<void> saveEmbeddings(List<FaceEmbedding> embeddings) async {
    try {
      final embeddingsFile = await _getEmbeddingsFile();
      final jsonList = embeddings.map((e) => e.toJson()).toList();
      final json = jsonEncode(jsonList);
      await embeddingsFile.writeAsString(json);

      // Update cache
      _cachedEmbeddings = embeddings;
    } catch (e) {
      print('Error saving embeddings: $e');
      throw Exception('Failed to save embeddings: $e');
    }
  }

  /// Load embeddings into cache
  Future<void> _loadEmbeddingsCache() async {
    _cachedEmbeddings = await loadEmbeddings();
    print('Loaded ${_cachedEmbeddings?.length ?? 0} embeddings into cache');
  }

  /// Add a new face to the bank with quality validation
  /// Returns the filename if successful, throws exception if quality check fails
  Future<String> addFace(File imageFile, String personName) async {
    if (!_isInitialized) {
      throw Exception('Service not initialized. Call initialize() first.');
    }

    try {
      // Step 1: Validate face quality
      print('Validating face quality...');
      final qualityResult = await _faceDetector.validateFaceQuality(imageFile.path);

      if (!qualityResult.isGoodQuality) {
        throw Exception(qualityResult.message ?? 'Face quality check failed');
      }

      print('Face quality validated: ${(qualityResult.confidence! * 100).toStringAsFixed(1)}% confidence');

      // Step 2: Extract face embedding
      print('Extracting face embedding...');
      final embedding = await _embeddingService.extractEmbedding(
        imageFile.path,
        face: qualityResult.detectedFace,
      );

      // Step 3: Save image to face bank
      final faceBank = await _getFaceBankDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final filename = 'face_${timestamp}.jpg';
      final savedFile = File('${faceBank.path}/$filename');

      await imageFile.copy(savedFile.path);

      // Step 4: Update metadata
      final metadata = await loadFaceMetadata();
      metadata[filename] = personName;
      await saveFaceMetadata(metadata);

      // Step 5: Save embedding
      final embeddings = _cachedEmbeddings ?? [];
      embeddings.add(FaceEmbedding(
        embedding: embedding,
        personName: personName,
        imageFilename: filename,
      ));
      await saveEmbeddings(embeddings);

      print('Added face: $filename -> $personName with ${embedding.length}-dim embedding');
      return filename;
    } catch (e) {
      print('Error adding face: $e');
      throw Exception('Failed to add face: $e');
    }
  }

  /// Get all face images from the bank
  Future<List<File>> getAllFaceImages() async {
    try {
      final faceBank = await _getFaceBankDirectory();
      final files = await faceBank.list().toList();

      // Filter only image files (not the metadata file)
      return files
          .whereType<File>()
          .where((file) => file.path.endsWith('.jpg') || file.path.endsWith('.jpeg') || file.path.endsWith('.png'))
          .toList();
    } catch (e) {
      print('Error getting face images: $e');
      return [];
    }
  }

  /// Get person name from filename
  Future<String?> getPersonName(String filename) async {
    final metadata = await loadFaceMetadata();
    return metadata[filename];
  }

  /// Recognize face in image
  /// Returns: FaceQualityResult with issue if quality check fails,
  /// or FaceMatch with person name and confidence if match found,
  /// or null if no match (unknown person)
  Future<({FaceQualityResult? qualityIssue, FaceMatch? match})> recognizeFace(
    File imageFile,
  ) async {
    if (!_isInitialized) {
      throw Exception('Service not initialized. Call initialize() first.');
    }

    try {
      // Step 1: Validate face quality
      print('Validating face quality...');
      final qualityResult = await _faceDetector.validateFaceQuality(imageFile.path);

      if (!qualityResult.isGoodQuality) {
        return (qualityIssue: qualityResult, match: null);
      }

      print('Face quality validated: ${(qualityResult.confidence! * 100).toStringAsFixed(1)}% confidence');

      // Step 2: Extract face embedding
      print('Extracting face embedding...');
      final embedding = await _embeddingService.extractEmbedding(
        imageFile.path,
        face: qualityResult.detectedFace,
      );

      // Step 3: Find best match in cached embeddings
      final knownEmbeddings = _cachedEmbeddings ?? [];

      if (knownEmbeddings.isEmpty) {
        print('No known faces in database');
        return (qualityIssue: null, match: null);
      }

      final match = _embeddingService.findBestMatch(embedding, knownEmbeddings);

      if (match != null) {
        print('Match found: ${match.personName} (${(match.similarity * 100).toStringAsFixed(1)}% similarity)');
      } else {
        print('No match found (similarity below threshold)');
      }

      return (qualityIssue: null, match: match);
    } catch (e) {
      print('Error recognizing face: $e');
      throw Exception('Failed to recognize face: $e');
    }
  }

  /// Validate face quality without recognition
  Future<FaceQualityResult> validateFaceQuality(File imageFile) async {
    if (!_isInitialized) {
      throw Exception('Service not initialized. Call initialize() first.');
    }

    return await _faceDetector.validateFaceQuality(imageFile.path);
  }

  /// Clear all faces from the bank (for testing/debugging)
  Future<void> clearAllFaces() async {
    try {
      final faceBank = await _getFaceBankDirectory();
      await faceBank.delete(recursive: true);
      await faceBank.create(recursive: true);

      // Clear cache
      _cachedEmbeddings = [];

      print('Face bank cleared');
    } catch (e) {
      print('Error clearing face bank: $e');
    }
  }

  /// Dispose of resources
  void dispose() {
    _faceDetector.dispose();
    _embeddingService.dispose();
    _cachedEmbeddings = null;
    _isInitialized = false;
  }

  bool get isInitialized => _isInitialized;
  int get cachedFaceCount => _cachedEmbeddings?.length ?? 0;
}
