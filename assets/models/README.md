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

---

# HITNet Stereo Depth Model

This directory should also contain the HITNet TFLite model for stereoscopic depth estimation.

## Required File

- `hitnet_middlebury_480x640.tflite` - The stereo depth estimation model

## How to Get the Model

### Option 1: Download from PINTO Model Zoo

1. Download the model archive:
   ```bash
   wget https://s3.ap-northeast-2.wasabisys.com/pinto-model-zoo/142_HITNET/resources.tar.gz
   ```

2. Extract the archive:
   ```bash
   tar -xzf resources.tar.gz
   ```

3. Find the appropriate TFLite model in the extracted files:
   - Look for `middlebury_d400` variant
   - Choose the `480x640` resolution for quality or `320x240` for speed
   - Copy the `.tflite` file to this directory as `hitnet_middlebury_480x640.tflite`

### Option 2: Convert from ONNX

If you have the ONNX model, convert to TFLite using PINTO's onnx2tf tool:
```bash
pip install onnx2tf
onnx2tf -i hitnet.onnx -o output_tflite
```

## Model Specifications

The HITNet model expects:
- **Input**: Concatenated left+right RGB images
  - Shape: `(1, 480, 640, 6)` for the 480x640 model
  - 6 channels = left RGB (3) + right RGB (3)
  - Values normalized to [0, 1]

- **Output**: Disparity map
  - Shape: `(1, 480, 640, 1)`
  - Higher values = closer objects

## Performance Notes

- The 480x640 model provides better quality but slower inference (~3-5 FPS on mobile)
- The 320x240 model is faster (~10-15 FPS) but lower resolution
- GPU delegate significantly improves performance on supported devices
- Samsung S24 Ultra with Exynos NPU can achieve ~2+ FPS with GPU delegate

## Verification

After adding the model, the Stereo Depth screen will:
1. Load the model when initialized
2. Print tensor information for debugging
3. Show "GPU delegate enabled" indicator if hardware acceleration is active

Without the model, depth estimation will not work and the screen will show an error.
