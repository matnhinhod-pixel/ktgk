import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

import '../../core/session.dart';
import '../attendance/attendance_pages.dart';
import '../resources/resource_page.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key, required this.api, required this.user, required this.onLogout});

  final ApiClient api;
  final SessionUser user;
  final VoidCallback onLogout;

  bool get isAdmin => user.role.toLowerCase() == 'admin';
  bool get isGuest => user.role.toLowerCase() == 'guest';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('DOMINHNHAT'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'logout') onLogout();
              if (value == 'biometric') _configureBiometrics(context);
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'biometric', child: Text('Mở khóa sinh trắc học')),
              PopupMenuItem(value: 'logout', child: Text('Đăng xuất')),
            ],
            icon: const Icon(Icons.account_circle_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: LinearGradient(colors: [theme.colorScheme.primary, theme.colorScheme.tertiary]),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Xin chào, ${user.username}', style: theme.textTheme.titleLarge?.copyWith(
                  color: theme.colorScheme.onPrimary, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text('Bảng điều khiển ${isAdmin ? 'quản trị' : isGuest ? 'khách' : 'nhân viên'}',
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onPrimary.withValues(alpha: .85))),
              const SizedBox(height: 18),
              Align(
                alignment: Alignment.centerLeft,
                child: Chip(
                  avatar: Icon(isAdmin ? Icons.admin_panel_settings_outlined : Icons.badge_outlined, size: 18),
                  label: Text(user.role),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ]),
          ),
          const SizedBox(height: 24),
          if (!isGuest) ...[
            Text('Chấm công', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
          ],
          if (!isAdmin && !isGuest) ...[
            _ActionCard(
              icon: Icons.qr_code_scanner_rounded,
              title: 'Quét QR để check-in',
              subtitle: 'Gửi QR và vị trí GPS để xác minh ca',
              color: theme.colorScheme.primaryContainer,
              onTap: () => _open(context, AttendanceScannerPage(api: api)),
            ),
            _ActionCard(
              icon: Icons.logout_rounded,
              title: 'Check-out',
              subtitle: 'Ghi nhận vị trí khi kết thúc ca',
              color: theme.colorScheme.secondaryContainer,
              onTap: () => _open(context, CheckOutPage(api: api)),
            ),
          ],
          if (!isGuest) _ActionCard(
            icon: Icons.history_rounded,
            title: isAdmin ? 'Bản ghi chấm công' : 'Lịch sử chấm công',
            subtitle: isAdmin ? 'Xem và rà soát các lượt chấm công' : 'Theo dõi các lượt của bạn',
            color: theme.colorScheme.surfaceContainerHighest,
            onTap: () => _open(context, ResourcePage(api: api, kind: ResourceKind.attendance, canManage: isAdmin)),
          ),
          const SizedBox(height: 20),
          Text(isAdmin ? 'Quản trị hệ thống' : isGuest ? 'Thông tin dành cho khách' : 'Thông tin ca làm',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          if (isAdmin) ...[
            _ActionCard(icon: Icons.people_alt_outlined, title: 'Nhân viên', subtitle: 'Quản lý hồ sơ nhân viên',
                color: theme.colorScheme.surfaceContainerHighest,
                onTap: () => _open(context, ResourcePage(api: api, kind: ResourceKind.employees, canManage: true))),
            _ActionCard(icon: Icons.schedule_rounded, title: 'Ca làm', subtitle: 'Tạo và quản lý ca làm',
                color: theme.colorScheme.surfaceContainerHighest,
                onTap: () => _open(context, ResourcePage(api: api, kind: ResourceKind.shifts, canManage: true))),
            _ActionCard(icon: Icons.location_on_outlined, title: 'Nơi làm việc', subtitle: 'Thiết lập tọa độ và bán kính GPS',
                color: theme.colorScheme.surfaceContainerHighest,
                onTap: () => _open(context, ResourcePage(api: api, kind: ResourceKind.worksites, canManage: true))),
            _ActionCard(icon: Icons.qr_code_2_rounded, title: 'Tạo mã QR chấm công', subtitle: 'QR có hạn dùng và chỉ sử dụng một lần',
                color: theme.colorScheme.secondaryContainer,
                onTap: () => _open(context, CreateQrPage(api: api))),
          ] else ...[
            _ActionCard(icon: Icons.calendar_month_outlined, title: 'Ca làm đang hoạt động', subtitle: 'Xem danh sách ca hiện tại',
                color: theme.colorScheme.surfaceContainerHighest,
                onTap: () => _open(context, ResourcePage(api: api, kind: ResourceKind.shifts, readOnly: true))),
          ],
          const SizedBox(height: 12),
          Text('Tài khoản: ${user.email}', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  void _open(BuildContext context, Widget page) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

  Future<void> _configureBiometrics(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final enabled = await api.session.biometricUnlockEnabled;
    if (enabled) {
      await api.session.setBiometricUnlockEnabled(false);
      messenger.showSnackBar(const SnackBar(content: Text('Đã tắt mở khóa sinh trắc học.')));
      return;
    }

    final auth = LocalAuthentication();
    try {
      if ((await auth.getAvailableBiometrics()).isEmpty) {
        messenger.showSnackBar(const SnackBar(content: Text('Thiết bị chưa đăng ký sinh trắc học.')));
        return;
      }
      final verified = await auth.authenticate(
        localizedReason: 'Xác thực để bật mở khóa DOMINHNHAT',
        biometricOnly: true,
      );
      if (!verified) return;
      await api.session.setBiometricUnlockEnabled(true);
      messenger.showSnackBar(const SnackBar(content: Text('Đã bật. Lần mở app sau, xác thực bằng sinh trắc học thiết bị.')));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('Không thể dùng sinh trắc học trên thiết bị này.')));
    }
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({required this.icon, required this.title, required this.subtitle, required this.color, required this.onTap});
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
          contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          leading: CircleAvatar(child: Icon(icon)),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: onTap,
        ),
      );
}
