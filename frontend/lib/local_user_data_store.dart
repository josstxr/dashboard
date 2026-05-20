part of 'main.dart';

class LocalUserDataStore {
  static const _workoutsPrefix = 'healthy_t_user_workouts_';
  static const _dietsPrefix = 'healthy_t_user_diets_';
  static const _workoutIdPrefix = 'healthy_t_user_workout_id_';
  static const _dietIdPrefix = 'healthy_t_user_diet_id_';
  static const _exerciseIdPrefix = 'healthy_t_user_exercise_id_';
  static const _mealIdPrefix = 'healthy_t_user_meal_id_';
  static const _dailyMealsPrefix = 'healthy_t_user_daily_meals_';

  static String _userToken(String email) => email.trim().toLowerCase();
  static String _workoutsKey(String email) =>
      '$_workoutsPrefix${_userToken(email)}';
  static String _dietsKey(String email) => '$_dietsPrefix${_userToken(email)}';
  static String _workoutIdKey(String email) =>
      '$_workoutIdPrefix${_userToken(email)}';
  static String _dietIdKey(String email) =>
      '$_dietIdPrefix${_userToken(email)}';
  static String _exerciseIdKey(String email) =>
      '$_exerciseIdPrefix${_userToken(email)}';
  static String _mealIdKey(String email) =>
      '$_mealIdPrefix${_userToken(email)}';
  static String _dailyMealsKey(String email, String date) =>
      '$_dailyMealsPrefix${_userToken(email)}_$date';

  static Future<List<Map<String, dynamic>>> loadWorkouts(String email) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_workoutsKey(email));
    if (raw == null || raw.isEmpty) {
      return [];
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
      }
      return [];
    } catch (e) {
      debugPrint('Error decoding workouts: $e');
      return [];
    }
  }

  static Future<void> saveWorkouts(String email, List workouts) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_workoutsKey(email), jsonEncode(workouts));
  }

  static Future<List<Map<String, dynamic>>> loadDiets(String email) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_dietsKey(email));
    if (raw == null || raw.isEmpty) {
      return [];
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
      }
      return [];
    } catch (e) {
      debugPrint('Error decoding diets: $e');
      return [];
    }
  }

  static Future<void> saveDiets(String email, List diets) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_dietsKey(email), jsonEncode(diets));
  }

  static Future<List<Map<String, dynamic>>> loadDailyMeals(
    String email,
    String date,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_dailyMealsKey(email, date));
    if (raw == null || raw.isEmpty) {
      return [];
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
      } else if (decoded is Map && decoded['meals'] is List) {
        // Fallback si la estructura es diferente
        return (decoded['meals'] as List)
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
      }
      return [];
    } catch (e) {
      debugPrint('Error decoding daily meals: $e');
      return [];
    }
  }

  static Future<void> saveDailyMeals(
    String email,
    String date,
    List meals,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_dailyMealsKey(email, date), jsonEncode(meals));
  }

  static Future<void> clearUserData(String email) async {
    final prefs = await SharedPreferences.getInstance();
    final token = _userToken(email);
    final keys = prefs.getKeys().where((key) {
      return key == _workoutsKey(email) ||
          key == _dietsKey(email) ||
          key == _workoutIdKey(email) ||
          key == _dietIdKey(email) ||
          key == _exerciseIdKey(email) ||
          key == _mealIdKey(email) ||
          key.startsWith('$_dailyMealsPrefix$token');
    }).toList();

    for (final key in keys) {
      await prefs.remove(key);
    }
  }

  static Future<int> nextWorkoutId(String email) =>
      _nextCounter(_workoutIdKey(email));
  static Future<int> nextDietId(String email) =>
      _nextCounter(_dietIdKey(email));
  static Future<int> nextExerciseId(String email) =>
      _nextCounter(_exerciseIdKey(email));
  static Future<int> nextMealId(String email) =>
      _nextCounter(_mealIdKey(email));

  static Future<int> _nextCounter(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final nextValue = (prefs.getInt(key) ?? 0) + 1;
    await prefs.setInt(key, nextValue);
    return nextValue;
  }
}
