import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/image_service.dart';
import '../services/llama_service.dart';

class ImagePickerScreen extends StatefulWidget {
  const ImagePickerScreen({super.key});

  @override
  State<ImagePickerScreen> createState() => _ImagePickerScreenState();
}

class _ImagePickerScreenState extends State<ImagePickerScreen> {
  final ImageService _imageService = ImageService();
  final LlamaService _llamaService = LlamaService();

  File? _selectedImage;
  String _description = '';
  bool _isLoading = false;
  bool _serverAvailable = false;
  bool _isInitializing = false;
  double _downloadProgress = 0.0;

  @override
  void initState() {
    super.initState();
    _requestPermissionsAndInitialize();
  }

  Future<void> _requestPermissionsAndInitialize() async {
    // Request camera permission
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      setState(() {
        _serverAvailable = false;
        _isInitializing = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Camera permission is required to take photos'),
            duration: Duration(seconds: 5),
          ),
        );
      }
      return;
    }

    // Permission granted, initialize
    await _initializeLlm();
  }

  Future<void> _initializeLlm() async {
    setState(() {
      _isInitializing = true;
      _downloadProgress = 0.0;
    });

    // Initialize Gemini API (no model download needed!)
    final success = await _llamaService.initialize();

    if (mounted) {
      setState(() {
        _isInitializing = false;
        _serverAvailable = success;
      });

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Gemini API ready!'),
            duration: Duration(seconds: 2),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to initialize: Check your API key in .env'),
            duration: Duration(seconds: 5),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _checkServerHealth() async {
    final isHealthy = await _llamaService.checkServerHealth();
    setState(() {
      _serverAvailable = isHealthy;
    });
  }

  Future<void> _takePhotoAndDescribe() async {
    try {
      setState(() {
        _isLoading = true;
        _description = '';
      });

      // Take photo
      final image = await _imageService.takePhoto();
      if (image == null) {
        setState(() {
          _isLoading = false;
        });
        return;
      }

      setState(() {
        _selectedImage = image;
      });

      // Get description from LLM using image path
      final response = await _llamaService.describeImage(image.path);

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
    _llamaService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Third Eye'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: Icon(
              _serverAvailable ? Icons.cloud_done : Icons.cloud_off,
              color: _serverAvailable ? Colors.green : Colors.red,
            ),
            onPressed: _checkServerHealth,
            tooltip: _serverAvailable ? 'Server connected' : 'Server offline',
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Image preview
              if (_selectedImage != null)
                Container(
                  height: 300,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(
                      _selectedImage!,
                      fit: BoxFit.contain,
                    ),
                  ),
                )
              else
                Container(
                  height: 300,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey),
                    color: Colors.grey[200],
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.image,
                      size: 64,
                      color: Colors.grey,
                    ),
                  ),
                ),

              const SizedBox(height: 24),

              // API initialization indicator
              if (_isInitializing)
                Card(
                  color: Colors.blue[50],
                  child: const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        Text(
                          'Connecting to Gemini API...',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 12),
                        CircularProgressIndicator(),
                      ],
                    ),
                  ),
                ),

              // Take photo button
              if (!_isInitializing)
                ElevatedButton.icon(
                  onPressed: _isLoading || !_serverAvailable
                      ? null
                      : _takePhotoAndDescribe,
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Take Photo'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),

              const SizedBox(height: 24),

              // Loading indicator or description
              if (_isLoading)
                const Center(
                  child: Column(
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Analyzing image...'),
                    ],
                  ),
                )
              else if (_description.isNotEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Description:',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _description,
                          style: const TextStyle(fontSize: 16),
                        ),
                      ],
                    ),
                  ),
                ),

              const SizedBox(height: 16),

              // API status info
              if (!_serverAvailable && !_isInitializing)
                Card(
                  color: Colors.orange[100],
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Row(
                      children: [
                        const Icon(Icons.warning, color: Colors.orange),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Gemini API not connected. Check your API key in .env file.',
                            style: TextStyle(fontSize: 14),
                          ),
                        ),
                        TextButton(
                          onPressed: _requestPermissionsAndInitialize,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
