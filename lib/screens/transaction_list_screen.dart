import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/transaction_provider.dart';
import '../models/my_transaction.dart';

class TransactionListScreen extends StatelessWidget {
  const TransactionListScreen({super.key});

  Future<void> _addSampleTransaction(BuildContext context) async {
    try {
      await context.read<TransactionProvider>().addTransaction(
        'ค่าอาหาร',
        120.0,
        DateTime.now(),
        TransactionType.expense,
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('เพิ่มรายการไม่สำเร็จ กรุณาลองใหม่')),
      );
    }
  }

  Future<void> _delete(BuildContext context, MyTransaction transaction) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('ลบรายการ'),
        content: Text('ต้องการลบ "${transaction.title}" หรือไม่?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('ลบ'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await context.read<TransactionProvider>().deleteTransaction(
        transaction.id!,
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('ลบไม่สำเร็จ กรุณาลองใหม่')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final txProvider = context.watch<TransactionProvider>();
    final transactions = txProvider.transactions;
    final money = NumberFormat('#,##0.00');
    return Scaffold(
      appBar: AppBar(
        title: const Text('รายรับ-รายจ่าย'),
        actions: [
          IconButton(
            tooltip: 'โหลดข้อมูลใหม่',
            onPressed: txProvider.isLoading
                ? null
                : txProvider.fetchAndSetTransactions,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          if (txProvider.isLoading) const LinearProgressIndicator(),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: Theme.of(context).colorScheme.primaryContainer,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('ยอดคงเหลือ'),
                Text(
                  '${money.format(txProvider.balance)} บาท',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ],
            ),
          ),
          if (txProvider.error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Text(txProvider.error!),
                  TextButton(
                    onPressed: txProvider.isLoading
                        ? null
                        : txProvider.fetchAndSetTransactions,
                    child: const Text('ลองใหม่'),
                  ),
                ],
              ),
            ),
          Expanded(
            child: transactions.isEmpty
                ? Center(
                    child: Text(
                      txProvider.isLoading
                          ? 'กำลังโหลดข้อมูล...'
                          : txProvider.error != null
                          ? 'ยังโหลดรายการไม่ได้'
                          : 'ไม่มีรายการ',
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 88),
                    itemCount: transactions.length,
                    itemBuilder: (ctx, i) {
                      final tx = transactions[i];
                      final income = tx.type == TransactionType.income;
                      return ListTile(
                        leading: CircleAvatar(
                          child: Text(income ? 'รับ' : 'จ่าย'),
                        ),
                        title: Text(tx.title),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(DateFormat.yMMMd().format(tx.date)),
                            Text(
                              '${income ? '+' : '-'}${money.format(tx.amount)} บาท',
                              style: TextStyle(
                                color: income ? Colors.green : Colors.red,
                              ),
                            ),
                            if (tx.note.isNotEmpty) Text(tx.note),
                          ],
                        ),
                        trailing: IconButton(
                          tooltip: 'ลบรายการ',
                          onPressed: txProvider.isLoading
                              ? null
                              : () => _delete(context, tx),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: txProvider.isLoading
            ? null
            : () => _addSampleTransaction(context),
        tooltip: 'เพิ่มรายการ',
        child: const Icon(Icons.add),
      ),
    );
  }
}
