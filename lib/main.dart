import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'screens/image_picker_screen.dart';

Future<void> main() async {
  // Load environment variables
  await dotenv.load(fileName: ".env");
  runApp(const ThirdEyeApp());
}

class ThirdEyeApp extends StatelessWidget {
  const ThirdEyeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Third Eye',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const ImagePickerScreen(),
    );
  }
}
