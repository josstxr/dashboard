part of 'main.dart';

class HealthService {
  // Instancia principal de Health
  final Health health = Health();
  bool _isConfigured = false;

  Future<void> _ensureConfigured() async {
    if (_isConfigured || kIsWeb) {
      return;
    }
    await health.configure();
    _isConfigured = true;
  }

  Future<bool> initAndRequestPermissions() async {
    // Omitir Apple Health si estamos en la Web (PWA)
    if (kIsWeb) {
      debugPrint("Apple Health no está soportado en la versión Web (PWA).");
      return false;
    }

    final types = [
      HealthDataType.STEPS,
      HealthDataType.APPLE_STAND_HOUR,
      HealthDataType.ACTIVE_ENERGY_BURNED,
      HealthDataType.DIETARY_ENERGY_CONSUMED,
      HealthDataType.DIETARY_PROTEIN_CONSUMED,
      HealthDataType.DIETARY_CARBS_CONSUMED,
      HealthDataType.DIETARY_FATS_CONSUMED,
      HealthDataType.WORKOUT,
      HealthDataType.EXERCISE_TIME,
      HealthDataType.SLEEP_ASLEEP,
      HealthDataType.SLEEP_DEEP,
      HealthDataType.SLEEP_LIGHT,
      HealthDataType.SLEEP_REM,
      HealthDataType.SLEEP_UNKNOWN,
      HealthDataType.SLEEP_IN_BED,
      HealthDataType.RESTING_HEART_RATE,
    ];

    final permissions = [
      HealthDataAccess.READ,
      HealthDataAccess.READ,
      HealthDataAccess.READ,
      HealthDataAccess.WRITE,
      HealthDataAccess.WRITE,
      HealthDataAccess.WRITE,
      HealthDataAccess.WRITE,
      HealthDataAccess.WRITE,
      HealthDataAccess.READ,
      HealthDataAccess.READ,
      HealthDataAccess.READ,
      HealthDataAccess.READ,
      HealthDataAccess.READ,
      HealthDataAccess.READ,
      HealthDataAccess.READ,
      HealthDataAccess.READ,
    ];

    try {
      await _ensureConfigured();
      // Solicitamos la pantalla de permisos nativa de iOS
      return await health.requestAuthorization(types, permissions: permissions);
    } catch (e) {
      debugPrint("Error solicitando permisos de salud: $e");
      return false;
    }
  }

  // Ejemplo para guardar un alimento procesado con IA a Apple Health
  Future<void> saveMealToHealth(Map<String, dynamic> meal) async {
    if (kIsWeb) return;

    try {
      await _ensureConfigured();
      final now = DateTime.now();

      final calories =
          double.tryParse(meal['calories']?.toString() ?? '0') ?? 0;
      final protein = double.tryParse(meal['protein']?.toString() ?? '0') ?? 0;
      final carbs = double.tryParse(meal['carbs']?.toString() ?? '0') ?? 0;
      final fats = double.tryParse(meal['fats']?.toString() ?? '0') ?? 0;

      if (calories > 0) {
        await health.writeHealthData(
          value: calories,
          type: HealthDataType.DIETARY_ENERGY_CONSUMED,
          startTime: now,
          endTime: now,
        );
      }
      if (protein > 0) {
        await health.writeHealthData(
          value: protein,
          type: HealthDataType.DIETARY_PROTEIN_CONSUMED,
          startTime: now,
          endTime: now,
        );
      }
      if (carbs > 0) {
        await health.writeHealthData(
          value: carbs,
          type: HealthDataType.DIETARY_CARBS_CONSUMED,
          startTime: now,
          endTime: now,
        );
      }
      if (fats > 0) {
        await health.writeHealthData(
          value: fats,
          type: HealthDataType.DIETARY_FATS_CONSUMED,
          startTime: now,
          endTime: now,
        );
      }
    } catch (e) {
      print("Error guardando en Apple Health: $e");
    }
  }

