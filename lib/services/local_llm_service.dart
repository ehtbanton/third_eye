import 'dart:async';
import 'dart:io';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class LocalLlmService {
  GenerativeModel? _model;
  bool _isInitialized = false;

  /// Initialize the Gemini API service
  Future<bool> initialize(String modelPath, String mmprojPath) async {
    try {
      // Load API key from environment
      final apiKey = dotenv.env['GEMINI_API_KEY'];
      if (apiKey == null || apiKey.isEmpty || apiKey == 'your_api_key_here') {
        print('ERROR: GEMINI_API_KEY not set in .env file');
        return false;
      }

      // Initialize Gemini model (2.5 Flash with vision support)
      _model = GenerativeModel(
        model: 'gemini-2.0-flash-exp',
        apiKey: apiKey,
      );

      _isInitialized = true;
      print('Gemini API initialized successfully');
      return true;
    } catch (e) {
      print('Failed to initialize Gemini API: $e');
      return false;
    }
  }

  /// Generate a description for an image using Gemini
  Future<String> describeImage(String imagePath) async {
    print('describeImage called with: $imagePath');

    if (!_isInitialized || _model == null) {
      print('ERROR: Model not initialized');
      throw Exception('Model not initialized. Please initialize first.');
    }

    try {
      // Read image file
      print('Reading image file: $imagePath');
      final imageFile = File(imagePath);
      if (!await imageFile.exists()) {
        throw Exception('Image file not found: $imagePath');
      }

      final imageBytes = await imageFile.readAsBytes();
      print('Image size: ${imageBytes.length} bytes');

      // Create image part for Gemini
      final imagePart = DataPart('image/jpeg', imageBytes);

      // Create prompt
      final prompt = TextPart('Describe this image in one sentence.');

      // Generate content with image
      print('Sending request to Gemini API...');
      final response = await _model!.generateContent([
        Content.multi([prompt, imagePart])
      ]);

      final text = response.text;
      print('Gemini response: $text');

      return text?.trim().isNotEmpty == true
          ? text!.trim()
          : 'No description generated';
    } catch (e) {
      print('ERROR in describeImage: $e');
      throw Exception('Failed to generate description: $e');
    }
  }

  /// Extract text from an image using Gemini
  Future<String> extractText(String imagePath) async {
    print('extractText called with: $imagePath');

    if (!_isInitialized || _model == null) {
      print('ERROR: Model not initialized');
      throw Exception('Model not initialized. Please initialize first.');
    }

    try {
      // Read image file
      print('Reading image file: $imagePath');
      final imageFile = File(imagePath);
      if (!await imageFile.exists()) {
        throw Exception('Image file not found: $imagePath');
      }

      final imageBytes = await imageFile.readAsBytes();
      print('Image size: ${imageBytes.length} bytes');

      // Create image part for Gemini
      final imagePart = DataPart('image/jpeg', imageBytes);

      // Create prompt
      final prompt = TextPart('Write out any text that is visible on screen, and nothing else.');

      // Generate content with image
      print('Sending request to Gemini API...');
      final response = await _model!.generateContent([
        Content.multi([prompt, imagePart])
      ]);

      final text = response.text;
      print('Gemini response: $text');

      return text?.trim().isNotEmpty == true
          ? text!.trim()
          : 'No text detected';
    } catch (e) {
      print('ERROR in extractText: $e');
      throw Exception('Failed to extract text: $e');
    }
  }

  /// Recognize face in an image by comparing with known faces
  /// Returns: 'no_face' if no clear single face, person name if matched, or 'unknown' if new face
  Future<String> recognizeFace(String imagePath, List<String> knownFacePaths, Map<String, String> faceNameMap) async {
    print('recognizeFace called with: $imagePath');

    if (!_isInitialized || _model == null) {
      print('ERROR: Model not initialized');
      throw Exception('Model not initialized. Please initialize first.');
    }

    try {
      // Read the captured image
      print('Reading captured image: $imagePath');
      final imageFile = File(imagePath);
      if (!await imageFile.exists()) {
        throw Exception('Image file not found: $imagePath');
      }

      final imageBytes = await imageFile.readAsBytes();
      print('Captured image size: ${imageBytes.length} bytes');

      // Create image part for the captured image
      final capturedImagePart = DataPart('image/jpeg', imageBytes);

      // If there are no known faces, this is definitely a new person
      if (knownFacePaths.isEmpty) {
        print('No known faces in database');
        return 'unknown';
      }

      // Read all known face images
      final knownFaceParts = <DataPart>[];
      final knownFaceNames = <String>[];

      for (final facePath in knownFacePaths) {
        final faceFile = File(facePath);
        if (await faceFile.exists()) {
          final faceBytes = await faceFile.readAsBytes();
          knownFaceParts.add(DataPart('image/jpeg', faceBytes));

          // Get the filename from path
          final filename = facePath.split(Platform.pathSeparator).last;
          final personName = faceNameMap[filename] ?? 'Unknown';
          knownFaceNames.add(personName);
          print('Loaded known face: $filename -> $personName');
        }
      }

      // Create a comprehensive prompt for face recognition
      final prompt = StringBuffer();
      prompt.writeln('Analyze the first image and determine if it contains exactly one clear, visible human face.');
      prompt.writeln('If there is no face, or multiple faces, or the face is unclear, respond with exactly: NO_FACE');
      prompt.writeln('');
      prompt.writeln('If there is exactly one clear face, compare it with the following known faces:');

      for (int i = 0; i < knownFaceNames.length; i++) {
        prompt.writeln('Image ${i + 2}: ${knownFaceNames[i]}');
      }

      prompt.writeln('');
      prompt.writeln('Carefully compare the person in image 1 with each of the known faces.');
      prompt.writeln('If the face in image 1 matches one of the known faces, respond with exactly: MATCHED:<name>');
      prompt.writeln('If the face in image 1 does not match any known face, respond with exactly: UNKNOWN');
      prompt.writeln('');
      prompt.writeln('Be strict in matching - only say MATCHED if you are confident it is the same person.');

      // Build the content array with captured image first, then known faces
      final contentParts = <Part>[
        TextPart(prompt.toString()),
        capturedImagePart,
        ...knownFaceParts,
      ];

      // Generate content
      print('Sending request to Gemini API for face recognition...');
      final response = await _model!.generateContent([
        Content.multi(contentParts)
      ]);

      final text = response.text?.trim() ?? '';
      print('Gemini response: $text');

      // Parse the response
      if (text.startsWith('NO_FACE')) {
        return 'no_face';
      } else if (text.startsWith('MATCHED:')) {
        final name = text.substring('MATCHED:'.length).trim();
        return name;
      } else if (text.startsWith('UNKNOWN')) {
        return 'unknown';
      } else {
        // Default to unknown if response format is unexpected
        print('Unexpected response format, defaulting to unknown');
        return 'unknown';
      }
    } catch (e) {
      print('ERROR in recognizeFace: $e');
      throw Exception('Failed to recognize face: $e');
    }
  }

  /// Check if the service is initialized
  bool get isInitialized => _isInitialized;

  /// Dispose of resources
  Future<void> dispose() async {
    _model = null;
    _isInitialized = false;
    print('Gemini service disposed');
  }
}
