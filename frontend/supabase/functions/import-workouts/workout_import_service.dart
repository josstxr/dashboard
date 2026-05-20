import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;

class WorkoutImportService {
  // ⚠️ REEMPLAZA ESTO CON TU LLAVE DE GOOGLE GEMINI REAL
  static const String _geminiApiKey = 'AIzaSyAmv1zPhL7932zQjLQamMTZAWIMu5dyGuM';

  static Future<void> importWorkoutFromPdf(BuildContext context) async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        withData: true, 
      );

      if (result == null || result.files.single.bytes == null) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Analizando PDF con IA...')),
      );

      // 1. Convertir el PDF a Base64
      final base64Pdf = base64Encode(result.files.single.bytes!);

      // 2. Llamada directa a Gemini REST API
      final payload = {
        "contents": [
          {
            "parts": [
              {
                "text": "Analiza el texto de este plan de entrenamiento. Devuelve UNICAMENTE JSON válido con esta estructura: {\"workouts\": [{\"name\": \"Día 1: Pecho\", \"day_of_week\": 1, \"exercises\": [{\"name\": \"Sentadillas\", \"sets\": 4, \"reps\": \"10-12\", \"rest_seconds\": 60, \"notes\": \"Bajar lento\"}]}]}"
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

      if (response.statusCode != 200) throw Exception('Error en IA: ${response.statusCode}');

      final data = jsonDecode(response.body);
      final textResult = data['candidates'][0]['content']['parts'][0]['text'];
      final parsedJson = jsonDecode(textResult);

      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;
      if (user == null) throw Exception('No autenticado');

      // 3. Guardar directamente en tu base de datos localmente desde la app
      for (var workout in parsedJson['workouts'] ?? []) {
        final wRes = await supabase.from('workouts').insert({
          'name': workout['name'],
          'user_id': user.id,
          'day_of_week': workout['day_of_week'] ?? 1
        }).select().single();

        if (workout['exercises'] != null && workout['exercises'].isNotEmpty) {
          final exercises = (workout['exercises'] as List).map((e) => {
            ...e,
            'workout_id': wRes['id'],
          }).toList();
          
          await supabase.from('exercises').insert(exercises);
        }
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ ¡Rutinas guardadas exitosamente!'), backgroundColor: Colors.green),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  static Future<List<Map<String, dynamic>>> fetchWorkoutExercises() async {
    final response = await Supabase.instance.client
        .from('exercises')
        .select()
        .order('order_index', ascending: true);

    return response;
  }

  static Future<void> uploadAndProcessRoutine() async {
    // 1. Seleccionar el archivo PDF
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: true, // Requerido para poder leer los bytes del archivo en memoria
    );

    if (result != null && result.files.first.bytes != null) {
      final fileBytes = result.files.first.bytes;
      final fileName = result.files.first.name;

      // 2. Llamar a la Edge Function de Supabase
      try {
        final response = await Supabase.instance.client.functions.invoke(
          'process-routine-pdf',
          body: {'fileName': fileName, 'fileBase64': base64Encode(fileBytes!)},
        );
        
        print("¡Rutina procesada y guardada!");
        // Aquí puedes refrescar tu UI
      } catch (e) {
        print("Error procesando el PDF: $e");
      }
    }
  }
}