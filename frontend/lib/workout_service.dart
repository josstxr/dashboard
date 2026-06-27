import 'package:flutter/services.dart';

class WorkoutPlatformService {
  static const platform = MethodChannel('com.josh.workout/timer');

  Future<void> startLiveActivity() async {
    try {
      final now = DateTime.now();
      final endTime = now.add(const Duration(minutes: 2)); 

      await platform.invokeMethod('startTimer', {
        'title': 'Descanso Heavy Duty',
        'startTime': now.millisecondsSinceEpoch ~/ 1000,
        'endTime': endTime.millisecondsSinceEpoch ~/ 1000,
      });
      print("Isla Dinámica activada 😎");
    } on PlatformException catch (e) {
      print("Error al iniciar Live Activity: '${e.message}'.");
    }
  }

  Future<void> stopLiveActivity() async {
    try {
      await platform.invokeMethod('stopTimer');
    } on PlatformException catch (e) {
      print("Error al detener Live Activity: '${e.message}'.");
    }
  }
}