  // Guarda una rutina terminada en Apple Health
  Future<void> saveWorkoutToHealth(
    String name,
    DateTime start,
    DateTime end,
  ) async {
    if (kIsWeb) return;

    try {
      await _ensureConfigured();
      if (end.difference(start).inMinutes < 1) return;

      await health.writeWorkoutData(
        activityType: HealthWorkoutActivityType.TRADITIONAL_STRENGTH_TRAINING,
        start: start,
        end: end,
        title: name,
      );
    } catch (e) {
      print("Error guardando rutina en Apple Health: $e");
    }
  }

  // Obtiene los pasos registrados entre un tiempo de inicio y fin
  Future<int> getStepsDuringInterval(
    DateTime startTime,
    DateTime endTime,
  ) async {
    if (kIsWeb) return 0;

    try {
      await _ensureConfigured();
      final steps = await health.getTotalStepsInInterval(startTime, endTime);
      return steps ?? 0;
    } catch (e) {
      print("Error leyendo pasos de Apple Health: $e");
      return 0;
    }
  }

  Future<RecoverySnapshot> getRecoverySnapshot() async {
    if (kIsWeb) {
      return const RecoverySnapshot(
        sleepHours: 0,
        restHoursSinceWorkout: 0,
        stepCount: 0,
        activeEnergyKcal: 0,
        exerciseMinutes: 0,
        standHours: 0,
        restingHeartRate: 0,
        recommendedRestHours: 8,
        lastWorkoutEnd: null,
        sourceSummary: 'No disponible en web',
        status: 'No disponible en web',
        recommendation:
            'Abre la app iOS/Android instalada para vincular datos del teléfono.',
        hasHealthData: false,
      );
    }

    try {
      await _ensureConfigured();
      final now = DateTime.now();
      final sleepStart = now.subtract(const Duration(hours: 36));
      final workoutStart = now.subtract(const Duration(days: 14));
      final todayStart = DateTime(now.year, now.month, now.day);

      List<HealthDataPoint> sleepPoints = [];
      List<HealthDataPoint> workoutPoints = [];
      List<HealthDataPoint> energyPoints = [];
      List<HealthDataPoint> exerciseTimePoints = [];
      List<HealthDataPoint> standPoints = [];
      List<HealthDataPoint> heartPoints = [];
      List<HealthDataPoint> stepPoints = [];
      var stepCount = 0;

      try {
        sleepPoints = await health.getHealthDataFromTypes(
          types: const [
            HealthDataType.SLEEP_DEEP,
            HealthDataType.SLEEP_LIGHT,
            HealthDataType.SLEEP_REM,
            HealthDataType.SLEEP_ASLEEP,
            HealthDataType.SLEEP_UNKNOWN,
            HealthDataType.SLEEP_IN_BED,
          ],
          startTime: sleepStart,
          endTime: now,
        );
      } catch (e) {
        debugPrint("No pude leer sueño de Salud: $e");
      }

      try {
        workoutPoints = await health.getHealthDataFromTypes(
          types: const [HealthDataType.WORKOUT],
          startTime: workoutStart,
          endTime: now,
        );
      } catch (e) {
        debugPrint("No pude leer entrenamientos de Salud: $e");
      }

      try {
        stepPoints = await health.getHealthDataFromTypes(
          types: const [HealthDataType.STEPS],
          startTime: todayStart,
          endTime: now,
        );
        stepCount = await health.getTotalStepsInInterval(todayStart, now) ?? 0;
      } catch (e) {
        debugPrint("No pude leer pasos de Salud: $e");
      }

      try {
        energyPoints = await health.getHealthDataFromTypes(
          types: const [HealthDataType.ACTIVE_ENERGY_BURNED],
          startTime: todayStart,
          endTime: now,
        );
      } catch (e) {
        debugPrint("No pude leer calorías activas de Salud: $e");
      }

      try {
        exerciseTimePoints = await health.getHealthDataFromTypes(
          types: const [HealthDataType.EXERCISE_TIME],
          startTime: todayStart,
          endTime: now,
        );
      } catch (e) {
        debugPrint("No pude leer minutos de ejercicio de Salud: $e");
      }

      try {
        standPoints = await health.getHealthDataFromTypes(
          types: const [HealthDataType.APPLE_STAND_HOUR],
          startTime: todayStart,
          endTime: now,
        );
      } catch (e) {
        debugPrint("No pude leer horas de pie de Salud: $e");
      }

      try {
        heartPoints = await health.getHealthDataFromTypes(
          types: const [HealthDataType.RESTING_HEART_RATE],
          startTime: todayStart,
          endTime: now,
        );
      } catch (e) {
        debugPrint("No pude leer frecuencia cardiaca de Salud: $e");
      }

      final sleepMinutes = _sleepMinutesFromPoints(sleepPoints);
      final lastWorkoutEnd = workoutPoints
          .map((point) => point.dateTo)
          .where((date) => date.isBefore(now) || date.isAtSameMomentAs(now))
          .fold<DateTime?>(null, (latest, date) {
            if (latest == null || date.isAfter(latest)) return date;
            return latest;
          });

      final sleepHours = sleepMinutes / 60.0;
      final activeEnergyKcal = _sumNumericHealthValues(energyPoints);
      final exerciseMinutes = _sumNumericHealthValues(exerciseTimePoints);
      final standHours = _sumNumericHealthValues(standPoints);
      final restingHeartRate = _latestNumericHealthValue(heartPoints);
      final sourceSummary = _sourceSummaryFromPoints([
        ...stepPoints,
        ...energyPoints,
        ...exerciseTimePoints,
        ...standPoints,
        ...heartPoints,
        ...sleepPoints,
        ...workoutPoints,
      ]);
      final restHours = lastWorkoutEnd == null
          ? 0.0
          : now.difference(lastWorkoutEnd).inMinutes / 60.0;
      final recommendedHours = _recommendedRestHours(sleepHours, restHours);
      final ready = lastWorkoutEnd == null || restHours >= recommendedHours;

      return RecoverySnapshot(
        sleepHours: sleepHours,
        restHoursSinceWorkout: restHours,
        stepCount: stepCount,
        activeEnergyKcal: activeEnergyKcal,
        exerciseMinutes: exerciseMinutes,
        standHours: standHours,
        restingHeartRate: restingHeartRate,
        recommendedRestHours: recommendedHours,
        lastWorkoutEnd: lastWorkoutEnd,
        sourceSummary: sourceSummary,
        status: ready ? 'Listo para entrenar' : 'Salud',
        recommendation: _recoveryRecommendation(
          sleepHours: sleepHours,
          restHours: restHours,
          recommendedHours: recommendedHours,
          hasWorkout: lastWorkoutEnd != null,
        ),
        hasHealthData:
            sleepPoints.isNotEmpty ||
            workoutPoints.isNotEmpty ||
            stepCount > 0 ||
            activeEnergyKcal > 0 ||
            exerciseMinutes > 0 ||
            standHours > 0 ||
            restingHeartRate > 0,
      );
    } catch (e) {
      debugPrint("Error leyendo recuperación del teléfono: $e");
      return const RecoverySnapshot(
        sleepHours: 0,
        restHoursSinceWorkout: 0,
        stepCount: 0,
        activeEnergyKcal: 0,
        exerciseMinutes: 0,
        standHours: 0,
        restingHeartRate: 0,
        recommendedRestHours: 8,
        lastWorkoutEnd: null,
        sourceSummary: 'Apple Salud',
        status: 'Sin datos',
        recommendation:
            'Concede permisos de sueño y entrenamientos en Salud para calcular tu descanso.',
        hasHealthData: false,
      );
    }
  }

