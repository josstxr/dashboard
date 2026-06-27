import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;

class DietImportService {
  // Llave de Google Gemini compartida
  static const String _geminiApiKey = 'AIzaSyAmv1zPhL7932zQjLQamMTZAWIMu5dyGuM';

  static Future<void> importDietFromPdf(BuildContext context) async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        withData: true,
      );

      if (result == null || result.files.single.bytes == null) return;

      // 🔥 MOSTRAR EL SPINNER CIRCULAR EN EL CENTRO
      showDialog(
        context: context,
        barrierDismissible: false, // Impide que el usuario lo cierre tocando afuera
        builder: (BuildContext context) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.green),
          );
        },
      );

      // 1. Convertir el PDF a Base64
      final base64Pdf = base64Encode(result.files.single.bytes!);

      // 2. Llamada a Gemini 2.0
      final payload = {
        "contents": [
          {
            "parts": [
              {
                "text": "Analiza este archivo nutricional de forma MINUCIOSA. Devuelve UNICAMENTE un JSON válido con esta estructura: {\"diets\": [{\"name\": \"Día 1\", \"day_of_week\": 1, \"meals\": [{\"name\": \"Desayuno\", \"calories\": 0, \"protein\": 0, \"carbs\": 0, \"fats\": 0, \"notes\": \"[Opción 1]\\n• Categoría: [Valor]\\n  Alimento: [Valor]\\n  Cantidad: [Número] [Unidad]\\n  Notas: [Valor]\\n\\n• Categoría: ...\"}]}]}. REGLA CRÍTICA Y ESTRICTA: El campo 'notes' será el único lugar donde se guarde la comida, por lo tanto DEBES extraer obligatoriamente CADA alimento con sus propiedades separadas por saltos de línea (Categoría, Alimento, Cantidad y Unidad, Notas) justo como en el ejemplo exacto usando viñetas. Si hay múltiples ingredientes, haz un bloque para cada uno. PROHIBIDO RESUMIR, ACORTAR O JUNTAR ELEMENTOS EN UNA SOLA LÍNEA."
              },
              {
                "inlineData": {
                  "mimeType": "application/pdf",
                  "data": base64Pdf
                }
              }
            ]
          }
        ],
        "generationConfig": {
          "responseMimeType": "application/json",
          "temperature": 0.2
        }
      };

      final response = await http.post(
        Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=$_geminiApiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );

      if (response.statusCode != 200) throw Exception('Error en Inteligencia Artificial');

      final data = jsonDecode(response.body);
      final textResult = data['candidates'][0]['content']['parts'][0]['text'];
      final cleanText = textResult.replaceAll(RegExp(r'```(?:json)?'), '').trim();
      final parsedJson = jsonDecode(cleanText);

      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;
      if (user == null) throw Exception('No autenticado');

      // 3. Guardar dieta y comidas a Supabase
      for (var diet in parsedJson['diets'] ?? []) {
        final dRes = await supabase.from('diets').insert({
          'name': diet['name'],
          'user_id': user.id,
          'day_of_week': diet['day_of_week'] ?? 1
        }).select().single();

        if (diet['meals'] != null && diet['meals'].isNotEmpty) {
          final meals = (diet['meals'] as List).map((m) => {
            ...m,
            'diet_id': dRes['id'],
          }).toList();
          
          await supabase.from('meals').insert(meals);
        }
      }

      // 4. Cerrar el Spinner cuando termine correctamente
      if (Navigator.canPop(context)) Navigator.of(context).pop();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ ¡Dieta importada con IA exitosamente!'), backgroundColor: Colors.green),
      );
    } catch (e) {
      // Cerrar el Spinner si ocurre un error
      if (Navigator.canPop(context)) Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Error: $e'), backgroundColor: Colors.red),
      );
    }
  }
}