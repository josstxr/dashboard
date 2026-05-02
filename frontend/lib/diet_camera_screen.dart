import 'dart:convert';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class DietCameraScreen extends StatefulWidget {
  const DietCameraScreen({super.key});

  @override
  State<DietCameraScreen> createState() => _DietCameraScreenState();
}

class _DietCameraScreenState extends State<DietCameraScreen> {
  CameraController? _controller;
  late List<CameraDescription> _cameras;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    _cameras = await availableCameras();
    // Usamos la cámara trasera por defecto
    _controller = CameraController(_cameras[0], ResolutionPreset.medium);
    await _controller!.initialize();
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _takePictureAndSend() async {
    if (_controller == null || !_controller!.value.isInitialized || _isProcessing) return;

    setState(() => _isProcessing = true);

    try {
      final XFile image = await _controller!.takePicture();
      
      final File imageFile = File(image.path);
      final List<int> imageBytes = await imageFile.readAsBytes();
      final String base64Image = base64Encode(imageBytes);

      // RECUERDA: Verifica que esta sea tu IP actual de la MacBook Air
      final url = Uri.parse('http://192.168.1.75:8000/api/diet/identify');      
      
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'image': base64Image}),
      );

      if (response.statusCode == 200) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('¡Alimento registrado exitosamente! 🥗')),
        );
        Navigator.pop(context); 
      } else {
        throw Exception('Error en el servidor: ${response.statusCode}');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null || !_controller!.value.isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Escanear Alimento')),
      body: Stack(
        children: [
          CameraPreview(_controller!),
          if (_isProcessing)
            Container(
              color: Colors.black54,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 10),
                    Text('Analizando con IA...', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
            ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.all(30.0),
              child: FloatingActionButton(
                onPressed: _isProcessing ? null : _takePictureAndSend,
                backgroundColor: _isProcessing ? Colors.grey : Colors.deepPurple,
                child: const Icon(Icons.camera_alt, size: 30),
              ),
            ),
          ),
        ],
      ),
    );
  }
}