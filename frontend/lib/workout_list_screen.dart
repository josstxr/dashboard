part of 'main.dart';

class WorkoutListScreen extends StatefulWidget {
  const WorkoutListScreen({super.key, required this.currentUser});

  final LocalAuthUser currentUser;

  @override
  State<WorkoutListScreen> createState() => _WorkoutListScreenState();
}

class _WorkoutListScreenState extends State<WorkoutListScreen> {
  List<Map<String, dynamic>> workouts = [];
  bool isLoading = true;
  int _currentIndex = 0;
  int _lastContentIndex = 0;
  List<Map<String, dynamic>> diets = [];
  List<Map<String, dynamic>> _dailyMeals = [];
  WeeklyWorkoutLog? _weeklyWorkoutLog;

  // Mapa para guardar el estado de las sesiones en curso.
  // Key: workoutId, Value: {'exerciseIndex': X, 'set': Y}
  final Map<String, Map<String, int>> _activeSessions = {};

  double _otherWorkoutsStackProgress = 0;
  bool _otherWorkoutsStackForcedOpen = false;

  // Estado de sincronización con Apple Health
  bool _isHealthSyncEnabled = false;
  bool _isLoadingRecovery = false;
  RecoverySnapshot? _recoverySnapshot;
  String? _recoveryError;
  bool _isLightMode = healthyTThemeMode.value != ThemeMode.dark;
  final TextEditingController _adminTargetEmailController =
      TextEditingController();
  final TextEditingController _feedbackController = TextEditingController();
  bool _isFeedbackExpanded = false;
  dynamic _selectedAdminWorkoutId;
  dynamic _selectedAdminDietId;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  @override
  void dispose() {
    _adminTargetEmailController.dispose();
    _feedbackController.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    try {
      setState(() => isLoading = true);

      final storedWorkouts = _normalizeWorkouts(
        await LocalUserDataStore.loadWorkouts(widget.currentUser.email),
      );
      final storedDiets = _normalizeDiets(
        await LocalUserDataStore.loadDiets(widget.currentUser.email),
      );
      final storedDailyMeals = _normalizeDailyMeals(
        await LocalUserDataStore.loadDailyMeals(
          widget.currentUser.email,
          _todayIsoDate(),
        ),
      );

      final prefs = await SharedPreferences.getInstance();

      if (!mounted) {
        return;
      }

      setState(() {
        workouts = storedWorkouts;
        diets = storedDiets;
        _dailyMeals = storedDailyMeals;
        _isHealthSyncEnabled = prefs.getBool('health_sync_enabled') ?? false;
        _isLightMode =
            prefs.getBool(_themePreferenceKey) ??
            (healthyTThemeMode.value != ThemeMode.dark);
        isLoading = false;
      });
      unawaited(_loadWeeklyWorkoutLog(storedWorkouts));

      await _claimPendingAssignments();

      final backendWorkouts = _normalizeWorkouts(
        await _fetchWorkoutsFromBackend() ?? storedWorkouts,
      );
      final backendDiets = _normalizeDiets(
        await _fetchDietsFromBackend() ?? storedDiets,
      );
      final backendDailyMeals = _normalizeDailyMeals(
        await _fetchDailyNutritionFromBackend(
              previousMeals: storedDailyMeals,
            ) ??
            storedDailyMeals,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        workouts = backendWorkouts.isNotEmpty
            ? backendWorkouts
            : storedWorkouts;
        diets = backendDiets.isNotEmpty ? backendDiets : storedDiets;
        _dailyMeals = backendDailyMeals.isNotEmpty
            ? backendDailyMeals
            : storedDailyMeals;
        _isHealthSyncEnabled = prefs.getBool('health_sync_enabled') ?? false;
        _isLightMode =
            prefs.getBool(_themePreferenceKey) ??
            (healthyTThemeMode.value != ThemeMode.dark);
        isLoading = false;
      });
      await _loadWeeklyWorkoutLog(
        backendWorkouts.isNotEmpty ? backendWorkouts : storedWorkouts,
      );
      if (_isHealthSyncEnabled) {
        unawaited(_loadRecoverySnapshot());
      }
    } catch (e) {
      debugPrint('Error cargando datos del usuario: $e');
      if (!mounted) return;
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> _loadWeeklyWorkoutLog([
    List<Map<String, dynamic>>? sourceWorkouts,
  ]) async {
    final log = await WeeklyWorkoutRegistryStore.load(
      email: widget.currentUser.email,
      workouts: sourceWorkouts ?? workouts,
    );
    if (!mounted) return;
    setState(() => _weeklyWorkoutLog = log);
  }

  Future<void> _persistWeeklyWorkoutLog(WeeklyWorkoutLog log) async {
    setState(() => _weeklyWorkoutLog = log);
    await WeeklyWorkoutRegistryStore.save(
      email: widget.currentUser.email,
      log: log,
    );
  }

  Future<void> _updateWeeklyWorkoutEntry(
    WeeklyWorkoutEntry entry,
    WeeklyWorkoutEntry Function(WeeklyWorkoutEntry entry) update,
  ) async {
    final currentLog =
        _weeklyWorkoutLog ??
        await WeeklyWorkoutRegistryStore.load(
          email: widget.currentUser.email,
          workouts: workouts,
        );
    final updatedEntries = currentLog.entries.map((item) {
      return item.workoutId == entry.workoutId ? update(item) : item;
    }).toList();
    await _persistWeeklyWorkoutLog(
      currentLog.copyWith(entries: updatedEntries),
    );
  }

  Future<void> _toggleWeeklyWorkoutCompletion(WeeklyWorkoutEntry entry) async {
    await _updateWeeklyWorkoutEntry(
      entry,
      (item) =>
          item.copyWith(completed: !item.completed, updatedAt: DateTime.now()),
    );
  }

  Future<void> _updateWeeklyWorkoutRestRating(
    WeeklyWorkoutEntry entry,
    int rating,
  ) async {
    await _updateWeeklyWorkoutEntry(
      entry,
      (item) => item.copyWith(
        restRating: rating.clamp(1, 5),
        updatedAt: DateTime.now(),
      ),
    );
  }

  List<Map<String, dynamic>> _normalizeWorkouts(
    List<Map<String, dynamic>>? items,
  ) {
    if (items == null || items.isEmpty) {
      return [];
    }

    try {
      return _sortByDay(
        items.map((item) {
          try {
            final workout = Map<String, dynamic>.from(item);
            final exercises =
                (workout['exercises'] as List?)
                    ?.whereType<Map>()
                    .toList()
                    .asMap()
                    .entries
                    .map(
                      (entry) => _normalizeExercise(
                        Map<String, dynamic>.from(entry.value),
                        fallbackOrder: entry.key,
                      ),
                    )
                    .toList() ??
                <Map<String, dynamic>>[];
            exercises.sort((a, b) {
              final orderA = parseWholeNumber(a['exercise_order']);
              final orderB = parseWholeNumber(b['exercise_order']);
              final orderCompare = orderA.compareTo(orderB);
              if (orderCompare != 0) {
                return orderCompare;
              }
              final idA = int.tryParse(a['id']?.toString() ?? '') ?? 0;
              final idB = int.tryParse(b['id']?.toString() ?? '') ?? 0;
              return idA.compareTo(idB);
            });
            final day =
                int.tryParse(workout['day_of_week']?.toString() ?? '') ?? 1;
            final rawWorkoutName = workout['name']?.toString().trim() ?? '';
            final exercisePdfTitle = exercises
                .map((exercise) => exercise['dia']?.toString().trim() ?? '')
                .firstWhere((title) => title.isNotEmpty, orElse: () => '');
            final displayName =
                rawWorkoutName.isNotEmpty &&
                    !_isGenericWorkoutTitle(rawWorkoutName)
                ? rawWorkoutName
                : _formatImportedWorkoutTitle(
                    exercisePdfTitle.isNotEmpty
                        ? exercisePdfTitle
                        : rawWorkoutName,
                    day: day,
                    ordinal: day,
                  );
            return {
              ...workout,
              'name': displayName,
              'day_of_week': day,
              'exercises': exercises,
            };
          } catch (e) {
            debugPrint('Error normalizando workout: $e');
            return {'name': 'Rutina', 'day_of_week': 1, 'exercises': []};
          }
        }).toList(),
      );
    } catch (e) {
      debugPrint('Error en _normalizeWorkouts: $e');
      return [];
    }
  }

  Map<String, dynamic> _normalizeExercise(
    Map<String, dynamic> exercise, {
    int fallbackOrder = 0,
  }) {
    final pr = exercisePrData(exercise);
    return {
      ...exercise,
      'name': exercise['name']?.toString().trim().isNotEmpty == true
          ? exercise['name']
          : 'Ejercicio',
      'sets': _parseSetsValue(exercise['sets']),
      'reps': _normalizeRepsValue(exercise['reps']),
      'rest_seconds': _parseRestSecondsValue(
        exercise['rest_seconds'] ?? exercise['rest'],
      ),
      'notes': exercise['notes']?.toString() ?? '',
      'max_weight': exerciseMaxWeightText(exercise),
      'load': exerciseMaxWeightText(exercise),
      'pr_weight': pr['weight'] ?? '',
      'pr_reps': pr['reps'] ?? '',
      'pr_date': pr['date'] ?? '',
      'pr_notes': pr['notes'] ?? '',
      'exercise_order':
          int.tryParse(exercise['exercise_order']?.toString() ?? '') ??
          fallbackOrder,
    };
  }

  int _parseSetsValue(dynamic value) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty) {
      return 0;
    }

    final numberMatch = RegExp(r'\d+(?:[.,]\d+)?').firstMatch(text);
    if (numberMatch == null) {
      return int.tryParse(text) ?? 0;
    }

