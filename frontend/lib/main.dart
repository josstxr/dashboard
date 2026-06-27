import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'workout_session_screen.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' as xlsx;
import 'auth_screen.dart';
import 'diet_camera_screen.dart';
import 'rSemanalWorkout.dart';
import 'dart:ui';
import 'package:flutter/services.dart';
import 'package:health/health.dart';
import 'package:flutter/foundation.dart'; // Importante para usar kIsWeb
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'api_config.dart';

part 'theme.dart';
part 'app_models.dart';
part 'workout_helpers.dart';
part 'health_service.dart';
part 'app_shell.dart';
part 'local_user_data_store.dart';
part 'workout_list_screen.dart';
part 'workout_editor_screen.dart';
part 'diet_option_table.dart';
part 'diet_editor_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: ApiConfig.supabaseUrl,
    anonKey: ApiConfig.supabaseAnonKey,
  );

  final prefs = await SharedPreferences.getInstance();
  final isLightMode = prefs.getBool(_themePreferenceKey) ?? true;
  healthyTThemeMode.value = isLightMode ? ThemeMode.light : ThemeMode.dark;

  runApp(const MyApp());
}
