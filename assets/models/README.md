# Face Recognition Model

This directory should contain the MobileFaceNet TFLite model for face recognition.

## Required File

- `mobilefacenet.tflite` - The face recognition model file

## How to Get the Model

### Option 1: Pre-converted MobileFaceNet
1. Download from: https://github.com/sirius-ai/MobileFaceNet_TF
2. Look for the `.tflite` file in their releases
3. Place it in this directory as `mobilefacenet.tflite`

### Option 2: Convert from TensorFlow
If you have a TensorFlow model, you can convert it to TFLite format:
```python
import tensorflow as tf

converter = tf.lite.TFLiteConverter.from_saved_model('path/to/saved_model')
converter.optimizations = [tf.lite.Optimize.DEFAULT]
tflite_model = converter.convert()

with open('mobilefacenet.tflite', 'wb') as f:
    f.write(tflite_model)
```

### Option 3: Use a Pre-trained Model
Search for "mobilefacenet.tflite" or "facenet.tflite" models online. Common sources:
- TensorFlow Model Garden
- MediaPipe models
- Community-shared models on GitHub

## Model Specifications

The current code expects:
- Input size: 112x112x3 (RGB image)
- Output size: 192-dimensional embedding vector
- Input normalization: [-1, 1] range

If using a different model (like FaceNet with 160x160 input and 512-dim output), update the constants in `lib/services/face_embedding_service.dart`:
- `_inputSize`
- `_embeddingSize`

## Verification

After adding the model, the app will:
1. Load the model on startup
2. Print "TFLite face recognition model loaded successfully" if successful
3. Throw an error if the model is missing or invalid

Without the model, face recognition features will not work and will show an error message.
