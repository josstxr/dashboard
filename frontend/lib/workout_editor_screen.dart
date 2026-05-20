part of 'main.dart';

// --- NUEVA PANTALLA: EDITOR DE RUTINAS COMPLETAS ---
class WorkoutEditorScreen extends StatefulWidget {
  final Map<String, dynamic> workout;
  final String currentUserEmail;

  const WorkoutEditorScreen({
    super.key,
    required this.workout,
    required this.currentUserEmail,
  });

  @override
  State<WorkoutEditorScreen> createState() => _WorkoutEditorScreenState();
}

class _WorkoutEditorScreenState extends State<WorkoutEditorScreen> {
  late TextEditingController _nameController;
  late int _selectedDay;
  List<Map<String, dynamic>> _exercises = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.workout['name']);
    _selectedDay =
        int.tryParse(widget.workout['day_of_week']?.toString() ?? '1') ?? 1;
    _exercises = List<Map<String, dynamic>>.from(
      widget.workout['exercises'] ?? [],
    );
  }

  Future<void> _saveWorkoutChanges() async {
    setState(() => _isLoading = true);
    await _persistWorkout();
    setState(() => _isLoading = false);
    if (mounted)
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Rutina guardada')));
  }

  void _editExercise(Map<String, dynamic> ex, int index) {
    TextEditingController nameC = TextEditingController(text: ex['name']);
    TextEditingController setsC = TextEditingController(
      text: ex['sets'].toString(),
    );
    TextEditingController repsC = TextEditingController(
      text: ex['reps'].toString(),
    );
    TextEditingController weightC = TextEditingController(
      text: exerciseMaxWeightText(ex),
    );
    TextEditingController restC = TextEditingController(
      text: ex['rest_seconds'].toString(),
    );
    TextEditingController notesC = TextEditingController(
      text: notesWithoutExerciseWeight(ex['notes']?.toString() ?? ''),
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Editar Ejercicio'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameC,
                decoration: const InputDecoration(labelText: 'Nombre'),
              ),
              TextField(
                controller: setsC,
                decoration: const InputDecoration(labelText: 'Series'),
                keyboardType: TextInputType.number,
              ),
              TextField(
                controller: repsC,
                decoration: const InputDecoration(labelText: 'Repeticiones'),
              ),
              TextField(
                controller: weightC,
                decoration: const InputDecoration(
                  labelText: 'Peso máximo (opcional)',
                  hintText: 'Ej. 25kg / 55 lb',
                ),
              ),
              TextField(
                controller: restC,
                decoration: const InputDecoration(
                  labelText: 'Descanso (segundos)',
                ),
                keyboardType: TextInputType.number,
              ),
              TextField(
                controller: notesC,
                decoration: const InputDecoration(labelText: 'Notas'),
                maxLines: 3,
                minLines: 1,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              // Eliminar el ejercicio del backend
              final exId = ex['id'];
              if (exId != null) {
                try {
                  await Supabase.instance.client
                      .from('exercises')
                      .delete()
                      .eq('id', exId);
                } catch (e) {
                  debugPrint(
                    'No se pudo eliminar ejercicio en Supabase, se elimina local: $e',
                  );
                }
              }

              setState(() => _exercises.removeAt(index));
              await _persistWorkout();
              if (mounted) Navigator.pop(ctx);
            },
            child: const Text('ELIMINAR', style: TextStyle(color: Colors.red)),
          ),
          TextButton(
            onPressed: () async {
              // Actualizar el ejercicio en el backend
              final exId = ex['id'];
              var updatedNotes = notesWithExerciseWeight(
                notesC.text,
                weightC.text,
              );
              final existingPr = exercisePrData(ex);
              if ((existingPr['weight'] ?? '').isNotEmpty) {
                updatedNotes = notesWithExercisePr(
                  updatedNotes,
                  weight: existingPr['weight'] ?? '',
                  reps: existingPr['reps'] ?? '',
                  date: existingPr['date'] ?? '',
                  prNotes: existingPr['notes'] ?? '',
                );
              }
              final updatedData = {
                'name': nameC.text,
                'sets': int.tryParse(setsC.text) ?? 0,
                'reps': normalizeRepsText(repsC.text),
                'rest_seconds': int.tryParse(restC.text) ?? 0,
                'notes': updatedNotes,
                'max_weight': weightC.text.trim(),
                'load': weightC.text.trim(),
                'exercise_order': index,
              };

              if (exId != null) {
                try {
                  await Supabase.instance.client
                      .from('exercises')
                      .update({
                        'name': updatedData['name'],
                        'sets': updatedData['sets'],
                        'reps': updatedData['reps'],
                        'rest_seconds': updatedData['rest_seconds'],
                        'notes': updatedData['notes'],
                        'exercise_order': updatedData['exercise_order'],
                      })
                      .eq('id', exId);
                } catch (e) {}
              }

              setState(() {
                _exercises[index] = {...ex, ...updatedData};
              });
              await _persistWorkout();
              if (mounted) Navigator.pop(ctx);
            },
            child: const Text('GUARDAR'),
          ),
        ],
      ),
    );
  }

  void _registerExercisePr(Map<String, dynamic> ex, int index) {
    final currentPr = exercisePrData(ex);
    final currentWeight = currentPr['weight'] ?? '';
    final weightC = TextEditingController(text: currentWeight);
    final repsC = TextEditingController(text: currentPr['reps'] ?? '');
    final dateC = TextEditingController(
      text: (currentPr['date'] ?? '').isNotEmpty
          ? currentPr['date']!
          : _todayIsoDate(),
    );
    final notesC = TextEditingController(text: currentPr['notes'] ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Registrar PR'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                ex['name']?.toString() ?? 'Ejercicio',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: weightC,
                decoration: const InputDecoration(
                  labelText: 'Peso del PR',
                  hintText: 'Ej. 80 kg / 175 lb',
                ),
                keyboardType: TextInputType.text,
              ),
              TextField(
                controller: repsC,
                decoration: const InputDecoration(
                  labelText: 'Repeticiones',
                  hintText: 'Ej. 5',
                ),
                keyboardType: TextInputType.number,
              ),
              TextField(
                controller: dateC,
                decoration: const InputDecoration(
                  labelText: 'Fecha',
                  hintText: 'AAAA-MM-DD',
                ),
              ),
              TextField(
                controller: notesC,
                decoration: const InputDecoration(labelText: 'Notas del PR'),
                maxLines: 3,
                minLines: 1,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CANCELAR'),
          ),
          TextButton(
            onPressed: () async {
              final weight = weightC.text.trim();
              final updatedData = {
                'pr_weight': weight,
                'pr_reps': repsC.text.trim(),
                'pr_date': dateC.text.trim(),
                'pr_notes': notesC.text.trim(),
                'notes': notesWithExercisePr(
                  ex['notes']?.toString() ?? '',
                  weight: weight,
                  reps: repsC.text.trim(),
                  date: dateC.text.trim(),
                  prNotes: notesC.text.trim(),
                ),
              };

              final exId = ex['id'];
              if (exId != null) {
                try {
                  await Supabase.instance.client
                      .from('exercises')
                      .update({'notes': updatedData['notes']})
                      .eq('id', exId);
                } catch (e) {
                  debugPrint(
                    'No se pudo guardar PR en Supabase, se guarda local: $e',
                  );
                }
              }

              setState(() {
                _exercises[index] = {...ex, ...updatedData};
              });
              await _persistWorkout();
              if (mounted) Navigator.pop(ctx);
            },
            child: const Text('GUARDAR PR'),
          ),
        ],
      ),
    );
  }

  Future<void> _addExercise() async {
    TextEditingController nameC = TextEditingController();
    TextEditingController setsC = TextEditingController(text: "3");
    TextEditingController repsC = TextEditingController(text: "10");
    TextEditingController weightC = TextEditingController();
    TextEditingController restC = TextEditingController(text: "60");
    TextEditingController notesC = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nuevo Ejercicio'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameC,
                decoration: const InputDecoration(labelText: 'Nombre'),
              ),
              TextField(
                controller: setsC,
                decoration: const InputDecoration(labelText: 'Series'),
                keyboardType: TextInputType.number,
              ),
              TextField(
                controller: repsC,
                decoration: const InputDecoration(labelText: 'Repeticiones'),
              ),
              TextField(
                controller: weightC,
                decoration: const InputDecoration(
                  labelText: 'Peso máximo (opcional)',
                  hintText: 'Ej. 25kg / 55 lb',
                ),
              ),
              TextField(
                controller: restC,
                decoration: const InputDecoration(
                  labelText: 'Descanso (segundos)',
                ),
                keyboardType: TextInputType.number,
              ),
              TextField(
                controller: notesC,
                decoration: const InputDecoration(labelText: 'Notas'),
                maxLines: 3,
                minLines: 1,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CANCELAR'),
          ),
          TextButton(
            onPressed: () async {
              Map<String, dynamic> newExercise = {
                'id': 'local_exercise_${DateTime.now().millisecondsSinceEpoch}',
                'name': nameC.text,
                'sets': int.tryParse(setsC.text) ?? 0,
                'reps': normalizeRepsText(repsC.text),
                'rest_seconds': int.tryParse(restC.text) ?? 0,
                'notes': notesWithExerciseWeight(notesC.text, weightC.text),
                'max_weight': weightC.text.trim(),
                'load': weightC.text.trim(),
                'exercise_order': _exercises.length,
                'local_only': true,
              };

              // Guardar el nuevo ejercicio en el backend
              try {
                final response = await Supabase.instance.client
                    .from('exercises')
                    .insert({
                      'workout_id': widget.workout['id'],
                      'name': nameC.text,
                      'sets': int.tryParse(setsC.text) ?? 0,
                      'reps': normalizeRepsText(repsC.text),
                      'rest_seconds': int.tryParse(restC.text) ?? 0,
                      'notes': notesWithExerciseWeight(
                        notesC.text,
                        weightC.text,
                      ),
                      'exercise_order': _exercises.length,
                    })
                    .select()
                    .single();

                newExercise = {
                  ...Map<String, dynamic>.from(response),
                  'max_weight': weightC.text.trim(),
                  'load': weightC.text.trim(),
                };
              } catch (e) {}

              setState(() => _exercises.add(newExercise));
              await _persistWorkout();
              if (mounted) Navigator.pop(ctx);
            },
            child: const Text('AÑADIR'),
          ),
        ],
      ),
    );
  }

  Future<void> _persistWorkout() async {
    // Guardar cambios generales de la rutina en el backend
    try {
      await Supabase.instance.client
          .from('workouts')
          .update({'name': _nameController.text, 'day_of_week': _selectedDay})
          .eq('id', widget.workout['id']);
      await _persistExerciseOrderToBackend();
    } catch (e) {}

    _exercises = _orderedExercisesForSave();
    final workouts = await LocalUserDataStore.loadWorkouts(
      widget.currentUserEmail,
    );
    final updatedWorkout = {
      ...Map<String, dynamic>.from(widget.workout),
      'name': _nameController.text,
      'day_of_week': _selectedDay,
      'exercises': _orderedExercisesForSave(),
    };

    final updatedWorkouts = workouts.map((workout) {
      if (workout['id'] != widget.workout['id']) {
        return workout;
      }
      return updatedWorkout;
    }).toList();

    await LocalUserDataStore.saveWorkouts(
      widget.currentUserEmail,
      updatedWorkouts,
    );
  }

  String _todayIsoDate() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  List<Map<String, dynamic>> _orderedExercisesForSave() {
    return _exercises.asMap().entries.map((entry) {
      return {...entry.value, 'exercise_order': entry.key};
    }).toList();
  }

  Future<void> _persistExerciseOrderToBackend() async {
    for (final entry in _exercises.asMap().entries) {
      final exerciseId = entry.value['id'];
      if (exerciseId == null) {
        continue;
      }
      try {
        await Supabase.instance.client
            .from('exercises')
            .update({'exercise_order': entry.key})
            .eq('id', exerciseId);
      } catch (e) {
        debugPrint('Error guardando orden de ejercicio: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Editor de Rutina'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveWorkoutChanges,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Nombre de la rutina',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  value: _selectedDay,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Día de la semana',
                    border: OutlineInputBorder(),
                  ),
                  items:
                      [
                            'Lunes',
                            'Martes',
                            'Miércoles',
                            'Jueves',
                            'Viernes',
                            'Sábado',
                            'Domingo',
                          ]
                          .asMap()
                          .entries
                          .map(
                            (e) => DropdownMenuItem(
                              value: e.key + 1,
                              child: Text(e.value),
                            ),
                          )
                          .toList(),
                  onChanged: (val) => setState(() => _selectedDay = val ?? 1),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Ejercicios',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _addExercise,
                      icon: const Icon(Icons.add),
                      label: const Text('Añadir'),
                    ),
                  ],
                ),
                const Divider(),
                ReorderableListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: false,
                  itemCount: _exercises.length,
                  onReorder: (oldIndex, newIndex) async {
                    if (newIndex > oldIndex) {
                      newIndex -= 1;
                    }
                    final movedExercise = _exercises.removeAt(oldIndex);
                    _exercises.insert(newIndex, movedExercise);
                    setState(() {});
                    await _persistWorkout();
                  },
                  itemBuilder: (context, idx) {
                    final ex = _exercises[idx];
                    final notes = notesWithoutExerciseWeight(
                      ex['notes']?.toString() ?? '',
                    );
                    final maxWeight = exerciseMaxWeightText(ex);
                    final prText = exercisePrText(ex);
                    final subtitleText =
                        '${ex['sets']}x${normalizeRepsText(ex['reps'])} • ${ex['rest_seconds']}s desc.' +
                        (prText.isNotEmpty ? '\nPR: $prText' : '') +
                        (prText.isEmpty && maxWeight.isNotEmpty
                            ? '\nPeso máximo: $maxWeight'
                            : '') +
                        (notes.isNotEmpty ? '\nNotas: $notes' : '');
                    return Card(
                      key: ValueKey(
                        ex['id']?.toString() ?? '${ex['name'] ?? 'ex'}_$idx',
                      ),
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        title: Text(
                          exerciseDisplayTitle(_exercises, idx),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(subtitleText),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Registrar PR',
                              icon: const Icon(
                                Icons.emoji_events_rounded,
                                size: 22,
                              ),
                              onPressed: () => _registerExercisePr(ex, idx),
                            ),
                            const Icon(Icons.edit, size: 20),
                            const SizedBox(width: 10),
                            ReorderableDragStartListener(
                              index: idx,
                              child: const Icon(Icons.drag_handle_rounded),
                            ),
                          ],
                        ),
                        onTap: () => _editExercise(ex, idx),
                      ),
                    );
                  },
                ),
              ],
            ),
    );
  }
}