  double _sleepMinutesFromPoints(List<HealthDataPoint> points) {
    final stagedTypes = {
      HealthDataType.SLEEP_DEEP,
      HealthDataType.SLEEP_LIGHT,
      HealthDataType.SLEEP_REM,
    };
    final staged = points.where((point) => stagedTypes.contains(point.type));
    final source = staged.isNotEmpty
        ? staged
        : points.where(
            (point) =>
                point.type == HealthDataType.SLEEP_ASLEEP ||
                point.type == HealthDataType.SLEEP_UNKNOWN ||
                point.type == HealthDataType.SLEEP_IN_BED,
          );

    final intervals =
        source
            .where((point) => point.dateTo.isAfter(point.dateFrom))
            .map((point) => MapEntry(point.dateFrom, point.dateTo))
            .toList()
          ..sort((a, b) => a.key.compareTo(b.key));
    if (intervals.isEmpty) {
      return 0;
    }

    var totalMinutes = 0.0;
    var currentStart = intervals.first.key;
    var currentEnd = intervals.first.value;

    for (final interval in intervals.skip(1)) {
      if (interval.key.isAfter(currentEnd)) {
        totalMinutes += currentEnd.difference(currentStart).inMinutes;
        currentStart = interval.key;
        currentEnd = interval.value;
      } else if (interval.value.isAfter(currentEnd)) {
        currentEnd = interval.value;
      }
    }
    totalMinutes += currentEnd.difference(currentStart).inMinutes;

    return totalMinutes.clamp(0, 16 * 60);
  }

