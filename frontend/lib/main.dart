import 'dart:typed_data';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const MyApp());
}

// Main App Widget
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SnackBuddy',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF1B1B1B), // Darker matte grey
        primaryColor: Colors.grey[850], // Very dark grey for primary elements
        colorScheme: ColorScheme.dark(
          primary: Colors.grey.shade700, // Dark grey for active elements
          secondary: Colors.grey.shade600, // Slightly lighter for secondary
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF2A2A2A), // Dark grey inside textboxes
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.grey.shade700),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.grey.shade700),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.grey.shade500),
          ),
          labelStyle: const TextStyle(color: Colors.white70),
          hintStyle: const TextStyle(color: Colors.white54),
        ),
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: Colors.white),
          bodyMedium: TextStyle(color: Colors.white70),
          titleLarge: TextStyle(color: Colors.white),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.deepPurpleAccent,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
      home: const HomePage(),
    );
  }
}


// HomePage StatefulWidget
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

// HomePage State
class _HomePageState extends State<HomePage> {
  File? _image;
  Uint8List? _webImage;
  String _result = '';
  final picker = ImagePicker();
  final TextEditingController _allergenController = TextEditingController();

  Future<void> _pickImage(ImageSource source) async {
    final pickedFile = await picker.pickImage(source: source);

    if (pickedFile != null) {
      if (kIsWeb) {
        final bytes = await pickedFile.readAsBytes();
        setState(() {
          _webImage = bytes;
          _image = null; // Clear mobile image
        });
      } else {
        setState(() {
          _image = File(pickedFile.path);
          _webImage = null; // Clear web image
        });
      }
    }
  }

  Future<void> _uploadImage() async {
    if ((_image == null && _webImage == null) || _allergenController.text.isEmpty) return;

    final request = http.MultipartRequest(
      'POST',
      Uri.parse('http://localhost:8000/upload?allergens=${_allergenController.text}'),
    );

    if (kIsWeb && _webImage != null) {
      request.files.add(
        http.MultipartFile.fromBytes(
          'image',
          _webImage!,
          filename: 'upload.png',
        ),
      );
    } else if (_image != null) {
      request.files.add(await http.MultipartFile.fromPath('image', _image!.path));
    }

    final response = await request.send();
    final respStr = await response.stream.bytesToString();

    setState(() {
      if (response.statusCode == 200) {
        _result = jsonDecode(respStr)['allergens'].map((a) => a['name']).join(', ');
      } else {
        _result = 'Error: Make sure the barcode is clearly visible';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    Widget imageDisplay;
    if (kIsWeb && _webImage != null) {
      imageDisplay = Image.memory(_webImage!, height: 200, fit: BoxFit.cover);
    } else if (_image != null) {
      imageDisplay = Image.file(_image!, height: 200, fit: BoxFit.cover);
    } else {
      imageDisplay = const Text(
        'No image selected',
        style: TextStyle(color: Colors.grey),
        textAlign: TextAlign.center,
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('SnackBuddy'),
        centerTitle: true,
        backgroundColor: Colors.grey[900],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _allergenController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Enter allergens (comma separated)',
                labelStyle: TextStyle(color: Colors.white70),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Use Camera'),
                  onPressed: () => _pickImage(ImageSource.camera),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey[800],
                  ),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.photo_library),
                  label: const Text('Pick from Gallery'),
                  onPressed: () => _pickImage(ImageSource.gallery),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey[800],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Container(
                color: const Color(0xFF1E1E1E),
                height: 200,
                child: Center(child: imageDisplay),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _uploadImage,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.grey[700],
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: const Text(
                'Check for Allergens',
                style: TextStyle(fontSize: 16),
              ),
            ),
            const SizedBox(height: 30),
            if (_result.isNotEmpty)
              Card(
                color: const Color(0xFF1E1E1E),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(color: Colors.grey.shade700),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Text(
                        _result.contains('Error') ? 'No Allergens Found' : 'Allergens Found:',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: _result.contains('Error') ? Colors.redAccent : Colors.greenAccent,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _result,
                        style: const TextStyle(fontSize: 16, color: Colors.white70),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
