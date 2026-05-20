part of 'main.dart';

class GeminiQuotaException implements Exception {
  final String message;

  const GeminiQuotaException(this.message);

  @override
  String toString() => message;
}

class RecoverySnapshot {
  final double sleepHours;
  final double restHoursSinceWorkout;
  final int stepCount;
  final double activeEnergyKcal;
  final double exerciseMinutes;
  final double standHours;
  final double restingHeartRate;
  final int recommendedRestHours;
  final DateTime? lastWorkoutEnd;
  final String sourceSummary;
  final String status;
  final String recommendation;
  final bool hasHealthData;

  const RecoverySnapshot({
    required this.sleepHours,
    required this.restHoursSinceWorkout,
    required this.stepCount,
    required this.activeEnergyKcal,
    required this.exerciseMinutes,
    required this.standHours,
    required this.restingHeartRate,
    required this.recommendedRestHours,
    required this.lastWorkoutEnd,
    required this.sourceSummary,
    required this.status,
    required this.recommendation,
    required this.hasHealthData,
  });
}

class _PickedAdminExcelFile {
  final String name;
  final List<int> bytes;

  const _PickedAdminExcelFile({required this.name, required this.bytes});
}
