import 'dart:convert';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'api_config.dart';

class GeminiImageQuotaException implements Exception {
  final String message;

  const GeminiImageQuotaException(this.message);

  @override
  String toString() => message;
}

class DietCameraScreen extends StatefulWidget {
  const DietCameraScreen({super.key});

  @override
  State<DietCameraScreen> createState() => _DietCameraScreenState();
}

class _DietCameraScreenState extends State<DietCameraScreen> {
  static const double _aiImageMaxDimension = 960;
  static const int _aiImageQuality = 55;

  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  bool _isProcessing = false;
  String? _cameraError;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        if (!mounted) return;
        setState(() => _cameraError = 'No se encontró una cámara disponible.');
        return;
      }

      final camera = _cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras.first,
      );

      _controller = CameraController(
        camera,
        ResolutionPreset.low,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await _controller!.initialize();
      if (!mounted) return;
      setState(() => _cameraError = null);
    } on CameraException catch (e) {
      if (!mounted) return;
      setState(() {
        _cameraError =
            'No se pudo abrir la cámara: ${e.description ?? e.code}. Revisa el permiso de cámara.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _cameraError = 'No se pudo abrir la cámara: $e');
    }
  }

  Future<void> _takePictureAndSend() async {
    if (_controller == null ||
        !_controller!.value.isInitialized ||
        _isProcessing) {
      return;
    }

    setState(() => _isProcessing = true);

    try {
      final XFile image = await _controller!.takePicture();
      await _processAndSendImage(File(image.path));
    } catch (e) {
      if (!mounted) return;
      final errorText = e.toString().replaceAll('Exception: ', '');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(errorText)));
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _pickFromGallery() async {
    if (_isProcessing) return;

    setState(() => _isProcessing = true);
    try {
      final picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: _aiImageMaxDimension,
        maxHeight: _aiImageMaxDimension,
        imageQuality: _aiImageQuality,
      );
      if (image == null) {
        setState(() => _isProcessing = false);
        return;
      }
      await _processAndSendImage(File(image.path));
    } catch (e) {
      if (!mounted) return;
      final errorText = e.toString().replaceAll('Exception: ', '');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(errorText)));
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _processAndSendImage(File imageFile) async {
    try {
      final imageBytes = await imageFile.readAsBytes();
      final decoded = await _analyzeFoodImageDirectly(imageBytes);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aportaciones estimadas con IA')),
      );
      Navigator.pop(context, decoded);
    } catch (e) {
      if (!mounted) return;
      final errorText = e is GeminiImageQuotaException
          ? e.message
          : e.toString().replaceAll('Exception: ', '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorText),
          duration: const Duration(seconds: 7),
        ),
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<Map<String, dynamic>> _analyzeFoodImageDirectly(
    List<int> imageBytes,
  ) async {
    final payload = {
      'contents': [
        {
          'parts': [
            {
              'text':
                  'Analiza la imagen de comida y estima las aportaciones nutricionales visibles. Responde UNICAMENTE JSON valido con esta forma exacta: {"name":"nombre breve del plato en espanol","calories":0,"protein":0,"carbs":0,"fats":0,"estimated_grams":0,"confidence":0,"items":[{"name":"alimento","estimated_grams":0,"calories":0,"protein":0,"carbs":0,"fats":0}]}. calories/protein/carbs/fats deben ser el total estimado de toda la porcion visible, no por 100g. items debe explicar la aportacion por alimento. Si la imagen no contiene comida, usa name="No se detecto comida" y todos los numeros en 0. No incluyas texto fuera del JSON.',
            },
            {
              'inlineData': {
                'mimeType': 'image/jpeg',
                'data': base64Encode(imageBytes),
              },
            },
          ],
        },
      ],
      'generationConfig': {
        'response_mime_type': 'application/json',
        'temperature': 0.15,
      },
    };

    Exception? lastError;
    String? quotaMessage;
    for (final model in ApiConfig.geminiPdfModels) {
      try {
        final response = await http
            .post(
              Uri.parse(
                'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=${ApiConfig.geminiApiKey}',
              ),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(payload),
            )
            .timeout(const Duration(seconds: 180));

        if (response.statusCode < 200 || response.statusCode >= 300) {
          if (_isGeminiQuotaError(response)) {
            quotaMessage = _friendlyGeminiQuotaMessage(response.body);
            continue;
          }
          lastError = Exception('Gemini respondió ${response.statusCode}');
          continue;
        }

        final data = jsonDecode(response.body);
        final text = data['candidates']?[0]?['content']?['parts']?[0]?['text'];
        if (text is! String || text.trim().isEmpty) {
          lastError = Exception('Gemini no devolvió contenido');
          continue;
        }

        final parsed = jsonDecode(
          text.replaceAll('```json', '').replaceAll('```', '').trim(),
        );
        if (parsed is Map) {
          return Map<String, dynamic>.from(parsed);
        }
      } catch (e) {
        lastError = Exception(e.toString());
      }
    }

    if (quotaMessage != null) {
      throw GeminiImageQuotaException(quotaMessage);
    }
    throw lastError ?? Exception('No se pudo analizar la imagen');
  }

  bool _isGeminiQuotaError(http.Response response) {
    final body = response.body.toLowerCase();
    return response.statusCode == 429 ||
        body.contains('resource_exhausted') ||
        body.contains('quota exceeded') ||
        body.contains('rate limit');
  }

  String _friendlyGeminiQuotaMessage(String body) {
    final retryMatch = RegExp(
      r'Please retry in ([0-9.]+)s',
      caseSensitive: false,
    ).firstMatch(body);
    final retrySeconds = retryMatch == null
        ? null
        : double.tryParse(retryMatch.group(1) ?? '');
    final waitText = retrySeconds == null
        ? 'unos minutos'
        : '${retrySeconds.ceil()} segundos';

    return 'Gemini alcanzó el límite para analizar imágenes. Intenta de nuevo en $waitText o usa registro manual mientras se libera la cuota.';
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final primaryText = isLight ? const Color(0xFF111315) : Colors.white;
    final panelColor = isLight
        ? const Color(0xFFE9EDF1).withOpacity(0.86)
        : Colors.black54;

    if (_cameraError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Escanear Alimento')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.no_photography_rounded, size: 46),
                const SizedBox(height: 14),
                Text(
                  _cameraError!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 18),
                ElevatedButton.icon(
                  onPressed: _initializeCamera,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Intentar de nuevo'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_controller == null || !_controller!.value.isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Escanear Alimento')),
      body: Stack(
        children: [
          CameraPreview(_controller!),
          if (isLight)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.04),
                  ),
                ),
              ),
            ),
          if (_isProcessing)
            Container(
              color: panelColor,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: primaryText),
                    const SizedBox(height: 10),
                    Text(
                      'Analizando con IA...',
                      style: TextStyle(color: primaryText),
                    ),
                  ],
                ),
              ),
            ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.all(30.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FloatingActionButton(
                    heroTag: 'galleryBtn',
                    onPressed: _isProcessing ? null : _pickFromGallery,
                    backgroundColor: _isProcessing
                        ? Colors.grey
                        : (isLight ? const Color(0xFF111315) : Colors.white24),
                    elevation: 0,
                    child: Icon(
                      Icons.photo_library,
                      size: 28,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 24),
                  FloatingActionButton(
                    heroTag: 'cameraBtn',
                    onPressed: _isProcessing ? null : _takePictureAndSend,
                    backgroundColor: _isProcessing
                        ? Colors.grey
                        : Colors.deepPurple,
                    child: const Icon(Icons.camera_alt, size: 30),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
