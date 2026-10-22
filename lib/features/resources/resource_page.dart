import 'package:flutter/material.dart';

import '../../core/session.dart';

enum ResourceKind { employees, shifts, worksites, attendance }

class ResourcePage extends StatefulWidget {
  const ResourcePage({
    super.key,
    required this.api,
    required this.kind,
    this.readOnly = false,
    this.canManage = false,
  });
  final ApiClient api;
  final ResourceKind kind;
  final bool readOnly;
  final bool canManage;

  @override
  State<ResourcePage> createState() => _ResourcePageState();
}

class _ResourcePageState extends State<ResourcePage> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _error;

  String get _path => switch (widget.kind) {
    ResourceKind.employees => '/api/v1/employees',
    ResourceKind.shifts => '/api/v1/shifts',
    ResourceKind.worksites => '/api/v1/worksites',
    ResourceKind.attendance => '/api/v1/attendance/history',
  };

  String get _title => switch (widget.kind) {
    ResourceKind.employees => 'Nhân viên',
    ResourceKind.shifts => 'Ca làm',
    ResourceKind.worksites => 'Nơi làm việc',
    ResourceKind.attendance => 'Chấm công',
  };

  List<_Field> get _fields => switch (widget.kind) {
    ResourceKind.employees => const [
      _Field('employeeCode', 'Mã nhân viên'),
      _Field('fullName', 'Họ và tên'),
      _Field('email', 'Email', keyboardType: TextInputType.emailAddress),
      _Field('department', 'Phòng ban'),
      _Field('worksiteId', 'Worksite ID (tuỳ chọn)'),
    ],
    ResourceKind.shifts => const [
      _Field('name', 'Tên ca'),
      _Field('startTime', 'Bắt đầu (HH:mm)'),
      _Field('endTime', 'Kết thúc (HH:mm)'),
      _Field(
        'graceMinutes',
        'Thời gian linh động (phút)',
        keyboardType: TextInputType.number,
        isNumeric: true,
      ),
      _Field('worksiteId', 'Worksite ID'),
    ],
    ResourceKind.worksites => const [
      _Field('name', 'Tên nơi làm việc'),
      _Field(
        'latitude',
        'Vĩ độ',
        keyboardType: TextInputType.numberWithOptions(
          decimal: true,
          signed: true,
        ),
        isNumeric: true,
      ),
      _Field(
        'longitude',
        'Kinh độ',
        keyboardType: TextInputType.numberWithOptions(
          decimal: true,
          signed: true,
        ),
        isNumeric: true,
      ),
      _Field(
        'allowedRadiusMeters',
        'Bán kính cho phép (m)',
        keyboardType: TextInputType.number,
        isNumeric: true,
      ),
    ],
    ResourceKind.attendance => const [],
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.api.get(_path);
      final list = (result as List)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
      if (mounted) {
        setState(() {
          _items = list;
          _loading = false;
        });
      }
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _error = error.message;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Không tải được dữ liệu.';
          _loading = false;
        });
      }
    }
  }

  Future<void> _edit([Map<String, dynamic>? item]) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _EditDialog(
        title: '${item == null ? 'Thêm' : 'Sửa'} $_title',
        fields: _fields,
        initial: item,
      ),
    );
    if (result == null) return;
    try {
      if (item == null) {
        await widget.api.post(_path, result);
      } else {
        await widget.api.put('$_path/${item['id']}', result);
      }
      await _load();
    } on ApiException catch (error) {
      if (mounted) _showError(error.message);
    }
  }

  Future<void> _delete(Map<String, dynamic> item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xác nhận vô hiệu hoá'),
        content: Text(
          'Vô hiệu hoá mục "${_itemTitle(item)}"? Dữ liệu lịch sử vẫn được giữ lại.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Vô hiệu hoá'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.api.delete('$_path/${item['id']}');
      await _load();
    } on ApiException catch (error) {
      if (mounted) _showError(error.message);
    }
  }

  void _showError(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  String _itemTitle(Map<String, dynamic> item) =>
      (item['fullName'] ??
              item['name'] ??
              item['employeeCode'] ??
              item['employeeId'] ??
              item['id'] ??
              'Record')
          .toString();
  String _itemSubtitle(Map<String, dynamic> item) {
    final details = switch (widget.kind) {
      ResourceKind.employees =>
        '${item['employeeCode'] ?? ''} • ${item['department'] ?? 'Chưa có phòng ban'}',
      ResourceKind.shifts =>
        '${item['startTime'] ?? ''} – ${item['endTime'] ?? ''} • ${item['worksiteId'] ?? 'Chưa gán worksite'}',
      ResourceKind.worksites =>
        '${item['latitude']}, ${item['longitude']} • bán kính ${item['allowedRadiusMeters']} m',
      ResourceKind.attendance =>
        '${_verificationLabel(item['verificationStatus']?.toString())} • ${_recordStatusLabel(item['status']?.toString())} • ${item['checkInAtUtc'] ?? 'Chưa có thời gian'}',
    };
    if (item.containsKey('isActive')) {
      return '$details • ${item['isActive'] == true ? 'Đang hoạt động' : 'Đã vô hiệu hoá'}';
    }
    return details;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(_title),
      actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
    ),
    floatingActionButton:
        widget.canManage &&
            !widget.readOnly &&
            widget.kind != ResourceKind.attendance
        ? FloatingActionButton.extended(
            onPressed: () => _edit(),
            icon: const Icon(Icons.add),
            label: const Text('Thêm'),
          )
        : null,
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
        ? _ErrorState(message: _error!, onRetry: _load)
        : _items.isEmpty
        ? RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              children: const [SizedBox(height: 180), _EmptyState()],
            ),
          )
        : RefreshIndicator(
            onRefresh: _load,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
              itemCount: _items.length,
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final item = _items[index];
                final actionsEnabled =
                    widget.canManage &&
                    !widget.readOnly &&
                    widget.kind != ResourceKind.attendance;
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: widget.kind == ResourceKind.attendance
                          ? _attendanceStatusColor(
                              context,
                              item['verificationStatus']?.toString(),
                            ).withValues(alpha: .12)
                          : Theme.of(context).colorScheme.primaryContainer,
                      foregroundColor: widget.kind == ResourceKind.attendance
                          ? _attendanceStatusColor(
                              context,
                              item['verificationStatus']?.toString(),
                            )
                          : Theme.of(context).colorScheme.primary,
                      child: Icon(_icon),
                    ),
                    title: Text(
                      _itemTitle(item),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      _itemSubtitle(item),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: actionsEnabled
                        ? PopupMenuButton<String>(
                            onSelected: (value) =>
                                value == 'edit' ? _edit(item) : _delete(item),
                            itemBuilder: (_) => const [
                              PopupMenuItem(value: 'edit', child: Text('Sửa')),
                              PopupMenuItem(
                                value: 'delete',
                                child: Text('Vô hiệu hoá'),
                              ),
                            ],
                          )
                        : null,
                    onTap: widget.kind == ResourceKind.attendance
                        ? () => _showAttendance(item)
                        : null,
                  ),
                );
              },
            ),
          ),
  );

  IconData get _icon => switch (widget.kind) {
    ResourceKind.employees => Icons.person_outline,
    ResourceKind.shifts => Icons.schedule,
    ResourceKind.worksites => Icons.location_on_outlined,
    ResourceKind.attendance => Icons.fact_check_outlined,
  };

  Future<void> _showAttendance(Map<String, dynamic> item) async {
    final flags = item['flags'] is List ? (item['flags'] as List) : const [];
    List<Map<String, dynamic>> auditEvents = [];
    try {
      final result = await widget.api.get(
        '/api/v1/attendance/${item['id']}/audit',
      );
      auditEvents = (result as List)
          .map((event) => Map<String, dynamic>.from(event as Map))
          .toList();
    } on ApiException catch (error) {
      if (mounted) _showError(error.message);
    }
    if (!mounted) return;
    final explanation = TextEditingController(
      text: (item[widget.canManage ? 'adminNote' : 'explanation'] ?? '')
          .toString(),
    );
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Chi tiết lượt chấm công',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 14),
              _DetailLine(
                'Trạng thái',
                '${_recordStatusLabel(item['status']?.toString())} / ${_verificationLabel(item['verificationStatus']?.toString())}',
              ),
              _DetailLine('Nhân viên', '${item['employeeId'] ?? '-'}'),
              _DetailLine(
                'Ca làm',
                '${item['shiftName'] ?? item['shiftId'] ?? '-'}',
              ),
              _DetailLine('Check-in', '${item['checkInAtUtc'] ?? '-'}'),
              _DetailLine('Check-out', '${item['checkOutAtUtc'] ?? '-'}'),
              _DetailLine(
                'QR',
                item['qrVerified'] == true ? 'Đã xác thực' : 'Chưa lưu dữ liệu',
              ),
              _DetailLine(
                'Độ chính xác GPS',
                item['checkInAccuracyMeters'] == null
                    ? 'Chưa lưu dữ liệu'
                    : '${(item['checkInAccuracyMeters'] as num).round()} m',
              ),
              _DetailLine(
                'Khoảng cách',
                item['distanceToWorksiteMeters'] == null
                    ? 'Chưa lưu dữ liệu'
                    : '${(item['distanceToWorksiteMeters'] as num).round()} m / bán kính ${(item['allowedRadiusMeters'] as num?)?.round() ?? '-'} m',
              ),
              if (item['verificationChecks'] is List) ...[
                const SizedBox(height: 6),
                Text(
                  'Các bước xác minh',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                for (final check
                    in (item['verificationChecks'] as List).whereType<Map>())
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      check['passed'] == true
                          ? Icons.check_circle
                          : Icons.error_outline,
                      color: check['passed'] == true
                          ? Colors.green
                          : Theme.of(context).colorScheme.error,
                    ),
                    title: Text('${check['label'] ?? 'Kiểm tra'}'),
                    subtitle: Text('${check['detail'] ?? ''}'),
                  ),
              ],
              _DetailLine(
                'Cảnh báo',
                flags.isEmpty
                    ? 'Không có'
                    : flags
                          .map((flag) => _flagLabel(flag.toString()))
                          .join(', '),
              ),
              if ((item['explanation'] ?? '').toString().isNotEmpty)
                _DetailLine('Giải trình', item['explanation'].toString()),
              if ((item['adminNote'] ?? '').toString().isNotEmpty)
                _DetailLine('Ghi chú quản trị', item['adminNote'].toString()),
              if (auditEvents.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  'Lịch sử xử lý',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                for (final event in auditEvents)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.history),
                    title: Text(
                      '${_auditAction(event['action']?.toString())} • ${_verificationLabel(event['verificationStatus']?.toString())}',
                    ),
                    subtitle: Text(
                      '${event['actorRole'] ?? ''} • ${event['createdAtUtc'] ?? ''}${(event['note'] ?? '').toString().isEmpty ? '' : '\n${event['note']}'}',
                    ),
                  ),
              ],
              if (widget.canManage) ...[
                const SizedBox(height: 14),
                TextField(
                  controller: explanation,
                  maxLength: 2000,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Ghi chú quản trị',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _reviewAttendance(
                        item,
                        'ReviewRequired',
                        explanation.text.trim(),
                      ),
                      icon: const Icon(Icons.flag_outlined),
                      label: const Text('Cần xem xét'),
                    ),
                    FilledButton.icon(
                      onPressed: () => _reviewAttendance(
                        item,
                        'Verified',
                        explanation.text.trim(),
                      ),
                      icon: const Icon(Icons.verified_outlined),
                      label: const Text('Duyệt hợp lệ'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _reviewAttendance(
                        item,
                        'Rejected',
                        explanation.text.trim(),
                      ),
                      icon: const Icon(Icons.cancel_outlined),
                      label: const Text('Từ chối'),
                    ),
                    if (item['status'] != 'Voided')
                      TextButton.icon(
                        onPressed: () => _voidAttendance(item),
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Hủy bản ghi'),
                      ),
                  ],
                ),
              ] else ...[
                const SizedBox(height: 14),
                TextField(
                  controller: explanation,
                  maxLength: 2000,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Giải trình',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: () async {
                    try {
                      await widget.api.post(
                        '/api/v1/attendance/${item['id']}/explanations',
                        {'explanation': explanation.text.trim()},
                      );
                      if (context.mounted) Navigator.pop(context);
                      await _load();
                    } on ApiException catch (error) {
                      if (context.mounted) _showError(error.message);
                    }
                  },
                  icon: const Icon(Icons.send_outlined),
                  label: const Text('Gửi giải trình'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    explanation.dispose();
  }

  String _verificationLabel(String? value) => switch (value) {
    'Verified' => 'Hợp lệ',
    'ReviewRequired' => 'Cần xem xét',
    'ExplanationSubmitted' => 'Đã gửi giải trình',
    'Rejected' => 'Từ chối',
    _ => value ?? 'Chưa xác định',
  };

  String _recordStatusLabel(String? value) => switch (value) {
    'Open' => 'Đang làm',
    'Closed' => 'Đã kết thúc',
    'Voided' => 'Đã hủy',
    _ => value ?? 'Chưa xác định',
  };

  String _flagLabel(String value) => switch (value) {
    'outside_shift_window' => 'Ngoài khung giờ ca',
    'low_gps_accuracy' => 'GPS chưa đủ chính xác',
    'worksite_inactive' => 'Nơi làm việc đã ngừng hoạt động',
    'outside_worksite_radius' => 'Vượt bán kính nơi làm việc',
    'worksite_not_configured' => 'Không tìm thấy nơi làm việc',
    'shift_has_no_worksite' => 'Ca chưa được gán nơi làm việc',
    _ => value,
  };

  Color _attendanceStatusColor(BuildContext context, String? value) {
    final colors = Theme.of(context).colorScheme;
    return switch (value) {
      'Verified' => const Color(0xFF24734D),
      'Rejected' => colors.error,
      'ReviewRequired' || 'ExplanationSubmitted' => const Color(0xFF9A6410),
      _ => colors.primary,
    };
  }

  String _auditAction(String? value) => switch (value) {
    'check_in_recorded' => 'Đã chấm công',
    'check_out_recorded' => 'Đã kết thúc ca',
    'explanation_submitted' => 'Nhân viên gửi giải trình',
    'admin_reviewed' => 'Quản trị viên xử lý',
    'attendance_voided' => 'Bản ghi đã hủy',
    _ => value ?? 'Cập nhật',
  };

  Future<void> _reviewAttendance(
    Map<String, dynamic> item,
    String status,
    String? note,
  ) async {
    try {
      await widget.api.put('/api/v1/attendance/${item['id']}', {
        'verificationStatus': status,
        'explanation': note,
      });
      if (mounted) Navigator.pop(context);
      await _load();
    } on ApiException catch (error) {
      if (mounted) _showError(error.message);
    }
  }

  Future<void> _voidAttendance(Map<String, dynamic> item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Hủy lượt chấm công?'),
        content: const Text(
          'Bản ghi sẽ được đánh dấu đã hủy và vẫn được giữ trong lịch sử kiểm tra.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Quay lại'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Hủy bản ghi'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.api.delete('/api/v1/attendance/${item['id']}');
      if (mounted) Navigator.pop(context);
      await _load();
    } on ApiException catch (error) {
      if (mounted) _showError(error.message);
    }
  }
}

