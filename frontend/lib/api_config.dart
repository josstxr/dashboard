class ApiConfig {
  // Configuración de Supabase - URL del proyecto
  static const String supabaseUrl = 'https://ggvogbkqicsufzjodady.supabase.co';

  // Configuración de Supabase - Anon Key para acceso público
  static const String supabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imdndm9nYmtxaWNzdWZ6am9kYWR5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzgwMTc4NzUsImV4cCI6MjA5MzU5Mzg3NX0.Kg70ULIV4oU5E0aBfzgtQB8Rx3jDotNSwlpoy8kViG8';

  // URLs de Edge Functions
  static const String importWorkoutsFunction =
      '$supabaseUrl/functions/v1/import-workouts';
  static const String importDietsFunction =
      '$supabaseUrl/functions/v1/import-diets';
  static const String identifyFoodFunction =
      '$supabaseUrl/functions/v1/identify-food';

  // Llave usada para convertir PDFs de rutinas directamente desde la app.
  static const String geminiApiKey = 'AIzaSyAmv1zPhL7932zQjLQamMTZAWIMu5dyGuM';

  // Modelos para PDF, en orden de menor costo/cuota más amigable a fallback.
  static const List<String> geminiPdfModels = [
    'gemini-2.0-flash-lite',
    'gemini-2.5-flash-lite',
    'gemini-2.0-flash',
  ];
}
