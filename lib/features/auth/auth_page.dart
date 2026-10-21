import 'package:flutter/material.dart';

import '../../core/session.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({super.key, required this.api, required this.onAuthenticated});

  final ApiClient api;
  final ValueChanged<SessionUser> onAuthenticated;

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _otp = TextEditingController();
  bool _register = false;
  bool _waitingForOtp = false;
  bool _busy = false;
  bool _hidePassword = true;
  String _accountType = 'Employee';
  String? _challengeId;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _email.dispose();
    _password.dispose();
    _otp.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_waitingForOtp) {
        final response = await widget.api.postPublic('/api/v1/auth/verify-otp', {
          'challengeId': _challengeId,
          'code': _otp.text.trim(),
        }) as Map<String, dynamic>;
        await widget.api.session.save(
          response['accessToken'] as String,
          response['refreshToken'] as String,
        );
        widget.onAuthenticated(SessionUser.fromJson(
          Map<String, dynamic>.from(response['user'] as Map),
        ));
      } else if (_register) {
        await widget.api.postPublic('/api/v1/auth/register', {
          'username': _username.text.trim(),
          'email': _email.text.trim(),
          'password': _password.text,
          'accountType': _accountType,
        });
        if (!mounted) return;
        setState(() => _register = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tài khoản đã tạo. Đăng nhập để nhận OTP qua email.')),
        );
      } else {
        final response = await widget.api.postPublic('/api/v1/auth/login', {
          'username': _username.text.trim(),
          'password': _password.text,
        }) as Map<String, dynamic>;
        if (!mounted) return;
        if (response['accessToken'] is String) {
          await widget.api.session.save(
            response['accessToken'] as String,
            response['refreshToken'] as String,
          );
          widget.onAuthenticated(SessionUser.fromJson(
            Map<String, dynamic>.from(response['user'] as Map),
          ));
        } else {
          setState(() {
            _challengeId = response['challengeId'] as String;
            _waitingForOtp = true;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Đã gửi mã OTP tới email đăng ký.')),
          );
        }
      }
    } on ApiException catch (exception) {
      if (mounted) setState(() => _error = _friendlyError(exception));
    } catch (_) {
      if (mounted) setState(() => _error = 'Đã xảy ra lỗi. Vui lòng thử lại.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _friendlyError(ApiException exception) {
    if (exception.statusCode == 0) return 'Không kết nối được máy chủ. Kiểm tra mạng hoặc URL API.';
    if (exception.statusCode == 503) return 'Dịch vụ chưa được cấu hình Firestore hoặc email OTP.';
    if (exception.statusCode == 401) {
      return _waitingForOtp
          ? 'Mã OTP sai, hết hạn hoặc đã được sử dụng.'
          : 'Tên đăng nhập hoặc mật khẩu không đúng.';
    }
    if (exception.statusCode == 409) return exception.message;
    return exception.message;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [colors.primaryContainer.withValues(alpha: .42), colors.surface, colors.surface],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Card(
                  elevation: 0,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 30, 24, 24),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          CircleAvatar(
                            radius: 30,
                            backgroundColor: colors.primary,
                            foregroundColor: colors.onPrimary,
                            child: const Icon(Icons.badge_outlined, size: 30),
                          ),
                          const SizedBox(height: 18),
          Text('DOMINHNHAT', textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                          const SizedBox(height: 6),
                          Text(
                            _waitingForOtp ? 'Xác minh đăng nhập' : (_register ? 'Tạo tài khoản ${_accountType == 'Guest' ? 'khách' : 'nhân viên'}' : 'Chấm công thông minh'),
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
                          ),
                          const SizedBox(height: 26),
                          if (!_waitingForOtp) ...[
                            _field(_username, 'Tên đăng nhập', Icons.person_outline,
                                validator: _register ? _validUsername : _required),
                            if (_register) ...[
                              const SizedBox(height: 14),
                              DropdownButtonFormField<String>(
                                initialValue: _accountType,
                                decoration: const InputDecoration(
                                  labelText: 'Loại tài khoản',
                                  prefixIcon: Icon(Icons.badge_outlined),
                                ),
                                items: const [
                                  DropdownMenuItem(value: 'Employee', child: Text('Nhân viên')),
                                  DropdownMenuItem(value: 'Guest', child: Text('Khách / Customer')),
                                ],
                                onChanged: (value) {
                                  if (value != null) setState(() => _accountType = value);
                                },
                              ),
                              const SizedBox(height: 14),
                              _field(_email, 'Email', Icons.mail_outline, keyboardType: TextInputType.emailAddress,
                                  validator: (value) => value != null && value.contains('@') ? null : 'Nhập email hợp lệ.'),
                            ],
                            const SizedBox(height: 14),
                            TextFormField(
                              controller: _password,
                              obscureText: _hidePassword,
                              validator: (value) {
                                if (value == null || value.isEmpty) return 'Nhập mật khẩu.';
                                if (_register && value.length < 10) return 'Mật khẩu cần ít nhất 10 ký tự.';
                                if (_register && value.length > 128) return 'Mật khẩu tối đa 128 ký tự.';
                                return null;
                              },
                              decoration: InputDecoration(
                                labelText: 'Mật khẩu',
                                prefixIcon: const Icon(Icons.lock_outline),
                                suffixIcon: IconButton(
                                  onPressed: () => setState(() => _hidePassword = !_hidePassword),
                                  icon: Icon(_hidePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                                ),
                              ),
                            ),
                          ] else ...[
                            Text('Nhập mã 6 chữ số đã gửi tới email của bạn.',
                                style: Theme.of(context).textTheme.bodyMedium),
                            const SizedBox(height: 16),
                            _field(_otp, 'Mã OTP', Icons.password, keyboardType: TextInputType.number,
                                validator: (value) => value != null && RegExp(r'^\d{6}$').hasMatch(value)
                                    ? null : 'Mã OTP gồm 6 chữ số.'),
                          ],
                          if (_error != null) ...[
                            const SizedBox(height: 14),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(color: colors.errorContainer, borderRadius: BorderRadius.circular(12)),
                              child: Text(_error!, style: TextStyle(color: colors.onErrorContainer)),
                            ),
                          ],
                          const SizedBox(height: 22),
                          FilledButton.icon(
                            onPressed: _busy ? null : _submit,
                            icon: _busy
                                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                : Icon(_waitingForOtp ? Icons.verified_user_outlined : Icons.arrow_forward_rounded),
                            label: Text(_waitingForOtp ? 'Xác minh OTP' : (_register ? 'Đăng ký' : 'Đăng nhập')),
                          ),
                          const SizedBox(height: 8),
                          if (_waitingForOtp)
                            TextButton(onPressed: _busy ? null : () => setState(() { _waitingForOtp = false; _otp.clear(); }),
                                child: const Text('Quay lại đăng nhập'))
                          else
                            TextButton(
                              onPressed: _busy ? null : () => setState(() { _register = !_register; _error = null; }),
                              child: Text(_register ? 'Đã có tài khoản? Đăng nhập' : 'Chưa có tài khoản? Đăng ký'),
                            ),
                          const SizedBox(height: 8),
                          Text('Kết nối bảo mật qua HTTPS', textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(TextEditingController controller, String label, IconData icon,
      {TextInputType? keyboardType, String? Function(String?)? validator}) => TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        validator: validator ?? _required,
        decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
      );

  String? _required(String? value) => value == null || value.trim().isEmpty ? 'Trường này không được để trống.' : null;

  String? _validUsername(String? value) {
    final username = value?.trim() ?? '';
    if (username.length < 3 || username.length > 40) return 'Tên đăng nhập cần từ 3 đến 40 ký tự.';
    if (!RegExp(r'^[\p{L}\p{N}_.-]+$', unicode: true).hasMatch(username)) {
      return 'Chỉ dùng chữ cái, số, dấu chấm, gạch dưới hoặc gạch ngang.';
    }
    return null;
  }
}
