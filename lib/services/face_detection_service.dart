import 'dart:io';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;

enum FaceQualityIssue {
  noFace,
  multipleFaces,
  tooSmall,
  tooBlurry,
  poorLighting,
  faceNotCentered,
}

class FaceQualityResult {
  final bool isGoodQuality;
  final FaceQualityIssue? issue;
  final String? message;
  final Face? detectedFace;
  final double? confidence;

  FaceQualityResult.success(this.detectedFace, this.confidence)
      : isGoodQuality = true,
        issue = null,
        message = null;

  FaceQualityResult.failure(this.issue, this.message)
      : isGoodQuality = false,
        detectedFace = null,
        confidence = null;
}

class FaceDetectionService {
  late FaceDetector _faceDetector;
  bool _isInitialized = false;

  // Quality thresholds
  static const double _minFaceSize = 100.0; // minimum face width in pixels
  static const double _minConfidence = 0.7; // minimum face detection confidence
  static const double _minCenterThreshold = 0.3; // face should be within 30% of image center

  Future<void> initialize() async {
    try {
      // Configure face detector with optimal settings
      final options = FaceDetectorOptions(
        enableContours: false,
        enableClassification: true, // Enable smile and eye open detection
        enableLandmarks: true,
        enableTracking: false,
        minFaceSize: 0.15, // Face must be at least 15% of image
        performanceMode: FaceDetectorMode.accurate,
      );

      _faceDetector = FaceDetector(options: options);
      _isInitialized = true;
      print('Face detection service initialized');
    } catch (e) {
      print('Error initializing face detection service: $e');
      throw Exception('Failed to initialize face detection: $e');
    }
  }

  /// Detect faces and validate image quality
  Future<FaceQualityResult> validateFaceQuality(String imagePath) async {
    if (!_isInitialized) {
      throw Exception('Face detection service not initialized');
    }

    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final faces = await _faceDetector.processImage(inputImage);

      print('Detected ${faces.length} faces');

      // Check if no faces detected
      if (faces.isEmpty) {
        return FaceQualityResult.failure(
          FaceQualityIssue.noFace,
          'No face detected. Please ensure your face is clearly visible.',
        );
      }

      // Check if multiple faces detected
      if (faces.length > 1) {
        return FaceQualityResult.failure(
          FaceQualityIssue.multipleFaces,
          'Multiple faces detected. Please ensure only one person is in frame.',
        );
      }

      final face = faces.first;
      final boundingBox = face.boundingBox;

      print('Face bounding box: ${boundingBox.width} x ${boundingBox.height}');

      // Check face size
      if (boundingBox.width < _minFaceSize || boundingBox.height < _minFaceSize) {
        return FaceQualityResult.failure(
          FaceQualityIssue.tooSmall,
          'Face is too small. Please move closer to the camera.',
        );
      }

      // Estimate confidence based on face quality indicators
      double confidence = 1.0;

      // Check if face landmarks are detected (indicates good face visibility)
      final hasGoodLandmarks = face.landmarks.isNotEmpty;
      if (!hasGoodLandmarks) {
        confidence *= 0.7;
      }

      // Check head rotation (prefer frontal faces)
      final headYaw = face.headEulerAngleY ?? 0;
      final headPitch = face.headEulerAngleX ?? 0;
      final headRoll = face.headEulerAngleZ ?? 0;

      // Penalize extreme head poses
      if (headYaw.abs() > 30 || headPitch.abs() > 30 || headRoll.abs() > 30) {
        confidence *= 0.8;
        print('Warning: Head pose not ideal. Yaw: $headYaw, Pitch: $headPitch, Roll: $headRoll');
      }

      // Check if eyes are open (if classification is available)
      if (face.leftEyeOpenProbability != null && face.rightEyeOpenProbability != null) {
        final leftEyeOpen = face.leftEyeOpenProbability!;
        final rightEyeOpen = face.rightEyeOpenProbability!;

        if (leftEyeOpen < 0.5 || rightEyeOpen < 0.5) {
          confidence *= 0.9;
          print('Warning: Eyes might be closed');
        }
      }

      // Check if face is reasonably centered
      final imageFile = File(imagePath);
      final imageBytes = await imageFile.readAsBytes();
      final decodedImage = img.decodeImage(imageBytes);

      if (decodedImage == null) {
        throw Exception('Failed to decode image for dimension check');
      }

      final imageWidth = decodedImage.width.toDouble();
      final imageHeight = decodedImage.height.toDouble();

      final faceCenterX = boundingBox.left + boundingBox.width / 2;
      final faceCenterY = boundingBox.top + boundingBox.height / 2;
      final imageCenterX = imageWidth / 2;
      final imageCenterY = imageHeight / 2;

      final xOffset = (faceCenterX - imageCenterX).abs() / imageWidth;
      final yOffset = (faceCenterY - imageCenterY).abs() / imageHeight;

      if (xOffset > _minCenterThreshold || yOffset > _minCenterThreshold) {
        return FaceQualityResult.failure(
          FaceQualityIssue.faceNotCentered,
          'Face is not centered. Please center your face in the frame.',
        );
      }

      // Final confidence check
      if (confidence < _minConfidence) {
        return FaceQualityResult.failure(
          FaceQualityIssue.tooBlurry,
          'Image quality is poor. Please ensure good lighting and hold the camera steady.',
        );
      }

      print('Face quality validated. Confidence: ${(confidence * 100).toStringAsFixed(1)}%');
      return FaceQualityResult.success(face, confidence);
    } catch (e) {
      print('Error validating face quality: $e');
      throw Exception('Failed to validate face quality: $e');
    }
  }

  /// Detect all faces in an image (without quality validation)
  Future<List<Face>> detectFaces(String imagePath) async {
    if (!_isInitialized) {
      throw Exception('Face detection service not initialized');
    }

    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final faces = await _faceDetector.processImage(inputImage);
      return faces;
    } catch (e) {
      print('Error detecting faces: $e');
      throw Exception('Failed to detect faces: $e');
    }
  }

  void dispose() {
    _faceDetector.close();
    _isInitialized = false;
    print('Face detection service disposed');
  }

  bool get isInitialized => _isInitialized;
}
