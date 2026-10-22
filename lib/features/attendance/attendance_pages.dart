import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/session.dart';
import '../resources/resource_page.dart';

class AttendanceScannerPage extends StatefulWidget {
  const AttendanceScannerPage({super.key, required this.api});
  final ApiClient api;

  @override
  State<AttendanceScannerPage> createState() => _AttendanceScannerPageState();
}

class _AttendanceScannerPageState extends State<AttendanceScannerPage> {
  final _controller = MobileScannerController();
  bool _busy = false;
  String? _message;
  Map<String, dynamic>? _receipt;
  bool _isError = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_busy || capture.barcodes.isEmpty) return;
    final raw = capture.barcodes.first.rawValue;
    if (raw == null || raw.isEmpty) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await _controller.stop();
      final payload = jsonDecode(raw) as Map<String, dynamic>;
      final shiftId = payload['shiftId']?.toString();
      final qrToken = payload['qrToken']?.toString();
      if (shiftId == null ||
          shiftId.isEmpty ||
          qrToken == null ||
          qrToken.isEmpty) {
        throw const FormatException('QR không chứa shiftId và qrToken hợp lệ.');
      }
      final position = await _currentPosition();
      final response =
          await widget.api.post('/api/v1/attendance/check-in', {
                'shiftId': shiftId,
                'qrToken': qrToken,
                'latitude': position.latitude,
                'longitude': position.longitude,
                'accuracyMeters': position.accuracy,
              })
              as Map<String, dynamic>;
      final flags = response['flags'] is List
          ? (response['flags'] as List).join(', ')
          : '';
      if (mounted) {
        setState(() {
          _message =
              '${response['message'] ?? 'Đã ghi nhận chấm công.'}${flags.isNotEmpty ? '\nCần xem xét: $flags' : ''}';
          _receipt = response;
          _isError = false;
        });
      }
    } on ApiException catch (error) {
      final message = error.statusCode == 403
          ? 'Tài khoản này không có quyền check-in. Hãy quét bằng tài khoản Employee; Admin chỉ tạo QR.'
          : error.message;
      if (mounted) {
        setState(() {
          _message = message;
          _isError = true;
        });
      }
    } on FormatException catch (error) {
      if (mounted) {
        setState(() {
          _message = error.message;
          _isError = true;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _message = 'Không thể lấy vị trí hoặc xử lý QR: $error';
          _isError = true;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Quét mã chấm công')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: SizedBox(
              height: 370,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  MobileScanner(
                    controller: _controller,
                    onDetect: _onDetect,
                    errorBuilder: (context, error) => ColoredBox(
                      color: Colors.black87,
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Text(
                            error.errorCode ==
                                    MobileScannerErrorCode.permissionDenied
                                ? 'Chưa có quyền Camera. Vào Cài đặt ứng dụng và cho phép dùng Camera, sau đó mở lại màn hình quét.'
                                : 'Không mở được Camera: ${error.errorCode.message}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                  ),
                  IgnorePointer(
                    child: Center(
                      child: Container(
                        width: 245,
                        height: 245,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.white, width: 3),
                          borderRadius: BorderRadius.circular(24),
                        ),
                      ),
                    ),
                  ),
                  if (_busy)
                    const ColoredBox(
                      color: Color(0x99000000),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Đưa mã QR của ca làm vào khung quét. Ứng dụng sẽ gửi QR và vị trí GPS để máy chủ xác minh.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (_message != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _isError
                    ? colors.errorContainer
                    : colors.secondaryContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                _message!,
                style: TextStyle(
                  color: _isError
                      ? colors.onErrorContainer
                      : colors.onSecondaryContainer,
                ),
              ),
            ),
            if (_isError)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: OutlinedButton.icon(
                  onPressed: () async {
                    setState(() {
                      _message = null;
                    });
                    await _controller.start();
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Quét lại'),
                ),
              ),
            if (!_isError && _receipt != null) ...[
              const SizedBox(height: 16),
              _AttendanceReceipt(receipt: _receipt!),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ResourcePage(
                      api: widget.api,
                      kind: ResourceKind.attendance,
                    ),
                  ),
                ),
                icon: const Icon(Icons.history),
                label: const Text('Mở lịch sử và giải trình'),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _AttendanceReceipt extends StatelessWidget {
  const _AttendanceReceipt({required this.receipt});
  final Map<String, dynamic> receipt;

  @override
  Widget build(BuildContext context) {
    final checks = receipt['verificationChecks'] is List
        ? (receipt['verificationChecks'] as List).whereType<Map>().toList()
        : const <Map>[];
    final verified = receipt['verificationStatus'] == 'Verified';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  verified
                      ? Icons.verified_outlined
                      : Icons.fact_check_outlined,
                  color: verified
                      ? Colors.green
                      : Theme.of(context).colorScheme.tertiary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    verified
                        ? 'Phiếu chấm công hợp lệ'
                        : 'Phiếu cần quản lý xem xét',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _ReceiptLine(
              'Ca làm',
              '${receipt['shiftName'] ?? receipt['shiftId'] ?? '-'}',
            ),
            _ReceiptLine(
              'Nơi làm việc',
              '${receipt['worksiteName'] ?? 'Chưa cấu hình'}',
            ),
            _ReceiptLine('Thời điểm', '${receipt['checkInAtUtc'] ?? '-'}'),
            _ReceiptLine(
              'QR',
              receipt['qrVerified'] == true ? 'Đã xác thực' : 'Chưa xác thực',
            ),
            _ReceiptLine(
              'Độ chính xác GPS',
              '${(receipt['checkInAccuracyMeters'] as num?)?.round() ?? '-'} m',
            ),
            _ReceiptLine(
              'Khoảng cách',
              receipt['distanceToWorksiteMeters'] == null
                  ? 'Chưa có dữ liệu nơi làm việc'
                  : '${(receipt['distanceToWorksiteMeters'] as num).round()} m / bán kính ${(receipt['allowedRadiusMeters'] as num?)?.round() ?? '-'} m',
            ),
            if (checks.isNotEmpty) ...[
              const Divider(height: 22),
              for (final check in checks)
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
          ],
        ),
      ),
    );
  }
}

class _ReceiptLine extends StatelessWidget {
  const _ReceiptLine(this.label, this.value);
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(label, style: Theme.of(context).textTheme.labelLarge),
        ),
        Expanded(child: Text(value)),
      ],
    ),
  );
}

