part of 'main.dart';

int parseWholeNumber(dynamic value) {
  final match = RegExp(r'\d+(?:[.,]\d+)?').firstMatch(value?.toString() ?? '');
  if (match == null) {
    return 0;
  }
  final parsed = double.tryParse(match.group(0)!.replaceAll(',', '.'));
  return parsed?.round() ?? 0;
}

String normalizeRepsText(dynamic value) {
  final text = value?.toString().trim() ?? '';
  if (text.isEmpty) {
    return '-';
  }

  final numericText = text.replaceAll(',', '.');
  final numericValue = double.tryParse(numericText);
  if (numericValue != null && numericValue >= 30000) {
    final excelDate = DateTime(
      1899,
      12,
      30,
    ).add(Duration(days: numericValue.round()));
    final first = excelDate.day;
    final second = excelDate.month;
    if (first > 0 && first <= 30 && second > 0 && second <= 30) {
      final low = first < second ? first : second;
      final high = first < second ? second : first;
      return '$low-$high';
    }
  }

  var normalized = text
      .replaceAll(RegExp(r'\breps?\b', caseSensitive: false), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  normalized = normalized.replaceAllMapped(
    RegExp(r'(\d+)[\.,]0+(?!\d)'),
    (match) => match.group(1)!,
  );
  normalized = normalized.replaceAll(',', '-');
  normalized = normalized.replaceAll(RegExp(r'\s*-\s*'), '-');
  normalized = normalized.replaceAll(RegExp(r'\s*/\s*'), '/');

  return normalized.isEmpty ? '-' : normalized;
}

String exerciseMaxWeightText(Map<dynamic, dynamic> exercise) {
  for (final key in const ['max_weight', 'load', 'weight']) {
    final value = exercise[key]?.toString().trim() ?? '';
    if (value.isNotEmpty) {
      return value;
    }
  }

  final notes = exercise['notes']?.toString() ?? '';
  final match = RegExp(
    r'(?:^|\|\s*)(?:Peso\s+m[áa]ximo|Carga):\s*([^|]+)',
    caseSensitive: false,
  ).firstMatch(notes);
  return match?.group(1)?.trim() ?? '';
}

String exercisePrText(Map<dynamic, dynamic> exercise) {
  final data = exercisePrData(exercise);
  final weight = data['weight'] ?? '';
  if (weight.isEmpty) return '';

  final reps = data['reps'] ?? '';
  final date = data['date'] ?? '';
  return [
    weight,
    if (reps.isNotEmpty) 'x $reps',
    if (date.isNotEmpty) '• $date',
  ].join(' ');
}

Map<String, String> exercisePrData(Map<dynamic, dynamic> exercise) {
  final directWeight = exercise['pr_weight']?.toString().trim() ?? '';
  if (directWeight.isNotEmpty) {
    return {
      'weight': directWeight,
      'reps': exercise['pr_reps']?.toString().trim() ?? '',
      'date': exercise['pr_date']?.toString().trim() ?? '',
      'notes': exercise['pr_notes']?.toString().trim() ?? '',
    };
  }

  final notes = exercise['notes']?.toString() ?? '';
  final match = RegExp(
    r'(?:^|\|\s*)PR:\s*([^|]+)',
    caseSensitive: false,
  ).firstMatch(notes);
  final raw = match?.group(1)?.trim() ?? '';
  if (raw.isEmpty) {
    return const {'weight': '', 'reps': '', 'date': '', 'notes': ''};
  }

  final weightMatch = RegExp(
    r'\d+(?:[.,]\d+)?\s*(?:kg|lb|lbs)?',
  ).firstMatch(raw);
  final repsMatch = RegExp(
    r'(?:x|reps?:?)\s*(\d+)',
    caseSensitive: false,
  ).firstMatch(raw);
  final dateMatch = RegExp(r'\d{4}-\d{2}-\d{2}').firstMatch(raw);

  return {
    'weight': weightMatch?.group(0)?.trim() ?? raw,
    'reps': repsMatch?.group(1)?.trim() ?? '',
    'date': dateMatch?.group(0)?.trim() ?? '',
    'notes': '',
  };
}

String notesWithoutExerciseWeight(String notes) {
  return notes
      .replaceAll(
        RegExp(
          r'(?:^|\s*\|\s*)(?:Peso\s+m[áa]ximo|Carga):\s*[^|]+',
          caseSensitive: false,
        ),
        '',
      )
      .replaceAll(
        RegExp(r'(?:^|\s*\|\s*)PR:\s*[^|]+', caseSensitive: false),
        '',
      )
      .replaceAll(RegExp(r'\s*\|\s*\|\s*'), ' | ')
      .replaceAll(RegExp(r'^\s*\|\s*|\s*\|\s*$'), '')
      .trim();
}

String notesWithExerciseWeight(String notes, String weight) {
  final cleanNotes = notesWithoutExerciseWeight(notes);
  final cleanWeight = weight.trim();
  return [
    if (cleanWeight.isNotEmpty) 'Peso máximo: $cleanWeight',
    if (cleanNotes.isNotEmpty) cleanNotes,
  ].join(' | ');
}

String notesWithExercisePr(
  String notes, {
  required String weight,
  required String reps,
  required String date,
  required String prNotes,
}) {
  final cleanNotes = notes
      .replaceAll(
        RegExp(r'(?:^|\s*\|\s*)PR:\s*[^|]+', caseSensitive: false),
        '',
      )
      .replaceAll(RegExp(r'^\s*\|\s*|\s*\|\s*$'), '')
      .trim();
  final cleanWeight = weight.trim();
  final cleanReps = reps.trim();
  final cleanDate = date.trim();
  final cleanPrNotes = prNotes.trim();
  final prText = [
    if (cleanWeight.isNotEmpty) cleanWeight,
    if (cleanReps.isNotEmpty) 'x $cleanReps',
    if (cleanDate.isNotEmpty) cleanDate,
    if (cleanPrNotes.isNotEmpty) cleanPrNotes,
  ].join(' • ');

  return [
    if (cleanNotes.isNotEmpty) cleanNotes,
    if (prText.isNotEmpty) 'PR: $prText',
  ].join(' | ');
}

extension _StringFallback on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}

