import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

import '../../core/session.dart';
import '../attendance/attendance_pages.dart';
import '../resources/resource_page.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({
    super.key,
    required this.api,
    required this.user,
    required this.onLogout,
  });

  final ApiClient api;
  final SessionUser user;
  final VoidCallback onLogout;

  bool get isAdmin => user.role.toLowerCase() == 'admin';
  bool get isGuest => user.role.toLowerCase() == 'guest';
  bool get isEmployee => user.role.toLowerCase() == 'employee';
  bool get hasSupportedRole => isAdmin || isGuest || isEmployee;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(
              Icons.access_time_filled_rounded,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 9),
            const Text('DOMINHNHAT'),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'logout') onLogout();
              if (value == 'biometric') _configureBiometricLogin(context);
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'biometric',
                child: Text('Bật/tắt đăng nhập khuôn mặt / vân tay'),
              ),
              PopupMenuItem(value: 'logout', child: Text('Đăng xuất')),
            ],
            icon: const Icon(Icons.account_circle_outlined),
          ),
        ],
      ),
      body: hasSupportedRole
          ? SafeArea(
              top: false,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 30),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              theme.colorScheme.primary,
                              theme.colorScheme.tertiary,
                            ],
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  radius: 25,
                                  backgroundColor: theme.colorScheme.onPrimary
                                      .withValues(alpha: .16),
                                  foregroundColor: theme.colorScheme.onPrimary,
                                  child: Icon(
                                    isAdmin
                                        ? Icons.admin_panel_settings_outlined
                                        : Icons.person_outline_rounded,
                                    size: 27,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Xin chào, ${user.username}',
                                        style: theme.textTheme.titleLarge
                                            ?.copyWith(
                                              color:
                                                  theme.colorScheme.onPrimary,
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Bảng điều khiển ${isAdmin
                                            ? 'quản trị'
                                            : isGuest
                                            ? 'khách'
                                            : 'nhân viên'}',
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(
                                              color: theme.colorScheme.onPrimary
                                                  .withValues(alpha: .82),
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Chip(
                                backgroundColor: theme.colorScheme.onPrimary
                                    .withValues(alpha: .16),
                                side: BorderSide.none,
                                avatar: Icon(
                                  isAdmin
                                      ? Icons.admin_panel_settings_outlined
                                      : Icons.badge_outlined,
                                  size: 18,
                                  color: theme.colorScheme.onPrimary,
                                ),
                                label: Text(
                                  user.role,
                                  style: TextStyle(
                                    color: theme.colorScheme.onPrimary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      if (!isGuest) ...[
                        Text(
                          'Chấm công',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                      if (isEmployee) ...[
                        _ActionCard(
                          icon: Icons.qr_code_scanner_rounded,
                          title: 'Quét QR để check-in',
                          subtitle: 'Gửi QR và vị trí GPS để xác minh ca',
                          color: theme.colorScheme.primaryContainer,
                          onTap: () =>
                              _open(context, AttendanceScannerPage(api: api)),
                        ),
                        _ActionCard(
                          icon: Icons.logout_rounded,
                          title: 'Check-out',
                          subtitle: 'Ghi nhận vị trí khi kết thúc ca',
                          color: theme.colorScheme.secondaryContainer,
                          onTap: () => _open(context, CheckOutPage(api: api)),
                        ),
                      ],
                      if (isAdmin || isEmployee)
                        _ActionCard(
                          icon: Icons.history_rounded,
                          title: isAdmin
                              ? 'Bản ghi chấm công'
                              : 'Lịch sử chấm công',
                          subtitle: isAdmin
                              ? 'Xem và rà soát các lượt chấm công'
                              : 'Theo dõi các lượt của bạn',
                          color: theme.colorScheme.surfaceContainerHighest,
                          onTap: () => _open(
                            context,
                            ResourcePage(
                              api: api,
                              kind: ResourceKind.attendance,
                              canManage: isAdmin,
                            ),
                          ),
                        ),
                      const SizedBox(height: 20),
                      Text(
                        isAdmin
                            ? 'Quản trị hệ thống'
                            : isGuest
                            ? 'Thông tin dành cho khách'
                            : 'Thông tin ca làm',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (isAdmin) ...[
                        _ActionCard(
                          icon: Icons.people_alt_outlined,
                          title: 'Nhân viên',
                          subtitle: 'Quản lý hồ sơ nhân viên',
                          color: theme.colorScheme.surfaceContainerHighest,
                          onTap: () => _open(
                            context,
                            ResourcePage(
                              api: api,
                              kind: ResourceKind.employees,
                              canManage: true,
                            ),
                          ),
                        ),
                        _ActionCard(
                          icon: Icons.schedule_rounded,
                          title: 'Ca làm',
                          subtitle: 'Tạo và quản lý ca làm',
                          color: theme.colorScheme.surfaceContainerHighest,
                          onTap: () => _open(
                            context,
                            ResourcePage(
                              api: api,
                              kind: ResourceKind.shifts,
                              canManage: true,
                            ),
                          ),
                        ),
                        _ActionCard(
                          icon: Icons.location_on_outlined,
                          title: 'Nơi làm việc',
                          subtitle: 'Thiết lập tọa độ và bán kính GPS',
                          color: theme.colorScheme.surfaceContainerHighest,
                          onTap: () => _open(
                            context,
                            ResourcePage(
                              api: api,
                              kind: ResourceKind.worksites,
                              canManage: true,
                            ),
                          ),
                        ),
                        _ActionCard(
                          icon: Icons.qr_code_2_rounded,
                          title: 'Tạo mã QR chấm công',
                          subtitle: 'QR có hạn dùng và chỉ sử dụng một lần',
                          color: theme.colorScheme.secondaryContainer,
                          onTap: () => _open(context, CreateQrPage(api: api)),
                        ),
                      ] else ...[
                        _ActionCard(
                          icon: Icons.calendar_month_outlined,
                          title: 'Ca làm đang hoạt động',
                          subtitle: 'Xem danh sách ca hiện tại',
                          color: theme.colorScheme.surfaceContainerHighest,
                          onTap: () => _open(
                            context,
                            ResourcePage(
                              api: api,
                              kind: ResourceKind.shifts,
                              readOnly: true,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Text(
                        'Tài khoản: ${user.email}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          : Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.gpp_bad_outlined, size: 56),
                    const SizedBox(height: 12),
                    Text(
                      'Tài khoản chưa được cấp vai trò hợp lệ.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Vui lòng liên hệ quản trị viên để được phân quyền.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  void _open(BuildContext context, Widget page) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

  Future<void> _configureBiometricLogin(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final enabled = await api.session.biometricLoginEnabled;
    if (enabled) {
      await api.session.setBiometricLoginEnabled(false);
      messenger.showSnackBar(
        const SnackBar(content: Text('Đã tắt đăng nhập sinh trắc học.')),
      );
      return;
    }

    final auth = LocalAuthentication();
    try {
      if (!await auth.canCheckBiometrics ||
          (await auth.getAvailableBiometrics()).isEmpty) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Thiết bị chưa đăng ký khuôn mặt hoặc vân tay.'),
          ),
        );
        return;
      }
      final verified = await auth.authenticate(
        localizedReason:
            'Xác thực để bật đăng nhập khuôn mặt hoặc vân tay trên thiết bị này',
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
      if (!verified) return;
      await api.session.setBiometricLoginEnabled(true);
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Đã bật. Lần sau, dùng khuôn mặt hoặc vân tay để mở tài khoản trên thiết bị này.',
          ),
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Không thể xác thực sinh trắc học trên thiết bị này.'),
        ),
      );
    }
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    color: color,
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      minLeadingWidth: 50,
      leading: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface.withValues(alpha: .78),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon, color: Theme.of(context).colorScheme.primary),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
      ),
      trailing: Icon(
        Icons.arrow_forward_ios_rounded,
        size: 16,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      onTap: onTap,
    ),
  );
}
