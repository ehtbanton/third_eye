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

## Contributing

1. Fork the repository
2. Create your feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

- [Flutter Documentation](https://docs.flutter.dev/)
- [Google Gemini API Docs](https://ai.google.dev/docs)
- [Native LLM Setup Guide](./NATIVE_LLM_SETUP.md)