class CheckOutPage extends StatefulWidget {
  const CheckOutPage({super.key, required this.api});
  final ApiClient api;
  @override
  State<CheckOutPage> createState() => _CheckOutPageState();
}

class _CheckOutPageState extends State<CheckOutPage> {
  bool _busy = false;
  String? _message;
  bool _error = false;

  Future<void> _checkOut() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final position = await _currentPosition();
      final response =
          await widget.api.post('/api/v1/attendance/check-out', {
                'latitude': position.latitude,
                'longitude': position.longitude,
                'accuracyMeters': position.accuracy,
              })
              as Map<String, dynamic>;
      if (mounted) {
        setState(() {
          _message = 'Đã check-out lúc ${response['checkOutAtUtc']}';
          _error = false;
        });
      }
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _message = error.message;
          _error = true;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _message = 'Không thể lấy vị trí hoặc check-out: $error';
          _error = true;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Kết thúc ca làm')),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.logout_rounded, size: 56),
            const SizedBox(height: 16),
            const Text('Vị trí GPS sẽ được gửi cùng thời điểm check-out.'),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _busy ? null : _checkOut,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_circle_outline),
              label: const Text('Ghi nhận check-out'),
            ),
            if (_message != null)
              Padding(
                padding: const EdgeInsets.only(top: 18),
                child: Text(
                  _message!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _error
                        ? Theme.of(context).colorScheme.error
                        : Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class CreateQrPage extends StatefulWidget {
  const CreateQrPage({super.key, required this.api});
  final ApiClient api;
  @override
  State<CreateQrPage> createState() => _CreateQrPageState();
}

class _CreateQrPageState extends State<CreateQrPage> {
  final _lifetime = TextEditingController(text: '60');
  List<Map<String, dynamic>> _shifts = [];
  String? _selectedShiftId;
  bool _loadingShifts = true;
  bool _busy = false;
  Map<String, dynamic>? _challenge;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadShifts();
  }

  @override
  void dispose() {
    _lifetime.dispose();
    super.dispose();
  }

  Future<void> _loadShifts() async {
    try {
      final result = await widget.api.get('/api/v1/shifts');
      if (mounted) {
        setState(() {
          _shifts = (result as List)
              .map((item) => Map<String, dynamic>.from(item as Map))
              .toList();
          _loadingShifts = false;
        });
      }
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _error = error.message;
          _loadingShifts = false;
        });
      }
    }
  }

  Future<void> _create() async {
    final lifetime = int.tryParse(_lifetime.text.trim());
    if (_selectedShiftId == null ||
        lifetime == null ||
        lifetime < 15 ||
        lifetime > 300) {
      setState(() => _error = 'Chọn ca làm và thời hạn từ 15 đến 300 giây.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _challenge = null;
    });
    try {
      final data =
          await widget.api.post('/api/v1/attendance/qr-challenges', {
                'shiftId': _selectedShiftId,
                'lifetimeSeconds': lifetime,
              })
              as Map<String, dynamic>;
      if (mounted) setState(() => _challenge = data);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Tạo QR chấm công')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'QR có thời hạn và chỉ sử dụng một lần.',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 18),
        if (_loadingShifts) const LinearProgressIndicator(),
        if (!_loadingShifts)
          DropdownButtonFormField<String>(
            initialValue: _selectedShiftId,
            decoration: const InputDecoration(
              labelText: 'Ca làm',
              prefixIcon: Icon(Icons.schedule),
            ),
            items: _shifts
                .map(
                  (shift) => DropdownMenuItem(
                    value: shift['id']?.toString(),
                    child: Text(
                      '${shift['name']} (${shift['startTime']}–${shift['endTime']})',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: (value) => setState(() => _selectedShiftId = value),
          ),
        if (!_loadingShifts && _shifts.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('Chưa có ca làm. Hãy tạo ca trước khi sinh QR.'),
          ),
        const SizedBox(height: 12),
        TextField(
          controller: _lifetime,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Thời hạn (giây)',
            prefixIcon: Icon(Icons.timer_outlined),
          ),
        ),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: _busy ? null : _create,
          icon: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.qr_code_2),
          label: const Text('Tạo mã mới'),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (_challenge != null) ...[
          const SizedBox(height: 26),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  QrImageView(
                    data: jsonEncode({
                      'shiftId': _selectedShiftId,
                      'qrToken': _challenge!['qrToken'],
                    }),
                    version: QrVersions.auto,
                    size: 250,
                    backgroundColor: Colors.white,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Hết hạn: ${_challenge!['expiresAtUtc']}',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Không chụp hoặc chia sẻ ảnh QR này.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    ),
  );
}

Future<Position> _currentPosition() async {
  if (!await Geolocator.isLocationServiceEnabled()) {
    throw Exception('Hãy bật dịch vụ vị trí trên điện thoại.');
  }
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  if (permission == LocationPermission.denied ||
      permission == LocationPermission.deniedForever) {
    throw Exception('Ứng dụng cần quyền vị trí để chấm công.');
  }
  return Geolocator.getCurrentPosition(
    locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
  );
}
