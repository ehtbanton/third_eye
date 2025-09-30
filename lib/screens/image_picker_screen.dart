import 'dart:io';
import 'package:flutter/material.dart';
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

  @override
  void initState() {
    super.initState();
    _checkServerHealth();
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

      // Convert to base64
      final base64Image = await _imageService.imageToBase64(image);

      // Get description from LLM
      final response = await _llamaService.describeImage(base64Image);

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

              // Pick image button
              ElevatedButton.icon(
                onPressed: _isLoading ? null : _pickAndDescribeImage,
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
              if (!_serverAvailable)
                Card(
                  color: Colors.orange[100],
                  child: const Padding(
                    padding: EdgeInsets.all(12.0),
                    child: Row(
                      children: [
                        Icon(Icons.warning, color: Colors.orange),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'LLM server not detected. Make sure llama.cpp server is running on localhost:8080',
                            style: TextStyle(fontSize: 14),
                          ),
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