  double _sumNumericHealthValues(List<HealthDataPoint> points) {
    return points.fold<double>(0, (sum, point) {
      if (point.value is NumericHealthValue) {
        return sum +
            (point.value as NumericHealthValue).numericValue.toDouble();
      }
      return sum;
    });
  }

  double _latestNumericHealthValue(List<HealthDataPoint> points) {
    final numericPoints =
        points.where((point) => point.value is NumericHealthValue).toList()
          ..sort((a, b) => b.dateTo.compareTo(a.dateTo));
    if (numericPoints.isEmpty) {
      return 0;
    }
    return (numericPoints.first.value as NumericHealthValue).numericValue
        .toDouble();
  }

  String _sourceSummaryFromPoints(List<HealthDataPoint> points) {
    final sources = <String>{};
    for (final point in points) {
      final name = point.sourceName.trim();
      if (name.isNotEmpty) {
        sources.add(name);
      }
    }

    if (sources.isEmpty) {
      return 'Apple Salud';
    }

    final sorted = sources.toList()
      ..sort((a, b) {
        final aHuawei = a.toLowerCase().contains('huawei');
        final bHuawei = b.toLowerCase().contains('huawei');
        if (aHuawei && !bHuawei) return -1;
        if (!aHuawei && bHuawei) return 1;
        return a.compareTo(b);
      });

    if (sorted.length <= 2) {
      return sorted.join(' + ');
    }
    return '${sorted.take(2).join(' + ')} + ${sorted.length - 2} más';
  }

  int _recommendedRestHours(double sleepHours, double restHours) {
    return 8;
  }

  String _recoveryRecommendation({
    required double sleepHours,
    required double restHours,
    required int recommendedHours,
    required bool hasWorkout,
  }) {
    if (!hasWorkout) {
      return sleepHours > 0
          ? 'No encontré entrenamientos recientes. Usa el sueño y tu actividad de hoy como guía.'
          : 'Puedo leer pasos y actividad aunque falte sueño. Activa sueño/entrenamientos en Salud para una recomendación completa.';
    }

    final remaining = recommendedHours - restHours;
    if (remaining <= 0) {
      return sleepHours >= 6
          ? 'Tu descanso está dentro del rango. Puedes entrenar normal si te sientes con energía.'
          : 'Ya pasó suficiente tiempo, pero dormiste poco: baja un poco la intensidad.';
    }

    return 'Espera ${remaining.ceil()} h más o haz una sesión ligera/movilidad antes de volver a entrenar fuerte.';
  }
}

class RecoveryDetailScreen extends StatefulWidget {
  final RecoverySnapshot? initialSnapshot;
  final bool isHealthSyncEnabled;
  final String? recoveryError;
  final Future<void> Function()? onEnableHealthSync;

  const RecoveryDetailScreen({
    super.key,
    required this.initialSnapshot,
    required this.isHealthSyncEnabled,
    this.recoveryError,
    this.onEnableHealthSync,
  });

  @override
  State<RecoveryDetailScreen> createState() => _RecoveryDetailScreenState();
}

