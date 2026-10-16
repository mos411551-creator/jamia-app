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

  Map<int, Map<String, dynamic>> _payoutsByMonth = {};
  Map<int, List<Map<String, dynamic>>> _paymentsByMonth = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: widget.totalMonths, vsync: this);
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
      ORDER BY p.month_index ASC
    ''', [widget.circleId]);

    final paymentsData = await db.rawQuery('''
      SELECT pay.*, m.name as member_name, m.phone as member_phone
      FROM payments pay
      JOIN members m ON pay.member_id = m.id
      WHERE pay.circle_id = ?
      ORDER BY pay.month_index ASC, m.id ASC
    ''', [widget.circleId]);

    Map<int, Map<String, dynamic>> tempPayouts = {};
    for (var row in payoutsData) {
      tempPayouts[row['month_index'] as int] = row;
    }

    Map<int, List<Map<String, dynamic>>> tempPayments = {};
    for (var row in paymentsData) {
      final month = row['month_index'] as int;
      tempPayments.putIfAbsent(month, () => []).add(row);
    }

    setState(() {
      _payoutsByMonth = tempPayouts;
      _paymentsByMonth = tempPayments;
      _isLoading = false;
    });
  }

  Future<void> _togglePayment(int paymentId, int currentStatus) async {
    if (currentStatus == 1) {
      final db = await DBHelper.instance.database;
      await db.update('payments', {'is_paid': 0, 'payment_date': null}, where: 'id = ?', whereArgs: [paymentId]);
      await _loadCircleData();
      return;
    }

    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('اختر وسيلة التوريد للسداد', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            ListTile(
              leading: const Icon(Icons.money, color: Colors.green),
              title: const Text('نقداً (كاش)'),
              onTap: () => _confirmPayment(paymentId, 'cash'),
            ),
            ListTile(
              leading: const Icon(Icons.phone_android, color: Colors.red),
              title: const Text('محفظة إلكترونية (فودافون كاش)'),
              onTap: () => _confirmPayment(paymentId, 'wallet'),
            ),
            ListTile(
              leading: const Icon(Icons.account_balance, color: Colors.purple),
              title: const Text('إنستاباي / تحويل بنكي'),
              onTap: () => _confirmPayment(paymentId, 'bank'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmPayment(int paymentId, String method) async {
    Navigator.pop(context);
    final db = await DBHelper.instance.database;
    await db.update(
      'payments',
      {
        'is_paid': 1,
        'payment_method': method,
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

  void _showReceiptDialog(Map<String, dynamic> item, int month) {
    final key = GlobalKey();
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PaymentReceiptCard(
              boundaryKey: key,
              circleName: widget.circleName,
              memberName: item['member_name'],
              amount: widget.shareAmount,
              paymentMethod: item['payment_method'] ?? 'cash',
              paymentDate: item['payment_date'] ?? '',
              monthIndex: month,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              icon: const Icon(Icons.share),
              label: const Text('مشاركة الإيصال على واتساب'),
              onPressed: () => ReceiptHelper.shareReceipt(key, item['member_name'], widget.circleName),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.circleName),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            tooltip: 'تصدير كشف حساب PDF',
            onPressed: () async {
              final curMonth = _tabController.index + 1;
              final pInfo = _payoutsByMonth[curMonth];
              final pays = _paymentsByMonth[curMonth] ?? [];
              if (pInfo == null) return;

              final bytes = await PdfService.generateCircleReport(
                circleName: widget.circleName,
                cycleType: widget.cycleType,
                currentCycleIndex: curMonth,
                shareAmount: widget.shareAmount,
                receiverName: pInfo['receiver_name'],
                payoutDate: pInfo['payout_date'],
                isReceived: pInfo['is_received'] == 1,
                payments: pays,
              );
              await PdfService.sharePdfReport(
                circleName: widget.circleName,
                cycleIndex: curMonth,
                pdfBytes: bytes,
              );
            },
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
    final payoutInfo = _payoutsByMonth[monthIndex];
    final payments = _paymentsByMonth[monthIndex] ?? [];
    final paidCount = payments.where((p) => p['is_paid'] == 1).length;
    final totalMembers = payments.length;
    final progress = totalMembers > 0 ? (paidCount / totalMembers) : 0.0;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (payoutInfo != null)
          Card(
            color: Colors.teal.shade50,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  const CircleAvatar(backgroundColor: Colors.teal, child: Icon(Icons.star, color: Colors.white)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('مستحق القبض:', style: TextStyle(fontSize: 12, color: Colors.black54)),
                        Text(payoutInfo['receiver_name'], style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        Text('التاريخ: ${payoutInfo['payout_date']}', style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                  FilterChip(
                    label: Text(payoutInfo['is_received'] == 1 ? 'تم القبض' : 'لم يقبض'),
                    selected: payoutInfo['is_received'] == 1,
                    onSelected: (_) => _togglePayout(payoutInfo['id'], payoutInfo['is_received']),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('نسبة تحصيل الدور', style: TextStyle(fontWeight: FontWeight.bold)),
                    Text('${(progress * 100).toStringAsFixed(0)}%'),
                  ],
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(value: progress, minHeight: 8, borderRadius: BorderRadius.circular(4)),
                const SizedBox(height: 6),
                Text('سدد $paidCount من $totalMembers مشترك', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text('جدول المشتركين والأقساط:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        const SizedBox(height: 8),
        ...payments.map((item) {
          final isPaid = item['is_paid'] == 1;
          return Card(
            margin: const EdgeInsets.symmetric(vertical: 4),
            child: ListTile(
              leading: Checkbox(
                value: isPaid,
                onChanged: (_) => _togglePayment(item['id'], item['is_paid']),
              ),
              title: Text(item['member_name'], style: TextStyle(fontWeight: FontWeight.w600, decoration: isPaid ? TextDecoration.lineThrough : null)),
              subtitle: Text(isPaid ? 'تم الدفع: ${item['payment_method']} (${item['payment_date'] ?? ""})' : 'قيمة القسط: ${widget.shareAmount} ج.م'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isPaid)
                    IconButton(
                      icon: const Icon(Icons.receipt_long, color: Colors.teal),
                      tooltip: 'إيصال رقمي',
                      onPressed: () => _showReceiptDialog(item, monthIndex),
                    ),
                  if (!isPaid)
                    IconButton(
                      icon: const Icon(Icons.share, color: Colors.green),
                      tooltip: 'تذكير واتساب ورابط دفع',
                      onPressed: () => PaymentLinkService.sendPaymentReminder(
                        memberPhone: item['member_phone'] ?? '',
                        memberName: item['member_name'],
                        circleName: widget.circleName,
                        amount: widget.shareAmount,
                        turnIndex: monthIndex,
                      ),
                    ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }
}
