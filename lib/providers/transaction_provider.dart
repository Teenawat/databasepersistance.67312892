import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/my_transaction.dart';

class BalanceComparison {
  const BalanceComparison({
    required this.rowCount,
    required this.sqlBalance,
    required this.dartBalance,
    required this.sqlTime,
    required this.dartTime,
  });

  final int rowCount;
  final double sqlBalance;
  final double dartBalance;
  final Duration sqlTime;
  final Duration dartTime;
}

// ตามปฏิบัติการ Provider เป็นผู้เปิดฐานข้อมูลและจัดการ CRUD โดยตรง
class TransactionProvider extends ChangeNotifier {
  TransactionProvider({DatabaseFactory? factory, this.databasePath})
    : _factory = factory ?? databaseFactory {
    ready = fetchAndSetTransactions();
  }

  final DatabaseFactory _factory;
  final String? databasePath;
  late final Future<void> ready;
  Future<Database>? _opening;
  List<MyTransaction> _transactions = [];
  double _balance = 0;
  int _pending = 0;
  bool _disposed = false;
  String? _error;

  List<MyTransaction> get transactions => List.unmodifiable(_transactions);
  double get balance => _balance;
  bool get isLoading => _pending > 0;
  String? get error => _error;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<Database> _database() => _opening ??= _openDatabase();

  Future<Database> _openDatabase() async {
    try {
      final path =
          databasePath ??
          p.join(await _factory.getDatabasesPath(), 'expenses.db');
      return await _factory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 2,
          onCreate: (db, version) => db.execute('''
            CREATE TABLE transactions (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              title TEXT NOT NULL,
              amount REAL NOT NULL,
              date TEXT NOT NULL,
              type TEXT NOT NULL,
              note TEXT NOT NULL DEFAULT ''
            )
          '''),
          onUpgrade: (db, oldVersion, newVersion) async {
            // เพิ่มคอลัมน์โดยเก็บรายการเดิมทั้งหมดไว้
            if (oldVersion < 2) {
              await db.execute(
                "ALTER TABLE transactions ADD COLUMN note TEXT NOT NULL DEFAULT ''",
              );
            }
          },
        ),
      );
    } catch (_) {
      _opening = null;
      rethrow;
    }
  }

  static Future<double> _sumBalance(DatabaseExecutor db) async {
    final rows = await db.rawQuery('''
      SELECT COALESCE(SUM(CASE WHEN type = 'income'
        THEN amount ELSE -amount END), 0) AS balance
      FROM transactions
    ''');
    return (rows.single['balance'] as num).toDouble();
  }

  Future<void> _reload() async {
    final db = await _database();
    // อ่านรายการกับยอดรวมจาก snapshot เดียวกัน
    final snapshot = await db.transaction((txn) async {
      final rows = await txn.query(
        'transactions',
        orderBy: 'date DESC, id DESC',
      );
      return (rows, await _sumBalance(txn));
    });
    _transactions = snapshot.$1.map(MyTransaction.fromMap).toList();
    _balance = snapshot.$2;
  }

  Future<T> _run<T>(Future<T> Function() action) async {
    _pending++;
    _error = null;
    _notify();
    try {
      return await action();
    } catch (error, stack) {
      _error = 'ไม่สามารถอ่านหรือบันทึกข้อมูลได้ กรุณาลองใหม่';
      debugPrint('TransactionProvider: $error\n$stack');
      rethrow;
    } finally {
      _pending--;
      _notify();
    }
  }

  Future<void> fetchAndSetTransactions() async {
    try {
      await _run(_reload);
    } catch (_) {
      // เก็บ error ให้หน้าจอแสดงและให้ผู้ใช้ลองโหลดใหม่
    }
  }

  void _validate(MyTransaction transaction) {
    if (transaction.title.trim().isEmpty ||
        !transaction.amount.isFinite ||
        transaction.amount <= 0) {
      throw ArgumentError('กรอกชื่อรายการและจำนวนเงินที่มากกว่า 0');
    }
  }

  Future<void> addTransaction(
    String title,
    double amount,
    DateTime date,
    TransactionType type, {
    String note = '',
  }) => _run(() async {
    final item = MyTransaction(
      title: title.trim(),
      amount: amount,
      date: date,
      type: type,
      note: note.trim(),
    );
    _validate(item);
    final db = await _database();
    await db.insert('transactions', item.toMap());
    await _reload();
  });

  Future<void> updateTransaction(int id, MyTransaction newTransaction) =>
      _run(() async {
        _validate(newTransaction);
        final db = await _database();
        final data = newTransaction.toMap()..remove('id');
        data['title'] = newTransaction.title.trim();
        data['note'] = newTransaction.note.trim();
        final count = await db.update(
          'transactions',
          data,
          where: 'id = ?',
          whereArgs: [id],
        );
        if (count != 1) throw StateError('ไม่พบรายการที่ต้องการแก้ไข');
        await _reload();
      });

  // กระบวนการที่ 6: การ Delete
  Future<void> deleteTransaction(int id) => _run(() async {
    final db = await _database();
    await db.delete('transactions', where: 'id = ?', whereArgs: [id]);
    await _reload();
  });

  Future<Duration> importSampleTransactions({required bool useBatch}) => _run(
    () async {
      final db = await _database();
      final now = DateTime.now();
      final samples = List.generate(
        100,
        (index) => MyTransaction(
          title: 'รายการตัวอย่าง ${index + 1}',
          amount: (index + 1) * 10.0,
          date: now.subtract(Duration(minutes: index)),
          type: index.isEven ? TransactionType.income : TransactionType.expense,
          note: 'นำเข้าแบบ${useBatch ? ' batch' : 'ทีละรายการ'}',
        ),
      );
      final timer = Stopwatch()..start();
      if (useBatch) {
        await db.transaction((txn) async {
          final batch = txn.batch();
          for (final item in samples) {
            batch.insert('transactions', item.toMap());
          }
          await batch.commit(noResult: true);
        });
        await _reload();
      } else {
        for (final item in samples) {
          await addTransaction(
            item.title,
            item.amount,
            item.date,
            item.type,
            note: item.note,
          );
        }
      }
      timer.stop();
      return timer.elapsed;
    },
  );

  Future<BalanceComparison> compareBalanceCalculation() => _run(() async {
    final db = await _database();
    return db.transaction((txn) async {
      final sqlTimer = Stopwatch()..start();
      final sqlBalance = await _sumBalance(txn);
      sqlTimer.stop();
      final dartTimer = Stopwatch()..start();
      final rows = await txn.query('transactions', columns: ['amount', 'type']);
      final dartBalance = rows.fold<double>(0, (sum, row) {
        final amount = (row['amount'] as num).toDouble();
        return sum + (row['type'] == 'income' ? amount : -amount);
      });
      dartTimer.stop();
      return BalanceComparison(
        rowCount: rows.length,
        sqlBalance: sqlBalance,
        dartBalance: dartBalance,
        sqlTime: sqlTimer.elapsed,
        dartTime: dartTimer.elapsed,
      );
    });
  });

  Future<void> close() async {
    final opening = _opening;
    if (opening != null) {
      final db = await opening;
      await db.close();
      _opening = null;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(
      close().catchError((Object error) {
        debugPrint('Database close: $error');
      }),
    );
    super.dispose();
  }
}
