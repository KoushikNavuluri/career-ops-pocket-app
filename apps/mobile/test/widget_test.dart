import 'package:career_pocket/core/design/theme.dart';
import 'package:career_pocket/core/design/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() => AppTheme.useGoogleFonts = false);

  testWidgets('EmptyState and StatusChip render', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(body: Column(children: [StatusChip('Applied'), Expanded(child: EmptyState(icon: Icons.inbox, title: 'Nothing yet', message: 'Add a role'))])),
    ));
    expect(find.text('Applied'), findsOneWidget);
    expect(find.text('Nothing yet'), findsOneWidget);
  });
}