bool isApproximationExerciseName(dynamic value) {
  final text = value?.toString().toLowerCase() ?? '';
  return text.contains('aproxim');
}

String normalizeExerciseDisplayName(dynamic value) {
  final raw = value?.toString().trim() ?? '';
  if (raw.isEmpty) return '';

  final text = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
  final lower = text.toLowerCase();

  // Defensive repair for older PDF imports where a wrapped exercise cell was
  // captured from the middle and cut before the end.
  if (lower.startsWith('e pectoral') &&
      lower.contains('empujes') &&
      lower.contains('poleas medias')) {
    return 'APERTURAS DE PECTORAL MÁS EMPUJES EN POLEAS MEDIAS CON BANCO VERTICAL';
  }

  if (lower.contains('pectoral') &&
      lower.contains('poleas medias') &&
      lower.endsWith('con ban')) {
    return '${text}CO VERTICAL';
  }

  return text;
}

String exerciseDisplayTitle(List<dynamic> exercises, int index) {
  if (index < 0 || index >= exercises.length) {
    return 'Ejercicio';
  }

  final exercise = exercises[index] is Map ? exercises[index] as Map : {};
  final rawName = exercise['name']?.toString().trim();
  final normalizedName = normalizeExerciseDisplayName(rawName);
  final baseName = normalizedName.isEmpty ? 'Ejercicio' : normalizedName;
  if (!isApproximationExerciseName(baseName)) {
    return baseName;
  }

  for (var nextIndex = index + 1; nextIndex < exercises.length; nextIndex++) {
    final nextExercise = exercises[nextIndex] is Map
        ? exercises[nextIndex] as Map
        : {};
    final nextName = nextExercise['name']?.toString().trim();
    final normalizedNextName = normalizeExerciseDisplayName(nextName);
    if (normalizedNextName.isNotEmpty &&
        !isApproximationExerciseName(normalizedNextName)) {
      return 'Aproximación - $normalizedNextName';
    }
  }

  return 'Aproximación';
}
