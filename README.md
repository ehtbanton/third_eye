# third_eye

Vision Assistance, In Style

A Flutter application that provides vision assistance using AI models, supporting both cloud-based (Google Gemini) and local inference options.

## Prerequisites

Before you begin, ensure you have the following installed:

- **Flutter SDK** (3.5.4 or higher)
  - [Installation guide](https://docs.flutter.dev/get-started/install)
- **Android Studio** or **Android SDK** (for Android builds)
  - Android SDK 24 or higher
  - Android NDK (if building with native llama.cpp support)
- **Git**

## Project Setup

### 1. Clone the Repository

```bash
git clone <repository-url>
cd third_eye
```

### 2. Configure Environment Variables

Copy the example environment file and add your API keys:

```bash
cp .env.example .env
```

Edit `.env` and add your Google Gemini API key:
```
GEMINI_API_KEY=your_actual_api_key_here
```

Get your Gemini API key from: https://makersuite.google.com/app/apikey

### 3. Configure Android Build Paths

Copy the local properties template:

```bash
cp android/local.properties.example android/local.properties
```

Edit `android/local.properties` and update paths for your system:

#### Standard Setup (Most Users)
```properties
sdk.dir=/path/to/your/Android/Sdk
flutter.sdk=/path/to/your/flutter
```

**Finding your SDK paths:**
- **Android SDK**: Usually at:
  - Linux/Mac: `~/Android/Sdk` or `~/Library/Android/sdk`
  - Windows: `C:\Users\<username>\AppData\Local\Android\Sdk`
  - Or run: `echo $ANDROID_HOME` (if set)

- **Flutter SDK**: Usually where you installed Flutter:
  - Run: `which flutter` to find it
  - Or check: `echo $FLUTTER_ROOT`

#### Advanced: Custom CMake (Optional)

If you're building with custom CMake (e.g., Termux users):
```properties
cmake.dir=/data/data/com.termux/files/usr
```

Most users can omit this line - the Android NDK includes CMake automatically.

### 4. Install Dependencies

```bash
flutter pub get
```

### 5. Build and Run

#### For Android:

```bash
# Debug build
flutter run

# Release APK
flutter build apk --release

# App Bundle (for Play Store)
flutter build appbundle --release
```

#### For other platforms:

```bash
# Linux
flutter run -d linux

# Web
flutter run -d chrome
```

## Features

- 📸 **Image Capture & Selection**: Take photos or select from gallery
- 🤖 **AI Vision Analysis**: Describe images using Google Gemini API
- 🔒 **Privacy Focused**: Uses your own API key
- 🎨 **Modern UI**: Clean, accessible interface

## Architecture

- **Frontend**: Flutter/Dart
- **AI Models**:
  - Google Gemini Vision API (cloud)
  - llama.cpp integration (local - experimental, see `NATIVE_LLM_SETUP.md`)

## Troubleshooting

### Build fails with "SDK location not found"
- Ensure `android/local.properties` exists and has correct paths
- Run `flutter doctor` to verify your Flutter/Android setup

### API key errors
- Verify your `.env` file exists and has a valid `GEMINI_API_KEY`
- Ensure `.env` is in the project root directory

### CMake errors
- If not using custom CMake, remove the `cmake.dir` line from `local.properties`
- Ensure Android NDK is installed via Android Studio SDK Manager

### Gradle build fails
- Try `flutter clean` then rebuild
- Check `android/app/build.gradle` for correct SDK versions
- Ensure you have Java 8+ installed

## Contributing

1. Fork the repository
2. Create your feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## License

[Add your license here]

## Resources

- [Flutter Documentation](https://docs.flutter.dev/)
- [Google Gemini API Docs](https://ai.google.dev/docs)
- [Native LLM Setup Guide](./NATIVE_LLM_SETUP.md)