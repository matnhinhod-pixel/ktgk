import 'package:dominhnhat_mobile/core/session.dart';
import 'package:dominhnhat_mobile/features/auth/auth_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders DOMINHNHAT login form', (tester) async {
    final api = ApiClient(session: SessionStore(), baseUrl: 'https://example.com');
    await tester.pumpWidget(MaterialApp(home: AuthPage(api: api, onAuthenticated: (_) {})));

    expect(find.text('DOMINHNHAT'), findsOneWidget);
    expect(find.text('Đăng nhập'), findsOneWidget);
  });
}
