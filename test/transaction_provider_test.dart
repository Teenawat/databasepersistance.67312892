import 'dart:io';

import 'package:databasehelper/models/my_transaction.dart';
import 'package:databasehelper/providers/transaction_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  final factory = databaseFactoryFfi;
  late Directory directory;
  late String path;
  final providers = <TransactionProvider>[];

  Future<TransactionProvider> openProvider() async {
    final provider = TransactionProvider(factory: factory, databasePath: path);
    providers.add(provider);
    await provider.ready;
    expect(provider.error, isNull);
    return provider;
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('sqlite_exercise_');
    path = p.join(directory.path, 'expenses.db');
  });

  tearDown(() async {
    for (final provider in providers) {
      await provider.close();
      provider.dispose();
    }
    providers.clear();
    await directory.delete(recursive: true);
  });

  test('model round-trip preserves types, date and note without a null id', () {
    final item = MyTransaction(
      title: 'เงินเดือน',
      amount: 20000,
      date: DateTime(2026, 10, 7),
      type: TransactionType.income,
      note: 'ตุลาคม',
    );
    expect(item.toMap().containsKey('id'), isFalse);
    final restored = MyTransaction.fromMap({
      ...item.toMap(),
      'id': 1,
      'amount': 20000,
    });
    expect(restored.amount, 20000.0);
    expect(restored.type, TransactionType.income);
    expect(restored.date, item.date);
    expect(restored.note, 'ตุลาคม');
  });

  test(
    'CRUD, SQL balance and persistence survive closing and reopening',
    () async {
      final provider = await openProvider();
      expect(provider.balance, 0);
      await provider.addTransaction(
        'เงินเดือน',
        20000,
        DateTime(2026, 10, 1),
        TransactionType.income,
      );
      await provider.addTransaction(
        "ค่าอาหาร '); DROP TABLE transactions; --",
        120,
        DateTime(2026, 10, 7),
        TransactionType.expense,
        note: 'มื้อกลางวัน',
      );
      expect(provider.balance, 19880);
      final id = provider.transactions.first.id!;
      expect(provider.transactions.first.amount, 120);
      await provider.updateTransaction(
        id,
        MyTransaction(
          id: 999,
          title: 'ค่าอาหาร',
          amount: 150,
          date: DateTime(2026, 10, 7),
          type: TransactionType.expense,
          note: 'แก้ไขแล้ว',
        ),
      );
      expect(provider.transactions.first.id, id);
      expect(provider.balance, 19850);
      await provider.close();
      final reopened = await openProvider();
      expect(reopened.transactions, hasLength(2));
      expect(reopened.transactions.first.note, 'แก้ไขแล้ว');
      await reopened.deleteTransaction(id);
      expect(reopened.balance, 20000);
      await reopened.close();
      final finalProvider = await openProvider();
      expect(finalProvider.transactions, hasLength(1));
      expect(finalProvider.transactions.single.title, 'เงินเดือน');
    },
  );

  test('migration from v1 adds note without losing existing rows', () async {
    final oldDb = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) => db.execute(
          'CREATE TABLE transactions('
          'id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT, amount REAL, date TEXT, type TEXT)',
        ),
      ),
    );
    await oldDb.insert('transactions', {
      'id': 42,
      'title': 'รายการเดิม',
      'amount': 50,
      'date': DateTime(2026, 10, 1).toIso8601String(),
      'type': 'income',
    });
    await oldDb.close();
    final provider = await openProvider();
    expect(provider.transactions.single.id, 42);
    expect(provider.transactions.single.title, 'รายการเดิม');
    expect(provider.transactions.single.note, '');
    await provider.updateTransaction(
      42,
      MyTransaction(
        title: 'รายการเดิม',
        amount: 50,
        date: DateTime(2026, 10, 1),
        type: TransactionType.income,
        note: 'เพิ่มหมายเหตุ',
      ),
    );
    await provider.close();
    final db = await factory.openDatabase(path);
    expect(await db.getVersion(), 2);
    expect((await db.query('transactions')).single['note'], 'เพิ่มหมายเหตุ');
    await db.close();
  });

  test('both imports add 100 rows and SQL matches Dart for 3000 rows', () async {
    final provider = await openProvider();
    final sequential = await provider.importSampleTransactions(useBatch: false);
    expect(provider.transactions, hasLength(100));
    expect(provider.balance, -500);
    final batch = await provider.importSampleTransactions(useBatch: true);
    expect(provider.transactions, hasLength(200));
    expect(provider.balance, -1000);
    for (var i = 0; i < 28; i++) {
      await provider.importSampleTransactions(useBatch: true);
    }
    final result = await provider.compareBalanceCalculation();
    expect(result.rowCount, 3000);
    expect(result.sqlBalance, -15000);
    expect(result.dartBalance, result.sqlBalance);
    // Actual measured timings; not a speed assertion that depends on hardware.
    // ignore: avoid_print
    print(
      '100 rows: sequential=${sequential.inMicroseconds}us, '
      'batch=${batch.inMicroseconds}us; 3000 rows: '
      'SQL=${result.sqlTime.inMicroseconds}us, Dart=${result.dartTime.inMicroseconds}us',
    );
  });

  test('failed batch rolls back all rows', () async {
    final provider = await openProvider();
    final db = await factory.openDatabase(path);
    await db.execute('''
      CREATE TRIGGER reject_sample BEFORE INSERT ON transactions
      WHEN NEW.amount = 500
      BEGIN SELECT RAISE(ABORT, 'test failure'); END
    ''');
    await expectLater(
      provider.importSampleTransactions(useBatch: true),
      throwsException,
    );
    expect(provider.error, isNotNull);
    expect((await db.query('transactions')), isEmpty);
    expect(provider.isLoading, isFalse);
    await db.execute('DROP TRIGGER reject_sample');
    await provider.importSampleTransactions(useBatch: true);
    expect(provider.transactions, hasLength(100));
    expect(provider.error, isNull);
  });
}
