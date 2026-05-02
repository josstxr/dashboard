import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart'; 
import 'workout_session_screen.dart';
import 'dart:convert';
import 'auth_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  // Notificador global para cambiar el tema en tiempo real
  static final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.light);

  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (_, ThemeMode currentMode, __) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Healthy-T',
          theme: ThemeData(
            scaffoldBackgroundColor: Colors.white,
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple, brightness: Brightness.light),
            appBarTheme: const AppBarTheme(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
            ),
          ),
          darkTheme: ThemeData(
            scaffoldBackgroundColor: Colors.black,
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple, brightness: Brightness.dark),
            appBarTheme: const AppBarTheme(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
            ),
            cardTheme: CardThemeData(color: Colors.grey[900]),
          ),
          themeMode: currentMode,
          home: const AuthScreen(),
        );
      },
    );
  }
}

class WorkoutListScreen extends StatefulWidget {
  const WorkoutListScreen({super.key});

  @override
  State<WorkoutListScreen> createState() => _WorkoutListScreenState();
}

class _WorkoutListScreenState extends State<WorkoutListScreen> {
  List workouts = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    fetchWorkouts();
  }

  Future<void> fetchWorkouts() async {
    setState(() => isLoading = true);
    try {
      final response = await http.get(Uri.parse('http://192.168.100.5:8000/api/workouts'))
          .timeout(const Duration(seconds: 5)); 
      
      if (response.statusCode == 200) {
        setState(() {
          List fetched = json.decode(response.body);
          // Ordenamos las rutinas por día de la semana
          fetched.sort((a, b) => (a['day_of_week'] ?? 0).compareTo(b['day_of_week'] ?? 0));
          workouts = fetched;
          isLoading = false;
        });
      } else {
        setState(() => isLoading = false);
        _showErrorSnackBar('Error del servidor: ${response.statusCode}');
      }
    } catch (e) {
      print('Error de conexión: $e');
      setState(() => isLoading = false);
      _showErrorSnackBar('No se pudo conectar al servidor');
    }
  }

  // Corregido: Se eliminó ".platform" y se unificó el nombre de la función
  Future<void> pickAndUploadFile() async { 
    FilePickerResult? result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls', 'csv', 'pdf'], 
    );

    if (result != null && result.files.single.path != null) {
      setState(() => isLoading = true);
      
      try {
        var request = http.MultipartRequest(
          'POST', 
          Uri.parse('http://192.168.100.5:8000/api/workouts/import')
        );
        
        request.files.add(
          await http.MultipartFile.fromPath('file', result.files.single.path!)
        );

        var response = await request.send();
        
        if (response.statusCode == 200) {
          _showSuccessSnackBar('¡Archivo cargado con éxito! 🚀');
          fetchWorkouts();
        } else {
          setState(() => isLoading = false);
          
          // Capturar el mensaje exacto enviado por Laravel
          var responseBody = await response.stream.bytesToString();
          try {
            var errorData = json.decode(responseBody);
            _showErrorSnackBar('Error del servidor: ${errorData['error']}');
          } catch (_) {
            _showErrorSnackBar('Error al subir: ${response.statusCode}');
          }
        }
      } catch (e) {
        setState(() => isLoading = false);
        _showErrorSnackBar('Error de conexión al subir archivo');
      }
    }
  }

  Future<void> _changeWorkoutDay(int workoutId, int currentDay) async {
    DateTime? selectedDate = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: 'Selecciona una fecha para asignar el día de la semana',
      cancelText: 'Cancelar',
      confirmText: 'Asignar',
    );

    if (selectedDate != null) {
      // DateTime.weekday devuelve 1 para Lunes y 7 para Domingo,
      // lo cual coincide exactamente con la estructura de tu backend.
      int selectedDay = selectedDate.weekday;

      if (selectedDay != currentDay) {
        setState(() => isLoading = true);
        await http.put(
          Uri.parse('http://192.168.100.5:8000/api/workouts/$workoutId'),
          body: {'day_of_week': selectedDay.toString()},
        );
        fetchWorkouts(); // Recargamos la lista actualizada
      }
    }
  }

  Future<void> _deleteWorkout(int workoutId) async {
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar Rutina'),
        content: const Text('¿Estás seguro de que deseas eliminar este día de entrenamiento? Esta acción no se puede deshacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(context, true), 
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Eliminar')
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => isLoading = true);
      try {
        final response = await http.delete(
          Uri.parse('http://192.168.100.5:8000/api/workouts/$workoutId'),
        );
        if (response.statusCode == 200) {
          _showSuccessSnackBar('Día de entrenamiento eliminado');
        } else {
          _showErrorSnackBar('Error al eliminar: ${response.statusCode}');
        }
      } catch (e) {
        _showErrorSnackBar('Error de conexión al eliminar');
      }
      fetchWorkouts(); // Recargamos la lista actualizada
    }
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _showSuccessSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

  String _getWeekdayName(int? day) {
    switch(day) {
      case 1: return 'Lunes';
      case 2: return 'Martes';
      case 3: return 'Miércoles';
      case 4: return 'Jueves';
      case 5: return 'Viernes';
      case 6: return 'Sábado';
      case 7: return 'Domingo';
      default: return 'Día libre';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis Rutinas de Entrenamiento'),
        actions: [
          ValueListenableBuilder<ThemeMode>(
            valueListenable: MyApp.themeNotifier,
            builder: (_, ThemeMode currentMode, __) {
              return IconButton(
                icon: Icon(currentMode == ThemeMode.light ? Icons.dark_mode : Icons.light_mode),
                onPressed: () {
                  MyApp.themeNotifier.value = currentMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
                },
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: fetchWorkouts,
          )
        ],
      ),
      body: isLoading 
          ? const Center(child: CircularProgressIndicator()) 
          : workouts.isEmpty 
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('No hay rutinas. ¡Sube tu plan!'),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: fetchWorkouts, 
                      child: const Text('Reintentar conexión')
                    )
                  ],
                ),
              )
            : RefreshIndicator(
                onRefresh: fetchWorkouts,
                child: ListView.builder(
                  itemCount: workouts.length,
                  itemBuilder: (context, index) {
                    final workout = workouts[index];
                    final exercisesCount = workout['exercises']?.length ?? 0;

                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      child: ListTile(
                        leading: const Icon(Icons.fitness_center, color: Colors.deepPurple),
                        title: Text(
                          workout['name'],
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text('${_getWeekdayName(workout['day_of_week'])} • $exercisesCount ejercicios'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.red),
                              onPressed: () => _deleteWorkout(workout['id']),
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit_calendar, color: Colors.blue),
                              onPressed: () => _changeWorkoutDay(workout['id'], workout['day_of_week'] ?? 1),
                            ),
                            const Icon(Icons.play_circle_fill, color: Colors.green, size: 35),
                          ],
                        ),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => WorkoutSessionScreen(workout: workout),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: pickAndUploadFile, // Nombre corregido aquí
        label: const Text('Cargar Plan'),
        icon: const Icon(Icons.upload_file),
      ),
    );
  }
}