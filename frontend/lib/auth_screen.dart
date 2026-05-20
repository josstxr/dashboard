import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';
import 'dart:ui';
import 'main.dart'; // Para acceder a WorkoutListScreen

const _lastAuthUserKey = 'healthy_t_last_auth_user';

// Redefinimos el LocalAuthUser para que la app no marque error
class LocalAuthUser {
  final String id;
  final String email;
  final String name;
  final bool isAdmin;

  LocalAuthUser({
    required this.id,
    required this.email,
    required this.name,
    this.isAdmin = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'email': email,
    'name': name,
    'isAdmin': isAdmin,
  };

  static LocalAuthUser? fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }

    final id = json['id']?.toString() ?? '';
    final email = json['email']?.toString() ?? '';
    if (id.isEmpty || email.isEmpty) {
      return null;
    }

    return LocalAuthUser(
      id: id,
      email: email,
      name: json['name']?.toString().trim().isNotEmpty == true
          ? json['name'].toString()
          : email.split('@').first,
      isAdmin: json['isAdmin'] == true,
    );
  }
}

// Redefinimos la función de cerrar sesión
class LocalAuthStore {
  static Future<void> saveLastUser(LocalAuthUser user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastAuthUserKey, jsonEncode(user.toJson()));
  }

  static Future<LocalAuthUser?> loadLastUser() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_lastAuthUserKey);
    if (raw == null || raw.isEmpty) {
      return null;
    }

    try {
      final decoded = jsonDecode(raw);
      return decoded is Map
          ? LocalAuthUser.fromJson(Map<String, dynamic>.from(decoded))
          : null;
    } catch (e) {
      debugPrint('No se pudo cargar usuario local: $e');
      return null;
    }
  }

  static Future<void> logout() async {
    try {
      await Supabase.instance.client.auth.signOut();
    } finally {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_lastAuthUserKey);
    }
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  Future<LocalAuthUser?>? _cachedUserFuture;

  @override
  void initState() {
    super.initState();
    _cachedUserFuture = LocalAuthStore.loadLastUser();
  }

  LocalAuthUser _userFromSession(User user) {
    return LocalAuthUser(
      id: user.id,
      email: user.email ?? '',
      name:
          user.userMetadata?['name'] ?? user.email?.split('@')[0] ?? 'Usuario',
      isAdmin: user.userMetadata?['role'] == 'admin',
    );
  }

  Widget _offlineFallbackOrLogin() {
    return FutureBuilder<LocalAuthUser?>(
      future: _cachedUserFuture,
      builder: (context, snapshot) {
        final cachedUser = snapshot.data;
        if (cachedUser != null) {
          return WorkoutListScreen(currentUser: cachedUser);
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          final isLight = Theme.of(context).brightness == Brightness.light;
          return Scaffold(
            backgroundColor: isLight
                ? const Color(0xFFE9EDF1)
                : const Color(0xFF0D0F11),
            body: Center(
              child: CircularProgressIndicator(
                color: isLight
                    ? const Color(0xFF111315)
                    : const Color(0xFFF2F5F7),
              ),
            ),
          );
        }

        return const AuthScreen();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // onAuthStateChange se encarga de escuchar si hay un usuario logueado en Supabase
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          final isLight = Theme.of(context).brightness == Brightness.light;
          return Scaffold(
            backgroundColor: isLight
                ? const Color(0xFFE9EDF1)
                : const Color(0xFF0D0F11),
            body: Center(
              child: CircularProgressIndicator(
                color: isLight
                    ? const Color(0xFF111315)
                    : const Color(0xFFF2F5F7),
              ),
            ),
          );
        }

        final session = Supabase.instance.client.auth.currentSession;

        // Si la sesión existe, mandamos directo a la pantalla principal
        if (session != null) {
          final user = session.user;
          final localUser = _userFromSession(user);
          LocalAuthStore.saveLastUser(localUser);
          return WorkoutListScreen(currentUser: localUser);
        }

        // Si no hay sesión disponible, intentamos entrar con el último usuario cacheado.
        return _offlineFallbackOrLogin();
      },
    );
  }
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _isLogin = true;
  bool _createAsAdmin = false;

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty || (!_isLogin && name.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor, completa todos los campos requeridos'),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      if (_isLogin) {
        // Lógica de inicio de sesión con Supabase
        await Supabase.instance.client.auth.signInWithPassword(
          email: email,
          password: password,
        );
      } else {
        // Lógica de registro con Supabase
        await Supabase.instance.client.auth.signUp(
          email: email,
          password: password,
          data: {'name': name, if (_createAsAdmin) 'role': 'admin'},
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('¡Registro exitoso! Ya puedes iniciar sesión.'),
              backgroundColor: Colors.green,
            ),
          );
          setState(() => _isLogin = true);
        }
      }
    } on AuthException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.redAccent),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final primaryText = isLight
        ? const Color(0xFF111315)
        : const Color(0xFFF2F5F7);
    final secondaryText = isLight
        ? const Color(0xFF636A72)
        : const Color(0xFFB3BAC2);
    final fieldFill = isLight
        ? const Color(0xFF111315).withOpacity(0.055)
        : Colors.white.withOpacity(0.09);
    final fieldBorder = isLight
        ? const Color(0xFFCAD2DA).withOpacity(0.72)
        : Colors.white.withOpacity(0.14);

    return Scaffold(
      backgroundColor: isLight
          ? const Color(0xFFE9EDF1)
          : const Color(0xFF0D0F11),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(32),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: isLight
                      ? const Color(0xFFF5F7F9).withOpacity(0.76)
                      : const Color(0xFF111418).withOpacity(0.84),
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(color: fieldBorder),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.fitness_center_rounded,
                      size: 64,
                      color: primaryText,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _isLogin ? 'Iniciar Sesión' : 'Registrarse',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: primaryText,
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (!_isLogin) ...[
                      TextField(
                        controller: _nameController,
                        style: TextStyle(color: primaryText),
                        decoration: InputDecoration(
                          labelText: 'Nombre completo',
                          labelStyle: TextStyle(color: secondaryText),
                          filled: true,
                          fillColor: fieldFill,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SwitchListTile(
                        value: _createAsAdmin,
                        onChanged: (value) =>
                            setState(() => _createAsAdmin = value),
                        contentPadding: EdgeInsets.zero,
                        activeColor: Colors.greenAccent,
                        title: Text(
                          'Registrar como admin',
                          style: TextStyle(
                            color: primaryText,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        subtitle: Text(
                          'Podrá asignar rutinas a otros usuarios por correo.',
                          style: TextStyle(color: secondaryText),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    TextField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      style: TextStyle(color: primaryText),
                      decoration: InputDecoration(
                        labelText: 'Correo electrónico',
                        labelStyle: TextStyle(color: secondaryText),
                        filled: true,
                        fillColor: fieldFill,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _passwordController,
                      obscureText: true,
                      style: TextStyle(color: primaryText),
                      decoration: InputDecoration(
                        labelText: 'Contraseña',
                        labelStyle: TextStyle(color: secondaryText),
                        filled: true,
                        fillColor: fieldFill,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isLight
                              ? const Color(0xFF111315)
                              : Colors.white,
                          foregroundColor: isLight
                              ? Colors.white
                              : Colors.black,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: _isLoading
                            ? const CircularProgressIndicator(
                                color: Colors.black,
                              )
                            : Text(
                                _isLogin ? 'Entrar' : 'Crear Cuenta',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: () => setState(() => _isLogin = !_isLogin),
                      child: Text(
                        _isLogin
                            ? '¿No tienes cuenta? Regístrate aquí'
                            : '¿Ya tienes cuenta? Inicia sesión',
                        style: TextStyle(color: secondaryText),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
