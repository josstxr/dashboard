import 'package:flutter/material.dart';
import 'dart:async';
import 'package:http/http.dart' as http;

class WorkoutSessionScreen extends StatefulWidget {
  final Map workout;

  const WorkoutSessionScreen({super.key, required this.workout});

  @override
  State<WorkoutSessionScreen> createState() => _WorkoutSessionScreenState();
}

class _WorkoutSessionScreenState extends State<WorkoutSessionScreen> {
  int currentExerciseIndex = 0;
  int currentSet = 1;
  int _remainingTime = 0;
  int _initialRestTime = 1;
  Timer? _timer;
  bool _isResting = false;
  bool _isTimerPaused = false;

  // Helper para parsear el tiempo de descanso (ej: "3MIN" -> 180)
  int _parseRestTime(dynamic rest) {
    if (rest is int) return rest;
    String restStr = rest?.toString().toUpperCase() ?? '0';
    if (restStr.contains('MIN')) {
      int mins = int.tryParse(restStr.replaceAll('MIN', '').trim()) ?? 0;
      return mins * 60;
    }
    return int.tryParse(restStr.replaceAll('S', '').trim()) ?? 0;
  }

  void _completeSet(int totalSets, dynamic restValue) {
    int restSeconds = _parseRestTime(restValue);
    
    setState(() {
      _isResting = true;
      _remainingTime = restSeconds;
      _initialRestTime = restSeconds > 0 ? restSeconds : 1;
      _isTimerPaused = false;
    });

    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!_isTimerPaused) {
        setState(() {
          if (_remainingTime > 0) {
            _remainingTime--;
          } else {
            _timer?.cancel();
            _isResting = false;
            _advanceSetOrExercise(totalSets);
          }
        });
      }
    });
  }

  void _advanceSetOrExercise(int totalSets) {
    if (currentSet < totalSets) {
      setState(() => currentSet++);
    } else {
      if (currentExerciseIndex < (widget.workout['exercises'] as List).length - 1) {
        setState(() {
          currentExerciseIndex++;
          currentSet = 1;
        });
      } else {
        _showFinishDialog();
      }
    }
  }

  void _showFinishDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(0)), // Estilo Industrial
        title: const Text('SESIÓN FINALIZADA', style: TextStyle(fontWeight: FontWeight.black)),
        content: const Text('Los datos han sido registrados correctamente.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: const Text('CERRAR', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final exercises = widget.workout['exercises'] as List;
    if (exercises.isEmpty) return const Scaffold(body: Center(child: Text("No hay datos")));

    final currentExercise = exercises[currentExerciseIndex];
    
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5), // Gris muy claro industrial
      appBar: AppBar(
        title: Text(widget.workout['name']?.toString().toUpperCase() ?? 'SESIÓN', 
          style: const TextStyle(fontWeight: FontWeight.black, fontSize: 16)),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: Column(
        children: [
          // Barra de progreso minimalista
          LinearProgressIndicator(
            value: (currentExerciseIndex + 1) / exercises.length,
            backgroundColor: Colors.grey[300],
            color: Colors.black,
            minHeight: 6,
          ),
          
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildMainCard(currentExercise),
                  const SizedBox(height: 24),
                  if (exercises.length > currentExerciseIndex + 1) 
                    _buildNextExercises(exercises),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainCard(Map ex) {
    int totalSets = int.tryParse(ex['sets']?.toString() ?? '1') ?? 1;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, 10))
        ],
      ),
      child: Column(
        children: [
          if (!_isResting) ...[
            Text(ex['name']?.toString().toUpperCase() ?? '',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.black, letterSpacing: 1.5)),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildInfoColumn("SERIE", "$currentSet / $totalSets"),
                _buildInfoColumn("REPS", "${ex['reps'] ?? '-'}"),
                _buildInfoColumn("CARGA", "${ex['load'] ?? 'FALLO'}"),
              ],
            ),
            const SizedBox(height: 30),
            if (ex['notes'] != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                color: Colors.grey[100],
                child: Text("NOTAS: ${ex['notes']}", 
                  style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.w600)),
              ),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                onPressed: () => _completeSet(totalSets, ex['rest_seconds'] ?? ex['rest']),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text("COMPLETAR SERIE", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
              ),
            ),
          ] else ...[
            // VISTA DE DESCANSO
            const Text("DESCANSO", style: TextStyle(fontWeight: FontWeight.black, color: Colors.grey)),
            const SizedBox(height: 20),
            Text("$_remainingTime", style: const TextStyle(fontSize: 80, fontWeight: FontWeight.black)),
            const SizedBox(height: 20),
            TextButton(
              onPressed: () => setState(() => _isResting = false),
              child: const Text("SALTAR", style: TextStyle(color: Colors.black, decoration: TextDecoration.underline)),
            )
          ],
        ],
      ),
    );
  }

  Widget _buildInfoColumn(String label, String value) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.black)),
      ],
    );
  }

  Widget _buildNextExercises(List all) {
    final nextEx = all[currentExerciseIndex + 1];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("PRÓXIMO", style: TextStyle(fontWeight: FontWeight.black, fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.5),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: Row(
            children: [
              const Icon(Icons.redo, size: 16),
              const SizedBox(width: 12),
              Text(nextEx['name']?.toString().toUpperCase() ?? '', 
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            ],
          ),
        ),
      ],
    );
  }
}