    final parsed = double.tryParse(numberMatch.group(0)!.replaceAll(',', '.'));
    return parsed?.round() ?? 0;
  }

  String _normalizeRepsValue(dynamic value) {
    return normalizeRepsText(value);
  }

  int _parseRestSecondsValue(dynamic value) {
    final raw = value?.toString().trim() ?? '';
    if (raw.isEmpty) {
      return 0;
    }

    final normalized = raw.toLowerCase().replaceAll(',', '.').trim();

    final minuteMatch = RegExp(
      r'(\d+(?:\.\d+)?)\s*(min|minutos?|minutes?|m)\b',
    ).firstMatch(normalized);
    if (minuteMatch != null) {
      final minutes = double.tryParse(minuteMatch.group(1)!);
      return minutes == null ? 0 : (minutes * 60).round();
    }

    final secondMatch = RegExp(
      r'(\d+(?:\.\d+)?)\s*(s|seg|segs|secs|segundos?|seconds?)\b',
    ).firstMatch(normalized);
    if (secondMatch != null) {
      final seconds = double.tryParse(secondMatch.group(1)!);
      return seconds?.round() ?? 0;
    }

    final clockMatch = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(normalized);
    if (clockMatch != null) {
      final minutes = int.tryParse(clockMatch.group(1)!) ?? 0;
      final seconds = int.tryParse(clockMatch.group(2)!) ?? 0;
      return (minutes * 60) + seconds;
    }

    final numeric = double.tryParse(normalized);
    if (numeric != null) {
      if (numeric <= 15) {
        return (numeric * 60).round();
      }
      return numeric.round();
    }

    final firstNumber = RegExp(r'\d+(?:\.\d+)?').firstMatch(normalized);
    if (firstNumber != null) {
      final parsed = double.tryParse(firstNumber.group(0)!);
      if (parsed != null) {
        if (parsed <= 15) {
          return (parsed * 60).round();
        }
        return parsed.round();
      }
    }

    return 0;
  }

  List<Map<String, dynamic>> _normalizeDiets(
    List<Map<String, dynamic>>? items,
  ) {
    if (items == null || items.isEmpty) {
      return [];
    }

    try {
      return _sortByDay(
        items.map((item) {
          try {
            final diet = Map<String, dynamic>.from(item);
            final meals =
                (diet['meals'] as List?)
                    ?.whereType<Map>()
                    .map((meal) => Map<String, dynamic>.from(meal))
                    .toList() ??
                <Map<String, dynamic>>[];
            final orderedMeals = _sortDietMealsByDisplayOrder(meals);
            return {
              ...diet,
              'name': diet['name']?.toString().trim().isNotEmpty == true
                  ? diet['name']
                  : 'Dieta',
              'day_of_week':
                  int.tryParse(diet['day_of_week']?.toString() ?? '') ?? 1,
              'meals': orderedMeals,
            };
          } catch (e) {
            debugPrint('Error normalizando dieta: $e');
            return {'name': 'Dieta', 'day_of_week': 1, 'meals': []};
          }
        }).toList(),
      );
    } catch (e) {
      debugPrint('Error en _normalizeDiets: $e');
      return [];
    }
  }

  List<Map<String, dynamic>> _sortDietMealsByDisplayOrder(
    List<Map<String, dynamic>> meals,
  ) {
    final indexedMeals = meals.asMap().entries.map((entry) {
      return {...entry.value, '_fallback_index': entry.key};
    }).toList();

    indexedMeals.sort((a, b) {
      final orderA = int.tryParse(a['order_index']?.toString() ?? '');
      final orderB = int.tryParse(b['order_index']?.toString() ?? '');
      if (orderA != null || orderB != null) {
        return (orderA ?? (1 << 20)).compareTo(orderB ?? (1 << 20));
      }

      final rankCompare = _dietMealDisplayRank(
        a['name'],
      ).compareTo(_dietMealDisplayRank(b['name']));
      if (rankCompare != 0) {
        return rankCompare;
      }

      final idA = int.tryParse(a['id']?.toString() ?? '');
      final idB = int.tryParse(b['id']?.toString() ?? '');
      if (idA != null || idB != null) {
        return (idA ?? (1 << 20)).compareTo(idB ?? (1 << 20));
      }

      return (a['_fallback_index'] as int).compareTo(
        b['_fallback_index'] as int,
      );
    });

    return indexedMeals.map((meal) {
      final cleanMeal = Map<String, dynamic>.from(meal);
      cleanMeal.remove('_fallback_index');
      return cleanMeal;
    }).toList();
  }

  int _dietMealDisplayRank(dynamic value) {
    final name =
        value
            ?.toString()
            .toLowerCase()
            .replaceAll('-', ' ')
            .replaceAll('_', ' ') ??
        '';
    final mealNumber = RegExp(r'comida\s*(\d+)').firstMatch(name);
    if (mealNumber != null) {
      return (int.tryParse(mealNumber.group(1)!) ?? 99) * 10;
    }
    if (name.contains('pre') && name.contains('work')) {
      return 40;
    }
    if (name.contains('post') && name.contains('work')) {
      return 50;
    }
    if (name.contains('comod')) {
      return 60;
    }
    if (name.contains('suplement')) {
      return 70;
    }
    return 100;
  }

  List<Map<String, dynamic>> _mergeStoredDietMealOrder(
    List<Map<String, dynamic>> backendDiets,
    List<Map<String, dynamic>> storedDiets,
  ) {
    final storedById = <String, Map<String, dynamic>>{};
    for (final diet in storedDiets) {
      final id = diet['id']?.toString();
      if (id != null && id.isNotEmpty) {
        storedById[id] = diet;
      }
    }

    return backendDiets.map((diet) {
      final dietId = diet['id']?.toString();
      final storedDiet = dietId == null ? null : storedById[dietId];
      final storedMeals =
          (storedDiet?['meals'] as List?)
              ?.whereType<Map>()
              .map((meal) => Map<String, dynamic>.from(meal))
              .toList() ??
          <Map<String, dynamic>>[];
      if (storedMeals.isEmpty) {
        return diet;
      }

      final storedOrder = <String, int>{};
      for (var index = 0; index < storedMeals.length; index++) {
        final mealId = storedMeals[index]['id']?.toString();
        if (mealId != null && mealId.isNotEmpty) {
          storedOrder[mealId] = index;
        }
      }
      if (storedOrder.isEmpty) {
        return diet;
      }

      final meals =
          (diet['meals'] as List?)
              ?.whereType<Map>()
              .map((meal) => Map<String, dynamic>.from(meal))
              .toList() ??
          <Map<String, dynamic>>[];
      meals.sort((a, b) {
        final orderA = storedOrder[a['id']?.toString()];
        final orderB = storedOrder[b['id']?.toString()];
        if (orderA != null || orderB != null) {
          return (orderA ?? (1 << 20)).compareTo(orderB ?? (1 << 20));
        }
        return _dietMealDisplayRank(
          a['name'],
        ).compareTo(_dietMealDisplayRank(b['name']));
      });

      return {...diet, 'meals': meals};
    }).toList();
  }

  List<Map<String, dynamic>> _normalizeDailyMeals(
    List<Map<String, dynamic>>? items,
  ) {
    if (items == null || items.isEmpty) {
      return [];
    }

    try {
      final meals = items.map((item) {
        try {
          final meal = Map<String, dynamic>.from(item);
          return {
            ...meal,
            'name': meal['name']?.toString().trim().isNotEmpty == true
                ? meal['name']
                : 'Comida registrada',
            'meal_slot': meal['meal_slot']?.toString() ?? '',
            'calories': meal['calories'] ?? 0,
            'protein': meal['protein'] ?? 0,
            'carbs': meal['carbs'] ?? 0,
            'fats': meal['fats'] ?? 0,
            'estimated_grams': meal['estimated_grams'] ?? 0,
          };
        } catch (e) {
          debugPrint('Error normalizando comida: $e');
          return {'name': 'Comida registrada', 'meal_slot': '', 'calories': 0};
        }
      }).toList();
      meals.sort((a, b) {
        final timeA = DateTime.tryParse(a['logged_at']?.toString() ?? '');
        final timeB = DateTime.tryParse(b['logged_at']?.toString() ?? '');
        if (timeA == null && timeB == null) {
          return 0;
        }
        if (timeA == null) {
          return 1;
        }
        if (timeB == null) {
          return -1;
        }
        return timeA.compareTo(timeB);
      });
      return meals;
    } catch (e) {
      debugPrint('Error en _normalizeDailyMeals: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>?> _fetchWorkoutsFromBackend() async {
    try {
      final data = await Supabase.instance.client
          .from('workouts')
          .select('*, exercises(*)')
          .eq('user_id', widget.currentUser.id)
          .order('day_of_week', ascending: true)
          .order(
            'exercise_order',
            referencedTable: 'exercises',
            ascending: true,
          )
          .order('id', referencedTable: 'exercises', ascending: true);

      final workoutsData = data
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();

      final storedWorkouts = _normalizeWorkouts(
        await LocalUserDataStore.loadWorkouts(widget.currentUser.email),
      );
      final localOnlyWorkouts = storedWorkouts.where((workout) {
        final id = workout['id']?.toString() ?? '';
        return workout['local_only'] == true || id.startsWith('local_');
      }).toList();
      final normalizedWorkouts = _normalizeWorkouts([
        ...workoutsData,
        ...localOnlyWorkouts,
      ]);
      await LocalUserDataStore.saveWorkouts(
        widget.currentUser.email,
        normalizedWorkouts,
      );
      return normalizedWorkouts;
    } catch (e) {
      debugPrint('Error al sincronizar con el backend: $e');
      return null;
    }
  }

  Future<List<Map<String, dynamic>>?> _fetchDietsFromBackend() async {
    try {
      final data = await Supabase.instance.client
          .from('diets')
          .select('*, meals(*)')
          .eq('user_id', widget.currentUser.id)
          .order('day_of_week', ascending: true)
          .order('id', referencedTable: 'meals', ascending: true);

      final dietsData = data
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();

      final storedDiets = _normalizeDiets(
        await LocalUserDataStore.loadDiets(widget.currentUser.email),
      );
      final localOnlyDiets = storedDiets.where((diet) {
        final id = diet['id']?.toString() ?? '';
        return diet['local_only'] == true || id.startsWith('local_');
      }).toList();
      final normalizedDiets = _mergeStoredDietMealOrder(
        _normalizeDiets([...dietsData, ...localOnlyDiets]),
        storedDiets,
      );
      await LocalUserDataStore.saveDiets(
        widget.currentUser.email,
        normalizedDiets,
      );
      return normalizedDiets;
    } catch (e) {
      debugPrint('Error al sincronizar dietas con el backend: $e');
      return null;
    }
  }

  Future<List<Map<String, dynamic>>?> _fetchDailyNutritionFromBackend({
    List<Map<String, dynamic>>? previousMeals,
  }) async {
    try {
      final date = _todayIsoDate();

      final response = await Supabase.instance.client
          .from('daily_diets')
          .select('*')
          .eq('user_id', widget.currentUser.id)
          .eq('consumed_at', date)
          .order('created_at', ascending: true);

      final previousById = {
        for (final meal in (previousMeals ?? _dailyMeals))
          if (meal['id'] != null) meal['id'].toString(): meal,
      };

      final backendIds = response
          .map((entry) => entry['id']?.toString())
          .whereType<String>()
          .toSet();

      final mapped = response.whereType<Map>().map((entry) {
        final entryMap = Map<String, dynamic>.from(entry);
        final previous = previousById[entryMap['id']?.toString()];
        return {
          'id': entryMap['id'],
          'name': entryMap['name'] ?? 'Comida registrada',
          'meal_slot': entryMap['meal_slot'] ?? previous?['meal_slot'] ?? '',
          'calories': entryMap['calories'] ?? 0,
          'protein': entryMap['protein'] ?? 0,
          'carbs': entryMap['carbs'] ?? 0,
          'fats': entryMap['fats'] ?? 0,
          'estimated_grams':
              entryMap['grams'] ?? entryMap['estimated_grams'] ?? 0,
          'confidence': entryMap['confidence'] ?? previous?['confidence'] ?? 0,
          'items': entryMap['items'] is List
              ? entryMap['items']
              : previous?['items'] ?? [],
          'logged_at':
              entryMap['created_at'] ?? DateTime.now().toIso8601String(),
        };
      }).toList();
      mapped.addAll(
        (previousMeals ?? _dailyMeals).where(
          (meal) =>
              meal['manual'] == true &&
              !backendIds.contains(meal['id']?.toString()),
        ),
      );
      final normalizedMapped = _normalizeDailyMeals(mapped);
      await LocalUserDataStore.saveDailyMeals(
        widget.currentUser.email,
        date,
        normalizedMapped,
      );
      return normalizedMapped;
    } catch (e) {
      debugPrint('Error al sincronizar comidas diarias: $e');
      return null;
    }
  }

  Future<void> fetchDiets() async {
    final backendDiets = await _fetchDietsFromBackend();
    final storedDiets = _normalizeDiets(
      await LocalUserDataStore.loadDiets(widget.currentUser.email),
    );
    if (!mounted) {
      return;
    }

    setState(() {
      diets = backendDiets ?? storedDiets;
    });
  }

  Future<void> fetchDailyNutrition() async {
    final storedDailyMeals = _normalizeDailyMeals(
      await LocalUserDataStore.loadDailyMeals(
        widget.currentUser.email,
        _todayIsoDate(),
      ),
    );
    final backendDailyMeals = await _fetchDailyNutritionFromBackend(
      previousMeals: storedDailyMeals,
    );
    if (!mounted) {
      return;
    }

    setState(() {
      _dailyMeals = backendDailyMeals ?? storedDailyMeals;
    });
  }

  String _todayIsoDate() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  String _safeFileName(dynamic value) {
    final cleaned = value
        ?.toString()
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return cleaned == null || cleaned.isEmpty ? 'healthy_t' : cleaned;
  }

  Future<void> fetchWorkouts() async {
    final backendWorkouts = await _fetchWorkoutsFromBackend();
    final storedWorkouts = _normalizeWorkouts(
      await LocalUserDataStore.loadWorkouts(widget.currentUser.email),
    );
    final nextWorkouts = backendWorkouts ?? storedWorkouts;
    if (!mounted) {
      return;
    }

    setState(() {
      workouts = nextWorkouts;
      isLoading = false;
    });
    await _loadWeeklyWorkoutLog(nextWorkouts);
  }

  void _openConfigMenu() {
    setState(() {
      if (_currentIndex != 2) {
        _lastContentIndex = _currentIndex;
      }
      _currentIndex = 2;
    });
  }

  void _closeConfigMenu() {
    setState(() {
      _currentIndex = _lastContentIndex;
    });
  }

  List<Map<String, dynamic>> _sortByDay(List<Map<String, dynamic>> items) {
    items.sort((a, b) {
      final dayA = int.tryParse(a['day_of_week']?.toString() ?? '0') ?? 0;
      final dayB = int.tryParse(b['day_of_week']?.toString() ?? '0') ?? 0;
      return dayA.compareTo(dayB);
    });
    return items;
  }

  bool _isMissingPostgrestColumn(Object error, String column) {
    final message = error.toString().toLowerCase();
    return message.contains('pgrst204') &&
        message.contains(column.toLowerCase());
  }

  bool _isPostgrestRlsError(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('42501') ||
        message.contains('row-level security') ||
        message.contains('violates row-level security policy');
  }

  Future<void> _toggleHealthSync(bool value) async {
    if (value) {
      try {
        final authorized = await HealthService().initAndRequestPermissions();
        if (authorized) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('health_sync_enabled', true);
          setState(() => _isHealthSyncEnabled = true);
          unawaited(_loadRecoverySnapshot());
          _showSuccessSnackBar('Sincronización con Apple Health activada');
        } else {
          _showErrorSnackBar(
            'No se otorgaron los permisos de Salud. Si instalaste con AltStore o firma gratis, HealthKit puede no estar disponible; prueba una instalación nativa firmada con HealthKit activado.',
          );
        }
      } catch (e) {
        _showErrorSnackBar(
          'Error al solicitar permisos de Salud. Revisa que sea la app iOS nativa, no web, y que la firma incluya HealthKit: $e',
        );
      }
    } else {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('health_sync_enabled', false);
      setState(() {
        _isHealthSyncEnabled = false;
        _recoverySnapshot = null;
        _recoveryError = null;
      });
      _showSuccessSnackBar('Sincronización desactivada');
    }
  }

  Future<void> _loadRecoverySnapshot() async {
    if (!_isHealthSyncEnabled || kIsWeb) return;
    if (mounted) {
      setState(() {
        _isLoadingRecovery = true;
        _recoveryError = null;
      });
    }

    try {
      final snapshot = await HealthService().getRecoverySnapshot();
      if (!mounted) return;
      setState(() => _recoverySnapshot = snapshot);
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _recoveryError =
            'No pude leer el descanso del teléfono. Revisa permisos de Salud.',
      );
    } finally {
      if (mounted) {
        setState(() => _isLoadingRecovery = false);
      }
    }
  }

  void _openRecoveryDetails() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RecoveryDetailScreen(
          initialSnapshot: _recoverySnapshot,
          isHealthSyncEnabled: _isHealthSyncEnabled,
          recoveryError: _recoveryError,
          onEnableHealthSync: () => _toggleHealthSync(true),
        ),
      ),
    );
  }

  Future<void> _toggleLightMode(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_themePreferenceKey, value);
    healthyTThemeMode.value = value ? ThemeMode.light : ThemeMode.dark;
    if (!mounted) return;
    setState(() => _isLightMode = value);
    _showSuccessSnackBar(
      value ? 'Modo claro activado' : 'Modo oscuro activado',
    );
  }

  Future<void> _persistWorkouts(
    List<Map<String, dynamic>> updatedWorkouts,
  ) async {
    await LocalUserDataStore.saveWorkouts(
      widget.currentUser.email,
      updatedWorkouts,
    );
    await fetchWorkouts();
  }

  Future<void> _reorderDietMeal(
    Map<String, dynamic> diet,
    int oldIndex,
    int newIndex,
  ) async {
    if (newIndex > oldIndex) {
      newIndex -= 1;
    }

    final dietId = diet['id']?.toString();
    final meals =
        (diet['meals'] as List?)
            ?.whereType<Map>()
            .map((meal) => Map<String, dynamic>.from(meal))
            .toList() ??
        <Map<String, dynamic>>[];
    if (oldIndex < 0 ||
        oldIndex >= meals.length ||
        newIndex < 0 ||
        newIndex > meals.length) {
      return;
    }

    final movedMeal = meals.removeAt(oldIndex);
    meals.insert(newIndex, movedMeal);

    final updatedDiets = diets.map((item) {
      if (item['id']?.toString() != dietId) {
        return item;
      }
      return {...Map<String, dynamic>.from(item), 'meals': meals};
    }).toList();

    setState(() => diets = updatedDiets);
    await LocalUserDataStore.saveDiets(widget.currentUser.email, updatedDiets);
  }

  Future<void> _assignWorkoutToUserByEmail() async {
    final targetEmail = _adminTargetEmailController.text.trim().toLowerCase();
    if (targetEmail.isEmpty) {
      _showErrorSnackBar('Escribe el correo del usuario destino');
      return;
    }

    final selectedWorkout = workouts.cast<Map<String, dynamic>?>().firstWhere(
      (workout) =>
          workout?['id']?.toString() == _selectedAdminWorkoutId?.toString(),
      orElse: () => workouts.isNotEmpty ? workouts.first : null,
    );
    if (selectedWorkout == null) {
      _showErrorSnackBar('Crea o carga una rutina antes de asignarla');
      return;
    }

    try {
      final result = await Supabase.instance.client.rpc(
        'assign_workout_to_email',
        params: {
          'target_email': targetEmail,
          'workout_payload': _workoutAssignmentPayload(selectedWorkout),
        },
      );

      _adminTargetEmailController.clear();
      final wasPending = result?.toString().startsWith('pending:') == true;
      _showSuccessSnackBar(
        wasPending
            ? 'Rutina guardada para $targetEmail. Se entregará cuando inicie sesión.'
            : 'Rutina asignada a $targetEmail',
      );
    } catch (e) {
      _showErrorSnackBar('Error asignando rutina: $e');
    }
  }

  Future<void> _assignDietToUserByEmail() async {
    final targetEmail = _adminTargetEmailController.text.trim().toLowerCase();
    if (targetEmail.isEmpty) {
      _showErrorSnackBar('Escribe el correo del usuario destino');
      return;
    }

    final selectedDiet = diets.cast<Map<String, dynamic>?>().firstWhere(
      (diet) => diet?['id']?.toString() == _selectedAdminDietId?.toString(),
      orElse: () => diets.isNotEmpty ? diets.first : null,
    );
    if (selectedDiet == null) {
      _showErrorSnackBar('Crea o carga una dieta antes de asignarla');
      return;
    }

    try {
      final result = await Supabase.instance.client.rpc(
        'assign_diet_to_email',
        params: {
          'target_email': targetEmail,
          'diet_payload': _dietAssignmentPayload(selectedDiet),
        },
      );

      _adminTargetEmailController.clear();
      final wasPending = result?.toString().startsWith('pending:') == true;
      _showSuccessSnackBar(
        wasPending
            ? 'Dieta guardada para $targetEmail. Se entregará cuando inicie sesión.'
            : 'Dieta asignada a $targetEmail',
      );
    } catch (e) {
      _showErrorSnackBar('Error asignando dieta: $e');
    }
  }

  Future<void> _claimPendingAssignments() async {
    try {
      await Supabase.instance.client.rpc('claim_pending_assignments');
    } catch (e) {
      debugPrint('No se pudieron reclamar asignaciones pendientes: $e');
    }
  }

  Map<String, dynamic> _workoutAssignmentPayload(Map<String, dynamic> workout) {
    final exercises =
        (workout['exercises'] as List?)
            ?.whereType<Map>()
            .map(
              (exercise) => {
                'name': exercise['name']?.toString() ?? 'Ejercicio',
                'sets': parseWholeNumber(exercise['sets']),
                'reps': normalizeRepsText(exercise['reps']),
                'rest_seconds': parseWholeNumber(exercise['rest_seconds']),
                'notes': exercise['notes']?.toString() ?? '',
                'exercise_order': parseWholeNumber(exercise['exercise_order']),
              },
            )
            .toList() ??
        <Map<String, dynamic>>[];

    return {
      'name': workout['name']?.toString() ?? 'Rutina asignada',
      'day_of_week':
          int.tryParse(workout['day_of_week']?.toString() ?? '') ?? 1,
      'exercises': exercises,
    };
  }

  Map<String, dynamic> _dietAssignmentPayload(Map<String, dynamic> diet) {
    final meals =
        (diet['meals'] as List?)
            ?.whereType<Map>()
            .map(
              (meal) => {
                'name': meal['name']?.toString() ?? 'Comida',
                'calories': parseWholeNumber(meal['calories']),
                'protein': parseWholeNumber(meal['protein']),
                'carbs': parseWholeNumber(meal['carbs']),
                'fats': parseWholeNumber(meal['fats']),
                'notes': meal['notes']?.toString() ?? '',
              },
            )
            .toList() ??
        <Map<String, dynamic>>[];

    return {
      'name': diet['name']?.toString() ?? 'Dieta asignada',
      'day_of_week': int.tryParse(diet['day_of_week']?.toString() ?? '') ?? 1,
      'meals': meals,
    };
  }

  Future<void> _assignWorkoutExcelToUserByEmail() async {
    final targetEmail = _adminTargetEmailController.text.trim().toLowerCase();
    if (targetEmail.isEmpty) {
      _showErrorSnackBar('Escribe el correo del usuario destino');
      return;
    }

    try {
      final pickedFile = await _pickAdminExcelFile();
      if (pickedFile == null) {
        return;
      }

      final parsedWorkouts = _parseWorkoutExcelBytes(
        pickedFile.bytes,
        pickedFile.name,
      );
      if (parsedWorkouts.isEmpty) {
        _showErrorSnackBar('No encontré rutinas válidas en ese Excel');
        return;
      }

      var pendingCount = 0;
      for (final workout in parsedWorkouts) {
        final result = await Supabase.instance.client.rpc(
          'assign_workout_to_email',
          params: {
            'target_email': targetEmail,
            'workout_payload': _workoutAssignmentPayload(workout),
          },
        );
        if (result?.toString().startsWith('pending:') == true) {
          pendingCount++;
        }
      }

      _showSuccessSnackBar(
        pendingCount > 0
            ? '${parsedWorkouts.length} rutina(s) guardadas para $targetEmail'
            : '${parsedWorkouts.length} rutina(s) asignadas a $targetEmail',
      );
    } catch (e) {
      _showErrorSnackBar('Error asignando Excel de rutina: $e');
    }
  }

  Future<void> _assignDietExcelToUserByEmail() async {
    final targetEmail = _adminTargetEmailController.text.trim().toLowerCase();
    if (targetEmail.isEmpty) {
      _showErrorSnackBar('Escribe el correo del usuario destino');
      return;
    }

    try {
      final pickedFile = await _pickAdminExcelFile();
      if (pickedFile == null) {
        return;
      }

      final parsedDiets = _parseDietExcelBytes(
        pickedFile.bytes,
        pickedFile.name,
      );
      if (parsedDiets.isEmpty) {
        _showErrorSnackBar('No encontré dietas válidas en ese Excel');
        return;
      }

      var pendingCount = 0;
      for (final diet in parsedDiets) {
        final result = await Supabase.instance.client.rpc(
          'assign_diet_to_email',
          params: {
            'target_email': targetEmail,
            'diet_payload': _dietAssignmentPayload(diet),
          },
        );
        if (result?.toString().startsWith('pending:') == true) {
          pendingCount++;
        }
      }

      _showSuccessSnackBar(
        pendingCount > 0
            ? '${parsedDiets.length} dieta(s) guardadas para $targetEmail'
            : '${parsedDiets.length} dieta(s) asignadas a $targetEmail',
      );
    } catch (e) {
      _showErrorSnackBar('Error asignando Excel de dieta: $e');
    }
  }

  Future<_PickedAdminExcelFile?> _pickAdminExcelFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
      withData: true,
    );
    if (result == null) {
      return null;
    }

    final file = result.files.single;
    final bytes =
        file.bytes ??
        (file.path != null ? await File(file.path!).readAsBytes() : null);
    if (bytes == null) {
      throw Exception('No se pudo leer el Excel seleccionado');
    }
    return _PickedAdminExcelFile(name: file.name, bytes: bytes);
  }

  List<Map<String, dynamic>> _parseWorkoutExcelBytes(
    List<int> bytes,
    String fileName,
  ) {
    final excel = xlsx.Excel.decodeBytes(bytes);
    final sheet = excel.tables.values.isEmpty
        ? null
        : excel.tables.values.first;
    if (sheet == null || sheet.rows.isEmpty) {
      return [];
    }

    final headers = _excelHeaders(sheet.rows.first);
    final grouped = <String, List<Map<String, dynamic>>>{};
    final nameByKey = <String, String>{};
    final dayByName = <String, int>{};

    for (final row in sheet.rows.skip(1)) {
      final exerciseName = _excelTextByHeader(row, headers, 'ejercicio', 1);
      if (exerciseName.isEmpty) {
        continue;
      }

      final workoutName = _excelTextByHeader(row, headers, 'día', 0)
          .ifEmpty(_excelTextByHeader(row, headers, 'dia', 0))
          .ifEmpty('Rutina importada');
      final key = workoutName.toLowerCase();
      nameByKey[key] = workoutName;
      final exerciseIndex = grouped.putIfAbsent(key, () => []).length;
      dayByName.putIfAbsent(key, () => dayByName.length + 1);

      final load = _excelTextByHeader(row, headers, 'carga', 5);
      final notes = _excelTextByHeader(row, headers, 'notas', 6);
      grouped[key]!.add({
        'name': exerciseName,
        'sets': parseWholeNumber(_excelTextByHeader(row, headers, 'series', 2)),
        'rest_seconds': _parseRestSecondsValue(
          _excelTextByHeader(
            row,
            headers,
            'tiempo_de_descanso',
            3,
          ).ifEmpty(_excelTextByHeader(row, headers, 'descanso', 3)),
        ),
        'reps': normalizeRepsText(_excelTextByHeader(row, headers, 'reps', 4)),
        'load': load,
        'max_weight': load,
        'notes': [
          if (load.isNotEmpty) 'Carga: $load',
          if (notes.isNotEmpty) notes,
        ].join(' | '),
        'exercise_order': exerciseIndex,
      });
    }

    return grouped.entries.map((entry) {
      final name = nameByKey[entry.key] ?? 'Rutina importada';
      return {
        'name': name.isEmpty ? 'Rutina importada' : name,
        'day_of_week': (dayByName[entry.key] ?? 1).clamp(1, 7),
        'exercises': entry.value,
      };
    }).toList();
  }

  List<Map<String, dynamic>> _parseDietExcelBytes(
    List<int> bytes,
    String fileName,
  ) {
    final excel = xlsx.Excel.decodeBytes(bytes);
    final sheet = excel.tables.values.isEmpty
        ? null
        : excel.tables.values.first;
    if (sheet == null || sheet.rows.isEmpty) {
      return [];
    }

    final headers = _excelHeaders(sheet.rows.first);
    final rows = <Map<String, String>>[];
    for (final row in sheet.rows.skip(1)) {
      final meal = _excelTextByHeader(row, headers, 'comida', 0);
      final food = _excelTextByHeader(row, headers, 'alimento', 3);
      final category = _excelTextByHeader(
        row,
        headers,
        'categoría',
        2,
      ).ifEmpty(_excelTextByHeader(row, headers, 'categoria', 2));
      if (meal.isEmpty && food.isEmpty && category.isEmpty) {
        continue;
      }
      rows.add({
        'comida': meal.isEmpty ? 'Comida' : meal,
        'opcion': _excelTextByHeader(
          row,
          headers,
          'opción',
          1,
        ).ifEmpty(_excelTextByHeader(row, headers, 'opcion', 1)),
        'categoria': category,
        'alimento': food,
        'cantidad': _excelTextByHeader(row, headers, 'cantidad', 4),
        'unidad': _excelTextByHeader(row, headers, 'unidad', 5),
        'notas': _excelTextByHeader(row, headers, 'notas', 6),
      });
    }

    final meals = _groupDietRowsIntoMeals(rows)
        .whereType<Map>()
        .map((meal) {
          final mealRows = (meal['rows'] as List)
              .whereType<Map>()
              .map((row) => Map<String, String>.from(row))
              .toList();
          return {
            'name': meal['name']?.toString() ?? 'Comida',
            'calories': 0,
            'protein': 0,
            'carbs': 0,
            'fats': 0,
            'notes': _formatDietRowsAsNotes(mealRows),
          };
        })
        .where((meal) => meal['notes']?.toString().trim().isNotEmpty == true)
        .toList();

    if (meals.isEmpty) {
      return [];
    }

    return [
      {
        'name': fileName.replaceAll(
          RegExp(r'\.xlsx$', caseSensitive: false),
          '',
        ),
        'day_of_week': 1,
        'meals': _sortDietMealsByDisplayOrder(meals),
      },
    ];
  }

  Map<String, int> _excelHeaders(List<dynamic> row) {
    final headers = <String, int>{};
    for (var index = 0; index < row.length; index++) {
      final normalized = _normalizeHeader(_excelCellText(row[index]));
      if (normalized.isNotEmpty) {
        headers[normalized] = index;
      }
    }
    return headers;
  }

  String _excelTextByHeader(
    List<dynamic> row,
    Map<String, int> headers,
    String header,
    int fallbackIndex,
  ) {
    final index = headers[_normalizeHeader(header)] ?? fallbackIndex;
    if (index < 0 || index >= row.length) {
      return '';
    }
    return _excelCellText(row[index]);
  }

  String _excelCellText(dynamic cell) {
    final value = cell?.value;
    if (value == null) {
      return '';
    }
    if (value is xlsx.TextCellValue) {
      return value.value.text?.trim() ?? '';
    }
    return value.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String _normalizeHeader(String value) {
    return value
        .toLowerCase()
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }

  Future<void> pickAndUploadFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        withData: true,
      );

      if (result == null) {
        return;
      }

      final file = result.files.single;
      final fileBytes =
          file.bytes ??
          (file.path != null ? await File(file.path!).readAsBytes() : null);
      if (fileBytes == null) {
        _showErrorSnackBar('No se pudo leer el PDF seleccionado');
        return;
      }

      setState(() => isLoading = true);
      _showSuccessSnackBar('Analizando PDF y convirtiendo rutina...');

      final importedWorkouts = await _convertWorkoutPdfToExcelShape(
        fileBytes,
        file.name,
      );
      if (importedWorkouts.isEmpty) {
        _showErrorSnackBar('No se encontraron ejercicios en el PDF');
        return;
      }

      List<Map<String, dynamic>> savedWorkouts;
      try {
        savedWorkouts = await _saveImportedWorkouts(importedWorkouts);
      } catch (e) {
        final canFallback =
            _isMissingPostgrestColumn(e, 'day_of_week') ||
            _isPostgrestRlsError(e);
        if (!canFallback) {
          rethrow;
        }
        savedWorkouts = await _saveImportedWorkoutsLocally(importedWorkouts);
        final reason = _isPostgrestRlsError(e)
            ? 'RLS bloqueó la inserción en workouts'
            : 'Supabase no tiene day_of_week en workouts';
        _showErrorSnackBar(
          '$reason. Guardé la rutina localmente; corre el SQL de schema/policies para sincronizarla.',
        );
      }
      final updatedWorkouts = _normalizeWorkouts([
        ...workouts,
        ...savedWorkouts,
      ]);
      await LocalUserDataStore.saveWorkouts(
        widget.currentUser.email,
        updatedWorkouts,
      );
      if (mounted) {
        setState(() => workouts = updatedWorkouts);
      }
      _showSuccessSnackBar(
        'Rutina importada con estructura de Excel (${savedWorkouts.length} días)',
      );
      await _showImportReviewNotice('rutina');
    } on GeminiQuotaException catch (e) {
      _showErrorSnackBar(e.message);
    } catch (e) {
      _showErrorSnackBar('Error: $e');
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  Future<List<Map<String, dynamic>>> _convertWorkoutPdfToExcelShape(
    Uint8List pdfBytes,
    String fileName,
  ) async {
    final text = await _generateGeminiPdfJson(
      pdfBytes: pdfBytes,
      prompt: _workoutImportPrompt(fileName),
    );

    return _parseWorkoutImportPayload(text);
  }

  Future<String> _generateGeminiPdfJson({
    required Uint8List pdfBytes,
    required String prompt,
  }) async {
    String? quotaMessage;

    for (final model in ApiConfig.geminiPdfModels) {
      final response = await http.post(
        Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=${ApiConfig.geminiApiKey}',
        ),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [
            {
              'parts': [
                {'text': prompt},
                {
                  'inlineData': {
                    'mimeType': 'application/pdf',
                    'data': base64Encode(pdfBytes),
                  },
                },
              ],
            },
          ],
          'generationConfig': {
            'responseMimeType': 'application/json',
            'temperature': 0.1,
          },
        }),
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(response.body);
        final text = data['candidates']?[0]?['content']?['parts']?[0]?['text'];
        if (text is String && text.trim().isNotEmpty) {
          return text;
        }
        throw Exception('La IA no devolvió contenido válido');
      }

      if (_isGeminiQuotaError(response)) {
        quotaMessage = _friendlyGeminiQuotaMessage(response.body);
        continue;
      }

      throw Exception(
        'Gemini respondió ${response.statusCode}: ${_shortGeminiError(response.body)}',
      );
    }

    throw GeminiQuotaException(
      quotaMessage ??
          'Se agotó la cuota de Gemini para convertir PDFs. Espera un momento o activa billing en Google AI Studio.',
    );
  }

  bool _isGeminiQuotaError(http.Response response) {
    return response.statusCode == 429 ||
        response.body.contains('RESOURCE_EXHAUSTED') ||
        response.body.toLowerCase().contains('quota exceeded');
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

    return 'Gemini agotó la cuota para convertir PDFs. Intenta de nuevo en $waitText o activa billing/sube cuota en Google AI Studio.';
  }

  String _shortGeminiError(String body) {
    try {
      final decoded = jsonDecode(body);
      final message = decoded['error']?['message'];
      if (message is String && message.isNotEmpty) {
        return message.split('\n').first;
      }
    } catch (_) {}

    return body.length > 220 ? '${body.substring(0, 220)}...' : body;
  }

  Future<String> _generateGeminiTextJson(String prompt) async {
    String? quotaMessage;

    for (final model in ApiConfig.geminiPdfModels) {
      final response = await http.post(
        Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=${ApiConfig.geminiApiKey}',
        ),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [
            {
              'parts': [
                {'text': prompt},
              ],
            },
          ],
          'generationConfig': {
            'responseMimeType': 'application/json',
            'temperature': 0.35,
          },
        }),
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(response.body);
        final text = data['candidates']?[0]?['content']?['parts']?[0]?['text'];
        if (text is String && text.trim().isNotEmpty) {
          return text;
        }
        throw Exception('La IA no devolvió contenido válido');
      }

      if (_isGeminiQuotaError(response)) {
        quotaMessage = _friendlyGeminiQuotaMessage(response.body);
        continue;
      }

      throw Exception(
        'Gemini respondió ${response.statusCode}: ${_shortGeminiError(response.body)}',
      );
    }

    throw GeminiQuotaException(
      quotaMessage ??
          'Se agotó la cuota de Gemini para crear rutinas. Espera un momento o activa billing en Google AI Studio.',
    );
  }

  String _workoutImportPrompt(String fileName) {
    return '''
Convierte el PDF "$fileName" a la estructura exacta de esta plantilla de Excel:
DÍA | EJERCICIO | SERIES | TIEMPO DE DESCANSO | REPS | CARGA | NOTAS

Devuelve únicamente JSON válido, sin markdown, con esta forma:
{
  "workouts": [
    {
      "name": "DIA 1 LOWER A (GLUTEO E IZQUIOTIBIALES)",
      "day_of_week": 1,
      "rows": [
        {
          "dia": "DIA 1 LOWER A (GLUTEO E IZQUIOTIBIALES)",
          "ejercicio": "HIP THRUST CON BARRA",
          "series": 3,
          "tiempo_de_descanso": "3 MIN",
          "reps": "8-10",
          "carga": "FALLO",
          "notas": "SERIES UNICAS"
        }
      ]
    }
  ]
}

Reglas:
- Separa la rutina por cada día/plan detectado.
- Si un ejercicio especifica días como "lunes, miércoles y viernes", "L/M/V", "martes-jueves" o similares, duplícalo y ubícalo en cada day_of_week correspondiente.
- Si una fila tiene varios días, incluye también un campo "dias": ["lunes", "miércoles", "viernes"] en esa fila.
- Conserva el orden exacto en el que aparecen los días y los ejercicios en el PDF.
- Conserva nombres de ejercicios, acentos y mayúsculas cuando sea posible.
- El campo "ejercicio" debe ser el nombre COMPLETO y literal del PDF. Si el nombre está partido en varias líneas o continúa en la siguiente línea visual, une todas las partes antes de devolverlo.
- No cortes nombres de ejercicios al final de línea, al ancho de columna, ni a la mitad de una palabra. Ejemplo: si el PDF muestra "APERTURAS DE PECTORAL MÁS EMPUJES EN POLEAS MEDIAS CON BANCO VERTICAL", devuelve exactamente ese texto completo en "ejercicio".
- No muevas fragmentos del nombre del ejercicio a "notas"; "notas" solo debe contener texto adicional que no forme parte del nombre.
- Usa day_of_week real cuando el PDF mencione lunes, martes, miércoles, jueves, viernes, sábado o domingo.
- Si el PDF no menciona un día real, usa day_of_week 1 para el primer bloque/día encontrado, 2 para el segundo, y así sucesivamente.
- No incluyas calentamiento, explicación de progresión, volumen semanal ni texto que no sea ejercicio.
- Cada fila debe mapearse a las columnas del Excel: DÍA, EJERCICIO, SERIES, TIEMPO DE DESCANSO, REPS, CARGA, NOTAS.
- Si un dato no aparece, usa "" excepto series, que puede ser 0.
''';
  }

  List<Map<String, dynamic>> _parseWorkoutImportPayload(String rawText) {
    final cleanText = rawText
        .replaceAll('```json', '')
        .replaceAll('```', '')
        .trim();
    final decoded = jsonDecode(cleanText);
    final rawWorkouts = decoded is Map
        ? decoded['workouts']
        : decoded is List
        ? decoded
        : null;
    if (rawWorkouts is! List) {
      return [];
    }

    final collected = rawWorkouts
        .whereType<Map>()
        .toList()
        .asMap()
        .entries
        .expand((entry) {
          final workout = entry.value;
          final rows = workout['rows'] ?? workout['exercises'];
          final exercises = rows is List
              ? rows
                    .whereType<Map>()
                    .toList()
                    .asMap()
                    .entries
                    .map((row) {
                      final rowMap = row.value;
                      final carga = rowMap['carga']?.toString().trim() ?? '';
                      final notas = rowMap['notas'] ?? rowMap['notes'];
                      final notesText = notas?.toString().trim() ?? '';
                      final rowDays = _extractWorkoutDays(
                        rowMap['dias'] ??
                            rowMap['dia'] ??
                            rowMap['day'] ??
                            rowMap['days'] ??
                            workout['day_of_week'] ??
                            workout['name'],
                      );
                      return {
                        'name':
                            rowMap['ejercicio'] ??
                            rowMap['name'] ??
                            'Ejercicio',
                        'dia': rowMap['dia'] ?? workout['name'],
                        'days': rowDays,
                        'sets': _parseSetsValue(
                          rowMap['series'] ?? rowMap['sets'],
                        ),
                        'reps': _normalizeRepsValue(rowMap['reps']),
                        'rest_seconds': _parseRestSecondsValue(
                          rowMap['tiempo_de_descanso'] ??
                              rowMap['descanso'] ??
                              rowMap['rest_seconds'] ??
                              rowMap['rest'],
                        ),
                        'load': carga,
                        'max_weight': carga,
                        'notes': [
                          if (carga.isNotEmpty) 'Carga: $carga',
                          if (notesText.isNotEmpty) notesText,
                        ].join(' | '),
                        'exercise_order': row.key,
                      };
                    })
                    .where((exercise) {
                      final name = exercise['name']?.toString().trim() ?? '';
                      return name.isNotEmpty &&
                          name.toLowerCase() != 'ejercicio';
                    })
                    .toList()
              : <Map<String, dynamic>>[];

          final workoutDays = _extractWorkoutDays(
            workout['day_of_week'] ?? workout['dia'] ?? workout['name'],
          );
          final defaultDays = workoutDays.isNotEmpty
              ? workoutDays
              : <int>[(entry.key + 1).clamp(1, 7)];
          final fallbackDay = exercises.isNotEmpty
              ? exercises.first['dia']?.toString()
              : null;
          final name = workout['name']?.toString().trim();
          final grouped = <int, List<Map<String, dynamic>>>{};
          for (final exercise in exercises) {
            final exerciseDays = (exercise['days'] as List?)?.whereType<int>();
            final targetDays = (exerciseDays != null && exerciseDays.isNotEmpty)
                ? exerciseDays.toList()
                : defaultDays;
            for (final day in targetDays) {
              grouped.putIfAbsent(day, () => []).add({
                ...exercise,
                'days': null,
              });
            }
          }

          return grouped.entries.map((group) {
            final dayName = _getWeekdayName(group.key);
            final sourceName = name?.isNotEmpty == true
                ? name!
                : fallbackDay?.isNotEmpty == true
                ? fallbackDay!
                : dayName;
            return {
              'name': _formatImportedWorkoutTitle(
                sourceName,
                day: group.key,
                ordinal: entry.key + 1,
              ),
              'day_of_week': group.key,
              'exercises': group.value.asMap().entries.map((exerciseEntry) {
                return {
                  ...exerciseEntry.value,
                  'exercise_order': exerciseEntry.key,
                };
              }).toList(),
            };
          });
        })
        .where((workout) => (workout['exercises'] as List).isNotEmpty)
        .toList();

    return _mergeImportedWorkoutsByDay(collected);
  }

  List<Map<String, dynamic>> _mergeImportedWorkoutsByDay(
    List<Map<String, dynamic>> imported,
  ) {
    final grouped = <int, Map<String, dynamic>>{};
    final ordinalByDay = <int, int>{};
    for (final workout in imported) {
      final day = int.tryParse(workout['day_of_week']?.toString() ?? '') ?? 1;
      final current = grouped.putIfAbsent(day, () {
        ordinalByDay[day] = ordinalByDay.length + 1;
        return {
          'name': _formatImportedWorkoutTitle(
            workout['name'],
            day: day,
            ordinal: ordinalByDay[day] ?? ordinalByDay.length,
          ),
          'day_of_week': day,
          'exercises': <Map<String, dynamic>>[],
        };
      });
      final incomingName = _formatImportedWorkoutTitle(
        workout['name'],
        day: day,
        ordinal: ordinalByDay[day] ?? ordinalByDay.length,
      );
      if (_isGenericWorkoutTitle(current['name']) &&
          !_isGenericWorkoutTitle(incomingName)) {
        current['name'] = incomingName;
      }
      final currentExercises = (current['exercises'] as List)
          .whereType<Map>()
          .map((exercise) => Map<String, dynamic>.from(exercise))
          .toList();
      final seenExerciseKeys = currentExercises
          .map(_importedExerciseSignature)
          .toSet();
      for (final exercise in (workout['exercises'] as List).whereType<Map>()) {
        final cleanExercise = Map<String, dynamic>.from(exercise);
        final signature = _importedExerciseSignature(cleanExercise);
        if (seenExerciseKeys.add(signature)) {
          currentExercises.add(cleanExercise);
        }
      }
      current['exercises'] = currentExercises.asMap().entries.map((entry) {
        return {...entry.value, 'exercise_order': entry.key};
      }).toList();
    }

    return grouped.entries.map((entry) {
      final ordinal = ordinalByDay[entry.key] ?? entry.key;
      return {
        ...entry.value,
        'name': _formatImportedWorkoutTitle(
          entry.value['name'],
          day: entry.key,
          ordinal: ordinal,
        ),
      };
    }).toList()..sort((a, b) {
      return parseWholeNumber(
        a['day_of_week'],
      ).compareTo(parseWholeNumber(b['day_of_week']));
    });
  }

  String _importedExerciseSignature(Map<dynamic, dynamic> exercise) {
    return [
      exercise['name'],
      exercise['sets'],
      exercise['reps'],
      exercise['rest_seconds'],
      exercise['notes'],
    ].map((value) => value?.toString().trim().toLowerCase() ?? '').join('|');
  }

  String _formatImportedWorkoutTitle(
    dynamic value, {
    required int day,
    required int ordinal,
  }) {
    final raw = value?.toString().trim() ?? '';
    var title = raw
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(
          RegExp(r'^\s*rutina\s+\d+\s*:\s*', caseSensitive: false),
          '',
        )
        .replaceAll(RegExp(r'^\s*rutina\s+', caseSensitive: false), '')
        .trim();

    title = title
        .replaceFirst(
          RegExp(r'^(dia|día|day)\s*\d+\s*[-:.)]?\s*', caseSensitive: false),
          '',
        )
        .replaceFirst(
          RegExp(
            r'^(lunes|martes|miércoles|miercoles|jueves|viernes|sábado|sabado|domingo)\s*[-:.)]?\s*',
            caseSensitive: false,
          ),
          '',
        )
        .replaceFirst(
          RegExp(
            r'\s*-\s*(lunes|martes|miércoles|miercoles|jueves|viernes|sábado|sabado|domingo)$',
            caseSensitive: false,
          ),
          '',
        )
        .trim();

    title = title.replaceAll(RegExp(r'\s*\([^)]*\)\s*$'), '').trim();
    if (title.isEmpty || _isGenericWorkoutTitle(title)) {
      title = _getWeekdayName(day);
    }

    return 'Rutina $ordinal: ${_toDisplayTitle(title)}';
  }

  bool _isGenericWorkoutTitle(dynamic value) {
    final text = value?.toString().trim().toLowerCase() ?? '';
    if (text.isEmpty) return true;
    return RegExp(
      r'^(rutina\s*)?(lunes|martes|miércoles|miercoles|jueves|viernes|sábado|sabado|domingo)$',
    ).hasMatch(text);
  }

  String _toDisplayTitle(String value) {
    final acronyms = {'a', 'b', 'c', 'd'};
    return value
        .split(' ')
        .where((part) => part.trim().isNotEmpty)
        .map((part) {
          final clean = part.trim();
          if (clean.length <= 3 && clean == clean.toUpperCase()) {
            return clean;
          }
          final lower = clean.toLowerCase();
          if (acronyms.contains(lower)) return lower.toUpperCase();
          return lower[0].toUpperCase() + lower.substring(1);
        })
        .join(' ');
  }

  List<int> _extractWorkoutDays(dynamic value) {
    if (value == null) return [];
    if (value is num) {
      final day = value.round();
      return day >= 1 && day <= 7 ? [day] : [];
    }
    if (value is List) {
      return value.expand(_extractWorkoutDays).toSet().toList()..sort();
    }

    var text = value.toString().toLowerCase();
    text = text
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u');

    final days = <int>{};
    if (RegExp(r'\bl\s*[/,;.-]\s*m\s*[/,;.-]\s*v\b').hasMatch(text) ||
        RegExp(r'\blmv\b').hasMatch(text)) {
      days.addAll([1, 3, 5]);
    }

    final dayPatterns = <int, List<String>>{
      1: ['lunes', 'lun', ' l '],
      2: ['martes', 'mar', ' ma ', 'ma/'],
      3: ['miercoles', 'mier', 'mie', ' mi ', ' m ', ' x '],
      4: ['jueves', 'jue', ' ju ', ' j '],
      5: ['viernes', 'vie', ' vi ', ' v '],
      6: ['sabado', 'sab', ' s '],
      7: ['domingo', 'dom', ' d '],
    };

    final padded = ' ${text.replaceAll(RegExp(r'[^a-z0-9]+'), ' ')} ';
    for (final entry in dayPatterns.entries) {
      for (final token in entry.value) {
        if (padded.contains(token.trim().length <= 2 ? token : ' $token ')) {
          days.add(entry.key);
          break;
        }
      }
    }

    final explicitNumbers = RegExp(r'\b([1-7])\b').allMatches(text);
    for (final match in explicitNumbers) {
      days.add(int.parse(match.group(1)!));
    }

    return days.toList()..sort();
  }

  Future<List<Map<String, dynamic>>> _saveImportedWorkouts(
    List<Map<String, dynamic>> importedWorkouts,
  ) async {
    final savedWorkouts = <Map<String, dynamic>>[];
    final supabase = Supabase.instance.client;

    for (final importedWorkout in importedWorkouts) {
      final workoutResponse = await supabase
          .from('workouts')
          .insert({
            'name': importedWorkout['name'],
            'day_of_week': importedWorkout['day_of_week'],
            'user_id': widget.currentUser.id,
          })
          .select()
          .single();

      final workoutId = workoutResponse['id'];
      final rawExercises = (importedWorkout['exercises'] as List)
          .whereType<Map>()
          .toList();
      final exercisesToInsert = rawExercises.asMap().entries.map((entry) {
        final exercise = entry.value;
        return {
          'workout_id': workoutId,
          'name': exercise['name'],
          'sets': exercise['sets'],
          'reps': exercise['reps'],
          'rest_seconds': exercise['rest_seconds'],
          'notes': exercise['notes'],
          'exercise_order':
              int.tryParse(exercise['exercise_order']?.toString() ?? '') ??
              entry.key,
        };
      }).toList();

      List<Map<String, dynamic>> savedExercises = [];
      if (exercisesToInsert.isNotEmpty) {
        final exerciseResponse = await supabase
            .from('exercises')
            .insert(exercisesToInsert)
            .select();
        savedExercises = (exerciseResponse as List)
            .whereType<Map>()
            .map((exercise) => Map<String, dynamic>.from(exercise))
            .toList();
        savedExercises.sort((a, b) {
          final orderA = parseWholeNumber(a['exercise_order']);
          final orderB = parseWholeNumber(b['exercise_order']);
          return orderA.compareTo(orderB);
        });

        for (
          var i = 0;
          i < savedExercises.length && i < rawExercises.length;
          i++
        ) {
          savedExercises[i]['load'] = rawExercises[i]['load'];
          savedExercises[i]['max_weight'] =
              rawExercises[i]['max_weight'] ?? rawExercises[i]['load'];
        }
      }

      savedWorkouts.add({
        ...Map<String, dynamic>.from(workoutResponse),
        'exercises': savedExercises,
      });
    }

    return savedWorkouts;
  }

  Future<List<Map<String, dynamic>>> _saveImportedWorkoutsLocally(
    List<Map<String, dynamic>> importedWorkouts,
  ) async {
    final savedWorkouts = <Map<String, dynamic>>[];

    for (final importedWorkout in importedWorkouts) {
      final workoutId = await LocalUserDataStore.nextWorkoutId(
        widget.currentUser.email,
      );
      final rawExercises = (importedWorkout['exercises'] as List)
          .whereType<Map>()
          .toList();
      final savedExercises = <Map<String, dynamic>>[];

      for (final entry in rawExercises.asMap().entries) {
        final exercise = entry.value;
        savedExercises.add({
          ...Map<String, dynamic>.from(exercise),
          'id': await LocalUserDataStore.nextExerciseId(
            widget.currentUser.email,
          ),
          'workout_id': workoutId,
          'exercise_order':
              int.tryParse(exercise['exercise_order']?.toString() ?? '') ??
              entry.key,
        });
      }

      savedWorkouts.add({
        'id': workoutId,
        'name': importedWorkout['name'],
        'day_of_week': importedWorkout['day_of_week'] ?? 1,
        'user_id': widget.currentUser.id,
        'exercises': savedExercises,
      });
    }

    return savedWorkouts;
  }

  Future<void> exportWorkoutsToExcel({
    List<Map<String, dynamic>>? sourceWorkouts,
    String filePrefix = 'rutinas_healthy_t',
  }) async {
    try {
      final workoutsToExport = sourceWorkouts ?? workouts;
      if (workoutsToExport.isEmpty) {
        _showErrorSnackBar('No hay rutinas para exportar');
        return;
      }

      final excel = xlsx.Excel.createExcel();
      const sheetName = 'Rutinas';
      final sheet = excel[sheetName];
      final defaultSheet = excel.getDefaultSheet();
      if (defaultSheet != null && defaultSheet != sheetName) {
        excel.delete(defaultSheet);
      }

      sheet.appendRow([
        xlsx.TextCellValue('DÍA'),
        xlsx.TextCellValue('EJERCICIO'),
        xlsx.TextCellValue('SERIES'),
        xlsx.TextCellValue('TIEMPO DE DESCANSO'),
        xlsx.TextCellValue('REPS'),
        xlsx.TextCellValue('CARGA'),
        xlsx.TextCellValue('NOTAS'),
      ]);

      for (final workout in _sortByDay([...workoutsToExport])) {
        final dayName = workout['name']?.toString() ?? 'Rutina';
        final exercises =
            (workout['exercises'] as List?)?.whereType<Map>() ??
            const <Map<dynamic, dynamic>>[];
        for (final exercise in exercises) {
          final notes = exercise['notes']?.toString() ?? '';
          final load = exerciseMaxWeightText(exercise);
          sheet.appendRow([
            xlsx.TextCellValue(dayName),
            xlsx.TextCellValue(exercise['name']?.toString() ?? ''),
            xlsx.TextCellValue(exercise['sets']?.toString() ?? ''),
            xlsx.TextCellValue(
              _formatRestForExcel(exercise['rest_seconds'] ?? exercise['rest']),
            ),
            xlsx.TextCellValue(exercise['reps']?.toString() ?? ''),
            xlsx.TextCellValue(load),
            xlsx.TextCellValue(notesWithoutExerciseWeight(notes)),
          ]);
        }
      }

      final bytes = excel.encode();
      if (bytes == null) {
        throw Exception('No se pudo generar el archivo Excel');
      }

      final fileName = '${filePrefix}_${_todayIsoDate()}.xlsx';
      if (kIsWeb) {
        excel.save(fileName: fileName);
      } else if (Platform.isAndroid || Platform.isIOS) {
        await FilePicker.platform.saveFile(
          dialogTitle: 'Guardar rutina',
          fileName: fileName,
          type: FileType.custom,
          allowedExtensions: ['xlsx'],
          bytes: Uint8List.fromList(bytes),
        );
      } else {
        final path = await FilePicker.platform.saveFile(
          dialogTitle: 'Guardar rutina',
          fileName: fileName,
          type: FileType.custom,
          allowedExtensions: ['xlsx'],
        );
        if (path == null) {
          return;
        }
        await File(path).writeAsBytes(bytes, flush: true);
      }

      _showSuccessSnackBar('Rutinas exportadas en formato Excel');
    } catch (e) {
      _showErrorSnackBar('Error exportando rutinas: $e');
    }
  }

  Future<void> _exportSelectedAdminWorkoutToExcel() async {
    final selectedWorkout = workouts.cast<Map<String, dynamic>?>().firstWhere(
      (workout) =>
          workout?['id']?.toString() == _selectedAdminWorkoutId?.toString(),
      orElse: () => workouts.isNotEmpty ? workouts.first : null,
    );
    if (selectedWorkout == null) {
      _showErrorSnackBar('Selecciona una rutina para exportar');
      return;
    }
    await exportWorkoutsToExcel(
      sourceWorkouts: [Map<String, dynamic>.from(selectedWorkout)],
      filePrefix: 'rutina_${_safeFileName(selectedWorkout['name'])}',
    );
  }

  String _formatRestForExcel(dynamic value) {
    final seconds = _parseRestSecondsValue(value);
    if (seconds <= 0) {
      return '';
    }
    if (seconds % 60 == 0) {
      return '${seconds ~/ 60} MIN';
    }
    return '$seconds s';
  }

  Future<void> pickAndUploadDietFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        withData: true,
      );

      if (result == null) {
        return;
      }

      final file = result.files.single;
      final fileBytes =
          file.bytes ??
          (file.path != null ? await File(file.path!).readAsBytes() : null);
      if (fileBytes == null) {
        _showErrorSnackBar('No se pudo leer el PDF seleccionado');
        return;
      }

      final fileSizeMb = fileBytes.length / (1024 * 1024);
      if (fileSizeMb > 12) {
        _showErrorSnackBar(
          'El archivo pesa ${fileSizeMb.toStringAsFixed(1)} MB. Prueba con uno menor a 12 MB.',
        );
        return;
      }

      setState(() => isLoading = true);
      _showSuccessSnackBar('Analizando PDF y dividiendo comidas...');

      final importedDiets = await _convertDietPdfToExcelShape(
        fileBytes,
        file.name,
      ).timeout(const Duration(seconds: 75));
      if (importedDiets.isEmpty) {
        _showErrorSnackBar('No se encontraron comidas en el PDF');
        return;
      }

      List<Map<String, dynamic>> savedDiets;
      try {
        savedDiets = await _saveImportedDiets(importedDiets);
      } catch (e) {
        debugPrint('No se pudo guardar dieta en Supabase, fallback local: $e');
        savedDiets = await _saveImportedDietsLocally(importedDiets);
      }
      final updatedDiets = _normalizeDiets([...diets, ...savedDiets]);
      await LocalUserDataStore.saveDiets(
        widget.currentUser.email,
        updatedDiets,
      );
      if (mounted) {
        setState(() => diets = updatedDiets);
      }
      _showSuccessSnackBar(
        savedDiets.any((diet) => diet['local_only'] == true)
            ? 'Dieta importada offline con ${savedDiets.fold<int>(0, (sum, diet) => sum + ((diet['meals'] as List?)?.length ?? 0))} comidas'
            : 'Dieta importada con ${savedDiets.fold<int>(0, (sum, diet) => sum + ((diet['meals'] as List?)?.length ?? 0))} comidas',
      );
      await _showImportReviewNotice('dieta');
    } on TimeoutException {
      _showErrorSnackBar(
        'La subida tardó demasiado. Intenta con un archivo más pequeño o revisa tu conexión.',
      );
    } on SocketException {
      _showErrorSnackBar(
        'No se pudo conectar con el servidor. Revisa tu conexión a internet.',
      );
    } on http.ClientException catch (e) {
      _showErrorSnackBar('Error de conexión: ${e.message}');
    } on GeminiQuotaException catch (e) {
      _showErrorSnackBar(e.message);
    } catch (e) {
      _showErrorSnackBar('Error: $e');
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  Future<List<Map<String, dynamic>>> _convertDietPdfToExcelShape(
    Uint8List pdfBytes,
    String fileName,
  ) async {
    final text = await _generateGeminiPdfJson(
      pdfBytes: pdfBytes,
      prompt: _dietImportPrompt(fileName),
    );

    return _parseDietImportPayload(text);
  }

  String _dietImportPrompt(String fileName) {
    return '''
Convierte el PDF "$fileName" a la estructura exacta de esta plantilla de Excel:
Comida | Opción | Categoría | Alimento | Cantidad | Unidad | Notas

Devuelve únicamente JSON válido, sin markdown, con esta forma:
{
  "diets": [
    {
      "name": "Plan de alimentación",
      "day_of_week": 1,
      "meals": [
        {
          "name": "COMIDA 1",
          "rows": [
            {
              "comida": "COMIDA 1",
              "opcion": "OPCION A (HUEVOS CON JAMON)",
              "categoria": "Proteína",
              "alimento": "Huevo entero",
              "cantidad": "1",
              "unidad": "pza",
              "notas": "50g"
            }
          ]
        }
      ]
    }
  ]
}

Reglas:
- Divide por comidas: COMIDA 1, PRE WORKOUT, COMIDA 2, OPCION COMODIN, POST WORKOUT, COMIDA 3, SUPLEMENTACION, etc.
- Dentro de cada comida conserva todas las opciones detectadas: OPCION A, OPCION B, OPCION C, Intercambiable, Proteína, Hidratos, Lípidos.
- Para cada comida principal incluye siempre OPCION A, OPCION B y OPCION C. Si el PDF no muestra alguna opción, devuélvela vacía con alimento "" para que la app pueda mostrar el bloque.
- Si una comida trae OPCION A, OPCION B y OPCION C, cada alimento debe quedar bajo su opción correspondiente. No mezcles alimentos de distintas opciones en la misma opción.
- Si el PDF tiene nombres de preparación después de la opción, inclúyelos en la columna Opción, por ejemplo "OPCION A (HUEVOS CON JAMON)", "OPCION B (QUESADILLAS)", "OPCION C (BATIDO)".
- Cada alimento debe ser una fila individual con Comida, Opción, Categoría, Alimento, Cantidad, Unidad, Notas.
- Si una línea dice "o" o "/" entre alimentos equivalentes, sepáralos en filas distintas y usa una categoría con "(Elegir 1)" cuando aplique.
- No resumas ingredientes. Extrae cantidades y unidades aunque vengan pegadas como "100GR", "1/2 toma", "2 pzas".
- No incluyas instrucciones generales, lista de condimentos libres, agua, escala de hidratación o texto motivacional salvo que pertenezca a una comida/suplementación concreta.
- Si un dato no aparece, usa "".
''';
  }

  List<Map<String, dynamic>> _parseDietImportPayload(String rawText) {
    final cleanText = rawText
        .replaceAll('```json', '')
        .replaceAll('```', '')
        .trim();
    final decoded = jsonDecode(cleanText);
    final rawDietsValue = decoded is Map
        ? decoded['diets'] ?? decoded['diet']
        : decoded is List
        ? decoded
        : null;
    final rawDiets = rawDietsValue is List
        ? rawDietsValue
        : rawDietsValue is Map
        ? [rawDietsValue]
        : null;
    if (rawDiets is! List) {
      return [];
    }

    return rawDiets
        .whereType<Map>()
        .map((diet) {
          final rawMeals = diet['meals'] is List
              ? diet['meals'] as List
              : _groupDietRowsIntoMeals(diet['rows']);
          final meals = rawMeals
              .whereType<Map>()
              .map((meal) {
                final rows = meal['rows'] ?? meal['items'] ?? meal['foods'];
                final itemRows = rows is List
                    ? rows
                          .whereType<Map>()
                          .map(
                            (row) => {
                              'comida': _cleanDietText(
                                row['comida'] ?? meal['name'],
                              ),
                              'opcion': _cleanDietText(
                                row['opcion'] ?? row['option'],
                              ),
                              'categoria': _cleanDietText(
                                row['categoria'] ?? row['category'],
                              ),
                              'alimento': _cleanDietText(
                                row['alimento'] ?? row['food'] ?? row['name'],
                              ),
                              'cantidad': _cleanDietText(
                                row['cantidad'] ?? row['quantity'],
                              ),
                              'unidad': _cleanDietText(
                                row['unidad'] ?? row['unit'],
                              ),
                              'notas': _cleanDietText(
                                row['notas'] ?? row['notes'],
                              ),
                            },
                          )
                          .where(
                            (row) =>
                                row['alimento']!.isNotEmpty ||
                                row['categoria']!.isNotEmpty,
                          )
                          .toList()
                    : <Map<String, String>>[];

                final normalizedRows = _ensureImportedDietABCOptions(itemRows);

                final mealName = _cleanDietText(meal['name']).isNotEmpty
                    ? _cleanDietText(meal['name'])
                    : normalizedRows.isNotEmpty
                    ? normalizedRows.first['comida']!
                    : 'Comida';

                return {
                  'name': mealName,
                  'calories': _parseNumericDietValue(meal['calories']),
                  'protein': _parseNumericDietValue(meal['protein']),
                  'carbs': _parseNumericDietValue(meal['carbs']),
                  'fats': _parseNumericDietValue(meal['fats']),
                  'notes': _formatDietRowsAsNotes(normalizedRows),
                };
              })
              .where((meal) {
                final name = meal['name']?.toString().trim() ?? '';
                final notes = meal['notes']?.toString().trim() ?? '';
                return name.isNotEmpty && notes.isNotEmpty;
              })
              .toList();
          final orderedMeals = _sortDietMealsByDisplayOrder(meals);

          return {
            'name': _cleanDietText(diet['name']).isNotEmpty
                ? _cleanDietText(diet['name'])
                : 'Dieta importada',
            'day_of_week':
                int.tryParse(diet['day_of_week']?.toString() ?? '') ?? 1,
            'meals': orderedMeals,
          };
        })
        .where((diet) => (diet['meals'] as List).isNotEmpty)
        .toList();
  }

  List<Map<String, dynamic>> _groupDietRowsIntoMeals(dynamic rowsValue) {
    if (rowsValue is! List) {
      return [];
    }

    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final row in rowsValue.whereType<Map>()) {
      final mealName = _cleanDietText(row['comida'] ?? row['meal']);
      final key = mealName.isNotEmpty ? mealName : 'Comida';
      grouped.putIfAbsent(key, () => []).add(Map<String, dynamic>.from(row));
    }

    return grouped.entries
        .map((entry) => {'name': entry.key, 'rows': entry.value})
        .toList();
  }

  String _cleanDietText(dynamic value) {
    return value
            ?.toString()
            .replaceAll(RegExp(r'\s+'), ' ')
            .replaceAll(' :', ':')
            .trim() ??
        '';
  }

  int _parseNumericDietValue(dynamic value) {
    return parseWholeNumber(value);
  }

  List<Map<String, String>> _ensureImportedDietABCOptions(
    List<Map<String, String>> rows,
  ) {
    final optionTitles = <String, String>{};
    final existingOptions = <String>{};
    final mealName = rows.isNotEmpty ? rows.first['comida'] ?? '' : 'Comida';

    for (final row in rows) {
      final option = row['opcion'] ?? '';
      final canonical = _canonicalDietOptionKey(option);
      if (canonical.isEmpty) {
        continue;
      }
      existingOptions.add(canonical);
      optionTitles.putIfAbsent(canonical, () => option);
    }

    final normalizedRows = rows.map((row) {
      final canonical = _canonicalDietOptionKey(row['opcion'] ?? '');
      if (!{'OPCION A', 'OPCION B', 'OPCION C'}.contains(canonical)) {
        return row;
      }
      return {
        ...row,
        'opcion': row['opcion']?.trim().isNotEmpty == true
            ? row['opcion']!
            : canonical,
      };
    }).toList();

    for (final option in const ['OPCION A', 'OPCION B', 'OPCION C']) {
      if (existingOptions.contains(option)) {
        continue;
      }
      normalizedRows.add({
        'comida': mealName,
        'opcion': optionTitles[option] ?? option,
        'categoria': 'Pendiente',
        'alimento': 'No especificado en el PDF',
        'cantidad': '',
        'unidad': '',
        'notas': 'Completa esta opción si aplica.',
      });
    }

    normalizedRows.sort((a, b) {
      final aRank = _dietOptionRank(a['opcion'] ?? '');
      final bRank = _dietOptionRank(b['opcion'] ?? '');
      if (aRank != bRank) {
        return aRank.compareTo(bRank);
      }
      return 0;
    });

    return normalizedRows;
  }

  String _canonicalDietOptionKey(String option) {
    final normalized = option
        .toUpperCase()
        .replaceAll('Ó', 'O')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final match = RegExp(r'OPCION\s+([ABC])').firstMatch(normalized);
    return match == null ? '' : 'OPCION ${match.group(1)}';
  }

  int _dietOptionRank(String option) {
    switch (_canonicalDietOptionKey(option)) {
      case 'OPCION A':
        return 0;
      case 'OPCION B':
        return 1;
      case 'OPCION C':
        return 2;
      default:
        return 10;
    }
  }

  String _formatDietRowsAsNotes(List<Map<String, String>> rows) {
    final buffer = StringBuffer();
    String? currentOption;

    for (final row in rows) {
      final option = row['opcion'] ?? '';
      if (option.isNotEmpty && option != currentOption) {
        if (buffer.isNotEmpty) {
          buffer.writeln();
        }
        buffer.writeln('[$option]');
        currentOption = option;
      }
      buffer.writeln('• Categoría: ${row['categoria'] ?? ''}');
      buffer.writeln('  Alimento: ${row['alimento'] ?? ''}');
      buffer.writeln('  Cantidad: ${row['cantidad'] ?? ''}');
      buffer.writeln('  Unidad: ${row['unidad'] ?? ''}');
      buffer.writeln('  Notas: ${row['notas'] ?? ''}');
    }

    return buffer.toString().trim();
  }

  Future<List<Map<String, dynamic>>> _saveImportedDiets(
    List<Map<String, dynamic>> importedDiets,
  ) async {
    final savedDiets = <Map<String, dynamic>>[];
    final supabase = Supabase.instance.client;

    for (final importedDiet in importedDiets) {
      final dietResponse = await supabase
          .from('diets')
          .insert({
            'name': importedDiet['name'],
            'day_of_week': importedDiet['day_of_week'],
            'user_id': widget.currentUser.id,
          })
          .select()
          .single();

      final dietId = dietResponse['id'];
      final rawMeals = (importedDiet['meals'] as List)
          .whereType<Map>()
          .toList();
      final mealsToInsert = rawMeals.map((meal) {
        return {
          'diet_id': dietId,
          'name': meal['name'],
          'calories': parseWholeNumber(meal['calories']),
          'protein': parseWholeNumber(meal['protein']),
          'carbs': parseWholeNumber(meal['carbs']),
          'fats': parseWholeNumber(meal['fats']),
          'notes': meal['notes'] ?? '',
        };
      }).toList();

      List<Map<String, dynamic>> savedMeals = [];
      if (mealsToInsert.isNotEmpty) {
        final mealResponse = await supabase
            .from('meals')
            .insert(mealsToInsert)
            .select();
        savedMeals = (mealResponse as List)
            .whereType<Map>()
            .map((meal) => Map<String, dynamic>.from(meal))
            .toList();
      }

      savedDiets.add({
        ...Map<String, dynamic>.from(dietResponse),
        'meals': savedMeals,
      });
    }

    return savedDiets;
  }

  Future<List<Map<String, dynamic>>> _saveImportedDietsLocally(
    List<Map<String, dynamic>> importedDiets,
  ) async {
    final savedDiets = <Map<String, dynamic>>[];
    final now = DateTime.now().millisecondsSinceEpoch;

    for (var dietIndex = 0; dietIndex < importedDiets.length; dietIndex++) {
      final importedDiet = importedDiets[dietIndex];
      final dietId = 'local_diet_${now}_$dietIndex';
      final rawMeals =
          (importedDiet['meals'] as List?)?.whereType<Map>().toList() ??
          <Map>[];

      final savedMeals = rawMeals.asMap().entries.map((entry) {
        final meal = Map<String, dynamic>.from(entry.value);
        return {
          ...meal,
          'id': 'local_meal_${now}_${dietIndex}_${entry.key}',
          'diet_id': dietId,
          'calories': parseWholeNumber(meal['calories']),
          'protein': parseWholeNumber(meal['protein']),
          'carbs': parseWholeNumber(meal['carbs']),
          'fats': parseWholeNumber(meal['fats']),
          'order_index': entry.key,
          'local_only': true,
        };
      }).toList();

      savedDiets.add({
        ...Map<String, dynamic>.from(importedDiet),
        'id': dietId,
        'user_id': widget.currentUser.id,
        'meals': savedMeals,
        'local_only': true,
      });
    }

    return savedDiets;
  }

  Future<void> exportDietsToExcel({
    List<Map<String, dynamic>>? sourceDiets,
    String filePrefix = 'dieta_healthy_t',
  }) async {
    try {
      final dietsToExport = sourceDiets ?? diets;
      if (dietsToExport.isEmpty) {
        _showErrorSnackBar('No hay dietas para exportar');
        return;
      }

      final excel = xlsx.Excel.createExcel();
      const sheetName = 'Dieta';
      final sheet = excel[sheetName];
      final defaultSheet = excel.getDefaultSheet();
      if (defaultSheet != null && defaultSheet != sheetName) {
        excel.delete(defaultSheet);
      }

      sheet.appendRow([
        xlsx.TextCellValue('Comida'),
        xlsx.TextCellValue('Opción'),
        xlsx.TextCellValue('Categoría'),
        xlsx.TextCellValue('Alimento'),
        xlsx.TextCellValue('Cantidad'),
        xlsx.TextCellValue('Unidad'),
        xlsx.TextCellValue('Notas'),
      ]);

      for (final diet in _sortByDay([...dietsToExport])) {
        final meals =
            (diet['meals'] as List?)?.whereType<Map>() ??
            const <Map<dynamic, dynamic>>[];
        for (final meal in meals) {
          final mealName = meal['name']?.toString() ?? 'Comida';
          final rows = _dietNotesToExcelRows(
            mealName,
            meal['notes']?.toString() ?? '',
          );
          if (rows.isEmpty) {
            sheet.appendRow([
              xlsx.TextCellValue(mealName),
              xlsx.TextCellValue(''),
              xlsx.TextCellValue(''),
              xlsx.TextCellValue(''),
              xlsx.TextCellValue(''),
              xlsx.TextCellValue(''),
              xlsx.TextCellValue(''),
            ]);
            continue;
          }

          for (final row in rows) {
            sheet.appendRow([
              xlsx.TextCellValue(row['comida'] ?? mealName),
              xlsx.TextCellValue(row['opcion'] ?? ''),
              xlsx.TextCellValue(row['categoria'] ?? ''),
              xlsx.TextCellValue(row['alimento'] ?? ''),
              xlsx.TextCellValue(row['cantidad'] ?? ''),
              xlsx.TextCellValue(row['unidad'] ?? ''),
              xlsx.TextCellValue(row['notas'] ?? ''),
            ]);
          }
        }
      }

      final bytes = excel.encode();
      if (bytes == null) {
        throw Exception('No se pudo generar el archivo Excel');
      }

      final fileName = '${filePrefix}_${_todayIsoDate()}.xlsx';
      if (kIsWeb) {
        excel.save(fileName: fileName);
      } else if (Platform.isAndroid || Platform.isIOS) {
        await FilePicker.platform.saveFile(
          dialogTitle: 'Guardar dieta',
          fileName: fileName,
          type: FileType.custom,
          allowedExtensions: ['xlsx'],
          bytes: Uint8List.fromList(bytes),
        );
      } else {
        final path = await FilePicker.platform.saveFile(
          dialogTitle: 'Guardar dieta',
          fileName: fileName,
          type: FileType.custom,
          allowedExtensions: ['xlsx'],
        );
        if (path == null) {
          return;
        }
        await File(path).writeAsBytes(bytes, flush: true);
      }

      _showSuccessSnackBar('Dieta exportada en formato Excel');
    } catch (e) {
      _showErrorSnackBar('Error exportando dieta: $e');
    }
  }

  Future<void> _exportSelectedAdminDietToExcel() async {
    final selectedDiet = diets.cast<Map<String, dynamic>?>().firstWhere(
      (diet) => diet?['id']?.toString() == _selectedAdminDietId?.toString(),
      orElse: () => diets.isNotEmpty ? diets.first : null,
    );
    if (selectedDiet == null) {
      _showErrorSnackBar('Selecciona una dieta para exportar');
      return;
    }
    await exportDietsToExcel(
      sourceDiets: [Map<String, dynamic>.from(selectedDiet)],
      filePrefix: 'dieta_${_safeFileName(selectedDiet['name'])}',
    );
  }

  List<Map<String, String>> _dietNotesToExcelRows(
    String mealName,
    String notes,
  ) {
    final rows = <Map<String, String>>[];
    var currentOption = '';
    Map<String, String>? currentRow;

    void flushRow() {
      if (currentRow == null) {
        return;
      }
      final row = currentRow!;
      if ((row['categoria'] ?? '').isNotEmpty ||
          (row['alimento'] ?? '').isNotEmpty ||
          (row['cantidad'] ?? '').isNotEmpty) {
        rows.add(row);
      }
      currentRow = null;
    }

    for (final rawLine in notes.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) {
        continue;
      }

      final optionMatch = RegExp(r'^\[(.+)\]$').firstMatch(line);
      if (optionMatch != null) {
        flushRow();
        currentOption = optionMatch.group(1)?.trim() ?? '';
        continue;
      }

      if (line.startsWith('• Categoría:')) {
        flushRow();
        currentRow = {
          'comida': mealName,
          'opcion': currentOption,
          'categoria': line.replaceFirst('• Categoría:', '').trim(),
          'alimento': '',
          'cantidad': '',
          'unidad': '',
          'notas': '',
        };
        continue;
      }

      currentRow ??= {
        'comida': mealName,
        'opcion': currentOption,
        'categoria': '',
        'alimento': '',
        'cantidad': '',
        'unidad': '',
        'notas': '',
      };

      if (line.startsWith('Alimento:')) {
        currentRow!['alimento'] = line.replaceFirst('Alimento:', '').trim();
      } else if (line.startsWith('Cantidad:')) {
        currentRow!['cantidad'] = line.replaceFirst('Cantidad:', '').trim();
      } else if (line.startsWith('Unidad:')) {
        currentRow!['unidad'] = line.replaceFirst('Unidad:', '').trim();
      } else if (line.startsWith('Notas:')) {
        currentRow!['notas'] = line.replaceFirst('Notas:', '').trim();
      } else {
        final previous = currentRow!['notas'] ?? '';
        currentRow!['notas'] = previous.isEmpty ? line : '$previous $line';
      }
    }
    flushRow();

    if (rows.isEmpty && notes.trim().isNotEmpty) {
      return [
        {
          'comida': mealName,
          'opcion': '',
          'categoria': '',
          'alimento': notes.trim(),
          'cantidad': '',
          'unidad': '',
          'notas': '',
        },
      ];
    }

    return rows;
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
        // Enviar actualización de día al backend
        try {
          await Supabase.instance.client
              .from('workouts')
              .update({'day_of_week': selectedDay})
              .eq('id', workoutId);
        } catch (e) {
          debugPrint('Error actualizando día de rutina: $e');
        }

        final updatedWorkouts = workouts.map((workout) {
          if (workout['id'] != workoutId) {
            return workout;
          }
          return {
            ...Map<String, dynamic>.from(workout),
            'day_of_week': selectedDay,
          };
        }).toList();
        await _persistWorkouts(updatedWorkouts);
      }
    }
  }

  Future<void> _deleteWorkout(
    dynamic workoutId, {
    VoidCallback? onDeleted,
  }) async {
    final workoutIdValue = workoutId?.toString();
    if (workoutIdValue == null || workoutIdValue.isEmpty) {
      _showErrorSnackBar('No se pudo identificar la rutina a eliminar');
      return;
    }

    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar Rutina'),
        content: const Text(
          '¿Estás seguro de que deseas eliminar este día de entrenamiento? Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final removedWorkout = workouts.cast<Map<String, dynamic>?>().firstWhere(
        (workout) => workout?['id']?.toString() == workoutIdValue,
        orElse: () => null,
      );
      final updatedWorkouts = workouts
          .where((workout) => workout['id']?.toString() != workoutIdValue)
          .toList();
      if (mounted) {
        setState(() {
          workouts = updatedWorkouts;
          _activeSessions.remove(workoutIdValue);
          _selectedAdminWorkoutId =
              _selectedAdminWorkoutId?.toString() == workoutIdValue
              ? null
              : _selectedAdminWorkoutId;
        });
      }
      onDeleted?.call();
      await LocalUserDataStore.saveWorkouts(
        widget.currentUser.email,
        updatedWorkouts,
      );
      _showSuccessSnackBar(
        '${removedWorkout?['name']?.toString() ?? 'Rutina'} eliminada',
      );

      try {
        await Supabase.instance.client
            .from('workouts')
            .delete()
            .eq('id', workoutIdValue);
      } catch (e) {
        debugPrint('Error eliminando rutina: $e');
      }
    }
  }

  Future<void> _deleteDiet(dynamic dietId, {VoidCallback? onDeleted}) async {
    final dietIdValue = dietId?.toString();
    if (dietIdValue == null || dietIdValue.isEmpty) {
      _showErrorSnackBar('No se pudo identificar la dieta a eliminar');
      return;
    }

    final removedDiet = diets.cast<Map<String, dynamic>?>().firstWhere(
      (diet) => diet?['id']?.toString() == dietIdValue,
      orElse: () => null,
    );
    final updatedDiets = diets
        .where((diet) => diet['id']?.toString() != dietIdValue)
        .toList();
    if (mounted) {
      setState(() {
        diets = updatedDiets;
        _selectedAdminDietId = _selectedAdminDietId?.toString() == dietIdValue
            ? null
            : _selectedAdminDietId;
      });
    }
    onDeleted?.call();
    await LocalUserDataStore.saveDiets(widget.currentUser.email, updatedDiets);
    _showSuccessSnackBar(
      '${removedDiet?['name']?.toString() ?? 'Dieta'} eliminada',
    );

    try {
      await Supabase.instance.client
          .from('diets')
          .delete()
          .eq('id', dietIdValue);
    } catch (e) {
      debugPrint('Error eliminando dieta: $e');
    }
  }

  Future<void> _deleteDailyMeal(
    dynamic mealId, {
    VoidCallback? onDeleted,
  }) async {
    final mealIdValue = mealId?.toString();
    if (mealIdValue == null || mealIdValue.isEmpty) {
      _showErrorSnackBar('No se pudo identificar la comida');
      return;
    }

    final removedMeal = _dailyMeals.cast<Map<String, dynamic>?>().firstWhere(
      (meal) => meal?['id']?.toString() == mealIdValue,
      orElse: () => null,
    );
    final updatedMeals = _dailyMeals
        .where((meal) => meal['id']?.toString() != mealIdValue)
        .toList();
    if (mounted) {
      setState(() => _dailyMeals = updatedMeals);
    }
    onDeleted?.call();
    await LocalUserDataStore.saveDailyMeals(
      widget.currentUser.email,
      _todayIsoDate(),
      updatedMeals,
    );
    _showSuccessSnackBar(
      '${removedMeal?['name']?.toString() ?? 'Comida'} eliminada',
    );

    try {
      await Supabase.instance.client
          .from('daily_diets')
          .delete()
          .eq('id', mealIdValue)
          .eq('user_id', widget.currentUser.id);
    } catch (e) {
      debugPrint('Error al eliminar comida diaria: $e');
    }
  }

  void _startOrResumeWorkout(Map<String, dynamic> workout) async {
    final workoutId = workout['id']?.toString() ?? '';
    final existingSession = _activeSessions[workoutId];

    // Preservamos el tiempo de inicio original, o capturamos el actual si es una rutina nueva
    final startTimeEpoch =
        existingSession?['startTime'] ?? DateTime.now().millisecondsSinceEpoch;
    final startTime = DateTime.fromMillisecondsSinceEpoch(startTimeEpoch);

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => WorkoutSessionScreen(
          workout: workout,
          // Pasamos el estado guardado si existe
          initialState: existingSession,
          onExercisePrRegistered: (exerciseIndex, updatedExercise) =>
              _saveExercisePrFromSession(
                workout,
                exerciseIndex,
                updatedExercise,
              ),
        ),
      ),
    );

    // Cuando la pantalla de sesión se cierra, devuelve su estado
    if (result is Map) {
      // Si la sesión terminó, borramos el estado guardado
      if (result.containsKey('finished')) {
        setState(() {
          _activeSessions.remove(workoutId);
        });

        if (_isHealthSyncEnabled) {
          HealthService().saveWorkoutToHealth(
            workout['name']?.toString() ?? 'Rutina Healthy-T',
            startTime,
            DateTime.now(),
          );
        }
        await _recordFinishedWorkoutInWeeklyLog(workout);
      } else {
        // Si no, guardamos el estado para poder resumirla
        setState(() {
          final savedState = Map<String, int>.from(result);
          savedState['startTime'] = startTimeEpoch;
          _activeSessions[workoutId] = savedState;
        });
      }
    }
  }

  Future<void> _saveExercisePrFromSession(
    Map<String, dynamic> workout,
    int exerciseIndex,
    Map<String, dynamic> updatedExercise,
  ) async {
    final workoutId = workout['id']?.toString() ?? '';
    if (workoutId.isEmpty) return;

    final updatedWorkouts = workouts.map((item) {
      if (item['id']?.toString() != workoutId) {
        return item;
      }

      final exercises =
          (item['exercises'] as List?)
              ?.whereType<Map>()
              .map((exercise) => Map<String, dynamic>.from(exercise))
              .toList() ??
          <Map<String, dynamic>>[];
      if (exerciseIndex < 0 || exerciseIndex >= exercises.length) {
        return item;
      }
      exercises[exerciseIndex] = {
        ...exercises[exerciseIndex],
        ...updatedExercise,
      };
      workout['exercises'] = exercises;
      return {...item, 'exercises': exercises};
    }).toList();

    setState(() => workouts = updatedWorkouts);
    await LocalUserDataStore.saveWorkouts(
      widget.currentUser.email,
      updatedWorkouts,
    );

    final exerciseId = updatedExercise['id'];
    if (exerciseId != null) {
      try {
        await Supabase.instance.client
            .from('exercises')
            .update({'notes': updatedExercise['notes']})
            .eq('id', exerciseId);
      } catch (e) {
        debugPrint('No se pudo guardar PR en Supabase: $e');
      }
    }
  }

  Future<void> _saveExercisePrFromRegistry(WeeklyWorkoutPrUpdate update) async {
    final workout = workouts.cast<Map<String, dynamic>?>().firstWhere(
      (item) => item?['id']?.toString() == update.workoutId,
      orElse: () => null,
    );
    if (workout == null) return;

    final exercises =
        (workout['exercises'] as List?)
            ?.whereType<Map>()
            .map((exercise) => Map<String, dynamic>.from(exercise))
            .toList() ??
        <Map<String, dynamic>>[];
    if (update.exerciseIndex < 0 || update.exerciseIndex >= exercises.length) {
      return;
    }

    final exercise = exercises[update.exerciseIndex];
    final updatedExercise = {
      ...exercise,
      'pr_weight': update.delete ? '' : update.weight,
      'pr_reps': update.delete ? '' : update.reps,
      'pr_date': update.delete ? '' : update.date,
      'pr_notes': update.delete ? '' : update.notes,
      'notes': notesWithExercisePr(
        exercise['notes']?.toString() ?? '',
        weight: update.delete ? '' : update.weight,
        reps: update.delete ? '' : update.reps,
        date: update.delete ? '' : update.date,
        prNotes: update.delete ? '' : update.notes,
      ),
    };

    await _saveExercisePrFromSession(
      workout,
      update.exerciseIndex,
      updatedExercise,
    );
  }

  Future<void> _recordFinishedWorkoutInWeeklyLog(
    Map<String, dynamic> workout,
  ) async {
    final workoutId = workout['id']?.toString() ?? '';
    if (workoutId.isEmpty) return;

    final currentLog =
        _weeklyWorkoutLog ??
        await WeeklyWorkoutRegistryStore.load(
          email: widget.currentUser.email,
          workouts: workouts,
        );
    final entry = currentLog.entries.cast<WeeklyWorkoutEntry?>().firstWhere(
      (item) => item?.workoutId == workoutId,
      orElse: () => null,
    );
    if (entry == null) return;

    final updatedEntry = entry.copyWith(
      completed: true,
      updatedAt: DateTime.now(),
    );
    final updatedEntries = currentLog.entries.map((item) {
      return item.workoutId == workoutId ? updatedEntry : item;
    }).toList();
    await _persistWeeklyWorkoutLog(
      currentLog.copyWith(entries: updatedEntries),
    );
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 8),
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

  Future<void> _sendFeedbackEmail() async {
    final message = _feedbackController.text.trim();
    if (message.isEmpty) {
      _showErrorSnackBar('Escribe tu comentario antes de enviarlo');
      return;
    }

    final subject = Uri.encodeComponent('Comentario Healthy-T');
    final body = Uri.encodeComponent(
      'Usuario: ${widget.currentUser.email}\n\nComentario:\n$message',
    );
    final emailUri = Uri.parse(
      'mailto:jjoshtorcast@icloud.com?subject=$subject&body=$body',
    );

    try {
      final opened = await launchUrl(
        emailUri,
        mode: LaunchMode.externalApplication,
      );
      if (!opened) {
        _showErrorSnackBar('No pude abrir una app de correo en este equipo');
        return;
      }
      _feedbackController.clear();
      _showSuccessSnackBar('Correo preparado para enviar');
    } catch (e) {
      _showErrorSnackBar('No pude abrir el correo: $e');
    }
  }

  Future<void> _showImportReviewNotice(String type) async {
    if (!mounted) return;
    final title = type == 'dieta' ? 'Revisa tu dieta' : 'Revisa tu rutina';
    final body = type == 'dieta'
        ? 'La dieta se importó automáticamente. Revísala con detenimiento para corregir cantidades, comidas o duplicados que puedan aparecer en algunos casos.'
        : 'La rutina se importó automáticamente. Revísala con detenimiento para corregir nombres, cargas o posibles ejercicios duplicados; en PDFs complejos puede haber duplicidad.';

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('ENTENDIDO'),
          ),
        ],
      ),
    );
  }

  Future<void> _logout() async {
    await LocalAuthStore.logout();
    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const AuthScreen()),
      (route) => false,
    );
  }

  Future<void> _deleteAccount() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Borrar cuenta'),
        content: const Text(
          'Se eliminarán tus rutinas, dietas y registros locales de Healthy-T. Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );
    if (confirm != true) {
      return;
    }

    setState(() => isLoading = true);
    final supabase = Supabase.instance.client;
    try {
      await supabase.rpc('delete_own_account');
      await LocalUserDataStore.clearUserData(widget.currentUser.email);
      await WeeklyWorkoutRegistryStore.clearForUser(widget.currentUser.email);
      await LocalAuthStore.logout();
      if (!mounted) {
        return;
      }
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const AuthScreen()),
        (route) => false,
      );
    } catch (e) {
      if (mounted) {
        setState(() => isLoading = false);
      }
      _showErrorSnackBar(
        'No se pudo borrar definitivamente la cuenta. Corre el SQL actualizado y vuelve a intentar: $e',
      );
    }
  }

  String _getWeekdayName(int? day) {
    switch (day) {
      case 1:
        return 'Lunes';
      case 2:
        return 'Martes';
      case 3:
        return 'Miércoles';
      case 4:
        return 'Jueves';
      case 5:
        return 'Viernes';
      case 6:
        return 'Sábado';
      case 7:
        return 'Domingo';
      default:
        return 'Día libre';
    }
  }

  List<Map<String, dynamic>> _getTodayWorkouts() {
    int today = DateTime.now().weekday;
    return workouts
        .where((w) => int.tryParse(w['day_of_week']?.toString() ?? '') == today)
        .toList();
  }

  List<Map<String, dynamic>> _getOtherWorkouts() {
    int today = DateTime.now().weekday;
    return workouts
        .where((w) => int.tryParse(w['day_of_week']?.toString() ?? '') != today)
        .toList();
  }

  Future<void> _createNewWorkout() async {
    Map<String, dynamic> newWorkout = {
      'id': 'local_workout_${DateTime.now().millisecondsSinceEpoch}',
      'name': 'Nueva Rutina Personalizada',
      'day_of_week': 1,
      'user_id': widget.currentUser.id,
      'exercises': <Map<String, dynamic>>[],
      'local_only': true,
    };

    try {
      final response = await Supabase.instance.client
          .from('workouts')
          .insert({
            'name': 'Nueva Rutina Personalizada',
            'day_of_week': 1,
            'user_id': widget.currentUser.id,
          })
          .select()
          .single();

      response['exercises'] = <Map<String, dynamic>>[];
      newWorkout = Map<String, dynamic>.from(response);
    } catch (e) {
      debugPrint('No se pudo crear rutina en Supabase, se guardará local: $e');
    }

    final updatedWorkouts = _normalizeWorkouts([...workouts, newWorkout]);
    await LocalUserDataStore.saveWorkouts(
      widget.currentUser.email,
      updatedWorkouts,
    );
    if (mounted) {
      setState(() => workouts = updatedWorkouts);
    }
    _showSuccessSnackBar(
      newWorkout['local_only'] == true
          ? 'Rutina creada offline'
          : 'Rutina creada exitosamente',
    );
  }

  Future<void> _createWorkoutWithAi() async {
    final goalC = TextEditingController();
    final daysC = TextEditingController(text: 'Lunes, miércoles y viernes');
    final levelC = TextEditingController(text: 'Intermedio');
    final equipmentC = TextEditingController(text: 'Gimnasio completo');
    final notesC = TextEditingController();

    final specs = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Crear rutina con IA'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: goalC,
                decoration: const InputDecoration(
                  labelText: 'Objetivo',
                  hintText: 'Ej. ganar músculo, bajar grasa, fuerza',
                ),
              ),
              TextField(
                controller: daysC,
                decoration: const InputDecoration(
                  labelText: 'Días',
                  hintText: 'Ej. lunes, miércoles y viernes',
                ),
              ),
              TextField(
                controller: levelC,
                decoration: const InputDecoration(labelText: 'Nivel'),
              ),
              TextField(
                controller: equipmentC,
                decoration: const InputDecoration(labelText: 'Equipo'),
              ),
              TextField(
                controller: notesC,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Especificaciones',
                  hintText:
                      'Lesiones, músculos prioritarios, duración, ejercicios que quieres o no quieres',
                ),
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
            onPressed: () => Navigator.pop(ctx, {
              'goal': goalC.text.trim(),
              'days': daysC.text.trim(),
              'level': levelC.text.trim(),
              'equipment': equipmentC.text.trim(),
              'notes': notesC.text.trim(),
            }),
            child: const Text('GENERAR'),
          ),
        ],
      ),
    );

    if (specs == null) return;

    try {
      setState(() => isLoading = true);
      _showSuccessSnackBar('Creando rutina con IA...');
      final response = await _generateGeminiTextJson(
        _workoutAiCreationPrompt(specs),
      );
      final importedWorkouts = _parseWorkoutImportPayload(response);
      if (importedWorkouts.isEmpty) {
        _showErrorSnackBar('La IA no devolvió una rutina válida');
        return;
      }

      List<Map<String, dynamic>> savedWorkouts;
      try {
        savedWorkouts = await _saveImportedWorkouts(importedWorkouts);
      } catch (e) {
        final canFallback =
            _isMissingPostgrestColumn(e, 'day_of_week') ||
            _isPostgrestRlsError(e);
        if (!canFallback) rethrow;
        savedWorkouts = await _saveImportedWorkoutsLocally(importedWorkouts);
      }

      final updatedWorkouts = _normalizeWorkouts([
        ...workouts,
        ...savedWorkouts,
      ]);
      await LocalUserDataStore.saveWorkouts(
        widget.currentUser.email,
        updatedWorkouts,
      );
      await fetchWorkouts();
      _showSuccessSnackBar(
        'Rutina creada con IA (${savedWorkouts.length} días)',
      );
    } on GeminiQuotaException catch (e) {
      _showErrorSnackBar(e.message);
    } catch (e) {
      _showErrorSnackBar('Error creando rutina con IA: $e');
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  String _workoutAiCreationPrompt(Map<String, String> specs) {
    return '''
Crea una rutina de entrenamiento personalizada con estas especificaciones:
- Objetivo: ${specs['goal']?.isEmpty == true ? 'salud, fuerza e hipertrofia general' : specs['goal']}
- Días disponibles: ${specs['days']?.isEmpty == true ? 'lunes, miércoles y viernes' : specs['days']}
- Nivel: ${specs['level']?.isEmpty == true ? 'intermedio' : specs['level']}
- Equipo: ${specs['equipment']?.isEmpty == true ? 'gimnasio completo' : specs['equipment']}
- Notas/restricciones: ${specs['notes']?.isEmpty == true ? 'sin restricciones' : specs['notes']}

Devuelve únicamente JSON válido, sin markdown, con esta forma:
{
  "workouts": [
    {
      "name": "Rutina Lunes - Tren superior",
      "day_of_week": 1,
      "rows": [
        {
          "dia": "lunes",
          "dias": ["lunes"],
          "ejercicio": "Press banca",
          "series": 4,
          "tiempo_de_descanso": "2 MIN",
          "reps": "6-8",
          "carga": "RPE 8",
          "notas": "Controla la bajada"
        }
      ]
    }
  ]
}

Reglas:
- Usa day_of_week real: lunes=1, martes=2, miércoles=3, jueves=4, viernes=5, sábado=6, domingo=7.
- Crea solo los días solicitados por el usuario.
- Si el usuario pide un ejercicio para varios días, duplícalo en cada día correspondiente.
- Incluye 4 a 8 ejercicios por día salvo que el usuario pida otra cosa.
- Usa descansos claros: 60 SEG, 90 SEG, 2 MIN o 3 MIN.
- No incluyas calentamiento general como ejercicio principal.
- Cada fila debe mapearse a DÍA, EJERCICIO, SERIES, TIEMPO DE DESCANSO, REPS, CARGA, NOTAS.
''';
  }

  Future<void> _createNewDiet() async {
    Map<String, dynamic> newDiet = {
      'id': 'local_diet_${DateTime.now().millisecondsSinceEpoch}',
      'name': 'Nueva Dieta',
      'day_of_week': 1,
      'user_id': widget.currentUser.id,
      'meals': <Map<String, dynamic>>[],
      'local_only': true,
    };

    try {
      final response = await Supabase.instance.client
          .from('diets')
          .insert({
            'name': 'Nueva Dieta',
            'day_of_week': 1,
            'user_id': widget.currentUser.id,
          })
          .select()
          .single();

      response['meals'] = <Map<String, dynamic>>[];
      newDiet = Map<String, dynamic>.from(response);
    } catch (e) {
      debugPrint('No se pudo crear dieta en Supabase, se guardará local: $e');
    }

    final updatedDiets = _normalizeDiets([...diets, newDiet]);
    await LocalUserDataStore.saveDiets(widget.currentUser.email, updatedDiets);
    if (mounted) {
      setState(() => diets = updatedDiets);
    }
    _showSuccessSnackBar(
      newDiet['local_only'] == true
          ? 'Dieta creada offline'
          : 'Dieta creada exitosamente',
    );
  }

  Future<void> _scanFoodWithAi({String? mealSlot}) async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(builder: (_) => const DietCameraScreen()),
    );

    if (result == null) {
      return;
    }

    final details = Map<String, dynamic>.from(result['details'] ?? result);
    final entry = result['entry'] is Map ? result['entry'] as Map : {};
    final date = _todayIsoDate();
    var mealLog = {
      'id': entry['id'] ?? DateTime.now().microsecondsSinceEpoch,
      'name': details['name'] ?? 'Comida registrada',
      'meal_slot': mealSlot,
      'calories': parseWholeNumber(details['calories']),
      'protein': parseWholeNumber(details['protein']),
      'carbs': parseWholeNumber(details['carbs']),
      'fats': parseWholeNumber(details['fats']),
      'estimated_grams': parseWholeNumber(details['estimated_grams']),
      'confidence': details['confidence'] ?? 0,
      'items': details['items'] is List ? details['items'] : [],
      'logged_at': DateTime.now().toIso8601String(),
    };

    final backendMeal = await _persistDailyMealToBackend(mealLog);
    if (backendMeal != null) {
      mealLog = {...mealLog, ...backendMeal};
    }

    final updatedMeals = [..._dailyMeals, mealLog];
    await LocalUserDataStore.saveDailyMeals(
      widget.currentUser.email,
      date,
      updatedMeals,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _dailyMeals = updatedMeals;
    });
    _showSuccessSnackBar('Comida registrada en el conteo diario');

    if (_isHealthSyncEnabled) {
      HealthService().saveMealToHealth(mealLog);
    }

    await fetchDailyNutrition();
  }

  Future<Map<String, dynamic>?> _persistDailyMealToBackend(
    Map<String, dynamic> meal,
  ) async {
    try {
      final response = await Supabase.instance.client
          .from('daily_diets')
          .insert({
            'user_id': widget.currentUser.id,
            'name': meal['name']?.toString() ?? 'Comida registrada',
            'meal_slot': meal['meal_slot']?.toString() ?? '',
            'consumed_at': _todayIsoDate(),
            'calories': parseWholeNumber(meal['calories']),
            'protein': parseWholeNumber(meal['protein']),
            'carbs': parseWholeNumber(meal['carbs']),
            'fats': parseWholeNumber(meal['fats']),
            'grams': parseWholeNumber(meal['estimated_grams'] ?? meal['grams']),
            'estimated_grams': parseWholeNumber(
              meal['estimated_grams'] ?? meal['grams'],
            ),
            'confidence':
                double.tryParse(meal['confidence']?.toString() ?? '0') ?? 0,
            'items': meal['items'] is List ? meal['items'] : [],
          })
          .select()
          .single();

      return Map<String, dynamic>.from(response);
    } catch (e) {
      debugPrint('Error guardando comida diaria en Supabase: $e');
      _showErrorSnackBar(
        'La comida se guardó localmente. Corre el SQL de daily_diets para sincronizarla.',
      );
      return null;
    }
  }

  Future<void> _addManualFoodLog(String mealSlot) async {
    final nameC = TextEditingController(text: mealSlot);
    final caloriesC = TextEditingController(text: '0');
    final proteinC = TextEditingController(text: '0');
    final carbsC = TextEditingController(text: '0');
    final fatsC = TextEditingController(text: '0');
    final gramsC = TextEditingController(text: '0');

    final saved = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Agregar $mealSlot'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameC,
                decoration: const InputDecoration(labelText: 'Nombre'),
              ),
              TextField(
                controller: caloriesC,
                decoration: const InputDecoration(labelText: 'Calorías'),
                keyboardType: TextInputType.number,
              ),
              TextField(
                controller: proteinC,
                decoration: const InputDecoration(labelText: 'Proteína (g)'),
                keyboardType: TextInputType.number,
              ),
              TextField(
                controller: carbsC,
                decoration: const InputDecoration(
                  labelText: 'Hidratos / carbohidratos (g)',
                ),
                keyboardType: TextInputType.number,
              ),
              TextField(
                controller: fatsC,
                decoration: const InputDecoration(labelText: 'Grasas (g)'),
                keyboardType: TextInputType.number,
              ),
              TextField(
                controller: gramsC,
                decoration: const InputDecoration(labelText: 'Gramos'),
                keyboardType: TextInputType.number,
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
            onPressed: () => Navigator.pop(ctx, {
              'id': DateTime.now().microsecondsSinceEpoch,
              'name': nameC.text.trim().isEmpty ? mealSlot : nameC.text.trim(),
              'meal_slot': mealSlot,
              'calories': parseWholeNumber(caloriesC.text),
              'protein': parseWholeNumber(proteinC.text),
              'carbs': parseWholeNumber(carbsC.text),
              'fats': parseWholeNumber(fatsC.text),
              'estimated_grams': parseWholeNumber(gramsC.text),
              'logged_at': DateTime.now().toIso8601String(),
              'manual': true,
            }),
            child: const Text('GUARDAR'),
          ),
        ],
      ),
    );

    if (saved == null) return;

    final date = _todayIsoDate();
    final updatedMeals = [..._dailyMeals, saved];
    await LocalUserDataStore.saveDailyMeals(
      widget.currentUser.email,
      date,
      updatedMeals,
    );

    if (!mounted) return;
    setState(() => _dailyMeals = updatedMeals);
    _showSuccessSnackBar('Aportaciones agregadas manualmente');

    if (_isHealthSyncEnabled) {
      HealthService().saveMealToHealth(saved);
    }
  }

  Map<String, double> _dailyTotals() {
    double cals = 0, pro = 0, carbs = 0, fats = 0, grams = 0;
    try {
      for (var meal in _dailyMeals) {
        if (meal is! Map) continue;
        cals += double.tryParse(meal['calories']?.toString() ?? '0') ?? 0;
        pro += double.tryParse(meal['protein']?.toString() ?? '0') ?? 0;
        carbs += double.tryParse(meal['carbs']?.toString() ?? '0') ?? 0;
        fats += double.tryParse(meal['fats']?.toString() ?? '0') ?? 0;
        grams +=
            double.tryParse(meal['estimated_grams']?.toString() ?? '0') ?? 0;
      }
    } catch (e) {
      debugPrint('Error calculating daily totals: $e');
    }

    return {
      'calories': cals,
      'protein': pro,
      'carbs': carbs,
      'fats': fats,
      'grams': grams,
    };
  }

  List<Map<String, dynamic>> _dailyDietSlots() {
    final today = DateTime.now().weekday;
    final selectedDiet = diets.firstWhere(
      (diet) => int.tryParse(diet['day_of_week']?.toString() ?? '') == today,
      orElse: () => diets.isNotEmpty ? diets.first : <String, dynamic>{},
    );

    final importedMeals =
        (selectedDiet['meals'] as List?)
            ?.whereType<Map>()
            .map((m) => Map<String, dynamic>.from(m))
            .toList() ??
        [];

    final defaults = [
      'Comida 1',
      'Comida 2',
      'Comida 3',
      'Pre-Workout',
      'Post-Workout',
    ];
    final slots = <Map<String, dynamic>>[];

    final count = importedMeals.isNotEmpty
        ? importedMeals.length
        : defaults.length;

    for (var i = 0; i < count; i++) {
      final imported = importedMeals.length > i ? importedMeals[i] : null;
      final nameValue =
          imported?['name'] ??
          (defaults.length > i ? defaults[i] : 'Comida ${i + 1}');
      final name = nameValue.toString();

      slots.add({
        'name': name,
        'notes': imported?['notes'] ?? '',
        'calories': imported?['calories'] ?? 0,
        'protein': imported?['protein'] ?? 0,
        'carbs': imported?['carbs'] ?? 0,
        'fats': imported?['fats'] ?? 0,
      });
    }
    return slots;
  }

  List<Map<String, dynamic>> _logsForMealSlot(String slotName) {
    try {
      return _dailyMeals
          .where((meal) {
            if (meal is! Map) return false;
            return (meal['meal_slot']?.toString() ?? '') == slotName;
          })
          .map((meal) => Map<String, dynamic>.from(meal))
          .toList();
    } catch (e) {
      debugPrint('Error getting logs for meal slot: $e');
      return [];
    }
  }

  Map<String, double> _totalsForLogs(List<Map<String, dynamic>> logs) {
    double cals = 0, pro = 0, carbs = 0, fats = 0;
    try {
      for (final meal in logs) {
        if (meal is! Map) continue;
        cals += double.tryParse(meal['calories']?.toString() ?? '0') ?? 0;
        pro += double.tryParse(meal['protein']?.toString() ?? '0') ?? 0;
        carbs += double.tryParse(meal['carbs']?.toString() ?? '0') ?? 0;
        fats += double.tryParse(meal['fats']?.toString() ?? '0') ?? 0;
      }
    } catch (e) {
      debugPrint('Error calculating totals for logs: $e');
    }
    return {'calories': cals, 'protein': pro, 'carbs': carbs, 'fats': fats};
  }

  Widget _buildMainPlanView() {
    if (workouts.isEmpty) {
      return _buildEmptyState(
        title: 'No hay rutinas todavía',
        subtitle:
            'Gestiona tus rutinas desde Configuración para cargar, crear o editar tu plan.',
      );
    }
    final todayWorkouts = _getTodayWorkouts();
    final otherWorkouts = _getOtherWorkouts();
    return RefreshIndicator(
      onRefresh: () async {
        await fetchWorkouts();
        await _loadWeeklyWorkoutLog();
        if (_isHealthSyncEnabled) {
          await _loadRecoverySnapshot();
        }
      },
      color: _primaryTextColor,
      backgroundColor: _isLightMode
          ? const Color(0xFFE9EDF1)
          : const Color(0xFF111214),
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification.metrics.axis == Axis.vertical) {
            _updateOtherWorkoutStackProgress(notification.metrics.pixels);
          }
          return false;
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 164),
          children: [
            _buildDashboardHeader(
              title: 'Tu entrenamiento',
              subtitle:
                  '${_getWeekdayName(DateTime.now().weekday)} y planificación semanal',
              countLabel: '${workouts.length} rutinas',
            ),
            const SizedBox(height: 14),
            _buildWorkoutRecoverySummary(),
            if (todayWorkouts.isNotEmpty) ...[
              const SizedBox(height: 22),
              _buildSectionTitle('Hoy'),
              const SizedBox(height: 10),
              ...todayWorkouts.map((w) => _buildWorkoutCard(w, isToday: true)),
            ],
            if (otherWorkouts.isNotEmpty) ...[
              const SizedBox(height: 20),
              _buildSectionTitle('Otras rutinas', subtle: true),
              const SizedBox(height: 10),
              _buildStackedOtherWorkouts(otherWorkouts),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildWorkoutRecoverySummary() {
    final snapshot = _recoverySnapshot;

    if (!_isHealthSyncEnabled || kIsWeb) {
      return _buildRecoverySummaryTile(
        iconColor: _primaryTextColor,
        title: 'Descanso',
        subtitle: kIsWeb
            ? 'Disponible en la app instalada'
            : 'Toca para vincular sueño y recuperación',
      );
    }

    if (_isLoadingRecovery && snapshot == null) {
      return _buildGlassContainer(
        padding: const EdgeInsets.all(18),
        borderRadius: 24,
        child: Row(
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                color: _primaryTextColor,
                strokeWidth: 2.3,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Leyendo descanso del teléfono...',
                style: TextStyle(
                  color: _primaryTextColor,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final statusColor = _recoveryStatusColor(snapshot);
    return _buildRecoverySummaryTile(
      iconColor: statusColor,
      title: snapshot?.status ?? 'Descanso',
      subtitle: snapshot == null
          ? 'Toca para ver actividad, sueño y recuperación'
          : 'Mov ${snapshot.activeEnergyKcal.round()} kcal · Ej ${snapshot.exerciseMinutes.round()} min · Sueño ${_formatHealthHours(snapshot.sleepHours)}',
      footer:
          _recoveryError != null ||
              (snapshot != null && !snapshot.hasHealthData)
          ? _recoveryError ??
                'No encontré datos recientes. Revisa permisos de Salud.'
          : null,
    );
  }

  Widget _buildRecoverySummaryTile({
    required Color iconColor,
    required String title,
    required String subtitle,
    String? footer,
  }) {
    return GestureDetector(
      onTap: _openRecoveryDetails,
      child: _buildGlassContainer(
        padding: const EdgeInsets.all(16),
        borderRadius: 24,
        highlighted: true,
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: iconColor.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    Icons.bedtime_rounded,
                    color: iconColor,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: _primaryTextColor,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: _secondaryTextColor,
                          fontSize: 13,
                          height: 1.25,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: _secondaryTextColor,
                  size: 26,
                ),
              ],
            ),
            if (footer != null) ...[
              const SizedBox(height: 10),
              Text(
                footer,
                style: TextStyle(
                  color: _secondaryTextColor,
                  fontSize: 12,
                  height: 1.3,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Color _recoveryStatusColor(RecoverySnapshot? snapshot) {
    if (snapshot == null) {
      return _primaryTextColor;
    }
    return snapshot.status.toLowerCase().contains('listo')
        ? Colors.greenAccent
        : Colors.orangeAccent;
  }

  void _updateOtherWorkoutStackProgress(double scrollPixels) {
    if (_otherWorkoutsStackForcedOpen) {
      return;
    }

    final nextProgress = ((scrollPixels - 44) / 180).clamp(0.0, 1.0);
    if ((nextProgress - _otherWorkoutsStackProgress).abs() < 0.01) {
      return;
    }
    setState(() => _otherWorkoutsStackProgress = nextProgress);
  }

  Widget _buildStackedOtherWorkouts(List<Map<String, dynamic>> workouts) {
    if (workouts.length == 1) {
      return _buildWorkoutCard(workouts.first, isToday: false);
    }

    final progress = Curves.easeOutCubic.transform(
      _otherWorkoutsStackProgress.clamp(0.0, 1.0),
    );
    final visibleCount = workouts.length.clamp(0, 4);
    const cardExtent = 192.0;
    const collapsedPeek = 56.0;
    final collapsedHeight = cardExtent + ((visibleCount - 1) * collapsedPeek);
    final expandedHeight = workouts.length * cardExtent;
    final stackHeight = lerpDouble(collapsedHeight, expandedHeight, progress)!;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {
        setState(() {
          _otherWorkoutsStackForcedOpen = !_otherWorkoutsStackForcedOpen;
          _otherWorkoutsStackProgress = _otherWorkoutsStackForcedOpen ? 1 : 0;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 360),
        curve: Curves.easeOutQuart,
        height: stackHeight,
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: workouts.asMap().entries.toList().reversed.map((entry) {
            final index = entry.key;
            final workout = entry.value;
            final isTop = index == 0;
            final collapsedTop = index > 3
                ? (visibleCount - 1) * collapsedPeek
                : index * collapsedPeek;
            final expandedTop = index * cardExtent;
            final top = lerpDouble(collapsedTop, expandedTop, progress)!;
            final collapsedScale = index > 3 ? 0.86 : 1.0 - (index * 0.04);
            final scale = isTop
                ? 1.0
                : lerpDouble(collapsedScale, 1.0, progress)!;
            final opacity = index >= visibleCount
                ? progress
                : lerpDouble(1.0 - (index * 0.16), 1.0, progress)!;

            return Positioned(
              top: top,
              left: 0,
              right: 0,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 280),
                opacity: opacity.clamp(0.0, 1.0),
                child: Transform.scale(
                  scale: scale,
                  alignment: Alignment.topCenter,
                  child: IgnorePointer(
                    ignoring: !isTop && progress < 0.72,
                    child: _buildWorkoutCard(
                      workout,
                      isToday: false,
                      fixedHeight: cardExtent - 10,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildDietPlanView() {
    int today = DateTime.now().weekday;
    List<Map<String, dynamic>> todayDiets = diets
        .where((d) => int.tryParse(d['day_of_week']?.toString() ?? '') == today)
        .toList();

    if (todayDiets.isEmpty && diets.isNotEmpty) {
      todayDiets = [diets.first];
    }
    final todayDietIds = todayDiets.map((d) => d['id']).toSet();

    List<Map<String, dynamic>> otherDiets = diets
        .where((d) => !todayDietIds.contains(d['id']))
        .toList();

    return RefreshIndicator(
      onRefresh: () async {
        await fetchDiets();
        await fetchDailyNutrition();
      },
      color: _primaryTextColor,
      backgroundColor: _isLightMode
          ? const Color(0xFFE9EDF1)
          : const Color(0xFF111214),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        children: [
          _buildDashboardHeader(
            title: 'Tu nutrición',
            subtitle: 'Comidas del día y planificación semanal',
            countLabel: '${diets.length} dietas',
          ),
          const SizedBox(height: 18),
          _buildDailyNutritionCard(),
          if (otherDiets.isNotEmpty) ...[
            const SizedBox(height: 20),
            _buildSectionTitle('Otras dietas', subtle: true),
            const SizedBox(height: 10),
            ...otherDiets.map((d) => _buildDietCard(d, isToday: false)),
          ],
          if (diets.isEmpty) ...[
            const SizedBox(height: 18),
            _buildGlassContainer(
              padding: const EdgeInsets.all(18),
              borderRadius: 24,
              child: Text(
                'Carga tu PDF desde Configuración para convertirlo en un plan de comidas. También puedes registrar lo que comes tomando foto.',
                style: TextStyle(color: _secondaryTextColor, height: 1.35),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatHealthHours(double hours) {
    if (hours <= 0) return '--';
    if (hours < 1) return '${(hours * 60).round()} min';
    return '${hours.toStringAsFixed(hours >= 10 ? 0 : 1)} h';
  }

  Widget _buildConfigView() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 132),
      children: [
        _buildConfigProfileHeader(),
        const SizedBox(height: 16),
        _buildConfigMenuTile(
          icon: Icons.account_circle_rounded,
          title: 'Cuenta y seguridad',
          subtitle: 'Sesión, datos privados y acciones de cuenta.',
          meta: widget.currentUser.email,
          onTap: _openAccountSettings,
        ),
        const SizedBox(height: 10),
        _buildConfigMenuTile(
          icon: Icons.tune_rounded,
          title: 'Preferencias',
          subtitle: 'Modo claro, Apple Health y datos del teléfono.',
          meta: _isHealthSyncEnabled ? 'Salud activa' : 'Salud desconectada',
          onTap: _openPreferenceSettings,
        ),
        const SizedBox(height: 10),
        WeeklyWorkoutRegistrySection(
          log: _weeklyWorkoutLog,
          workouts: workouts,
          isLightMode: _isLightMode,
          primaryTextColor: _primaryTextColor,
          secondaryTextColor: _secondaryTextColor,
          onToggleCompleted: (entry) {
            unawaited(_toggleWeeklyWorkoutCompletion(entry));
          },
          onRestRatingChanged: (entry, rating) {
            unawaited(_updateWeeklyWorkoutRestRating(entry, rating));
          },
          onPrUpdated: (update) {
            unawaited(_saveExercisePrFromRegistry(update));
          },
        ),
        const SizedBox(height: 10),
        _buildConfigMenuTile(
          icon: Icons.fitness_center_rounded,
          title: 'Entrenamientos',
          subtitle: 'Importa, crea, exporta y edita rutinas.',
          meta: '${workouts.length} rutinas',
          onTap: _openWorkoutSettings,
        ),
        const SizedBox(height: 10),
        _buildConfigMenuTile(
          icon: Icons.restaurant_menu_rounded,
          title: 'Alimentación',
          subtitle: 'Importa, crea, exporta y edita dietas.',
          meta: '${diets.length} dietas',
          onTap: _openDietSettings,
        ),
        const SizedBox(height: 10),
        _buildFeedbackBox(),
        if (widget.currentUser.isAdmin) ...[
          const SizedBox(height: 10),
          _buildConfigMenuTile(
            icon: Icons.admin_panel_settings_rounded,
            title: 'Admin',
            subtitle: 'Asigna rutinas y dietas a otros usuarios.',
            meta: 'Herramientas avanzadas',
            onTap: _openAdminSettings,
          ),
        ],
      ],
    );
  }

  Widget _buildConfigProfileHeader() {
    return _buildGlassContainer(
      padding: const EdgeInsets.all(18),
      borderRadius: 28,
      highlighted: true,
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _isLightMode
                  ? const Color(0xFF101113).withOpacity(0.08)
                  : Colors.white.withOpacity(0.10),
            ),
            child: Icon(Icons.person_rounded, color: _primaryTextColor),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.currentUser.name,
                  style: TextStyle(
                    color: _primaryTextColor,
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.currentUser.isAdmin ? 'Administrador' : 'Usuario',
                  style: TextStyle(
                    color: _secondaryTextColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildConfigMetricChip(
                icon: Icons.fitness_center_rounded,
                label: '${workouts.length}',
              ),
              _buildConfigMetricChip(
                icon: Icons.restaurant_menu_rounded,
                label: '${diets.length}',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildConfigMenuTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required String meta,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: _buildGlassContainer(
        padding: const EdgeInsets.all(16),
        borderRadius: 24,
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: _isLightMode
                    ? const Color(0xFF101113).withOpacity(0.07)
                    : Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: _primaryTextColor, size: 23),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: _primaryTextColor,
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: _secondaryTextColor,
                      fontSize: 13,
                      height: 1.28,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    meta,
                    style: TextStyle(
                      color: _primaryTextColor.withOpacity(0.72),
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: _secondaryTextColor,
              size: 28,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeedbackBox() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        setState(() => _isFeedbackExpanded = !_isFeedbackExpanded);
      },
      child: _buildGlassContainer(
        padding: const EdgeInsets.all(16),
        borderRadius: 24,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: _isLightMode
                        ? const Color(0xFF101113).withOpacity(0.07)
                        : Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Icon(
                    Icons.chat_bubble_outline_rounded,
                    color: _primaryTextColor,
                    size: 21,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Comentarios',
                        style: TextStyle(
                          color: _primaryTextColor,
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _isFeedbackExpanded
                            ? 'Escribe y envia tu comentario por correo.'
                            : 'Enviar dudas, errores o sugerencias.',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _secondaryTextColor,
                          fontSize: 13,
                          height: 1.28,
                        ),
                      ),
                    ],
                  ),
                ),
                AnimatedRotation(
                  turns: _isFeedbackExpanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: _secondaryTextColor,
                    size: 28,
                  ),
                ),
              ],
            ),
            AnimatedCrossFade(
              firstChild: const SizedBox(width: double.infinity),
              secondChild: Column(
                children: [
                  const SizedBox(height: 14),
                  TextField(
                    controller: _feedbackController,
                    minLines: 3,
                    maxLines: 5,
                    textInputAction: TextInputAction.newline,
                    style: TextStyle(
                      color: _primaryTextColor,
                      fontWeight: FontWeight.w600,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Escribe tu comentario...',
                      hintStyle: TextStyle(color: _secondaryTextColor),
                      filled: true,
                      fillColor: _isLightMode
                          ? Colors.white.withOpacity(0.54)
                          : Colors.white.withOpacity(0.06),
                      contentPadding: const EdgeInsets.all(14),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide(
                          color: _isLightMode
                              ? Colors.white.withOpacity(0.64)
                              : Colors.white.withOpacity(0.08),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide(
                          color: _isLightMode
                              ? Colors.white.withOpacity(0.64)
                              : Colors.white.withOpacity(0.08),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide(
                          color: _primaryTextColor,
                          width: 1.2,
                        ),
                      ),
                    ),
                    onTap: () {},
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: _buildConfigActionButton(
                      icon: Icons.send_rounded,
                      label: 'Enviar',
                      onPressed: () {
                        unawaited(_sendFeedbackEmail());
                      },
                      isPrimary: true,
                    ),
                  ),
                ],
              ),
              crossFadeState: _isFeedbackExpanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 190),
              firstCurve: Curves.easeOut,
              secondCurve: Curves.easeOut,
              sizeCurve: Curves.easeOutCubic,
            ),
          ],
        ),
      ),
    );
  }

  void _openConfigPanel({
    required String title,
    required List<Widget> Function(VoidCallback refresh) childrenBuilder,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) {
          return StatefulBuilder(
            builder: (panelContext, refreshPanel) {
              void refresh() => refreshPanel(() {});
              return Scaffold(
                extendBodyBehindAppBar: true,
                appBar: AppBar(
                  title: Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                ),
                body: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: _pageGradientColors,
                    ),
                  ),
                  child: SafeArea(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
                      children: childrenBuilder(refresh),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _openAccountSettings() {
    _openConfigPanel(
      title: 'Cuenta',
      childrenBuilder: (_) => [
        _buildConfigSection(
          title: 'Cuenta y seguridad',
          subtitle: 'Sesión activa, privacidad y acciones delicadas.',
          actions: [
            _buildConfigActionButton(
              icon: Icons.logout_rounded,
              label: 'Cerrar sesión',
              onPressed: _logout,
            ),
            _buildConfigActionButton(
              icon: Icons.delete_forever_rounded,
              label: 'Borrar cuenta',
              onPressed: _deleteAccount,
              isDestructive: true,
            ),
          ],
          children: [
            _buildConfigInfoRow(
              icon: Icons.verified_user_rounded,
              title: 'Sesión actual',
              subtitle: 'Conectado como ${widget.currentUser.email}',
            ),
            const SizedBox(height: 10),
            _buildConfigInfoRow(
              icon: Icons.shield_moon_rounded,
              title: 'Datos privados',
              subtitle:
                  'Rutinas, dietas y registros se mantienen separados por cuenta.',
            ),
          ],
        ),
      ],
    );
  }

  void _openPreferenceSettings() {
    _openConfigPanel(
      title: 'Preferencias',
      childrenBuilder: (refresh) => [
        _buildConfigSection(
          title: 'Apariencia',
          subtitle: 'Controla cómo se ve Healthy-T en este dispositivo.',
          actions: const [],
          children: [
            _buildConfigSwitchRow(
              icon: Icons.light_mode_rounded,
              title: 'Modo claro',
              subtitle: 'Inicia y usa la app con liquid glass claro.',
              value: _isLightMode,
              onChanged: (value) {
                unawaited(_toggleLightMode(value).whenComplete(refresh));
                refresh();
              },
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildConfigSection(
          title: 'Integraciones',
          subtitle:
              'Conecta Apple Salud. Si Huawei Health escribe en Salud, también se toma esa información.',
          actions: const [],
          children: [
            _buildConfigSwitchRow(
              icon: Icons.health_and_safety_rounded,
              title: 'Apple Salud',
              subtitle:
                  'Lee pasos, calorías activas, sueño y entrenamientos del teléfono.',
              value: _isHealthSyncEnabled,
              onChanged: (value) {
                unawaited(_toggleHealthSync(value).whenComplete(refresh));
                refresh();
              },
            ),
          ],
        ),
      ],
    );
  }

  void _openWorkoutSettings() {
    _openConfigPanel(
      title: 'Entrenamientos',
      childrenBuilder: (refresh) => [
        _buildConfigSection(
          title: 'Rutinas',
          subtitle: 'Importa, crea, exporta y edita tus entrenamientos.',
          actions: [
            _buildConfigActionButton(
              icon: Icons.upload_file_rounded,
              label: 'Cargar',
              onPressed: () =>
                  unawaited(pickAndUploadFile().whenComplete(refresh)),
            ),
            _buildConfigActionButton(
              icon: Icons.add_rounded,
              label: 'Crear',
              onPressed: () =>
                  unawaited(_createNewWorkout().whenComplete(refresh)),
              isPrimary: true,
            ),
            _buildConfigActionButton(
              icon: Icons.auto_awesome_rounded,
              label: 'IA',
              onPressed: () =>
                  unawaited(_createWorkoutWithAi().whenComplete(refresh)),
            ),
            _buildConfigActionButton(
              icon: Icons.download_rounded,
              label: 'Excel',
              onPressed: () => unawaited(exportWorkoutsToExcel()),
            ),
          ],
          children: workouts
              .map((w) => _buildEditableWorkoutCard(w, onDeleted: refresh))
              .toList(),
        ),
      ],
    );
  }

  void _openDietSettings() {
    _openConfigPanel(
      title: 'Alimentación',
      childrenBuilder: (refresh) => [
        _buildConfigSection(
          title: 'Dietas',
          subtitle: 'Importa, crea, exporta y edita tu plan de comida.',
          actions: [
            _buildConfigActionButton(
              icon: Icons.upload_file_rounded,
              label: 'Cargar',
              onPressed: () =>
                  unawaited(pickAndUploadDietFile().whenComplete(refresh)),
            ),
            _buildConfigActionButton(
              icon: Icons.add_rounded,
              label: 'Crear',
              onPressed: () =>
                  unawaited(_createNewDiet().whenComplete(refresh)),
              isPrimary: true,
            ),
            _buildConfigActionButton(
              icon: Icons.download_rounded,
              label: 'Excel',
              onPressed: () => unawaited(exportDietsToExcel()),
            ),
          ],
          children: diets
              .map((d) => _buildEditableDietCard(d, onDeleted: refresh))
              .toList(),
        ),
      ],
    );
  }

  void _openAdminSettings() {
    _openConfigPanel(
      title: 'Admin',
      childrenBuilder: (_) => [
        _buildConfigSection(
          title: 'Asignaciones',
          subtitle:
              'Asigna rutinas o dietas existentes a otro usuario usando su correo.',
          actions: [
            _buildConfigActionButton(
              icon: Icons.send_rounded,
              label: 'Asignar rutina',
              onPressed: _assignWorkoutToUserByEmail,
              isPrimary: true,
            ),
            _buildConfigActionButton(
              icon: Icons.restaurant_menu_rounded,
              label: 'Asignar dieta',
              onPressed: _assignDietToUserByEmail,
            ),
          ],
          children: [_buildAdminAssignmentPanel()],
        ),
      ],
    );
  }

  Widget _buildDashboardHeader({
    required String title,
    required String subtitle,
    required String countLabel,
  }) {
    return _buildGlassContainer(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      borderRadius: 30,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: _isLightMode
                  ? const Color(0xFF101113).withOpacity(0.08)
                  : Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              countLabel.toUpperCase(),
              style: TextStyle(
                color: _primaryTextColor,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: TextStyle(
              color: _primaryTextColor,
              fontSize: 30,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.9,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: TextStyle(
              color: _secondaryTextColor,
              fontSize: 15,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, {bool subtle = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          color: subtle
              ? (_isLightMode ? const Color(0xFF747A84) : Colors.white54)
              : _primaryTextColor,
          fontSize: subtle ? 13 : 19,
          fontWeight: subtle ? FontWeight.w800 : FontWeight.w900,
          letterSpacing: 1.1,
        ),
      ),
    );
  }

  Widget _buildDailyNutritionCard() {
    final totals = _dailyTotals();

    return _buildGlassContainer(
      padding: const EdgeInsets.all(18),
      borderRadius: 28,
      highlighted: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isLightMode
                      ? const Color(0xFF101113).withOpacity(0.08)
                      : Colors.white.withOpacity(0.10),
                ),
                child: Icon(Icons.camera_alt_rounded, color: _primaryTextColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Conteo diario',
                      style: TextStyle(
                        color: _primaryTextColor,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Toma foto de cada comida para sumar tus macros del día.',
                      style: TextStyle(
                        color: _secondaryTextColor,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _buildNutritionPill(
                '${totals['calories']!.toInt()} kcal',
                Icons.local_fire_department_rounded,
              ),
              _buildNutritionPill(
                'P ${totals['protein']!.toInt()}g',
                Icons.egg_alt_rounded,
              ),
              _buildNutritionPill(
                'H ${totals['carbs']!.toInt()}g',
                Icons.grain_rounded,
              ),
              _buildNutritionPill(
                'G ${totals['fats']!.toInt()}g',
                Icons.opacity_rounded,
              ),
              _buildNutritionPill(
                '${totals['grams']!.toInt()}g total',
                Icons.scale_rounded,
              ),
            ],
          ),
          const SizedBox(height: 16),
          ..._dailyDietSlots().map(_buildMealTrackingSlot),
          if (_dailyMeals.isNotEmpty) ...[
            const SizedBox(height: 16),
            Divider(
              color: _isLightMode
                  ? const Color(0xFF101113).withOpacity(0.10)
                  : Colors.white12,
            ),
            const SizedBox(height: 8),
            ..._dailyMeals.reversed.map(
              (meal) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Icon(
                      Icons.restaurant_menu_rounded,
                      color: _secondaryTextColor,
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        meal['name']?.toString() ?? 'Comida registrada',
                        style: TextStyle(
                          color: _primaryTextColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${(double.tryParse(meal['calories']?.toString() ?? '0') ?? 0).toInt()} kcal',
                          style: TextStyle(
                            color: _secondaryTextColor,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'P ${(double.tryParse(meal['protein']?.toString() ?? '0') ?? 0).toInt()}g • H ${(double.tryParse(meal['carbs']?.toString() ?? '0') ?? 0).toInt()}g • G ${(double.tryParse(meal['fats']?.toString() ?? '0') ?? 0).toInt()}g',
                          style: TextStyle(
                            color: _secondaryTextColor,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      constraints: const BoxConstraints(),
                      padding: const EdgeInsets.only(left: 8),
                      icon: const Icon(
                        Icons.delete_outline_rounded,
                        color: Colors.redAccent,
                        size: 20,
                      ),
                      onPressed: () => _deleteDailyMeal(meal['id']),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMealTrackingSlot(Map<String, dynamic> slot) {
    final slotName = slot['name']?.toString() ?? 'Comida';
    final logs = _logsForMealSlot(slotName);
    final totals = _totalsForLogs(logs);
    final planMacros =
        '${(double.tryParse(slot['calories']?.toString() ?? '0') ?? 0).toInt()} kcal\nP ${(double.tryParse(slot['protein']?.toString() ?? '0') ?? 0).toInt()}g • H ${(double.tryParse(slot['carbs']?.toString() ?? '0') ?? 0).toInt()}g • G ${(double.tryParse(slot['fats']?.toString() ?? '0') ?? 0).toInt()}g';
    final preview = _dietMealPreview(slot);

    bool isExpanded = false;

    return StatefulBuilder(
      builder: (context, setState) {
        return GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            setState(() => isExpanded = !isExpanded);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _isLightMode
                  ? const Color(
                      0xFF101113,
                    ).withOpacity(isExpanded ? 0.08 : 0.04)
                  : Colors.white.withOpacity(isExpanded ? 0.12 : 0.06),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: _isLightMode
                    ? const Color(
                        0xFF101113,
                      ).withOpacity(isExpanded ? 0.18 : 0.08)
                    : (isExpanded ? Colors.white38 : Colors.white12),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        slotName,
                        style: TextStyle(
                          color: _primaryTextColor,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${totals['calories']!.toInt()} kcal',
                          style: TextStyle(
                            color: _primaryTextColor,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (totals['calories']! > 0)
                          Text(
                            'P ${totals['protein']!.toInt()}g • H ${totals['carbs']!.toInt()}g • G ${totals['fats']!.toInt()}g',
                            style: TextStyle(
                              color: _secondaryTextColor,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
                if ((double.tryParse(slot['calories']?.toString() ?? '0') ??
                            0) >
                        0 ||
                    (double.tryParse(slot['protein']?.toString() ?? '0') ?? 0) >
                        0 ||
                    (double.tryParse(slot['carbs']?.toString() ?? '0') ?? 0) >
                        0 ||
                    (double.tryParse(slot['fats']?.toString() ?? '0') ?? 0) >
                        0) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Plan:\n$planMacros',
                    style: TextStyle(
                      color: _secondaryTextColor,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ],
                if (preview.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeInOut,
                    alignment: Alignment.topCenter,
                    child: _DietOptionTable(
                      text: preview,
                      isExpanded: isExpanded,
                      collapsedRows: 3,
                    ),
                  ),
                ],
                if (logs.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ...logs.map(
                    (log) => Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                log['manual'] == true
                                    ? Icons.edit_note_rounded
                                    : Icons.camera_alt_rounded,
                                color: _secondaryTextColor,
                                size: 16,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  log['name']?.toString() ?? 'Registro',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: _secondaryTextColor,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    '${(double.tryParse(log['calories']?.toString() ?? '0') ?? 0).toInt()} kcal',
                                    style: TextStyle(
                                      color: _secondaryTextColor,
                                      fontSize: 12,
                                    ),
                                  ),
                                  Text(
                                    'P ${(double.tryParse(log['protein']?.toString() ?? '0') ?? 0).toInt()}g • H ${(double.tryParse(log['carbs']?.toString() ?? '0') ?? 0).toInt()}g • G ${(double.tryParse(log['fats']?.toString() ?? '0') ?? 0).toInt()}g',
                                    style: TextStyle(
                                      color: _secondaryTextColor.withOpacity(
                                        0.74,
                                      ),
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          if (log['items'] is List &&
                              (log['items'] as List).isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(left: 22, top: 2),
                              child: Text(
                                (log['items'] as List)
                                    .whereType<Map>()
                                    .map((item) {
                                      final grams =
                                          item['estimated_grams']?.toString() ??
                                          '0';
                                      final calories =
                                          item['calories']?.toString() ?? '0';
                                      return '${item['name'] ?? 'Alimento'}: ${grams}g, $calories kcal';
                                    })
                                    .join(' • '),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: _secondaryTextColor.withOpacity(0.74),
                                  fontSize: 10.5,
                                  height: 1.25,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _scanFoodWithAi(mealSlot: slotName),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          foregroundColor: _isLightMode
                              ? const Color(0xFF101113)
                              : Colors.white,
                          side: BorderSide(
                            color: _isLightMode
                                ? const Color(0xFF101113).withOpacity(0.26)
                                : Colors.white24,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.camera_alt_rounded, size: 20),
                            const SizedBox(height: 4),
                            const Text(
                              'Foto IA',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => _addManualFoodLog(slotName),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          backgroundColor: _isLightMode
                              ? const Color(0xFF101113)
                              : Colors.white,
                          foregroundColor: _isLightMode
                              ? Colors.white
                              : Colors.black,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.add_rounded, size: 20),
                            const SizedBox(height: 4),
                            const Text(
                              'Manual',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildNutritionPill(String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _isLightMode
            ? const Color(0xFF101113).withOpacity(0.06)
            : Colors.white.withOpacity(0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _isLightMode
              ? const Color(0xFF101113).withOpacity(0.10)
              : Colors.white.withOpacity(0.08),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: _primaryTextColor, size: 16),
          const SizedBox(width: 7),
          Text(
            label,
            style: TextStyle(
              color: _primaryTextColor,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState({required String title, required String subtitle}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: _buildGlassContainer(
          padding: const EdgeInsets.all(24),
          borderRadius: 30,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isLightMode
                      ? const Color(0xFF101113).withOpacity(0.08)
                      : Colors.white.withOpacity(0.08),
                ),
                child: Icon(
                  Icons.blur_on_rounded,
                  color: _primaryTextColor,
                  size: 30,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _primaryTextColor,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _secondaryTextColor,
                  fontSize: 15,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConfigSection({
    required String title,
    required String subtitle,
    required List<Widget> actions,
    required List<Widget> children,
    Widget? headerTrailing,
  }) {
    return _buildGlassContainer(
      padding: const EdgeInsets.all(18),
      borderRadius: 28,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: _primaryTextColor,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: TextStyle(
                  color: _secondaryTextColor,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
              if (headerTrailing != null) ...[
                const SizedBox(height: 14),
                headerTrailing,
              ],
            ],
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, constraints) {
                final itemWidth = actions.length == 1
                    ? constraints.maxWidth
                    : (constraints.maxWidth - 10) / 2;
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: actions
                      .map(
                        (action) => SizedBox(width: itemWidth, child: action),
                      )
                      .toList(),
                );
              },
            ),
          ],
          const SizedBox(height: 16),
          if (children.isEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
              decoration: BoxDecoration(
                color: _isLightMode
                    ? Colors.white.withOpacity(0.44)
                    : Colors.white.withOpacity(0.04),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _isLightMode
                      ? Colors.white.withOpacity(0.62)
                      : Colors.white.withOpacity(0.06),
                ),
              ),
              child: Text(
                'Todo listo en esta sección.',
                style: TextStyle(color: _secondaryTextColor),
              ),
            ),
          ] else
            ...children,
        ],
      ),
    );
  }

  Widget _buildConfigActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    bool isPrimary = false,
    bool isDestructive = false,
  }) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
        backgroundColor: isDestructive
            ? Colors.redAccent.withOpacity(0.18)
            : isPrimary
            ? (_isLightMode ? const Color(0xFF101113) : Colors.white)
            : (_isLightMode
                  ? const Color(0xFF101113).withOpacity(0.92)
                  : Colors.white.withOpacity(0.08)),
        foregroundColor: isDestructive
            ? Colors.redAccent
            : (_isLightMode
                  ? Colors.white
                  : (isPrimary ? Colors.black : Colors.white)),
        elevation: 0,
        side: isDestructive
            ? const BorderSide(color: Colors.redAccent)
            : BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 24),
          const SizedBox(height: 6), // Efecto de salto de línea (br)
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAdminAssignmentPanel() {
    final selectedWorkoutValue =
        workouts.any(
          (workout) =>
              workout['id']?.toString() == _selectedAdminWorkoutId?.toString(),
        )
        ? _selectedAdminWorkoutId
        : (workouts.isNotEmpty ? workouts.first['id'] : null);
    _selectedAdminWorkoutId = selectedWorkoutValue;

    final selectedDietValue =
        diets.any(
          (diet) => diet['id']?.toString() == _selectedAdminDietId?.toString(),
        )
        ? _selectedAdminDietId
        : (diets.isNotEmpty ? diets.first['id'] : null);
    _selectedAdminDietId = selectedDietValue;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _adminTargetEmailController,
          keyboardType: TextInputType.emailAddress,
          style: TextStyle(color: _primaryTextColor),
          decoration: InputDecoration(
            labelText: 'Correo del usuario',
            labelStyle: TextStyle(color: _secondaryTextColor),
            filled: true,
            fillColor: _isLightMode
                ? const Color(0xFF101113).withOpacity(0.05)
                : Colors.white.withOpacity(0.06),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide(
                color: _isLightMode
                    ? const Color(0xFF101113).withOpacity(0.10)
                    : Colors.white.withOpacity(0.08),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide(color: _primaryTextColor),
            ),
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<dynamic>(
          value: selectedWorkoutValue,
          isExpanded: true,
          dropdownColor: _isLightMode ? Colors.white : const Color(0xFF1E1E1E),
          style: TextStyle(color: _primaryTextColor),
          decoration: InputDecoration(
            labelText: 'Rutina a asignar',
            labelStyle: TextStyle(color: _secondaryTextColor),
            filled: true,
            fillColor: _isLightMode
                ? const Color(0xFF101113).withOpacity(0.05)
                : Colors.white.withOpacity(0.06),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide(
                color: _isLightMode
                    ? const Color(0xFF101113).withOpacity(0.10)
                    : Colors.white.withOpacity(0.08),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide(color: _primaryTextColor),
            ),
          ),
          items: workouts
              .map(
                (workout) => DropdownMenuItem<dynamic>(
                  value: workout['id'],
                  child: Text(workout['name']?.toString() ?? 'Rutina'),
                ),
              )
              .toList(),
          onChanged: workouts.isEmpty
              ? null
              : (value) => setState(() => _selectedAdminWorkoutId = value),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<dynamic>(
          value: selectedDietValue,
          isExpanded: true,
          dropdownColor: _isLightMode ? Colors.white : const Color(0xFF1E1E1E),
          style: TextStyle(color: _primaryTextColor),
          decoration: InputDecoration(
            labelText: 'Dieta a asignar',
            labelStyle: TextStyle(color: _secondaryTextColor),
            filled: true,
            fillColor: _isLightMode
                ? const Color(0xFF101113).withOpacity(0.05)
                : Colors.white.withOpacity(0.06),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide(
                color: _isLightMode
                    ? const Color(0xFF101113).withOpacity(0.10)
                    : Colors.white.withOpacity(0.08),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide(color: _primaryTextColor),
            ),
          ),
          items: diets
              .map(
                (diet) => DropdownMenuItem<dynamic>(
                  value: diet['id'],
                  child: Text(diet['name']?.toString() ?? 'Dieta'),
                ),
              )
              .toList(),
          onChanged: diets.isEmpty
              ? null
              : (value) => setState(() => _selectedAdminDietId = value),
        ),
        const SizedBox(height: 10),
        Text(
          'Si el correo aún no existe, la asignación queda pendiente y se entrega cuando ese usuario inicie sesión.',
          style: TextStyle(
            color: _secondaryTextColor,
            fontSize: 12,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _buildConfigActionButton(
                icon: Icons.file_download_rounded,
                label: 'Excel rutina',
                onPressed: _exportSelectedAdminWorkoutToExcel,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildConfigActionButton(
                icon: Icons.table_chart_rounded,
                label: 'Excel dieta',
                onPressed: _exportSelectedAdminDietToExcel,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _buildConfigActionButton(
                icon: Icons.upload_file_rounded,
                label: 'Asignar XLS rutina',
                onPressed: _assignWorkoutExcelToUserByEmail,
                isPrimary: true,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildConfigActionButton(
                icon: Icons.post_add_rounded,
                label: 'Asignar XLS dieta',
                onPressed: _assignDietExcelToUserByEmail,
                isPrimary: true,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildConfigMetricChip({
    required IconData icon,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _isLightMode
            ? Colors.white.withOpacity(0.52)
            : Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: _isLightMode
              ? Colors.white.withOpacity(0.66)
              : Colors.white.withOpacity(0.08),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: _primaryTextColor, size: 16),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: _primaryTextColor,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfigInfoRow({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _isLightMode
            ? Colors.white.withOpacity(0.48)
            : Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _isLightMode
              ? Colors.white.withOpacity(0.68)
              : Colors.white.withOpacity(0.06),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: _isLightMode
                  ? const Color(0xFF101113).withOpacity(0.06)
                  : Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: _primaryTextColor, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: _primaryTextColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: _secondaryTextColor,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfigSwitchRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _isLightMode
            ? Colors.white.withOpacity(0.48)
            : Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _isLightMode
              ? Colors.white.withOpacity(0.68)
              : Colors.white.withOpacity(0.06),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: _isLightMode
                  ? const Color(0xFF101113).withOpacity(0.06)
                  : Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: _primaryTextColor, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: _primaryTextColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: _secondaryTextColor,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: Colors.greenAccent,
          ),
        ],
      ),
    );
  }

  Widget _buildToolbarMenu() {
    final bool isConfigOpen = _currentIndex == 2;

    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: _isLightMode
                  ? Colors.white.withOpacity(0.72)
                  : const Color(0xFF020303).withOpacity(0.92),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _isLightMode
                    ? Colors.white.withOpacity(0.78)
                    : Colors.transparent,
              ),
              boxShadow: _isLightMode
                  ? null
                  : [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.42),
                        blurRadius: 18,
                        offset: const Offset(0, 10),
                      ),
                    ],
            ),
            child: isConfigOpen
                ? IconButton(
                    icon: Icon(
                      Icons.arrow_back_rounded,
                      size: 20,
                      color: _primaryTextColor,
                    ),
                    onPressed: _closeConfigMenu,
                  )
                : IconButton(
                    icon: Icon(
                      Icons.menu_rounded,
                      size: 20,
                      color: _primaryTextColor,
                    ),
                    onPressed: _openConfigMenu,
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildGlassNavBar() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: BoxDecoration(
            color: _isLightMode
                ? Colors.white.withOpacity(0.72)
                : const Color(0xFF020303).withOpacity(0.94),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: _isLightMode
                  ? Colors.white.withOpacity(0.78)
                  : Colors.transparent,
            ),
            boxShadow: _isLightMode
                ? [
                    BoxShadow(
                      color: const Color(0xFFB8C4D1).withOpacity(0.28),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.50),
                      blurRadius: 28,
                      offset: const Offset(0, 14),
                    ),
                  ],
          ),
          child: BottomNavigationBar(
            currentIndex: _currentIndex == 2
                ? _lastContentIndex
                : _currentIndex,
            onTap: (index) => setState(() {
              _currentIndex = index;
              _lastContentIndex = index;
            }),
            elevation: 0,
            backgroundColor: Colors.transparent,
            type: BottomNavigationBarType.fixed,
            items: const [
              BottomNavigationBarItem(
                icon: Icon(Icons.home_rounded),
                label: 'Mi Plan',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.restaurant_rounded),
                label: 'Mi Dieta',
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _currentTitle() {
    switch (_currentIndex) {
      case 1:
        return 'Mi dieta';
      case 2:
        return 'Configuración';
      default:
        return 'Healthy-T';
    }
  }

  Color get _primaryTextColor =>
      _isLightMode ? const Color(0xFF101113) : const Color(0xFFFFFFFF);
  Color get _secondaryTextColor =>
      _isLightMode ? const Color(0xFF5E6670) : const Color(0xFFD4DAE1);
  Color get _glassBaseColor =>
      _isLightMode ? const Color(0xFFF5F7F9) : const Color(0xFF101317);
  Color get _glassBorderColor => _isLightMode
      ? const Color(0xFFCAD2DA).withOpacity(0.72)
      : Colors.transparent;
  Color get _pageOrbColor => _isLightMode
      ? const Color(0xFFDCE4EB).withOpacity(0.70)
      : Colors.white.withOpacity(0.045);

  List<Color> get _pageGradientColors => _isLightMode
      ? const [Color(0xFFE9EDF1), Color(0xFFDDE4EA), Color(0xFFD2DBE3)]
      : const [Color(0xFF07090B), Color(0xFF030405), Color(0xFF000000)];

  Widget _buildGlassContainer({
    required Widget child,
    EdgeInsetsGeometry padding = EdgeInsets.zero,
    EdgeInsetsGeometry margin = EdgeInsets.zero,
    double borderRadius = 24,
    bool highlighted = false,
  }) {
    return Container(
      margin: margin,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(borderRadius),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  _glassBaseColor.withOpacity(
                    _isLightMode
                        ? (highlighted ? 0.72 : 0.54)
                        : (highlighted ? 0.92 : 0.82),
                  ),
                  _glassBaseColor.withOpacity(
                    _isLightMode
                        ? (highlighted ? 0.30 : 0.22)
                        : (highlighted ? 0.70 : 0.54),
                  ),
                ],
              ),
              border: Border.all(
                color: highlighted
                    ? _glassBorderColor
                    : _glassBorderColor.withOpacity(_isLightMode ? 0.62 : 0),
              ),
              boxShadow: _isLightMode
                  ? [
                      BoxShadow(
                        color: const Color(0xFFB8C4D1).withOpacity(0.22),
                        blurRadius: 24,
                        offset: const Offset(0, 12),
                      ),
                    ]
                  : [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.88),
                        blurRadius: highlighted ? 38 : 28,
                        offset: const Offset(0, 18),
                      ),
                      BoxShadow(
                        color: Colors.white.withOpacity(
                          highlighted ? 0.055 : 0.032,
                        ),
                        blurRadius: highlighted ? 22 : 16,
                        offset: const Offset(0, -4),
                      ),
                    ],
            ),
            child: IconTheme(
              data: IconThemeData(color: _primaryTextColor),
              child: DefaultTextStyle.merge(
                style: TextStyle(color: _primaryTextColor),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      appBar: AppBar(
        leading: Padding(
          padding: const EdgeInsets.only(left: 8.0),
          child: _buildToolbarMenu(),
        ),
        title: Text(
          _currentTitle(),
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.6,
          ),
        ),
      ),
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: _pageGradientColors,
              ),
            ),
          ),
          Positioned(
            top: -50,
            right: -20,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _pageOrbColor,
              ),
            ),
          ),
          Positioned(
            top: 140,
            left: -40,
            child: Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _isLightMode
                    ? const Color(0xFFDCE7F3).withOpacity(0.62)
                    : Colors.white.withOpacity(0.035),
              ),
            ),
          ),
          isLoading
              ? Center(
                  child: CircularProgressIndicator(color: _primaryTextColor),
                )
              : _currentIndex == 0
              ? _buildMainPlanView()
              : _currentIndex == 1
              ? _buildDietPlanView()
              : _buildConfigView(),
        ],
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: _buildGlassNavBar(),
      ),
    );
  }

  Widget _buildWorkoutCard(
    Map<String, dynamic> workout, {
    bool isToday = false,
    double? fixedHeight,
  }) {
    final exercisesCount =
        (workout['exercises'] as List?)?.whereType<Map>().length ?? 0;
    final workoutId = workout['id']?.toString() ?? '';
    final bool hasActiveSession = _activeSessions.containsKey(workoutId);
    final sessionState = _activeSessions[workoutId];
    final title = workout['name']?.toString() ?? 'Rutina';
    final subtitle = hasActiveSession
        ? 'EN PROGRESO • Ejercicio ${(sessionState?["exerciseIndex"] ?? 0) + 1}'
        : '${_getWeekdayName(int.tryParse(workout['day_of_week']?.toString() ?? ''))} • $exercisesCount ejercicios';

    Widget leadingIcon() {
      return Container(
        width: isToday ? 92 : 62,
        height: isToday ? 92 : 62,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _isLightMode
              ? const Color(0xFF101113).withOpacity(0.08)
              : Colors.white.withOpacity(0.12),
          border: _isLightMode ? null : null,
        ),
        child: Icon(
          Icons.fitness_center,
          color: _primaryTextColor,
          size: isToday ? 42 : 27,
        ),
      );
    }

    Widget playButton() {
      return IconButton(
        icon: Icon(
          hasActiveSession
              ? Icons.replay_circle_filled_rounded
              : Icons.play_circle_fill_rounded,
          color: _isLightMode ? const Color(0xFF101113) : Colors.white,
          size: isToday ? 72 : 44,
        ),
        onPressed: () => _startOrResumeWorkout(workout),
      );
    }

    Widget titleBlock({required bool wide}) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: wide ? 5 : 3,
            overflow: TextOverflow.visible,
            softWrap: true,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: wide ? 31 : 20,
              color: _primaryTextColor,
              height: wide ? 1.10 : 1.14,
            ),
          ),
          SizedBox(height: wide ? 14 : 9),
          Text(
            subtitle,
            maxLines: wide ? 2 : 1,
            overflow: TextOverflow.visible,
            softWrap: true,
            style: TextStyle(
              color: hasActiveSession
                  ? (_isLightMode ? const Color(0xFF0B7A2A) : Colors.white)
                  : _secondaryTextColor,
              fontSize: wide ? 18 : 15,
              fontWeight: hasActiveSession ? FontWeight.w700 : FontWeight.w600,
              height: 1.18,
            ),
          ),
        ],
      );
    }

    final cardContent = _buildGlassContainer(
      margin: EdgeInsets.symmetric(vertical: isToday ? 14 : 7),
      padding: EdgeInsets.all(isToday ? 32 : 20),
      borderRadius: isToday ? 36 : 30,
      highlighted: isToday,
      child: InkWell(
        onTap: () => _startOrResumeWorkout(workout),
        borderRadius: BorderRadius.circular(isToday ? 36 : 30),
        child: isToday
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [leadingIcon(), const Spacer(), playButton()]),
                  const SizedBox(height: 24),
                  titleBlock(wide: true),
                ],
              )
            : Row(
                children: [
                  leadingIcon(),
                  const SizedBox(width: 18),
                  Expanded(child: titleBlock(wide: false)),
                  const SizedBox(width: 12),
                  playButton(),
                ],
              ),
      ),
    );

    if (fixedHeight == null) {
      return cardContent;
    }

    return SizedBox(height: fixedHeight, child: cardContent);
  }

  Widget _buildEditableWorkoutCard(
    Map<String, dynamic> workout, {
    VoidCallback? onDeleted,
  }) {
    return _buildGlassContainer(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      borderRadius: 22,
      child: ListTile(
        leading: Icon(Icons.edit_note, color: _primaryTextColor),
        title: Text(
          workout['name'],
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: _primaryTextColor,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4.0),
          child: Text(
            '${_getWeekdayName(int.tryParse(workout['day_of_week']?.toString() ?? ''))}\n${workout['exercises']?.length ?? 0} ejercicios',
            style: TextStyle(color: _secondaryTextColor, height: 1.4),
          ),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete, color: Colors.redAccent),
          onPressed: () => _deleteWorkout(workout['id'], onDeleted: onDeleted),
        ),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => WorkoutEditorScreen(
                workout: workout,
                currentUserEmail: widget.currentUser.email,
              ),
            ),
          );
          fetchWorkouts();
        },
      ),
    );
  }

  String _dietMealPreview(Map<dynamic, dynamic> meal) {
    return meal['notes']?.toString().trim() ?? '';
  }

  Widget _buildDietCard(Map<String, dynamic> diet, {bool isToday = false}) {
    List meals = (diet['meals'] as List?)?.whereType<Map>().toList() ?? [];

    final mealsCount = meals.length;
    double cals = 0, pro = 0, carbs = 0, fats = 0;
    for (var m in meals) {
      cals += double.tryParse(m['calories']?.toString() ?? '0') ?? 0;
      pro += double.tryParse(m['protein']?.toString() ?? '0') ?? 0;
      carbs += double.tryParse(m['carbs']?.toString() ?? '0') ?? 0;
      fats += double.tryParse(m['fats']?.toString() ?? '0') ?? 0;
    }

    return _buildGlassContainer(
      margin: EdgeInsets.symmetric(vertical: isToday ? 12 : 6),
      padding: EdgeInsets.all(isToday ? 24 : 16),
      borderRadius: isToday ? 32 : 28,
      highlighted: isToday,
      child: Row(
        children: [
          Container(
            width: isToday ? 72 : 50,
            height: isToday ? 72 : 50,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _isLightMode
                  ? const Color(0xFF101113).withOpacity(0.08)
                  : Colors.white.withOpacity(0.08),
            ),
            child: Icon(
              Icons.restaurant_rounded,
              color: _primaryTextColor,
              size: isToday ? 34 : 22,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  diet['name']?.toString() ?? 'Dieta',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: isToday ? 24 : 17,
                    color: _primaryTextColor,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${_getWeekdayName(int.tryParse(diet['day_of_week']?.toString() ?? ''))}\n$mealsCount comidas',
                  style: TextStyle(
                    color: _secondaryTextColor,
                    fontSize: isToday ? 15 : 14,
                    height: 1.4,
                  ),
                ),
                if (mealsCount > 0) ...[
                  const SizedBox(height: 8),
                  if (cals > 0 || pro > 0 || carbs > 0 || fats > 0) ...[
                    Text(
                      '${cals.toInt()} kcal\nP ${pro.toInt()}g • H ${carbs.toInt()}g • G ${fats.toInt()}g',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: isToday ? 14 : 13,
                        color: _primaryTextColor,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  ...meals.map((meal) {
                    bool isExpanded = false;
                    final preview = _dietMealPreview(meal is Map ? meal : {});
                    return StatefulBuilder(
                      builder: (context, setState) => GestureDetector(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          setState(() => isExpanded = !isExpanded);
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.only(
                            top: 8,
                            bottom: 8,
                            left: 8,
                            right: 8,
                          ),
                          decoration: BoxDecoration(
                            color: isExpanded
                                ? (_isLightMode
                                      ? const Color(
                                          0xFF101113,
                                        ).withOpacity(0.06)
                                      : Colors.white.withOpacity(0.08))
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                meal['name']?.toString() ?? 'Comida',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: _primaryTextColor,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (preview.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 3),
                                  child: AnimatedSize(
                                    duration: const Duration(milliseconds: 250),
                                    curve: Curves.easeInOut,
                                    alignment: Alignment.topCenter,
                                    child: _buildDietPreviewText(
                                      preview,
                                      isExpanded: isExpanded,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDietPreviewText(String preview, {required bool isExpanded}) {
    return _DietOptionTable(
      text: preview,
      isExpanded: isExpanded,
      collapsedRows: 3,
    );
  }

  Widget _buildEditableDietCard(
    Map<String, dynamic> diet, {
    VoidCallback? onDeleted,
  }) {
    final meals =
        (diet['meals'] as List?)
            ?.whereType<Map>()
            .map((meal) => Map<String, dynamic>.from(meal))
            .toList() ??
        <Map<String, dynamic>>[];

    return _buildGlassContainer(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      borderRadius: 22,
      child: Column(
        children: [
          ListTile(
            leading: Icon(Icons.edit_note, color: _primaryTextColor),
            title: Text(
              diet['name'],
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: _primaryTextColor,
              ),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4.0),
              child: Text(
                '${_getWeekdayName(int.tryParse(diet['day_of_week']?.toString() ?? ''))}\n${meals.length} comidas',
                style: TextStyle(color: _secondaryTextColor, height: 1.4),
              ),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.delete, color: Colors.redAccent),
              onPressed: () => _deleteDiet(diet['id'], onDeleted: onDeleted),
            ),
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DietEditorScreen(
                    diet: diet,
                    currentUserEmail: widget.currentUser.email,
                  ),
                ),
              );
              fetchDiets();
            },
          ),
          if (meals.isNotEmpty) ...[
            Divider(
              color: _isLightMode
                  ? const Color(0xFF101113).withOpacity(0.10)
                  : Colors.white12,
              height: 8,
            ),
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: meals.length,
              onReorder: (oldIndex, newIndex) =>
                  _reorderDietMeal(diet, oldIndex, newIndex),
              itemBuilder: (context, index) {
                final meal = meals[index];
                return Container(
                  key: ValueKey(
                    '${diet['id']}_${meal['id'] ?? meal['name']}_$index',
                  ),
                  margin: const EdgeInsets.symmetric(vertical: 5),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: _isLightMode
                        ? const Color(0xFF101113).withOpacity(0.04)
                        : Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _isLightMode
                          ? const Color(0xFF101113).withOpacity(0.08)
                          : Colors.white.withOpacity(0.06),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 26,
                        height: 26,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _isLightMode
                              ? const Color(0xFF101113).withOpacity(0.08)
                              : Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Text(
                          '${index + 1}',
                          style: TextStyle(
                            color: _primaryTextColor,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          meal['name']?.toString() ?? 'Comida',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: _primaryTextColor,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      ReorderableDragStartListener(
                        index: index,
                        child: Icon(
                          Icons.drag_handle_rounded,
                          color: _secondaryTextColor,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}
