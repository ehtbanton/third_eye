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
    // Request storage permission
    final status = await Permission.storage.request();
    if (!status.isGranted) {
      // Try manageExternalStorage for Android 11+
      final manageStatus = await Permission.manageExternalStorage.request();
      if (!manageStatus.isGranted) {
        setState(() {
          _serverAvailable = false;
          _isInitializing = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Storage permission is required to download the AI model'),
              duration: Duration(seconds: 5),
            ),
          );
        }
        return;
      }
    }

    // Permission granted, initialize
    await _initializeLlm();
  }

  Future<void> _initializeLlm() async {
    setState(() {
      _isInitializing = true;
      _downloadProgress = 0.0;
    });

    final success = await _llamaService.initialize(
      onDownloadProgress: (progress) {
        if (mounted) {
          setState(() {
            _downloadProgress = progress;
          });
        }
      },
    );

    if (mounted) {
      setState(() {
        _isInitializing = false;
        _serverAvailable = success;
      });

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('AI model ready!'),
            duration: Duration(seconds: 2),
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

  Future<void> _pickAndDescribeImage() async {
    try {
      setState(() {
        _isLoading = true;
        _description = '';
      });

      // Pick image
      final image = await _imageService.pickImage();
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

              // Model initialization indicator
              if (_isInitializing)
                Card(
                  color: Colors.blue[50],
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        const Text(
                          'Initializing AI Model...',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        LinearProgressIndicator(value: _downloadProgress),
                        const SizedBox(height: 8),
                        Text(
                          _downloadProgress > 0
                              ? 'Downloading: ${(_downloadProgress * 100).toStringAsFixed(0)}%'
                              : 'Loading...',
                          style: const TextStyle(fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ),

              // Pick image button
              if (!_isInitializing)
                ElevatedButton.icon(
                  onPressed: _isLoading || !_serverAvailable
                      ? null
                      : _pickAndDescribeImage,
                  icon: const Icon(Icons.photo_library),
                  label: const Text('Select Image'),
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

              // Server status info
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
                            'AI model failed to initialize. Please restart the app.',
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
