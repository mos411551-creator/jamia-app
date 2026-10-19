import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../database/db_helper.dart';
import '../services/pdf_service.dart';
import '../services/payment_link_service.dart';
import '../widgets/receipt_card.dart';

class CircleDetailsScreen extends StatefulWidget {
  final int circleId;
  final String circleName;
  final double shareAmount;
  final int totalMonths;
  final String cycleType;

  const CircleDetailsScreen({
    super.key,
    required this.circleId,
    required this.circleName,
    required this.shareAmount,
    required this.totalMonths,
    required this.cycleType,
  });

  @override
  State<CircleDetailsScreen> createState() => _CircleDetailsScreenState();
}

class _CircleDetailsScreenState extends State<CircleDetailsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;

  Map<int, List<Map<String, dynamic>>> _payoutsByMonth = {};
  Map<int, List<Map<String, dynamic>>> _paymentsByMonth = {};
  List<Map<String, dynamic>> _allPayouts = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: widget.totalMonths > 0 ? widget.totalMonths : 1, vsync: this);
    _loadCircleData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadCircleData() async {
    setState(() => _isLoading = true);
    final db = await DBHelper.instance.database;

    final payoutsData = await db.rawQuery('''
      SELECT p.*, m.name as receiver_name, m.phone as receiver_phone 
      FROM payouts p
      JOIN members m ON p.member_id = m.id
      WHERE p.circle_id = ?
      ORDER BY p.month_index ASC, p.id ASC
    ''', [widget.circleId]);

    final paymentsData = await db.rawQuery('''
      SELECT pay.*, m.name as member_name, m.phone as member_phone
      FROM payments pay
      JOIN members m ON pay.member_id = m.id
      WHERE pay.circle_id = ?
      ORDER BY pay.month_index ASC, m.id ASC
    ''', [widget.circleId]);

    Map<int, List<Map<String, dynamic>>> tempPayouts = {};
    for (var row in payoutsData) {
      final month = row['month_index'] as int;
      tempPayouts.putIfAbsent(month, () => []).add(row);
    }

    Map<int, List<Map<String, dynamic>>> tempPayments = {};
    for (var row in paymentsData) {
      final month = row['month_index'] as int;
      tempPayments.putIfAbsent(month, () => []).add(row);
    }

    setState(() {
      _allPayouts = List<Map<String, dynamic>>.from(payoutsData);
      _payoutsByMonth = tempPayouts;
      _paymentsByMonth = tempPayments;
      _isLoading = false;
    });
  }

  void _showSwapDialog() {
    int? pIndex1;
    int? pIndex2;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('تبادل أدوار القبض'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButton<int>(
                isExpanded: true,
                hint: const Text('اختر الدور الأول'),
                value: pIndex1,
                items: _allPayouts.asMap().entries.map((e) {
                  final p = e.value;
                  return DropdownMenuItem(
                    value: e.key,
                    child: Text('دور ${p['month_index']} - ${p['receiver_name']} (${p['is_received'] == 1 ? "تم القبض" : "متاح"})'),
                  );
                }).toList(),
                onChanged: (val) => setDialogState(() => pIndex1 = val),
              ),
              const SizedBox(height: 12),
              DropdownButton<int>(
                isExpanded: true,
                hint: const Text('اختر الدور المراد التبديل معه'),
                value: pIndex2,
                items: _allPayouts.asMap().entries.map((e) {
                  final p = e.value;
                  return DropdownMenuItem(
                    value: e.key,
                    child: Text('دور ${p['month_index']} - ${p['receiver_name']} (${p['is_received'] == 1 ? "تم القبض" : "متاح"})'),
                  );
                }).toList(),
                onChanged: (val) => setDialogState(() => pIndex2 = val),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            FilledButton(
              onPressed: () async {
                if (pIndex1 != null && pIndex2 != null) {
                  final p1 = _allPayouts[pIndex1!];
                  final p2 = _allPayouts[pIndex2!];

                  final success = await DBHelper.instance.swapPayoutTurns(
                    payoutId1: p1['id'],
                    memberId1: p1['member_id'],
                    payoutId2: p2['id'],
                    memberId2: p2['member_id'],
                  );

                  Navigator.pop(ctx);
                  if (success) {
                    _loadCircleData();
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('لا يمكن التبديل لأن أحد العضوين قد استلم بالفعل!')),
                    );
                  }
                }
              },
              child: const Text('تبديل الأدوار'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _togglePayment(int paymentId, int currentStatus) async {
    final db = await DBHelper.instance.database;
    if (currentStatus == 1) {
      await db.update('payments', {'is_paid': 0, 'payment_date': null}, where: 'id = ?', whereArgs: [paymentId]);
      await _loadCircleData();
      return;
    }

    await db.update(
      'payments',
      {
        'is_paid': 1,
        'payment_method': 'cash',
        'payment_date': DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now()),
      },
      where: 'id = ?',
      whereArgs: [paymentId],
    );
    await _loadCircleData();
  }

  Future<void> _togglePayout(int payoutId, int currentStatus) async {
    final db = await DBHelper.instance.database;
    await db.update('payouts', {'is_received': currentStatus == 1 ? 0 : 1}, where: 'id = ?', whereArgs: [payoutId]);
    await _loadCircleData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.circleName),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.swap_horiz),
            tooltip: 'تبادل الأدوار',
            onPressed: _showSwapDialog,
          ),
        ],
        bottom: widget.totalMonths > 0
            ? TabBar(
                controller: _tabController,
                isScrollable: true,
                tabs: List.generate(widget.totalMonths, (i) => Tab(text: 'دور ${i + 1}')),
              )
            : null,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: List.generate(widget.totalMonths, (i) => _buildTab(i + 1)),
            ),
    );
  }

  Widget _buildTab(int monthIndex) {
    final payouts = _payoutsByMonth[monthIndex] ?? [];
    final payments = _paymentsByMonth[monthIndex] ?? [];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (payouts.isNotEmpty) ...[
          const Text('المستحقين للقبض في هذا الدور:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 6),
          ...payouts.map((pInfo) {
            final isRec = pInfo['is_received'] == 1;
            return Card(
              color: Colors.teal.shade50,
              child: ListTile(
                leading: const Icon(Icons.star, color: Colors.teal),
                title: Text(pInfo['receiver_name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('المبلغ: ${pInfo['expected_amount']} ج.م • التاريخ: ${pInfo['payout_date']}'),
                trailing: FilterChip(
                  label: Text(isRec ? 'تم القبض' : 'لم يقبض'),
                  selected: isRec,
                  onSelected: (_) => _togglePayout(pInfo['id'], pInfo['is_received']),
                ),
              ),
            );
          }),
        ],
        const SizedBox(height: 16),
        const Text('أقساط هذا الدور:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        const SizedBox(height: 8),
        ...payments.map((item) {
          final isPaid = item['is_paid'] == 1;
          return Card(
            child: ListTile(
              leading: Checkbox(
                value: isPaid,
                onChanged: (_) => _togglePayment(item['id'], item['is_paid']),
              ),
              title: Text(item['member_name'], style: TextStyle(fontWeight: FontWeight.w600, decoration: isPaid ? TextDecoration.lineThrough : null)),
              subtitle: Text('قيمة القسط: ${item['amount_paid']} ج.م ${isPaid ? "(تم السداد)" : ""}'),
              trailing: !isPaid
                  ? IconButton(
                      icon: const Icon(Icons.share, color: Colors.green),
                      onPressed: () => PaymentLinkService.sendPaymentReminder(
                        memberPhone: item['member_phone'] ?? '',
                        memberName: item['member_name'],
                        circleName: widget.circleName,
                        amount: (item['amount_paid'] as num).toDouble(),
                        turnIndex: monthIndex,
                      ),
                    )
                  : null,
            ),
          );
        }),
      ],
    );
  }
}
