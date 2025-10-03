import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/llama_service.dart';

class ImagePickerScreen extends StatefulWidget {
  const ImagePickerScreen({super.key});

  @override
  State<ImagePickerScreen> createState() => _ImagePickerScreenState();
}

class _ImagePickerScreenState extends State<ImagePickerScreen> {
  final LlamaService _llamaService = LlamaService();

  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  File? _capturedImage;
  String _description = '';
  bool _isLoading = false;
  bool _serverAvailable = false;
  bool _isInitializing = false;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    setState(() {
      _isInitializing = true;
    });

    // Request camera permission
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      setState(() {
        _isInitializing = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Camera permission is required'),
            duration: Duration(seconds: 5),
          ),
        );
      }
      return;
    }

    // Get available cameras
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        throw Exception('No cameras found');
      }

      // Initialize camera controller with back camera
      _cameraController = CameraController(
        _cameras.first,
        ResolutionPreset.high,
        enableAudio: false,
      );

      await _cameraController!.initialize();

      // Initialize Gemini API
      final success = await _llamaService.initialize();

      if (mounted) {
        setState(() {
          _isInitializing = false;
          _serverAvailable = success;
        });

        if (!success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to initialize: Check your API key in .env'),
              duration: Duration(seconds: 5),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      setState(() {
        _isInitializing = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Camera initialization failed: $e'),
            duration: const Duration(seconds: 5),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _captureAndDescribe() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    try {
      setState(() {
        _isLoading = true;
        _description = '';
      });

      // Capture image
      final XFile imageFile = await _cameraController!.takePicture();
      final File capturedFile = File(imageFile.path);

      setState(() {
        _capturedImage = capturedFile;
      });

      // Get description from LLM
      final response = await _llamaService.describeImage(capturedFile.path);

      setState(() {
        if (response.success) {
          _description = response.content;
        } else {
          _description = 'Error: ${response.error}';
        }
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _description = 'Error: $e';
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _llamaService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _isInitializing
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 16),
                  Text(
                    'Initializing camera...',
                    style: TextStyle(color: Colors.white),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                // Top half: Live camera preview with capture button
                Expanded(
                  flex: 1,
                  child: Stack(
                    children: [
                      // Camera preview
                      if (_cameraController != null &&
                          _cameraController!.value.isInitialized)
                        Center(
                          child: AspectRatio(
                            aspectRatio: _cameraController!.value.aspectRatio,
                            child: CameraPreview(_cameraController!),
                          ),
                        )
                      else
                        const Center(
                          child: Text(
                            'Camera not available',
                            style: TextStyle(color: Colors.white),
                          ),
                        ),

                      // Status indicator (top right)
                      Positioned(
                        top: 40,
                        right: 16,
                        child: Icon(
                          _serverAvailable ? Icons.check_circle : Icons.error,
                          color: _serverAvailable ? Colors.green : Colors.red,
                          size: 32,
                        ),
                      ),

                      // Capture button (bottom center)
                      Positioned(
                        bottom: 20,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: FloatingActionButton(
                            onPressed: _isLoading || !_serverAvailable
                                ? null
                                : _captureAndDescribe,
                            backgroundColor: _serverAvailable
                                ? Colors.white
                                : Colors.grey,
                            child: const Icon(
                              Icons.camera_alt,
                              color: Colors.black,
                              size: 32,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Bottom half: Image preview (left) and description (right)
                Expanded(
                  flex: 1,
                  child: Container(
                    color: Colors.grey[900],
                    child: Row(
                      children: [
                        // Left: Image preview
                        Expanded(
                          flex: 1,
                          child: Container(
                            padding: const EdgeInsets.all(8.0),
                            child: _capturedImage != null
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.file(
                                      _capturedImage!,
                                      fit: BoxFit.contain,
                                    ),
                                  )
                                : Center(
                                    child: Icon(
                                      Icons.image_outlined,
                                      size: 64,
                                      color: Colors.grey[700],
                                    ),
                                  ),
                          ),
                        ),

                        // Right: Description
                        Expanded(
                          flex: 1,
                          child: Container(
                            padding: const EdgeInsets.all(16.0),
                            child: _isLoading
                                ? const Center(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        CircularProgressIndicator(
                                            color: Colors.white),
                                        SizedBox(height: 16),
                                        Text(
                                          'Analyzing...',
                                          style: TextStyle(color: Colors.white),
                                        ),
                                      ],
                                    ),
                                  )
                                : _description.isNotEmpty
                                    ? SingleChildScrollView(
                                        child: Text(
                                          _description,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 14,
                                          ),
                                        ),
                                      )
                                    : Center(
                                        child: Text(
                                          'Tap the button to capture',
                                          style: TextStyle(
                                            color: Colors.grey[600],
                                            fontSize: 14,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
