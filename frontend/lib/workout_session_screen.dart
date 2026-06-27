import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:ui';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'main.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter/foundation.dart'; // Importante para usar kIsWeb
import 'package:supabase_flutter/supabase_flutter.dart';
import 'notification_logo_attachment_stub.dart'
    if (dart.library.io) 'notification_logo_attachment_io.dart';
import 'web_rest_notification_service_stub.dart'
    if (dart.library.html) 'web_rest_notification_service_web.dart';

class WorkoutSessionScreen extends StatefulWidget {
  final Map workout;
  final Map<String, int>? initialState;
  final Future<void> Function(int exerciseIndex, Map<String, dynamic> exercise)?
  onExercisePrRegistered;

  const WorkoutSessionScreen({
    super.key,
    required this.workout,
    this.initialState,
    this.onExercisePrRegistered,
  });

  @override
  State<WorkoutSessionScreen> createState() => _WorkoutSessionScreenState();
}

class _WorkoutSessionScreenState extends State<WorkoutSessionScreen>
    with WidgetsBindingObserver {
  int currentExerciseIndex = 0;
  int currentSet = 1;

  bool _isWarmUp = true;
  int _warmUpSet = 1;

  int _remainingTime = 0;
  int _initialRestTime = 1;
  DateTime? _restEndTime;
  Timer? _timer;
  Timer? _restAutoAdvanceTimer;
  Timer? _islandActionPoller;
  bool _isSyncingTimerState = false;
  bool _isRestTickInFlight = false;
  bool _isApplyingIslandAction = false;
  bool _isSeekingRestProgress = false;
  bool _isResting = false;
  bool _isTimerPaused = false;
  DateTime? _pauseTime;
  DateTime? _lastStepAdvanceAt;
  bool _canPop = false;

  // Define el MethodChannel con el mismo nombre que en AppDelegate.swift
  static const _workoutChannel = MethodChannel('com.josh.workout/timer');
  static const _wearableChannel = MethodChannel('com.aureadesign/wearable');

  // Variables para el tracking de cardio
  DateTime? _cardioStartTime;
  int _currentCardioSteps = 0;
  Timer? _stepUpdateTimer;
  Timer? _watchSyncTimer;
  late DateTime _sessionStartedAt;
  bool _isSyncingWatchState = false;
  bool _isWearableChannelUnavailable = false;

  static const int _restFinishedNotificationId = 0;
  static const int _watchWorkoutNotificationId = 1;
  static const String _androidNotificationIcon = 'ic_notification';

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  final WebRestNotificationService _webRestNotifications =
      WebRestNotificationService();

  bool get _isLightMode => Theme.of(context).brightness == Brightness.light;
  Color get _primaryTextColor => healthyTPrimaryText(context);
  Color get _secondaryTextColor => healthyTSecondaryText(context);
  Color get _panelBaseColor => healthyTGlassBase(context);
  Color get _panelBorderColor => healthyTGlassBorder(context);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sessionStartedAt = DateTime.now();

    // 🔥 Escuchar botones presionados desde la Isla Dinámica (Swift)
    _workoutChannel.setMethodCallHandler(_handleNativeMethodCall);
    _wearableChannel.setMethodCallHandler(_handleWearableMethodCall);

    if (!kIsWeb) {
      tz.initializeTimeZones();
      _initNotifications();
    } else {
      unawaited(_webRestNotifications.requestPermission());
    }

    if (widget.initialState != null) {
      currentExerciseIndex = widget.initialState!['exerciseIndex'] ?? 0;
      currentSet = widget.initialState!['set'] ?? 1;
      _isWarmUp = widget.initialState!['isWarmUp'] == 1;
      _warmUpSet = widget.initialState!['warmUpSet'] ?? 1;
      _isTimerPaused = widget.initialState!['isPaused'] == 1;

      int savedTime = widget.initialState!['remainingTime'] ?? 0;
      final savedRestEndTime = widget.initialState!['restEndTime'];
      if (kIsWeb && savedRestEndTime != null && !_isTimerPaused) {
        final endTime = DateTime.fromMillisecondsSinceEpoch(savedRestEndTime);
        savedTime = (endTime.difference(DateTime.now()).inSeconds + 1)
            .clamp(0, 1 << 30)
            .toInt();
        _restEndTime = savedTime > 0 ? endTime : DateTime.now();
        if (savedTime <= 0) {
          savedTime = 1;
        }
      }

      if (savedTime > 0) {
        _remainingTime = savedTime;
        _isResting = true;
        if (!kIsWeb) {
          _isTimerPaused =
              true; // Se pausa automáticamente al regresar de la lista
          _restEndTime = null;
        }
        _startTimerSyncLoop();
        _scheduleRestAutoAdvanceTimer();
      }
    }
    _islandActionPoller = Timer.periodic(const Duration(milliseconds: 250), (
      _,
    ) {
      _consumePendingIslandAction();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncWebRestTimer();
      _updateDynamicIsland();
      _startWatchSyncLoop();
      _syncWorkoutToWatch(force: true);
      _consumePendingIslandAction();
    });
  }

  // Llama a esto cuando el usuario le dé "Play" o inicie el ejercicio de Cardio
  void _startCardioTracking() {
    _cardioStartTime = DateTime.now();
    _currentCardioSteps = 0;

    // Actualizamos los pasos consultando a Apple Health cada 5 segundos
    _stepUpdateTimer = Timer.periodic(const Duration(seconds: 5), (
      timer,
    ) async {
      if (_cardioStartTime != null) {
        int steps = await HealthService().getStepsDuringInterval(
          _cardioStartTime!,
          DateTime.now(),
        );
        if (mounted) {
          setState(() {
            _currentCardioSteps = steps;
          });
        }
      }
    });
  }

  // Llama a esto cuando se pause o termine el ejercicio
  void _stopCardioTracking() {
    _stepUpdateTimer?.cancel();
  }

  int _parsePositiveInt(dynamic value, {required int fallback}) {
    if (value is num) {
      return value.toInt() > 0 ? value.toInt() : fallback;
    }

    final parsed = int.tryParse(value?.toString().trim() ?? '');
    if (parsed == null || parsed <= 0) {
      return fallback;
    }
    return parsed;
  }

  // -------------------------
  // 🔥 RECEPCIÓN DE COMANDOS NATIVOS
  // -------------------------
  Future<dynamic> _handleNativeMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'skipRest':
        _handleSkipRest();
        break;
      case 'restFinished':
        await _handleRestFinishedFromNative();
        break;
      case 'nextStep':
        await _handleNextStepFromIsland();
        break;
      case 'pauseTimer':
        final didSync = await _syncTimerState(force: true);
        if (!didSync) {
          await _applyIslandPauseAction();
        }
        break;
      case 'resumeTimer':
        final didSync = await _syncTimerState(force: true);
        if (!didSync) {
          await _applyIslandResumeAction();
        }
        break;
      case 'stopWorkout':
        _timer?.cancel();
        _cancelRestAutoAdvanceTimer();
        unawaited(_clearWorkoutWatch());
        _endLiveActivity();
        if (mounted) Navigator.of(context).pop({'finished': 1});
        break;
    }
  }

  Future<dynamic> _handleWearableMethodCall(MethodCall call) async {
    if (call.method != 'onWatchAction') return null;

    final rawPayload = call.arguments is Map
        ? (call.arguments as Map)['payload']?.toString() ?? ''
        : call.arguments?.toString() ?? '';
    final action = rawPayload.toLowerCase();

    if (action.contains('stop')) {
      _timer?.cancel();
      unawaited(_clearWorkoutWatch());
      _endLiveActivity();
      if (mounted) Navigator.of(context).pop({'finished': 1});
      return null;
    }

    if (action.contains('next') ||
        action.contains('siguiente') ||
        action.contains('skip')) {
      await _handleNextStepFromIsland();
      return null;
    }

    if (action.contains('pause') || action.contains('pausa')) {
      await _applyIslandPauseAction();
      await _updateDynamicIsland();
      return null;
    }

    if (action.contains('resume') ||
        action.contains('reanudar') ||
        action.contains('play')) {
      await _applyIslandResumeAction();
      await _updateDynamicIsland();
    }

    return null;
  }

  void _initNotifications() async {
    if (kIsWeb) return;

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings(_androidNotificationIcon);
    const DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings(
          requestAlertPermission: true,
          requestSoundPermission: true,
        );
    const InitializationSettings initializationSettings =
        InitializationSettings(
          android: initializationSettingsAndroid,
          iOS: initializationSettingsIOS,
        );
    await _localNotifications.initialize(initializationSettings);
    await _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
  }

  Future<void> _scheduleRestNotification(int seconds) async {
    if (kIsWeb) {
      await _webRestNotifications.scheduleRestFinishedNotification(
        seconds,
        body: _restFinishedNotificationBody(),
      );
      return;
    }

    await _localNotifications.cancel(_restFinishedNotificationId);
    if (seconds <= 0) return;

    final scheduledTime = tz.TZDateTime.now(
      tz.local,
    ).add(Duration(seconds: seconds));

    await _localNotifications.zonedSchedule(
      _restFinishedNotificationId,
      '¡Descanso terminado!',
      _restFinishedNotificationBody(),
      scheduledTime,
      await _restFinishedNotificationDetails(),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  String _restFinishedNotificationBody() {
    final nextStep = _nextWorkoutStepTitle(prefix: 'Siguiente');
    if (nextStep.toLowerCase().trim() == 'siguiente: fin') {
      return 'Último descanso terminado. Cierra la rutina cuando estés listo.';
    }

    return '$nextStep. Es hora de continuar.';
  }

  Future<NotificationDetails> _restFinishedNotificationDetails() async {
    final logoPath = await healthyTNotificationLogoPath();
    final iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentSound: true,
      sound: 'default',
      attachments: logoPath == null
          ? null
          : [
              DarwinNotificationAttachment(
                logoPath,
                identifier: 'healthy_t_logo',
              ),
            ],
      subtitle: 'Healty-T',
      threadIdentifier: 'healthy_t_workout_rest',
    );
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          'workout_rest_alerts_v1',
          'Alertas de descanso',
          channelDescription: 'Avisa cuando termina un descanso de la rutina.',
          icon: _androidNotificationIcon,
          largeIcon: DrawableResourceAndroidBitmap('launcher_icon'),
          importance: Importance.max,
          priority: Priority.high,
          category: AndroidNotificationCategory.alarm,
          enableVibration: true,
          color: Color(0xFF101113),
        );
    return NotificationDetails(android: androidDetails, iOS: iosDetails);
  }

  Future<void> _showRestFinishedNotificationNow() async {
    if (kIsWeb) return;

    await _localNotifications.cancel(_restFinishedNotificationId);
    await _localNotifications.show(
      _restFinishedNotificationId,
      '¡Descanso terminado!',
      _restFinishedNotificationBody(),
      await _restFinishedNotificationDetails(),
    );
  }

  Future<void> _finishRestNotifications() async {
    if (kIsWeb) return;
    await _localNotifications.cancel(_watchWorkoutNotificationId);
    await _showRestFinishedNotificationNow();
  }

  Future<void> _cancelWorkoutNotifications({bool includeWatch = true}) async {
    if (kIsWeb) return;
    await _localNotifications.cancel(_restFinishedNotificationId);
    if (includeWatch) {
      await _localNotifications.cancel(_watchWorkoutNotificationId);
    }
  }

  void _startWatchSyncLoop() {
    if (kIsWeb) return;
    _watchSyncTimer?.cancel();
    _watchSyncTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      unawaited(_syncWorkoutToWatch());
    });
  }

  Map<String, dynamic> _watchWorkoutStatePayload({
    String event = 'update',
    String? modeOverride,
  }) {
    final exercises = widget.workout['exercises'] as List<dynamic>? ?? [];
    final now = DateTime.now();
    final remainingSeconds = _isResting ? _remainingTime.clamp(0, 1 << 30) : 0;
    final elapsedSeconds = now
        .difference(_sessionStartedAt)
        .inSeconds
        .clamp(0, 1 << 30);
    final mode =
        modeOverride ??
        (event == 'finished'
            ? 'finished'
            : _isResting
            ? 'rest'
            : _isTimerPaused
            ? 'paused'
            : 'session');
    final status = event == 'finished'
        ? 'Finalizado'
        : _isResting
        ? (_isTimerPaused ? 'Descanso pausado' : 'Descanso')
        : (_isTimerPaused ? 'Pausado' : 'En sesión');
    final totalWorkoutSets = exercises.fold<int>(
      0,
      (sum, exercise) => sum + _parsePositiveInt(exercise['sets'], fallback: 1),
    );
    final completedSets = exercises
        .take(currentExerciseIndex)
        .fold<int>(
          0,
          (sum, exercise) =>
              sum + _parsePositiveInt(exercise['sets'], fallback: 1),
        );

    return {
      'event': event,
      'appName': 'Healty-T',
      'appIcon': 'healthy_t',
      'mode': mode,
      'status': status,
      'workoutName': widget.workout['name']?.toString() ?? 'Rutina',
      'current': _currentWorkoutStepTitle(),
      'next': _nextWorkoutStepTitle(prefix: 'Sig'),
      'currentExerciseIndex': currentExerciseIndex,
      'currentSet': currentSet,
      'totalExercises': exercises.length,
      'totalWorkoutSets': totalWorkoutSets,
      'completedSets': completedSets + (currentSet - 1),
      'remainingSeconds': remainingSeconds,
      'initialRestSeconds': _initialRestTime,
      'elapsedSeconds': elapsedSeconds,
      'isPaused': _isTimerPaused,
      'isResting': _isResting,
      'updatedAt': now.toIso8601String(),
    };
  }

  Future<void> _syncWorkoutToWatch({
    String event = 'update',
    bool force = false,
  }) async {
    if (kIsWeb) return;
    if (_isSyncingWatchState && !force) return;

    _isSyncingWatchState = true;
    try {
      final payload = _watchWorkoutStatePayload(event: event);
      await _sendWorkoutStateToWearable(payload);
      if (event == 'finished') {
        await _localNotifications.cancel(_watchWorkoutNotificationId);
      } else {
        await _showWatchWorkoutNotification(payload);
      }
    } finally {
      _isSyncingWatchState = false;
    }
  }

  Future<void> _clearWorkoutWatch() async {
    if (kIsWeb) return;
    final payload = _watchWorkoutStatePayload(
      event: 'finished',
      modeOverride: 'finished',
    );
    await _sendWorkoutStateToWearable(payload);
    await _localNotifications.cancel(_watchWorkoutNotificationId);
  }

  Future<void> _sendWorkoutStateToWearable(Map<String, dynamic> payload) async {
    if (_isWearableChannelUnavailable ||
        defaultTargetPlatform != TargetPlatform.iOS) {
      return;
    }

    try {
      await _wearableChannel.invokeMethod('sendToWatch', jsonEncode(payload));
    } on MissingPluginException {
      _isWearableChannelUnavailable = true;
    } on PlatformException catch (e) {
      if (e.code == 'UNAVAILABLE') {
        _isWearableChannelUnavailable = true;
        return;
      }
      debugPrint("Failed to send workout state to wearable: '$e'.");
    } catch (e) {
      debugPrint("Failed to send workout state to wearable: '$e'.");
    }
  }

  Future<void> _showWatchWorkoutNotification([
    Map<String, dynamic>? payload,
  ]) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;

    final state = payload ?? _watchWorkoutStatePayload();
    if (state['event'] == 'finished') {
      await _localNotifications.cancel(_watchWorkoutNotificationId);
      return;
    }

    final isResting = state['isResting'] == true;
    final isPaused = state['isPaused'] == true;
    final remainingSeconds =
        int.tryParse(state['remainingSeconds']?.toString() ?? '') ?? 0;
    final elapsedSeconds =
        int.tryParse(state['elapsedSeconds']?.toString() ?? '') ?? 0;
    final timerLabel = isResting
        ? '${_formatTime(remainingSeconds)} restantes'
        : '${_formatTime(elapsedSeconds)} en sesión';
    final body = [
      timerLabel,
      state['current']?.toString() ?? _currentWorkoutStepTitle(),
      state['next']?.toString() ?? _nextWorkoutStepTitle(prefix: 'Sig'),
    ].join(' · ');
    final chronometerAt = isResting
        ? DateTime.now().add(Duration(seconds: remainingSeconds))
        : _sessionStartedAt;

    final AndroidNotificationDetails
    androidDetails = AndroidNotificationDetails(
      'workout_watch_timer_v1',
      'Workout en reloj',
      channelDescription:
          'Muestra temporizadores, ejercicio actual y progreso en el reloj.',
      icon: _androidNotificationIcon,
      largeIcon: const DrawableResourceAndroidBitmap('launcher_icon'),
      importance: Importance.max,
      priority: Priority.high,
      category: AndroidNotificationCategory.progress,
      color: const Color(0xFF101113),
      ongoing: true,
      autoCancel: false,
      onlyAlertOnce: true,
      showWhen: true,
      when: isPaused ? null : chronometerAt.millisecondsSinceEpoch,
      usesChronometer: !isPaused,
      chronometerCountDown: isResting && !isPaused,
      showProgress: isResting && _initialRestTime > 1,
      maxProgress: isResting ? _initialRestTime : 0,
      progress: isResting
          ? (_initialRestTime - remainingSeconds).clamp(0, _initialRestTime)
          : 0,
      styleInformation: BigTextStyleInformation(
        body,
        contentTitle: state['status']?.toString() ?? 'En sesión',
        summaryText: state['workoutName']?.toString() ?? 'Rutina',
      ),
    );

    await _localNotifications.show(
      _watchWorkoutNotificationId,
      state['status']?.toString() ?? 'En sesión',
      body,
      NotificationDetails(android: androidDetails),
    );
  }

  // -------------------------
  // 🔥 LIVE ACTIVITY CONTROL
  // -------------------------

  Future<void> _updateDynamicIsland() async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final exercises = widget.workout['exercises'] as List<dynamic>? ?? [];
    if (exercises.isEmpty) return;

    final currentName = exerciseDisplayTitle(exercises, currentExerciseIndex);
    final totalSets = _parsePositiveInt(
      exercises[currentExerciseIndex]['sets'],
      fallback: 1,
    );
    final restSeconds =
        (num.tryParse(
          (exercises[currentExerciseIndex]['rest_seconds'] ??
                  exercises[currentExerciseIndex]['rest'] ??
                  0)
              .toString(),
        )?.toInt()) ??
        0;

    String title = "";
    int end = 0;

    if (_isResting) {
      end = now + _remainingTime;
      title = 'Descanso\n${_nextWorkoutStepTitle(prefix: "Sig")}';
    } else {
      end =
          now; // Envía un tiempo válido para evitar que iOS desenfoque la vista (error de rango invertido)
      title =
          'En sesión: $currentName $currentSet/$totalSets\n${_nextWorkoutStepTitle(prefix: "Sig")}';
    }

    if (kIsWeb) {
      await _updateRemoteLiveActivity(
        title: title,
        startTime: now,
        endTime: end,
        isPaused: _isTimerPaused,
        pausedRemaining: _isTimerPaused ? _remainingTime : null,
      );
      return;
    }

    try {
      // Evaluamos si ya hay una Isla Dinámica activa
      final state = await _workoutChannel.invokeMethod<Map<dynamic, dynamic>>(
        'getTimerState',
      );
      final isActive = state != null && state['isActive'] == true;

      if (isActive) {
        // Si ya está en pantalla, solo actualizamos los datos sin cerrarla
        await _workoutChannel.invokeMethod('updateTimer', {
          'title': title,
          'startTime': now,
          'endTime': end,
          'isPaused': _isTimerPaused,
          'pausedRemaining': _isTimerPaused ? _remainingTime : null,
          'currentExerciseIndex': currentExerciseIndex,
          'currentSet': currentSet,
          'totalSets': totalSets,
          'totalExercises': exercises.length,
          'restSeconds': restSeconds,
          'isResting': _isResting,
        });
        await _registerLiveActivityToken(state);
      } else {
        // Si no existe, la creamos
        final response = await _workoutChannel
            .invokeMethod<Map<dynamic, dynamic>>('startTimer', {
              'title': title,
              'startTime': now,
              'endTime': end,
              'isPaused': _isTimerPaused,
              'pausedRemaining': _isTimerPaused ? _remainingTime : null,
              'currentExerciseIndex': currentExerciseIndex,
              'currentSet': currentSet,
              'totalSets': totalSets,
              'totalExercises': exercises.length,
              'restSeconds': restSeconds,
              'isResting': _isResting,
            });
        await _registerLiveActivityToken(response);
        unawaited(_registerLiveActivityTokenFromNative());
      }
    } catch (e) {
      debugPrint("Failed to update live activity: '$e'.");
    }
  }

  Future<void> _updateRemoteLiveActivity({
    required String title,
    required int startTime,
    required int endTime,
    required bool isPaused,
    int? pausedRemaining,
  }) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      await Supabase.instance.client.functions.invoke(
        'update-live-activity',
        body: {
          'event': 'update',
          'state': {
            'title': title,
            'startTime': startTime,
            'endTime': endTime,
            'isPaused': isPaused,
            if (pausedRemaining != null) 'pausedRemaining': pausedRemaining,
          },
        },
      );
    } catch (e) {
      debugPrint("Failed to update remote live activity: '$e'.");
    }
  }

  Future<void> _endRemoteLiveActivity() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      await Supabase.instance.client.functions.invoke(
        'update-live-activity',
        body: {'event': 'end'},
      );
    } catch (e) {
      debugPrint("Failed to end remote live activity: '$e'.");
    }
  }

  Future<void> _registerLiveActivityToken(
    Map<dynamic, dynamic>? payload,
  ) async {
    if (kIsWeb || payload == null) return;

    final user = Supabase.instance.client.auth.currentUser;
    final activityId = payload['activityId']?.toString();
    final pushToken = payload['pushToken']?.toString();
    if (user == null ||
        activityId == null ||
        activityId.isEmpty ||
        pushToken == null ||
        pushToken.isEmpty) {
      return;
    }

    try {
      await Supabase.instance.client.from('live_activity_tokens').upsert({
        'user_id': user.id,
        'activity_id': activityId,
        'push_token': pushToken,
        'platform': 'ios',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'user_id,activity_id');
    } catch (e) {
      debugPrint("Failed to register live activity token: '$e'.");
    }
  }

  Future<void> _registerLiveActivityTokenFromNative() async {
    if (kIsWeb) return;

    await Future.delayed(const Duration(seconds: 1));
    try {
      final payload = await _workoutChannel.invokeMethod<Map<dynamic, dynamic>>(
        'getLiveActivityPushToken',
      );
      await _registerLiveActivityToken(payload);
    } catch (e) {
      debugPrint("Failed to fetch live activity token: '$e'.");
    }
  }

  Future<void> _endLiveActivity() async {
    if (kIsWeb) {
      _webRestNotifications.cancelRestNotification();
      await _endRemoteLiveActivity();
      return;
    }

    try {
      await _workoutChannel.invokeMethod('stopTimer');
    } catch (e) {
      print("Failed to end live activity: '$e'.");
    }
  }

  Future<void> _pauseLiveActivity() async {
    _cancelRestAutoAdvanceTimer();
    if (kIsWeb) {
      _syncWebRestTimer(advanceOnFinish: false);
      if (mounted) {
        setState(() {
          _isTimerPaused = true;
          _restEndTime = null;
        });
      } else {
        _isTimerPaused = true;
        _restEndTime = null;
      }
      _webRestNotifications.cancelRestNotification();
      await _updateDynamicIsland();
      return;
    }

    try {
      await _workoutChannel.invokeMethod('pauseTimer');
      await _cancelWorkoutNotifications(includeWatch: false);
      final didSync = await _syncTimerState(force: true);
      if (!didSync && mounted) setState(() => _isTimerPaused = true);
      await _showWatchWorkoutNotification();
      await _syncWorkoutToWatch(force: true);
    } catch (e) {
      print("Failed to pause live activity: '$e'.");
    }
  }

  Future<void> _resumeLiveActivity() async {
    if (kIsWeb) {
      if (mounted) {
        setState(() {
          _isTimerPaused = false;
          if (_isResting && _remainingTime > 0) {
            _restEndTime = DateTime.now().add(
              Duration(seconds: _remainingTime),
            );
          }
        });
      }
      if (_isResting) {
        _scheduleRestAutoAdvanceTimer();
        await _scheduleRestNotification(_remainingTime);
      }
      await _updateDynamicIsland();
      return;
    }

    try {
      await _workoutChannel.invokeMethod('resumeTimer');
      final didSync = await _syncTimerState(force: true);
      if (!didSync && mounted) setState(() => _isTimerPaused = false);
      if (_isResting) {
        _scheduleRestAutoAdvanceTimer();
        await _scheduleRestNotification(_remainingTime);
        await _showWatchWorkoutNotification();
      }
      await _syncWorkoutToWatch(force: true);
    } catch (e) {
      print("Failed to resume live activity: '$e'.");
    }
  }

  Future<bool> _syncTimerState({bool force = false}) async {
    if (_isSyncingTimerState) return false;
    if (!force && (!_isResting || _isApplyingIslandAction)) return false;

    if (kIsWeb) return false;

    _isSyncingTimerState = true;
    try {
      final state = await _workoutChannel.invokeMethod<Map<dynamic, dynamic>>(
        'getTimerState',
      );
      if (!mounted || state == null) return false;

      final isActive = state['isActive'] == true;
      if (!isActive) {
        _timer?.cancel();
        _cancelRestAutoAdvanceTimer();
        setState(() {
          _isResting = false;
          _isTimerPaused = false;
          _remainingTime = 0;
        });
        unawaited(_syncWorkoutToWatch(force: true));
        return true;
      }

      final isPaused = state['isPaused'] == true;
      final nativeIsResting = state['isResting'] == true;
      if (!nativeIsResting) {
        _timer?.cancel();
        _cancelRestAutoAdvanceTimer();
        if (!kIsWeb) {
          unawaited(_cancelWorkoutNotifications());
        } else {
          _webRestNotifications.cancelRestNotification();
        }
        final nativeExerciseIndex = (state['currentExerciseIndex'] as num?)
            ?.toInt();
        final nativeSet = (state['currentSet'] as num?)?.toInt();
        setState(() {
          if (nativeExerciseIndex != null) {
            currentExerciseIndex = nativeExerciseIndex;
          }
          if (nativeSet != null) {
            currentSet = nativeSet;
          }
          _remainingTime = (state['pausedRemaining'] as num?)?.toInt() ?? 0;
          _isResting = false;
          _isTimerPaused = isPaused;
        });
        unawaited(_updateDynamicIsland());
        unawaited(_syncWorkoutToWatch(force: true));
        return true;
      }

      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final pausedRemaining =
          (state['pausedRemaining'] as num?)?.toInt() ?? _remainingTime;
      final endTime = (state['endTime'] as num?)?.toInt() ?? now;
      final remaining = isPaused
          ? pausedRemaining
          : ((endTime - now).clamp(0, 1 << 30) as num).toInt();

      if (remaining <= 0) {
        final exercises = widget.workout['exercises'] as List<dynamic>? ?? [];
        if (exercises.isNotEmpty) {
          final sets = _parsePositiveInt(
            exercises[currentExerciseIndex]['sets'],
            fallback: 1,
          );
          _completeRestAndAdvance(
            exercises: exercises,
            totalSets: sets,
            vibrate: false,
          );
        } else {
          _timer?.cancel();
          if (!kIsWeb) {
            unawaited(_finishRestNotifications());
          } else {
            _webRestNotifications.cancelRestNotification();
          }
          setState(() {
            _remainingTime = 0;
            _restEndTime = null;
            _isResting = false;
            _isTimerPaused = false;
          });
          unawaited(_updateDynamicIsland());
        }
        return true;
      }

      setState(() {
        _remainingTime = remaining;
        _isTimerPaused = isPaused;
        _isResting = true;
        _restEndTime = isPaused
            ? null
            : DateTime.fromMillisecondsSinceEpoch(endTime * 1000);
      });
      _scheduleRestAutoAdvanceTimer();
      unawaited(_syncWorkoutToWatch());
      return true;
    } catch (e) {
      print("Failed to sync timer state: '$e'.");
      return false;
    } finally {
      _isSyncingTimerState = false;
    }
  }

  void _startTimerSyncLoop() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      unawaited(_runRestTimerFrame());
    });
    _scheduleRestAutoAdvanceTimer();
  }

  void _scheduleRestAutoAdvanceTimer() {
    _restAutoAdvanceTimer?.cancel();
    if (!_isResting || _isTimerPaused || _remainingTime <= 0) {
      _restAutoAdvanceTimer = null;
      return;
    }

    final expectedExerciseIndex = currentExerciseIndex;
    final expectedSet = currentSet;
    final seconds = _remainingTime;

    _restAutoAdvanceTimer = Timer(Duration(seconds: seconds), () {
      if (!_isResting ||
          _isTimerPaused ||
          currentExerciseIndex != expectedExerciseIndex ||
          currentSet != expectedSet) {
        return;
      }

      final exercises = widget.workout['exercises'] as List<dynamic>? ?? [];
      if (exercises.isEmpty) {
        return;
      }

      final sets = _parsePositiveInt(
        exercises[currentExerciseIndex]['sets'],
        fallback: 1,
      );
      _remainingTime = 0;
      _completeRestAndAdvance(
        exercises: exercises,
        totalSets: sets,
        vibrate: true,
      );
    });
  }

  void _cancelRestAutoAdvanceTimer() {
    _restAutoAdvanceTimer?.cancel();
    _restAutoAdvanceTimer = null;
  }

  Future<void> _runRestTimerFrame() async {
    if (_isRestTickInFlight || _isSyncingTimerState) return;

    _isRestTickInFlight = true;
    try {
      await _consumePendingIslandAction();
      final didSync = await _syncTimerState();
      if (!didSync) {
        _tickLocalRestTimer();
      }
    } finally {
      _isRestTickInFlight = false;
    }
  }

  Future<void> _consumePendingIslandAction() async {
    if (kIsWeb) return;

    try {
      _isApplyingIslandAction = true;
      final action = await _workoutChannel.invokeMethod<String?>(
        'consumePendingAction',
      );
      if (action == null || action.isEmpty) {
        return;
      }

      switch (action) {
        case 'skipRest':
          _handleSkipRest();
          break;
        case 'restFinished':
          await _handleRestFinishedFromNative();
          break;
        case 'nextStep':
          final didSync = await _syncTimerState(force: true);
          if (!didSync) {
            await _handleNextStepFromIsland();
          }
          break;
        case 'pauseTimer':
          final didSync = await _syncTimerState(force: true);
          if (!didSync) {
            await _applyIslandPauseAction();
          }
          break;
        case 'resumeTimer':
          final didSync = await _syncTimerState(force: true);
          if (!didSync) {
            await _applyIslandResumeAction();
          }
          break;
        case 'stopWorkout':
          _timer?.cancel();
          _cancelRestAutoAdvanceTimer();
          _endLiveActivity();
          if (mounted) Navigator.of(context).pop({'finished': 1});
          break;
      }
    } catch (e) {
      debugPrint("Failed to consume island action: '$e'.");
    } finally {
      _isApplyingIslandAction = false;
    }
  }

  Future<void> _handleRestFinishedFromNative() async {
    if (_isSyncingTimerState) return;

    final didSync = await _syncTimerState(force: true);
    if (didSync || !_isResting || _remainingTime > 1) {
      return;
    }

    final exercises = widget.workout['exercises'] as List<dynamic>? ?? [];
    if (exercises.isEmpty) {
      return;
    }

    final sets = _parsePositiveInt(
      exercises[currentExerciseIndex]['sets'],
      fallback: 1,
    );
    _remainingTime = 0;
    _completeRestAndAdvance(
      exercises: exercises,
      totalSets: sets,
      vibrate: false,
    );
  }

  void _tickLocalRestTimer() {
    if (!_isResting || _isTimerPaused || _remainingTime <= 0) {
      return;
    }

    if (kIsWeb && _syncWebRestTimer()) {
      return;
    }

    final exercises = widget.workout['exercises'] as List<dynamic>? ?? [];
    if (exercises.isEmpty) {
      return;
    }

    final sets = _parsePositiveInt(
      exercises[currentExerciseIndex]['sets'],
      fallback: 1,
    );

    setState(() {
      _remainingTime--;
      if (_remainingTime <= 0) {
        _remainingTime = 0;
      }
    });

    if (_remainingTime <= 0) {
      _completeRestAndAdvance(
        exercises: exercises,
        totalSets: sets,
        vibrate: true,
      );
      return;
    }

    unawaited(_syncWorkoutToWatch());
    unawaited(_showWatchWorkoutNotification());
  }

  void _completeRestAndAdvance({
    required List<dynamic> exercises,
    required int totalSets,
    required bool vibrate,
  }) {
    _timer?.cancel();
    _cancelRestAutoAdvanceTimer();

    if (!_canAdvanceWorkoutStep()) {
      _markRestFinishedWithoutAdvancing();
      return;
    }

    if (!kIsWeb) {
      unawaited(_finishRestNotifications());
      if (vibrate) {
        HapticFeedback.heavyImpact();
      }
    } else {
      _webRestNotifications.cancelRestNotification();
    }

    final finishedWorkout = _isFinalWorkoutStep(
      totalExercises: exercises.length,
      totalSets: totalSets,
    );

    if (mounted) {
      setState(() {
        _remainingTime = 0;
        _restEndTime = null;
        _isResting = false;
        _isTimerPaused = false;
        if (!finishedWorkout) {
          _advanceWorkoutStepState(
            totalExercises: exercises.length,
            totalSets: totalSets,
          );
        }
      });
    } else {
      _remainingTime = 0;
      _restEndTime = null;
      _isResting = false;
      _isTimerPaused = false;
      if (!finishedWorkout) {
        _advanceWorkoutStepState(
          totalExercises: exercises.length,
          totalSets: totalSets,
        );
      }
    }

    if (finishedWorkout) {
      _finishWorkout();
      return;
    }

    unawaited(_updateDynamicIsland());
    unawaited(_syncWorkoutToWatch(force: true));
  }

  void _markRestFinishedWithoutAdvancing() {
    if (mounted) {
      setState(() {
        _remainingTime = 0;
        _restEndTime = null;
        _isResting = false;
        _isTimerPaused = false;
      });
    } else {
      _remainingTime = 0;
      _restEndTime = null;
      _isResting = false;
      _isTimerPaused = false;
    }

    unawaited(_updateDynamicIsland());
    unawaited(_syncWorkoutToWatch(force: true));
  }

  bool _isFinalWorkoutStep({
    required int totalExercises,
    required int totalSets,
  }) {
    return currentSet >= totalSets &&
        currentExerciseIndex >= totalExercises - 1;
  }

  bool _syncWebRestTimer({bool advanceOnFinish = true}) {
    if (!kIsWeb || !_isResting || _isTimerPaused || _restEndTime == null) {
      return false;
    }

    final remaining = _restEndTime!.difference(DateTime.now()).inSeconds + 1;
    final nextRemaining = remaining.clamp(0, 1 << 30).toInt();
    if (nextRemaining == _remainingTime && nextRemaining > 0) {
      return true;
    }

    final exercises = widget.workout['exercises'] as List<dynamic>? ?? [];
    if (exercises.isEmpty) {
      if (mounted) {
        setState(() => _remainingTime = nextRemaining);
      } else {
        _remainingTime = nextRemaining;
      }
      return true;
    }

    if (nextRemaining <= 0 && advanceOnFinish) {
      final sets = _parsePositiveInt(
        exercises[currentExerciseIndex]['sets'],
        fallback: 1,
      );
      _completeRestAndAdvance(
        exercises: exercises,
        totalSets: sets,
        vibrate: false,
      );
      return true;
    }

    if (mounted) {
      setState(() => _remainingTime = nextRemaining);
    } else {
      _remainingTime = nextRemaining;
    }
    return true;
  }

  Future<void> _applyIslandPauseAction() async {
    if (_isTimerPaused) return;
    _cancelRestAutoAdvanceTimer();
    if (!kIsWeb) {
      if (mounted) setState(() => _isTimerPaused = true);
      await _cancelWorkoutNotifications(includeWatch: false);
      await _showWatchWorkoutNotification();
    } else {
      _syncWebRestTimer(advanceOnFinish: false);
      if (mounted) {
        setState(() {
          _isTimerPaused = true;
          _restEndTime = null;
        });
      } else {
        _isTimerPaused = true;
        _restEndTime = null;
      }
      _webRestNotifications.cancelRestNotification();
    }
    await _syncWorkoutToWatch(force: true);
  }

  Future<void> _applyIslandResumeAction() async {
    if (!_isTimerPaused) return;
    if (mounted) {
      setState(() {
        _isTimerPaused = false;
        if (kIsWeb && _isResting && _remainingTime > 0) {
          _restEndTime = DateTime.now().add(Duration(seconds: _remainingTime));
        }
      });
    } else {
      _isTimerPaused = false;
      if (kIsWeb && _isResting && _remainingTime > 0) {
        _restEndTime = DateTime.now().add(Duration(seconds: _remainingTime));
      }
    }
    if (_isResting) {
      _scheduleRestAutoAdvanceTimer();
      await _scheduleRestNotification(_remainingTime);
      await _showWatchWorkoutNotification();
    }
    await _syncWorkoutToWatch(force: true);
  }

  Future<void> _pauseWorkoutForMainScreen() async {
    _timer?.cancel();
    _cancelRestAutoAdvanceTimer();

    if (!kIsWeb) {
      if (mounted) {
        setState(() => _isTimerPaused = true);
      } else {
        _isTimerPaused = true;
      }
      await _cancelWorkoutNotifications(includeWatch: false);
      await _showWatchWorkoutNotification();
      await _syncWorkoutToWatch(force: true);
      try {
        await _workoutChannel.invokeMethod('pauseTimer');
      } catch (e) {
        debugPrint("Failed to pause live activity before returning: '$e'.");
      }
    } else {
      _syncWebRestTimer(advanceOnFinish: false);
      await _updateDynamicIsland();
    }
  }

  // -------------------------
  // 🔥 TIMER
  // -------------------------

  void _avanzarSerieOEjercicio(int totalExercises, int totalSets) {
    if (!_canAdvanceWorkoutStep()) return;

    if (_isFinalWorkoutStep(
      totalExercises: totalExercises,
      totalSets: totalSets,
    )) {
      _finishWorkout();
      return;
    }

    _advanceWorkoutStepState(
      totalExercises: totalExercises,
      totalSets: totalSets,
    );
    _updateDynamicIsland();
    unawaited(_syncWorkoutToWatch(force: true));
  }

  void _advanceWorkoutStepState({
    required int totalExercises,
    required int totalSets,
  }) {
    if (currentSet < totalSets) {
      currentSet++;
    } else {
      currentExerciseIndex++;
      currentSet = 1;
    }
  }

  void _finishWorkout() {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('¡Entrenamiento Finalizado! 🎉')),
    );
    unawaited(_clearWorkoutWatch());
    _endLiveActivity();
    Navigator.of(context).pop({'finished': 1});
  }

  bool _canAdvanceWorkoutStep() {
    final now = DateTime.now();
    final lastAdvance = _lastStepAdvanceAt;
    if (lastAdvance != null &&
        now.difference(lastAdvance) < const Duration(milliseconds: 700)) {
      return false;
    }
    _lastStepAdvanceAt = now;
    return true;
  }

  void _handleSkipRest() {
    if (!_isResting) return;
    _timer?.cancel();
    _cancelRestAutoAdvanceTimer();
    if (!kIsWeb) {
      unawaited(_cancelWorkoutNotifications());
    } else {
      _webRestNotifications.cancelRestNotification();
    }
    _restEndTime = null;
    _remainingTime = 0;
    final exercises = widget.workout['exercises'] as List<dynamic>? ?? [];
    final setsCount = _parsePositiveInt(
      exercises[currentExerciseIndex]['sets'],
      fallback: 1,
    );
    if (mounted) {
      setState(() {
        _isResting = false;
        _avanzarSerieOEjercicio(exercises.length, setsCount);
      });
    }
    _updateDynamicIsland();
    unawaited(_syncWorkoutToWatch(force: true));
  }

  Future<void> _handleNextStepFromIsland() async {
    if (_isResting) {
      _handleSkipRest();
      return;
    }

    await _continueWorkoutStep();
  }

  String _nextWorkoutStepTitle({String prefix = 'Sig'}) {
    final exercises = widget.workout['exercises'] as List<dynamic>? ?? [];
    if (exercises.isEmpty) return prefix;

    var nextExerciseIndex = currentExerciseIndex;
    var nextSet = currentSet + 1;
    final currentExercise = exercises[currentExerciseIndex];
    final totalSets = _parsePositiveInt(currentExercise['sets'], fallback: 1);

    if (nextSet > totalSets) {
      nextExerciseIndex = currentExerciseIndex + 1;
      nextSet = 1;
    }

    if (nextExerciseIndex >= exercises.length) {
      return '$prefix: Fin';
    }

    final nextExercise = exercises[nextExerciseIndex];
    final nextTotalSets = _parsePositiveInt(nextExercise['sets'], fallback: 1);
    final exerciseName = exerciseDisplayTitle(exercises, nextExerciseIndex);

    return '$prefix: $exerciseName $nextSet/$nextTotalSets';
  }

  String _currentWorkoutStepTitle() {
    final exercises = widget.workout['exercises'] as List<dynamic>? ?? [];
    if (exercises.isEmpty) return 'Rutina';

    final exercise = exercises[currentExerciseIndex];
    final totalSets = _parsePositiveInt(exercise['sets'], fallback: 1);
    final exerciseName = exerciseDisplayTitle(exercises, currentExerciseIndex);

    return '$exerciseName $currentSet/$totalSets';
  }

  Future<void> _completeSet(int totalSets, dynamic restValue) async {
    int restSeconds = (num.tryParse(restValue.toString())?.toInt()) ?? 0;

    // Si el ejercicio no tiene descanso configurado, avanzamos inmediatamente sin mostrar la pantalla de pausa
    if (restSeconds <= 0) {
      final exercises = widget.workout['exercises'] as List<dynamic>? ?? [];
      _avanzarSerieOEjercicio(exercises.length, totalSets);
      return;
    }

    setState(() {
      _isResting = true;
      _remainingTime = restSeconds;
      _initialRestTime = restSeconds > 0 ? restSeconds : 1;
      _isTimerPaused = false;
      _restEndTime = kIsWeb
          ? DateTime.now().add(Duration(seconds: restSeconds))
          : null;
    });

    _updateDynamicIsland();
    unawaited(_syncWorkoutToWatch(force: true));
    _startTimerSyncLoop();
    await _scheduleRestNotification(restSeconds);
    await _showWatchWorkoutNotification();
  }

  Future<void> _continueWorkoutStep({int? sets, dynamic restSeconds}) async {
    if (_isResting) return;

    if (sets != null && restSeconds != null) {
      await _completeSet(sets, restSeconds);
      return;
    }

    final exercises = widget.workout['exercises'] as List<dynamic>? ?? [];
    if (exercises.isEmpty || currentExerciseIndex >= exercises.length) return;

    final currentEx = exercises[currentExerciseIndex];
    final setsCount = _parsePositiveInt(currentEx['sets'], fallback: 1);
    final nextRestSeconds =
        currentEx['rest_seconds'] ?? currentEx['rest'] ?? 60;
    await _completeSet(setsCount, nextRestSeconds);
  }

  // -------------------------
  // 🔥 LIFECYCLE (CLAVE)
  // -------------------------

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _pauseTime = DateTime.now();
      // ❌ NO se debe iniciar una Live Activity desde aquí.
      // La actividad ya se inicia cuando comienza el descanso (_completeSet).
      // Intentar iniciarla aquí causa el error "Target is not foreground"
      // y provoca que la actividad existente se cancele y desaparezca.
    }

    if (state == AppLifecycleState.resumed) {
      _syncWebRestTimer();
      _consumePendingIslandAction();
      _syncTimerState(force: true);
      _pauseTime = null;
    }
  }

  // -------------------------
  // 🔥 UI
  // -------------------------

  Future<void> _showExerciseImage(String exerciseName) async {
    final googleUrl = Uri.https('www.google.com', '/search', {
      'tbm': 'isch',
      'q': '$exerciseName ejercicio técnica gimnasio',
    });

    try {
      await launchUrl(googleUrl, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo abrir Google: $e')));
    }
  }

  Future<void> _registerCurrentExercisePr() async {
    final exercises = widget.workout['exercises'] as List<dynamic>? ?? [];
    if (exercises.isEmpty || currentExerciseIndex >= exercises.length) {
      return;
    }

    final rawExercise = exercises[currentExerciseIndex];
    if (rawExercise is! Map) {
      return;
    }

    final exercise = Map<String, dynamic>.from(rawExercise);
    final currentPr = exercisePrData(exercise);
    final weightC = TextEditingController(text: currentPr['weight'] ?? '');
    final repsC = TextEditingController(text: currentPr['reps'] ?? '');
    final dateC = TextEditingController(
      text: (currentPr['date'] ?? '').isNotEmpty
          ? currentPr['date']!
          : _todayIsoDate(),
    );
    final notesC = TextEditingController(text: currentPr['notes'] ?? '');

    final updated = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Registrar PR'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                exerciseDisplayTitle(exercises, currentExerciseIndex),
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
            onPressed: () {
              final weight = weightC.text.trim();
              Navigator.pop(ctx, {
                ...exercise,
                'pr_weight': weight,
                'pr_reps': repsC.text.trim(),
                'pr_date': dateC.text.trim(),
                'pr_notes': notesC.text.trim(),
                'notes': notesWithExercisePr(
                  exercise['notes']?.toString() ?? '',
                  weight: weight,
                  reps: repsC.text.trim(),
                  date: dateC.text.trim(),
                  prNotes: notesC.text.trim(),
                ),
              });
            },
            child: const Text('GUARDAR PR'),
          ),
        ],
      ),
    );

    if (updated == null) return;

    setState(() {
      exercises[currentExerciseIndex] = updated;
    });
    await widget.onExercisePrRegistered?.call(currentExerciseIndex, updated);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('PR registrado en esta rutina')),
    );
  }

  String _todayIsoDate() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final exercises = widget.workout['exercises'] as List<dynamic>? ?? [];
    if (exercises.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: const Text(
            "Entrenamiento",
            style: TextStyle(fontWeight: FontWeight.w600, letterSpacing: -0.5),
          ),
        ),
        body: const Center(
          child: Text(
            "No hay ejercicios en esta rutina.",
            style: TextStyle(color: Colors.grey, fontSize: 17),
          ),
        ),
      );
    }

    final currentExercise = exercises[currentExerciseIndex];
    final exerciseName = exerciseDisplayTitle(exercises, currentExerciseIndex);
    final reps = currentExercise['reps'] ?? '-';
    final sets = currentExercise['sets'] ?? 1;
    final maxWeight = exerciseMaxWeightText(currentExercise);
    final prText = exercisePrText(currentExercise);
    final restSeconds =
        currentExercise['rest_seconds'] ?? currentExercise['rest'] ?? 60;
    final progress = exercises.isEmpty
        ? 0.0
        : (currentExerciseIndex + 1) / exercises.length;
    final setsCount = _parsePositiveInt(sets, fallback: 1);
    final completedSets = (currentExerciseIndex * setsCount) + (currentSet - 1);
    final totalSetsEstimate = exercises.fold<int>(
      0,
      (sum, exercise) => sum + _parsePositiveInt(exercise['sets'], fallback: 1),
    );
    final currentStepTitle = _currentWorkoutStepTitle();
    final nextStepTitle = _nextWorkoutStepTitle(
      prefix: 'Siguiente',
    ).replaceFirst('Siguiente: ', '');

    return PopScope(
      canPop: _canPop,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;

        setState(() {
          _canPop = true;
        });

        // Retornamos el estado de la rutina actual a la lista principal (main.dart)
        Future.microtask(() async {
          await _pauseWorkoutForMainScreen();
          if (mounted) {
            Navigator.of(context).pop(
              result ??
                  {
                    'exerciseIndex': currentExerciseIndex,
                    'set': currentSet,
                    'remainingTime': _isResting ? _remainingTime : 0,
                    'restEndTime': _isResting && _restEndTime != null
                        ? _restEndTime!.millisecondsSinceEpoch
                        : 0,
                    'isPaused': kIsWeb && _isResting && !_isTimerPaused ? 0 : 1,
                    'isResting': _isResting ? 1 : 0,
                  },
            );
          }
        });
      },
      child: Scaffold(
        backgroundColor: _isLightMode
            ? const Color(0xFFE9EDF1)
            : const Color(0xFF0D0F11),
        appBar: AppBar(
          title: Text(
            widget.workout['name'] ?? "Rutina",
            style: TextStyle(
              color: _primaryTextColor,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.6,
            ),
          ),
          backgroundColor: Colors.transparent,
          iconTheme: IconThemeData(color: _primaryTextColor),
          centerTitle: true,
          actions: [
            IconButton(
              icon: Icon(Icons.restart_alt, color: _primaryTextColor),
              tooltip: "Reiniciar rutina",
              onPressed: () {
                _timer?.cancel();
                _endLiveActivity();
                setState(() {
                  currentExerciseIndex = 0;
                  currentSet = 1;
                  _isResting = false;
                  _remainingTime = 0;
                });
                _updateDynamicIsland();
                unawaited(_syncWorkoutToWatch(force: true));
              },
            ),
            IconButton(
              icon: const Icon(
                Icons.stop_circle_outlined,
                color: Colors.redAccent,
              ),
              tooltip: "Detener rutina por completo",
              onPressed: () {
                _timer?.cancel();
                unawaited(_clearWorkoutWatch());
                _endLiveActivity();
                // Retornar 'finished': 1 borra la sesión pendiente en main.dart
                Navigator.of(context).pop({'finished': 1});
              },
            ),
          ],
        ),
        body: Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: healthyTPageGradient(context),
                ),
              ),
            ),
            Positioned(
              top: -70,
              right: -30,
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isLightMode
                      ? const Color(0xFFDCE4EB).withOpacity(0.58)
                      : Colors.white.withOpacity(0.025),
                ),
              ),
            ),
            Positioned(
              top: 180,
              left: -40,
              child: Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isLightMode
                      ? const Color(0xFFD4DEE7).withOpacity(0.42)
                      : Colors.white.withOpacity(0.02),
                ),
              ),
            ),
            SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 112),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeroCard(
                      progress: progress,
                      exerciseName: exerciseName.toString(),
                      exerciseIndex: currentExerciseIndex + 1,
                      totalExercises: exercises.length,
                      currentSetLabel: "$currentSet/$setsCount",
                      repsLabel: reps.toString(),
                      maxWeightLabel: maxWeight,
                      prLabel: prText,
                      completedSets: completedSets,
                      totalSetsEstimate: totalSetsEstimate,
                      onRegisterPr: _registerCurrentExercisePr,
                    ),
                    const SizedBox(height: 18),
                    _buildExerciseNavigator(exercises: exercises),
                  ],
                ),
              ),
            ),
            Positioned(
              right: 20,
              bottom: 20,
              child: SafeArea(
                minimum: const EdgeInsets.only(bottom: 10),
                child: _buildFloatingNextButton(
                  enabled: !_isResting,
                  onPressed: () => _continueWorkoutStep(
                    sets: setsCount,
                    restSeconds: restSeconds,
                  ),
                ),
              ),
            ),

            // Pantalla de Descanso (Overlay)
            if (_isResting)
              Positioned.fill(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 18.0, sigmaY: 18.0),
                  child: Container(
                    color:
                        (_isLightMode
                                ? const Color(0xFFE9EDF1)
                                : const Color(0xFF0D0F11))
                            .withOpacity(_isLightMode ? 0.72 : 0.62),
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Container(
                          width: double.infinity,
                          constraints: const BoxConstraints(maxWidth: 460),
                          padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(32),
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: _isLightMode
                                  ? const [Color(0xFFF1F4F6), Color(0xFFDDE4EA)]
                                  : const [
                                      Color(0xFF23201B),
                                      Color(0xFF161616),
                                    ],
                            ),
                            border: _isLightMode
                                ? Border.all(color: _panelBorderColor)
                                : null,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.35),
                                blurRadius: 30,
                                offset: const Offset(0, 18),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                      (_isTimerPaused
                                              ? Colors.green
                                              : (_isLightMode
                                                    ? const Color(0xFF111315)
                                                    : Colors.white))
                                          .withOpacity(
                                            _isTimerPaused ? 0.18 : 0.11,
                                          ),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  _isTimerPaused
                                      ? "DESCANSO EN PAUSA"
                                      : "TIEMPO DE DESCANSO",
                                  style: TextStyle(
                                    color: _isTimerPaused
                                        ? (_isLightMode
                                              ? Colors.green.shade700
                                              : Colors.green.shade200)
                                        : _primaryTextColor.withOpacity(0.92),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.3,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 18),
                              Text(
                                _formatTime(_remainingTime),
                                style: TextStyle(
                                  fontSize: 90,
                                  color: _primaryTextColor,
                                  fontWeight: FontWeight.w200,
                                  height: 0.95,
                                  fontFeatures: [FontFeature.tabularFigures()],
                                ),
                              ),
                              const SizedBox(height: 16),
                              _buildRestTimeProgressBar(),
                              const SizedBox(height: 14),
                              Text(
                                _isTimerPaused
                                    ? "La rutina y la isla dinámica están pausadas"
                                    : "Respira y prepárate para la siguiente serie",
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: _secondaryTextColor,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 18),
                              _buildRestExerciseFlow(
                                currentStepTitle: currentStepTitle,
                                nextStepTitle: nextStepTitle,
                              ),
                              const SizedBox(height: 24),
                              Row(
                                children: [
                                  Expanded(
                                    child: _buildRestButton(
                                      icon: _isTimerPaused
                                          ? Icons.play_arrow_rounded
                                          : Icons.pause_rounded,
                                      label: _isTimerPaused
                                          ? "REANUDAR"
                                          : "PAUSAR",
                                      color: _isTimerPaused
                                          ? Colors.green
                                          : Colors.green.withOpacity(0.82),
                                      textColor: Colors.white,
                                      onPressed: () async {
                                        if (_isTimerPaused) {
                                          await _resumeLiveActivity();
                                        } else {
                                          await _pauseLiveActivity();
                                        }
                                        _syncTimerState();
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _buildRestButton(
                                      icon: Icons.skip_next_rounded,
                                      label: "SIGUIENTE",
                                      color: _isLightMode
                                          ? const Color(0xFF111315)
                                          : Colors.white,
                                      textColor: _isLightMode
                                          ? Colors.white
                                          : Colors.black,
                                      onPressed: _handleSkipRest,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // -------------------------
  // 🔥 HELPERS UI
  // -------------------------

  String _formatTime(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return "$minutes:${remainingSeconds.toString().padLeft(2, '0')}";
  }

  double _restProgressValue() {
    final total = _initialRestTime <= 0 ? 1 : _initialRestTime;
    final remaining = _remainingTime.clamp(0, total).toInt();
    return ((total - remaining) / total).clamp(0.0, 1.0);
  }

  void _seekRestProgress(double progress) {
    if (!_isResting) return;

    final total = _initialRestTime <= 0 ? 1 : _initialRestTime;
    final elapsed = (progress.clamp(0.0, 1.0) * total).round();
    final nextRemaining = (total - elapsed).clamp(0, total).toInt();

    setState(() {
      _remainingTime = nextRemaining;
      if (!_isTimerPaused && nextRemaining > 0) {
        _restEndTime = DateTime.now().add(Duration(seconds: nextRemaining));
      }
    });
  }

  Future<void> _commitRestProgressSeek() async {
    if (!_isResting) return;

    if (_remainingTime <= 0) {
      _handleSkipRest();
      return;
    }

    if (!_isTimerPaused) {
      _scheduleRestAutoAdvanceTimer();
      await _scheduleRestNotification(_remainingTime);
    }
    await _updateDynamicIsland();
    await _showWatchWorkoutNotification();
    await _syncWorkoutToWatch(force: true);
  }

  Widget _buildRestTimeProgressBar() {
    final value = _restProgressValue();
    final elapsed = (_initialRestTime - _remainingTime)
        .clamp(0, _initialRestTime)
        .toInt();
    final fillColor = _isTimerPaused
        ? Colors.green
        : (_isLightMode ? const Color(0xFFFF8A1F) : const Color(0xFFFFB14A));
    final trackColor = _isLightMode
        ? const Color(0xFF111315).withOpacity(0.10)
        : Colors.white.withOpacity(0.10);

    return Column(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            const thumbSize = 22.0;
            const trackHeight = 7.0;

            void seekFromLocalDx(double dx) {
              if (width <= 0) return;
              _seekRestProgress((dx / width).clamp(0.0, 1.0));
            }

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (details) {
                HapticFeedback.selectionClick();
                seekFromLocalDx(details.localPosition.dx);
                unawaited(_commitRestProgressSeek());
              },
              onHorizontalDragStart: (details) {
                HapticFeedback.selectionClick();
                setState(() => _isSeekingRestProgress = true);
                seekFromLocalDx(details.localPosition.dx);
              },
              onHorizontalDragUpdate: (details) {
                seekFromLocalDx(details.localPosition.dx);
              },
              onHorizontalDragEnd: (_) async {
                setState(() => _isSeekingRestProgress = false);
                await _commitRestProgressSeek();
              },
              onHorizontalDragCancel: () {
                setState(() => _isSeekingRestProgress = false);
                unawaited(_commitRestProgressSeek());
              },
              child: SizedBox(
                height: 34,
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(end: value),
                  duration: _isTimerPaused || _isSeekingRestProgress
                      ? Duration.zero
                      : const Duration(milliseconds: 940),
                  curve: Curves.linear,
                  builder: (context, animatedValue, _) {
                    final fillWidth = width * animatedValue;
                    final maxThumbLeft = (width - thumbSize)
                        .clamp(0.0, double.infinity)
                        .toDouble();
                    final thumbLeft = (fillWidth - (thumbSize / 2))
                        .clamp(0.0, maxThumbLeft)
                        .toDouble();

                    return Stack(
                      alignment: Alignment.centerLeft,
                      children: [
                        Container(
                          height: trackHeight,
                          decoration: BoxDecoration(
                            color: trackColor,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                        Container(
                          width: fillWidth,
                          height: trackHeight,
                          decoration: BoxDecoration(
                            color: fillColor,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                        Positioned(
                          left: thumbLeft,
                          child: Container(
                            width: thumbSize,
                            height: thumbSize,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: fillColor.withOpacity(0.48),
                                width: 2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.24),
                                  blurRadius: 10,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Text(
              _formatTime(elapsed),
              style: TextStyle(
                color: _secondaryTextColor,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const Spacer(),
            Text(
              '-${_formatTime(_remainingTime)}',
              style: TextStyle(
                color: _secondaryTextColor,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildHeroCard({
    required double progress,
    required String exerciseName,
    required int exerciseIndex,
    required int totalExercises,
    required String currentSetLabel,
    required String repsLabel,
    required String maxWeightLabel,
    required String prLabel,
    required int completedSets,
    required int totalSetsEstimate,
    required VoidCallback onRegisterPr,
  }) {
    return _buildGlassPanel(
      padding: const EdgeInsets.fromLTRB(24, 26, 24, 24),
      borderRadius: 36,
      backgroundOpacity: 0.18,
      blurSigma: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.09),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  "EJERCICIO $exerciseIndex DE $totalExercises",
                  style: TextStyle(
                    color: _primaryTextColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
              const Spacer(),
              _buildStatusPill(
                label: _isTimerPaused
                    ? "PAUSADO"
                    : (_isResting
                          ? "DESCANSO"
                          : (_isWarmUp ? "CALENTAMIENTO" : "ACTIVO")),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                icon: const Icon(Icons.image_search_rounded),
                onPressed: () => _showExerciseImage(exerciseName),
                color: _primaryTextColor,
                tooltip: 'Ver ejemplo del ejercicio (IA)',
              ),
              IconButton(
                icon: const Icon(Icons.emoji_events_rounded),
                onPressed: onRegisterPr,
                color: _primaryTextColor,
                tooltip: 'Registrar PR',
              ),
            ],
          ),
          const SizedBox(height: 2),
          _buildExerciseTitle(exerciseName),
          const SizedBox(height: 22),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: _isLightMode
                  ? const Color(0xFF111315).withOpacity(0.10)
                  : Colors.white.withOpacity(0.08),
              valueColor: AlwaysStoppedAnimation(_primaryTextColor),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(child: _buildQuickStat("Serie actual", currentSetLabel)),
              const SizedBox(width: 12),
              Expanded(child: _buildQuickStat("Reps", repsLabel)),
            ],
          ),
          if (maxWeightLabel.isNotEmpty) ...[
            const SizedBox(height: 14),
            _buildQuickStat("Peso máximo", maxWeightLabel),
          ],
          if (prLabel.isNotEmpty) ...[
            const SizedBox(height: 14),
            _buildQuickStat("PR", prLabel),
          ],
          const SizedBox(height: 18),
          Text(
            "${(progress * 100).round()}% completado • $completedSets/$totalSetsEstimate series",
            style: TextStyle(
              color: _secondaryTextColor,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExerciseTitle(String exerciseName) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final words = exerciseName
            .split(RegExp(r'\s+'))
            .where((word) => word.trim().isNotEmpty)
            .toList();
        final longestWordLength = words.fold<int>(
          0,
          (maxLength, word) =>
              word.length > maxLength ? word.length : maxLength,
        );
        final baseSize = kIsWeb ? 30.0 : 34.0;
        final estimatedLongestWordWidth = longestWordLength * baseSize * 0.66;
        final availableWidth = constraints.maxWidth <= 0
            ? double.infinity
            : constraints.maxWidth;
        final widthScale = estimatedLongestWordWidth > availableWidth
            ? availableWidth / estimatedLongestWordWidth
            : 1.0;
        final titleFontSize = (baseSize * widthScale).clamp(22.0, baseSize);

        return Text(
          exerciseName,
          softWrap: true,
          overflow: TextOverflow.visible,
          textScaler: const TextScaler.linear(1.0),
          style: TextStyle(
            color: _primaryTextColor,
            fontSize: titleFontSize,
            fontWeight: FontWeight.w900,
            height: 1.04,
            letterSpacing: 0,
          ),
        );
      },
    );
  }

  Widget _buildFloatingNextButton({
    required bool enabled,
    required VoidCallback onPressed,
  }) {
    final backgroundColor = enabled
        ? (_isLightMode ? const Color(0xFF0B0D10) : Colors.white)
        : (_isLightMode ? const Color(0xFFCDD4DB) : const Color(0xFF2E3237));
    final foregroundColor = enabled
        ? (_isLightMode ? Colors.white : const Color(0xFF080A0D))
        : _secondaryTextColor.withOpacity(0.62);

    return Semantics(
      button: true,
      label: enabled ? 'Siguiente' : 'Descanso en curso',
      child: Tooltip(
        message: enabled ? 'Siguiente' : 'Descanso en curso',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? onPressed : null,
          child: Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: backgroundColor,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(_isLightMode ? 0.18 : 0.42),
                  blurRadius: 24,
                  offset: const Offset(0, 12),
                ),
                if (!_isLightMode && enabled)
                  BoxShadow(
                    color: Colors.white.withOpacity(0.08),
                    blurRadius: 18,
                    offset: const Offset(0, -4),
                  ),
              ],
            ),
            child: Icon(
              Icons.skip_next_rounded,
              color: foregroundColor,
              size: 34,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusPill({required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: _isLightMode
            ? const Color(0xFF111315).withOpacity(0.07)
            : Colors.white.withOpacity(0.09),
        borderRadius: BorderRadius.circular(999),
        border: _isLightMode ? Border.all(color: _panelBorderColor) : null,
      ),
      child: Text(
        label,
        style: TextStyle(
          color: label == "PAUSADO" ? Colors.green.shade600 : _primaryTextColor,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.1,
        ),
      ),
    );
  }

  Widget _buildQuickStat(String label, String value) {
    return _buildGlassPanel(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      borderRadius: 20,
      backgroundOpacity: 0.10,
      blurSigma: 14,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: _secondaryTextColor,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: _primaryTextColor,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricsRow({
    required int currentSet,
    required int sets,
    required String reps,
    required int restSeconds,
  }) {
    return Row(
      children: [
        Expanded(
          child: _buildMetricCard(
            icon: Icons.layers_rounded,
            title: "Volumen",
            value: "$currentSet de $sets",
            accent: _primaryTextColor,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildMetricCard(
            icon: Icons.repeat_rounded,
            title: "Repeticiones",
            value: reps,
            accent: _primaryTextColor,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildMetricCard(
            icon: Icons.timer_outlined,
            title: "Descanso",
            value: "${restSeconds}s",
            accent: _primaryTextColor,
          ),
        ),
      ],
    );
  }

  Widget _buildExerciseNavigator({required List<dynamic> exercises}) {
    final canGoBack = currentExerciseIndex > 0 && !_isResting;
    final canGoForward =
        currentExerciseIndex < exercises.length - 1 && !_isResting;

    return _buildGlassPanel(
      padding: const EdgeInsets.all(18),
      borderRadius: 28,
      backgroundOpacity: 0.10,
      blurSigma: 16,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _buildSecondaryAction(
                  icon: Icons.arrow_back_rounded,
                  label: "Ejercicio anterior",
                  enabled: canGoBack,
                  onPressed: () {
                    setState(() {
                      currentExerciseIndex--;
                      currentSet = 1;
                    });
                    _updateDynamicIsland();
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildSecondaryAction(
                  icon: Icons.skip_next_rounded,
                  label: "Siguiente ejercicio",
                  enabled: canGoForward,
                  onPressed: () {
                    setState(() {
                      currentExerciseIndex++;
                      currentSet = 1;
                    });
                    _updateDynamicIsland();
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard({
    required IconData icon,
    required String title,
    required String value,
    required Color accent,
  }) {
    return _buildGlassPanel(
      padding: const EdgeInsets.all(16),
      borderRadius: 24,
      backgroundOpacity: 0.10,
      blurSigma: 14,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: accent.withOpacity(0.14),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: accent, size: 20),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: TextStyle(
              color: _secondaryTextColor,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: _primaryTextColor,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionPanel({
    required int sets,
    required dynamic restSeconds,
    required bool isResting,
  }) {
    final buttonForeground = _isLightMode ? Colors.white : Colors.black;
    final iconBackground = (_isLightMode ? Colors.white : Colors.black)
        .withOpacity(isResting ? 0.12 : 0.16);

    return _buildGlassPanel(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      borderRadius: 28,
      backgroundOpacity: 0.10,
      blurSigma: 16,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isResting
                      ? const Color(0xFFFF8A1F)
                      : const Color(0xFF111418),
                  boxShadow: [
                    BoxShadow(
                      color:
                          (isResting
                                  ? const Color(0xFFFF8A1F)
                                  : const Color(0xFF111418))
                              .withOpacity(0.22),
                      blurRadius: 10,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 9),
              Text(
                isResting
                    ? "Descanso activo"
                    : (_isTimerPaused ? "Rutina pausada" : "Siguiente acción"),
                style: TextStyle(
                  color: _secondaryTextColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 74,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(26),
                boxShadow: [
                  BoxShadow(
                    color: _isLightMode
                        ? Colors.black.withOpacity(isResting ? 0.08 : 0.18)
                        : Colors.white.withOpacity(isResting ? 0.05 : 0.10),
                    blurRadius: 28,
                    offset: const Offset(0, 14),
                  ),
                ],
              ),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: isResting
                    ? null
                    : (_isTimerPaused
                          ? () => _resumeLiveActivity()
                          : () => _continueWorkoutStep(
                              sets: sets,
                              restSeconds: restSeconds,
                            )),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  decoration: BoxDecoration(
                    gradient: isResting
                        ? null
                        : LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: _isLightMode
                                ? const [
                                    Color(0xFF080A0D),
                                    Color(0xFF242A31),
                                    Color(0xFF101418),
                                  ]
                                : const [
                                    Color(0xFFFFFFFF),
                                    Color(0xFFE7EAEE),
                                    Color(0xFFC9CED5),
                                  ],
                          ),
                    color: isResting
                        ? (_isLightMode
                              ? const Color(0xFFCBD1D8)
                              : const Color(0xFF3A3D42))
                        : null,
                    borderRadius: BorderRadius.circular(26),
                    border: _isLightMode
                        ? Border.all(
                            color: isResting
                                ? Colors.white.withOpacity(0.10)
                                : Colors.white.withOpacity(0.18),
                            width: 1.2,
                          )
                        : null,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: Row(
                      children: [
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: iconBackground,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.12),
                                blurRadius: 14,
                                offset: const Offset(0, 5),
                              ),
                            ],
                          ),
                          child: Icon(
                            isResting
                                ? Icons.hourglass_top_rounded
                                : (_isTimerPaused
                                      ? Icons.play_arrow_rounded
                                      : Icons.arrow_forward_rounded),
                            size: 26,
                            color: buttonForeground,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isResting
                                    ? "Descanso en curso"
                                    : (_isTimerPaused
                                          ? "Reanudar"
                                          : "Continuar"),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: buttonForeground,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0,
                                  height: 1,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                isResting
                                    ? "La siguiente serie se habilita al terminar."
                                    : (_isTimerPaused
                                          ? "La rutina está pausada desde la isla."
                                          : "Termina tu serie e inicia el descanso."),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: buttonForeground.withOpacity(0.64),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  height: 1,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRestExerciseFlow({
    required String currentStepTitle,
    required String nextStepTitle,
  }) {
    return _buildGlassPanel(
      padding: const EdgeInsets.all(14),
      borderRadius: 22,
      backgroundOpacity: 0.08,
      blurSigma: 12,
      child: Column(
        children: [
          _buildRestExerciseRow(
            label: 'En curso',
            value: currentStepTitle,
            icon: Icons.fitness_center_rounded,
          ),
          const SizedBox(height: 12),
          Container(height: 1, color: _panelBorderColor),
          const SizedBox(height: 12),
          _buildRestExerciseRow(
            label: 'Siguiente',
            value: nextStepTitle,
            icon: Icons.arrow_forward_rounded,
            accent: Colors.green,
          ),
        ],
      ),
    );
  }

  Widget _buildRestExerciseRow({
    required String label,
    required String value,
    required IconData icon,
    Color? accent,
  }) {
    final iconColor = accent ?? _primaryTextColor;
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: iconColor.withOpacity(_isLightMode ? 0.10 : 0.16),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: iconColor, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label.toUpperCase(),
                style: TextStyle(
                  color: _secondaryTextColor,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _primaryTextColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  height: 1.15,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSecondaryAction({
    required IconData icon,
    required String label,
    required bool enabled,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      height: 76,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTapDown: enabled ? (_) => onPressed() : null,
          child: Container(
            decoration: BoxDecoration(
              color: _isLightMode
                  ? const Color(0xFF111315).withOpacity(enabled ? 0.08 : 0.04)
                  : Colors.white.withOpacity(enabled ? 0.10 : 0.05),
              borderRadius: BorderRadius.circular(20),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 24,
                  color: enabled
                      ? _primaryTextColor
                      : _secondaryTextColor.withOpacity(0.58),
                ),
                const SizedBox(height: 6), // Efecto de salto de línea
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: enabled
                        ? _primaryTextColor
                        : _secondaryTextColor.withOpacity(0.58),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String title, String value) {
    return Row(
      children: [
        Icon(icon, color: Colors.orange, size: 26),
        const SizedBox(width: 14),
        Text(
          title,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 17,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 19,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRestButton({
    required IconData icon,
    required String label,
    required Color color,
    required Color textColor,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      height: 58,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: Container(
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(_isLightMode ? 0.18 : 0.24),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 24, color: textColor),
                  const SizedBox(width: 10),
                  Text(
                    label,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.visible,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGlassPanel({
    required Widget child,
    required EdgeInsetsGeometry padding,
    required double borderRadius,
    required double backgroundOpacity,
    required double blurSigma,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: Container(
          width: double.infinity,
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(borderRadius),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                _panelBaseColor.withOpacity(
                  _isLightMode ? 0.66 : (backgroundOpacity + 0.60),
                ),
                _panelBaseColor.withOpacity(
                  _isLightMode ? 0.34 : (backgroundOpacity + 0.34),
                ),
              ],
            ),
            border: _isLightMode ? Border.all(color: _panelBorderColor) : null,
            boxShadow: [
              BoxShadow(
                color: (_isLightMode ? Colors.black : Colors.black).withOpacity(
                  _isLightMode ? 0.10 : 0.34,
                ),
                blurRadius: 24,
                offset: const Offset(0, 14),
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
    );
  }

  // -------------------------
  // 🔥 DISPOSE (IMPORTANTE)
  // -------------------------

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _cancelRestAutoAdvanceTimer();
    _islandActionPoller?.cancel();
    _watchSyncTimer?.cancel();
    _stopCardioTracking();
    if (!kIsWeb) {
      unawaited(_cancelWorkoutNotifications(includeWatch: false));
    }

    // ❌ NO cerrar Live Activity aquí
    // para que siga en Dynamic Island, ni la notificación del reloj
    // para que continúe visible si la sesión queda pausada en la lista.

    super.dispose();
  }
}
