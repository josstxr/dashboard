import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RoutineProcessor {
  // Configura tus llaves aquí
  final _model = GenerativeModel(
    model: 'gemini-1.5-flash',
    apiKey: 'TU_GEMINI_API_KEY_AQUI',
  );

  final _supabase = Supabase.instance.client;

  Future<void> selectAndProcessPDF() async {
    // 1. Seleccionar el archivo
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: true, // Importante para obtener los bytes
    );

    if (result == null) return;

    final fileBytes = result.files.first.bytes;
    if (fileBytes == null) return;

    // 2. Preparar el prompt para Gemini
    final prompt = """
    Analiza este PDF de entrenamiento y extrae la rutina.
    Devuelve un JSON estrictamente con esta estructura (sin texto extra):
    [
      {
        "name": "Nombre del ejercicio",
        "sets": 3,
        "reps": "10-12",
        "rest_time_seconds": 120,
        "notes": "Instrucciones"
      }
    ]
    """;

    // 3. Enviar a Gemini
    final content = [
      Content.multi([
        TextPart(prompt),
        DataPart('application/pdf', fileBytes),
      ])
    ];

    final response = await _model.generateContent(content);
    final jsonString = response.text!.replaceAll('```json', '').replaceAll('```', '').trim();
    
    // 4. Parsear y Guardar en Supabase
    await _saveToSupabase(jsonString);
  }

  Future<void> _saveToSupabase(String jsonString) async {
    final List<dynamic> data = jsonDecode(jsonString);

    // Creamos el registro del entrenamiento principal
    final workout = await _supabase
        .from('workouts')
        .insert({'name': 'Nueva Rutina PDF'})
        .select()
        .single();

    final String workoutId = workout['id'];

    // Preparamos los ejercicios para insertarlos todos de golpe (Batch Insert)
    final exercisesToInsert = data.asMap().entries.map((entry) {
      final index = entry.key;
      final item = entry.value;
      return {
        'workout_id': workoutId,
        'name': item['name'],
        'sets': item['sets'],
        'reps': item['reps'],
        'rest_time_seconds': item['rest_time_seconds'],
        'notes': item['notes'],
        'order_index': index,
      };
    }).toList();

    await _supabase.from('exercises').insert(exercisesToInsert);
    print("¡Todo guardado en Supabase con éxito!");
  }
}