class _RecoveryDetailScreenState extends State<RecoveryDetailScreen> {
  RecoverySnapshot? _snapshot;
  late bool _isHealthSyncEnabled;
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _snapshot = widget.initialSnapshot;
    _isHealthSyncEnabled = widget.isHealthSyncEnabled;
    _error = widget.recoveryError;
    if (_isHealthSyncEnabled && _snapshot == null && !kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadSnapshot());
    }
  }

  Future<void> _loadSnapshot() async {
    if (!_isHealthSyncEnabled || kIsWeb) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final snapshot = await HealthService().getRecoverySnapshot();
      if (!mounted) return;
      setState(() => _snapshot = snapshot);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'No pude leer los datos del teléfono: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _enableHealthSync() async {
    if (widget.onEnableHealthSync == null) return;
    setState(() => _isLoading = true);
    await widget.onEnableHealthSync!();
    if (!mounted) return;
    setState(() => _isHealthSyncEnabled = true);
    await _loadSnapshot();
  }

  @override
  Widget build(BuildContext context) {
    final isLight = healthyTIsLightMode(context);
    final primaryText = healthyTPrimaryText(context);
    final secondaryText = healthyTSecondaryText(context);
    final snapshot = _snapshot;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(
          'Salud y recuperación',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _isLoading ? null : _loadSnapshot,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: healthyTPageGradient(context),
          ),
        ),
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: _loadSnapshot,
            color: primaryText,
            backgroundColor: isLight
                ? const Color(0xFFE9EDF1)
                : const Color(0xFF111214),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
              children: [
                _healthOverviewCard(context, snapshot),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _detailMetric(
                        context,
                        icon: Icons.fitness_center_rounded,
                        title: 'Registros de ejercicio',
                        value: _formatRecoveryMinutes(
                          snapshot?.exerciseMinutes ?? 0,
                        ),
                        subtitle: snapshot?.lastWorkoutEnd == null
                            ? 'Sin entrenamiento reciente'
                            : 'Último entreno registrado',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _detailMetric(
                        context,
                        icon: Icons.favorite_rounded,
                        title: 'Corazón',
                        value: _formatHeartRate(
                          snapshot?.restingHeartRate ?? 0,
                        ),
                        subtitle: 'FC en reposo',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _detailMetric(
                        context,
                        icon: Icons.bedtime_rounded,
                        title: 'Sueño',
                        value: _formatRecoveryHours(snapshot?.sleepHours ?? 0),
                        subtitle: _sleepStatus(snapshot?.sleepHours ?? 0),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _detailMetric(
                        context,
                        icon: Icons.auto_awesome_rounded,
                        title: 'Descanso',
                        value: '${snapshot?.recommendedRestHours ?? 8} h',
                        subtitle: snapshot?.lastWorkoutEnd == null
                            ? 'Sin entreno reciente'
                            : '${_formatRecoveryHours(snapshot!.restHoursSinceWorkout)} desde entreno',
                      ),
                    ),
                  ],
                ),
                if (snapshot != null || _error != null) ...[
                  const SizedBox(height: 12),
                  _detailGlass(
                    context,
                    child: Text(
                      kIsWeb
                          ? 'La web no puede leer sueño ni entrenamientos del teléfono. Abre Healthy-T instalada.'
                          : _error ??
                                '${snapshot?.recommendation ?? ''}\nFuente: ${snapshot?.sourceSummary ?? 'Apple Salud'}.',
                      style: TextStyle(
                        color: secondaryText,
                        fontSize: 13,
                        height: 1.4,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
                if ((!_isHealthSyncEnabled || snapshot == null) && !kIsWeb) ...[
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: _isLoading
                        ? null
                        : (_isHealthSyncEnabled
                              ? _loadSnapshot
                              : _enableHealthSync),
                    icon: Icon(
                      _isHealthSyncEnabled
                          ? Icons.refresh_rounded
                          : Icons.link_rounded,
                    ),
                    label: Text(
                      _isHealthSyncEnabled
                          ? 'Actualizar datos'
                          : 'Vincular teléfono',
                    ),
                  ),
                ],
                if (_isLoading) ...[
                  const SizedBox(height: 18),
                  Center(child: CircularProgressIndicator(color: primaryText)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _healthOverviewCard(BuildContext context, RecoverySnapshot? snapshot) {
    final primaryText = healthyTPrimaryText(context);
    final secondaryText = healthyTSecondaryText(context);
    final movement = snapshot?.activeEnergyKcal ?? 0;
    final exercise = snapshot?.exerciseMinutes ?? 0;
    final stand = snapshot?.standHours ?? 0;
    final steps = snapshot?.stepCount ?? 0;

    return _detailGlass(
      context,
      highlighted: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  snapshot?.status ??
                      (_isHealthSyncEnabled
                          ? 'Datos de salud'
                          : 'Vincula tu teléfono'),
                  style: TextStyle(
                    color: primaryText,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    height: 1.05,
                  ),
                ),
              ),
              Icon(Icons.health_and_safety_rounded, color: primaryText),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _activityValue(
                  context,
                  color: const Color(0xFFFF5A3D),
                  label: 'Movimiento',
                  value: movement <= 0 ? '--' : movement.round().toString(),
                  unit: 'kcal',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _activityValue(
                  context,
                  color: const Color(0xFFFFB72E),
                  label: 'Ejercicio',
                  value: exercise <= 0 ? '--' : exercise.round().toString(),
                  unit: 'min',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _activityValue(
                  context,
                  color: const Color(0xFF4388FF),
                  label: 'De pie',
                  value: stand <= 0 ? '--' : stand.round().toString(),
                  unit: 'h',
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: primaryText.withOpacity(0.06),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.directions_walk_rounded,
                  color: Color(0xFF42C46B),
                  size: 22,
                ),
                const SizedBox(width: 10),
                Text(
                  'Pasos de hoy',
                  style: TextStyle(
                    color: secondaryText,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    steps <= 0 ? '--' : _formatDetailedSteps(steps),
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: primaryText,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _activityValue(
    BuildContext context, {
    required Color color,
    required String label,
    required String value,
    required String unit,
  }) {
    final primaryText = healthyTPrimaryText(context);
    final secondaryText = healthyTSecondaryText(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: secondaryText,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            color: primaryText,
            fontSize: 26,
            fontWeight: FontWeight.w900,
            height: 1,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          unit,
          style: TextStyle(
            color: secondaryText,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _detailGlass(
    BuildContext context, {
    required Widget child,
    bool highlighted = false,
  }) {
    final isLight = healthyTIsLightMode(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            color: isLight
                ? Colors.white.withOpacity(highlighted ? 0.70 : 0.54)
                : const Color(
                    0xFF020303,
                  ).withOpacity(highlighted ? 0.88 : 0.76),
            border: Border.all(
              color: isLight
                  ? Colors.white.withOpacity(0.78)
                  : Colors.transparent,
            ),
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _detailMetric(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String value,
    required String subtitle,
    bool wide = false,
  }) {
    final primaryText = healthyTPrimaryText(context);
    final secondaryText = healthyTSecondaryText(context);
    return _detailGlass(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: primaryText, size: 26),
          const SizedBox(height: 14),
          Text(
            title,
            style: TextStyle(
              color: secondaryText,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: primaryText,
              fontSize: wide ? 30 : 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: TextStyle(color: secondaryText, fontSize: 12, height: 1.3),
          ),
        ],
      ),
    );
  }

  String _formatRecoveryHours(double hours) {
    if (hours <= 0) return '--';
    if (hours < 1) return '${(hours * 60).round()} min';
    return '${hours.toStringAsFixed(hours >= 10 ? 0 : 1)} h';
  }

  String _formatRecoveryMinutes(double minutes) {
    if (minutes <= 0) return '--';
    final total = minutes.round();
    if (total < 60) return '$total min';
    return '${total ~/ 60} h, ${total % 60} min';
  }

  String _formatHeartRate(double bpm) {
    if (bpm <= 0) return '--';
    return '${bpm.round()} p. p. m.';
  }

  String _sleepStatus(double hours) {
    if (hours <= 0) return 'Sin datos de sueño';
    if (hours < 5) return 'Sueño insuficiente';
    if (hours < 6.5) return 'Sueño bajo';
    if (hours < 8) return 'Sueño adecuado';
    return 'Sueño sólido';
  }

  String _formatDetailedSteps(int steps) {
    return steps.toString().replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (match) => '${match.group(1)},',
    );
  }
}
