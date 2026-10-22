import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:local_auth/local_auth.dart';

import 'core/session.dart';
import 'features/auth/auth_page.dart';
import 'features/home/dashboard_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  final session = SessionStore();
  final api = ApiClient(session: session);
  runApp(DominhnhatApp(api: api));
}

class DominhnhatApp extends StatefulWidget {
  const DominhnhatApp({super.key, required this.api});
  final ApiClient api;

  @override
  State<DominhnhatApp> createState() => _DominhnhatAppState();
}

class _DominhnhatAppState extends State<DominhnhatApp> {
  SessionUser? _user;
  bool _restoring = true;
  bool _biometricLocked = false;
  bool _biometricBusy = false;
  String? _biometricError;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    try {
      final token = await widget.api.session.accessToken;
      if (token != null) {
        if (await widget.api.session.biometricLoginEnabled) {
          _biometricLocked = true;
        } else {
          final response =
              await widget.api.get('/api/v1/auth/me') as Map<String, dynamic>;
          _user = SessionUser.fromJson(response);
        }
      }
    } catch (_) {
      // Keep secure tokens when the API is temporarily unavailable.
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  void _authenticated(SessionUser user) => setState(() => _user = user);

  Future<void> _loginWithBiometrics() async {
    if (_biometricBusy) return;
    setState(() {
      _biometricBusy = true;
      _biometricError = null;
    });
    try {
      final authenticated = await LocalAuthentication().authenticate(
        localizedReason: 'Đăng nhập DOMINHNHAT bằng khuôn mặt hoặc vân tay',
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
      if (!authenticated) return;
      final response =
          await widget.api.get('/api/v1/auth/me') as Map<String, dynamic>;
      if (mounted) {
        setState(() {
          _user = SessionUser.fromJson(response);
          _biometricLocked = false;
        });
      }
    } catch (error) {
      if (mounted) {
        final message = error is ApiException
            ? error.message
            : 'Không xác thực được. Thử lại hoặc đăng nhập bằng mật khẩu.';
        setState(() => _biometricError = message);
      }
    } finally {
      if (mounted) setState(() => _biometricBusy = false);
    }
  }

  Future<void> _usePasswordLogin() async {
    await widget.api.logout();
    if (mounted) {
      setState(() {
        _user = null;
        _biometricLocked = false;
        _biometricError = null;
      });
    }
  }

  Future<void> _logout() async {
    await widget.api.logout();
    if (mounted) setState(() => _user = null);
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'DOMINHNHAT',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF246B62),
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: const Color(0xFFF5F7F6),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFFF5F7F6),
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      dividerTheme: const DividerThemeData(
        color: Color(0xFFE7ECEA),
        space: 1,
        thickness: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE3E9E7)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF246B62), width: 1.5),
        ),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    ),
    home: _restoring
        ? const Scaffold(body: Center(child: CircularProgressIndicator()))
        : _biometricLocked
        ? _BiometricLoginPage(
            busy: _biometricBusy,
            error: _biometricError,
            onLogin: _loginWithBiometrics,
            onUsePassword: _usePasswordLogin,
          )
        : _user == null
        ? AuthPage(api: widget.api, onAuthenticated: _authenticated)
        : DashboardPage(api: widget.api, user: _user!, onLogout: _logout),
  );
}

class _BiometricLoginPage extends StatelessWidget {
  const _BiometricLoginPage({
    required this.busy,
    required this.error,
    required this.onLogin,
    required this.onUsePassword,
  });

  final bool busy;
  final String? error;
  final VoidCallback onLogin;
  final VoidCallback onUsePassword;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Icon(
                        Icons.face_retouching_natural,
                        size: 58,
                        color: colors.primary,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Đăng nhập DOMINHNHAT',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Dùng khuôn mặt hoặc vân tay đã đăng ký trên thiết bị này để mở tài khoản đã đăng nhập trước đó.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      if (error != null) ...[
                        const SizedBox(height: 16),
                        Text(
                          'Không thể đăng nhập bằng sinh trắc học. Kiểm tra mạng hoặc dùng mật khẩu.\n$error',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: colors.error),
                        ),
                      ],
                      const SizedBox(height: 22),
                      FilledButton.icon(
                        onPressed: busy ? null : onLogin,
                        icon: busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.face_retouching_natural),
                        label: const Text('Đăng nhập bằng khuôn mặt / vân tay'),
                      ),
                      TextButton(
                        onPressed: busy ? null : onUsePassword,
                        child: const Text('Đăng nhập bằng mật khẩu'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
