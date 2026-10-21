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
  final LocalAuthentication _localAuth = LocalAuthentication();

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    try {
      final token = await widget.api.session.accessToken;
      if (token != null) {
        if (await widget.api.session.biometricUnlockEnabled) {
          _biometricLocked = true;
          final authenticated = await _authenticateBiometric();
          if (!authenticated) return;
          _biometricLocked = false;
        }
        final response = await widget.api.get('/api/v1/auth/me') as Map<String, dynamic>;
        _user = SessionUser.fromJson(response);
      }
    } catch (_) {
      // Keep secure tokens when the API is temporarily unavailable.
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  Future<bool> _authenticateBiometric() async {
    try {
      final biometrics = await _localAuth.getAvailableBiometrics();
      if (biometrics.isEmpty) return false;
      return await _localAuth.authenticate(
        localizedReason: 'Xác thực để mở DOMINHNHAT',
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
    } catch (_) {
      return false;
    }
  }

  void _authenticated(SessionUser user) => setState(() => _user = user);

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
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF246B62), brightness: Brightness.light),
          scaffoldBackgroundColor: const Color(0xFFF5F7F6),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE3E9E7))),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFF246B62), width: 1.5)),
          ),
          cardTheme: CardThemeData(color: Colors.white, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
          filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          )),
        ),
        home: _restoring
            ? const Scaffold(body: Center(child: CircularProgressIndicator()))
            : _biometricLocked
                ? _BiometricLockPage(
                    onUnlock: () async {
                      final ok = await _authenticateBiometric();
                      if (!mounted) return;
                      if (!ok) return;
                      await _restoreAfterUnlock();
                    },
                    onUsePassword: () async {
                      await widget.api.session.clear();
                      if (mounted) {
                        setState(() {
                          _biometricLocked = false;
                          _user = null;
                        });
                      }
                    },
                  )
                : _user == null
                ? AuthPage(api: widget.api, onAuthenticated: _authenticated)
                : DashboardPage(api: widget.api, user: _user!, onLogout: _logout),
      );

  Future<void> _restoreAfterUnlock() async {
    if (mounted) setState(() => _restoring = true);
    try {
      final response = await widget.api.get('/api/v1/auth/me') as Map<String, dynamic>;
      if (mounted) {
        setState(() {
          _user = SessionUser.fromJson(response);
          _biometricLocked = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _user = null;
          _biometricLocked = false;
        });
      }
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }
}

class _BiometricLockPage extends StatelessWidget {
  const _BiometricLockPage({required this.onUnlock, required this.onUsePassword});
  final VoidCallback onUnlock;
  final VoidCallback onUsePassword;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.fingerprint, size: 72),
              const SizedBox(height: 16),
              Text('DOMINHNHAT đang khóa', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              const Text('Xác thực bằng khuôn mặt hoặc vân tay đã đăng ký trên thiết bị để mở phiên. Ứng dụng không nhận hay lưu ảnh khuôn mặt.'),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onUnlock,
                icon: const Icon(Icons.lock_open_rounded),
                label: const Text('Mở khóa'),
              ),
              TextButton(onPressed: onUsePassword, child: const Text('Đăng nhập bằng mật khẩu')),
            ]),
          ),
        ),
      );
}