class _EditDialog extends StatefulWidget {
  const _EditDialog({required this.title, required this.fields, this.initial});
  final String title;
  final List<_Field> fields;
  final Map<String, dynamic>? initial;

  @override
  State<_EditDialog> createState() => _EditDialogState();
}

class _EditDialogState extends State<_EditDialog> {
  late final Map<String, TextEditingController> _controllers = {
    for (final field in widget.fields)
      field.keyName: TextEditingController(
        text: widget.initial?[field.keyName]?.toString() ?? '',
      ),
  };
  final _key = GlobalKey<FormState>();
  late bool _isActive = widget.initial?['isActive'] == true;

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 420,
      child: Form(
        key: _key,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.initial != null)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Đang hoạt động'),
                  value: _isActive,
                  onChanged: (value) => setState(() => _isActive = value),
                ),
              for (final field in widget.fields)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextFormField(
                    controller: _controllers[field.keyName],
                    keyboardType: field.keyboardType,
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Bắt buộc nhập.'
                        : null,
                    decoration: InputDecoration(labelText: field.label),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Huỷ'),
      ),
      FilledButton(
        onPressed: () {
          if (!_key.currentState!.validate()) return;
          final data = <String, dynamic>{};
          for (final field in widget.fields) {
            final value = _controllers[field.keyName]!.text.trim();
            data[field.keyName] = field.isNumeric
                ? (num.tryParse(value) ?? value)
                : value;
          }
          if (widget.initial != null) data['isActive'] = _isActive;
          Navigator.pop(context, data);
        },
        child: const Text('Lưu'),
      ),
    ],
  );
}

class _Field {
  const _Field(
    this.keyName,
    this.label, {
    this.keyboardType,
    this.isNumeric = false,
  });
  final String keyName;
  final String label;
  final TextInputType? keyboardType;
  final bool isNumeric;
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_outlined, size: 42),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Thử lại'),
          ),
        ],
      ),
    ),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) =>
      const Center(child: Text('Chưa có dữ liệu. Kéo xuống để tải lại.'));
}

class _DetailLine extends StatelessWidget {
  const _DetailLine(this.title, this.value);
  final String title;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 105,
          child: Text(title, style: Theme.of(context).textTheme.labelLarge),
        ),
        Expanded(child: Text(value)),
      ],
    ),
  );
}
