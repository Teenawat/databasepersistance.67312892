import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:databasehelper/main.dart';
import 'package:databasehelper/providers/transaction_provider.dart';

void main() {
  testWidgets('opens the transaction list screen', (WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => TransactionProvider(),
        child: const MyApp(),
      ),
    );

    expect(find.text('รายรับ-รายจ่าย'), findsOneWidget);
    expect(find.byIcon(Icons.add), findsOneWidget);
  });
}
