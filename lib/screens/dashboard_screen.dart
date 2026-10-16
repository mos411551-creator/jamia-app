import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import '../database/db_helper.dart';
import '../services/settings_controller.dart';
import 'add_edit_circle_screen.dart';
import 'circle_details_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _isLoading = true;
  double _totalCollectedAll = 0.0;
  double _totalPendingAll = 0.0;
  List<Map<String, dynamic>> _lateMembers = [];
  List<Map<String, dynamic>> _activeCircles = [];

  @override
  void initState() {
    super.initState();
    _fetchDashboardData();
  }

  Future<void> _fetchDashboardData() async {
    setState(() => _isLoading = true);
    final db = await DBHelper.instance.database;

    final stats = await db.rawQuery('''
      SELECT 
        SUM(CASE WHEN pay.is_paid = 1 THEN pay.amount_paid ELSE 0 END) as collected,
        SUM(CASE WHEN pay.is_paid = 0 THEN pay.amount_paid ELSE 0 END) as pending
      FROM payments pay
      JOIN circles c ON pay.circle_id = c.id
      WHERE c.status = 'active'
    ''');

    final lateList = await db.rawQuery('''
      SELECT 
        pay.id as payment_id,
        pay.amount_paid,
        pay.month_index,
        m.name as member_name,
        m.phone as member_phone,
        c.name as circle_name
      FROM payments pay
      JOIN members m ON pay.member_id = m.id
      JOIN circles c ON pay.circle_id = c.id
      WHERE pay.is_paid = 0 AND c.status = 'active'
      ORDER BY c.id, pay.month_index ASC
    ''');

    final circles = await db.query('circles', orderBy: 'id DESC');

    setState(() {
      _totalCollectedAll = (stats.first['collected'] as num?)?.toDouble() ?? 0.0;
      _totalPendingAll = (stats.first['pending'] as num?)?.toDouble() ?? 0.0;
      _lateMembers = List<Map<String, dynamic>>.from(lateList);
      _activeCircles = List<Map<String, dynamic>>.from(circles);
      _isLoading = false;
    });
  }

  DateTime _calculateEndDate(DateTime start, int totalMonths, String cycle) {
    final steps = totalMonths > 0 ? totalMonths - 1 : 0;
    switch (cycle) {
      case 'daily':
        return start.add(Duration(days: steps));
      case 'weekly':
        return start.add(Duration(days: steps * 7));
      case 'monthly':
      default:
        return DateTime(start.year, start.month + steps, start.day);
    }
  }

  void _confirmDeleteCircle(Map<String, dynamic> circle) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف الجمعية'),
        content: Text('هل أنت متأكد من حذف جمعية "${circle['name']}" وكافة سجلات السداد والأعضاء التابعة لها؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(ctx);
              await DBHelper.instance.deleteCircle(circle['id']);
              _fetchDashboardData();
            },
            child: const Text('تأكيد الحذف'),
          ),
        ],
      ),
    );
  }

  void _callMember(String phone) async {
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  void _sendLateReminder(Map<String, dynamic> item) {
    final cur = SettingsController.currencyNotifier.value;
    final msg = '''
السلام عليكم أ/ ${item['member_name']}،
نود تذكيرك بسداد القسط المستحق: ${item['amount_paid']} $cur
لجمعية: "${item['circle_name']}" (دور ${item['month_index']}).
يرجى المبادرة بالسداد. شكراً لتعاونكم.
''';
    Share.share(msg);
  }

  @override
  Widget build(BuildContext context) {
    final cur = SettingsController.currencyNotifier.value;

    return Scaffold(
      appBar: AppBar(
        title: const Text('لوحة المتابعة الشاملة'),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _fetchDashboardData,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _buildMetricCard(
                          'إجمالي المحصل',
                          '${_totalCollectedAll.toStringAsFixed(0)} $cur',
                          Colors.teal,
                          Icons.account_balance_wallet,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildMetricCard(
                          'المتبقي للتحصيل',
                          '${_totalPendingAll.toStringAsFixed(0)} $cur',
                          Colors.redAccent,
                          Icons.hourglass_bottom,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'الجمعيات المسجلة:',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      FilledButton.icon(
                        icon: const Icon(Icons.add),
                        label: const Text('إنشاء جمعية'),
                        onPressed: () async {
                          final res = await Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const AddEditCircleScreen()),
                          );
                          if (res == true) _fetchDashboardData();
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  if (_activeCircles.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(24),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text('لا توجد جمعيات حالياً. اضغط إنشاء جمعية للبدء.'),
                    )
                  else
                    ..._activeCircles.map((circle) {
                      final isCompleted = circle['status'] == 'completed';
                      final startDate = DateTime.tryParse(circle['start_date']) ?? DateTime.now();
                      final totalMonths = circle['total_months'] as int? ?? 1;
                      final cycleType = circle['cycle_type'] ?? 'monthly';
                      final endDate = _calculateEndDate(startDate, totalMonths, cycleType);

                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        elevation: 1.5,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => CircleDetailsScreen(
                                  circleId: circle['id'],
                                  circleName: circle['name'],
                                  shareAmount: circle['share_amount'],
                                  totalMonths: circle['total_months'],
                                  cycleType: cycleType,
                                ),
                              ),
                            );
                            _fetchDashboardData();
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    CircleAvatar(
                                      backgroundColor: isCompleted ? Colors.grey : Colors.teal.shade100,
                                      child: Icon(
                                        isCompleted ? Icons.check_circle : Icons.group_work,
                                        color: isCompleted ? Colors.white : Colors.teal.shade800,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            circle['name'],
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                          ),
                                          Text(
                                            'السهم: ${circle['share_amount']} $cur • ${circle['total_months']} أدوار ($cycleType)',
                                            style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                                          ),
                                        ],
                                      ),
                                    ),
                                    PopupMenuButton<String>(
                                      onSelected: (val) async {
                                        if (val == 'edit') {
                                          final res = await Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => AddEditCircleScreen(existingCircle: circle),
                                            ),
                                          );
                                          if (res == true) _fetchDashboardData();
                                        } else if (val == 'delete') {
                                          _confirmDeleteCircle(circle);
                                        }
                                      },
                                      itemBuilder: (_) => const [
                                        PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit, color: Colors.blue), SizedBox(width: 8), Text('تعديل الجمعية')])),
                                        PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete, color: Colors.red), SizedBox(width: 8), Text('حذف الجمعية')])),
                                      ],
                                    ),
                                  ],
                                ),
                                const Divider(height: 16),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(Icons.play_circle_outline, size: 16, color: Colors.green),
                                        const SizedBox(width: 4),
                                        Text('البداية: ${DateFormat('yyyy-MM-dd').format(startDate)}', style: const TextStyle(fontSize: 12)),
                                      ],
                                    ),
                                    Row(
                                      children: [
                                        const Icon(Icons.flag_outlined, size: 16, color: Colors.orange),
                                        const SizedBox(width: 4),
                                        Text('النهاية: ${DateFormat('yyyy-MM-dd').format(endDate)}', style: const TextStyle(fontSize: 12)),
                                      ],
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),

                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('قائمة المتأخرين عن السداد:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      Chip(
                        label: Text('${_lateMembers.length} قسط متأخر', style: const TextStyle(color: Colors.white, fontSize: 12)),
                        backgroundColor: Colors.red.shade700,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  if (_lateMembers.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(20),
                      alignment: Alignment.center,
                      child: const Text('لا توجد أقساط متأخرة، الحسابات منتظمة!'),
                    )
                  else
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _lateMembers.length,
                      itemBuilder: (context, index) {
                        final item = _lateMembers[index];
                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.red.shade50,
                              child: const Icon(Icons.person_outline, color: Colors.red),
                            ),
                            title: Text(item['member_name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text('${item['circle_name']} • دور ${item['month_index']} (${item['amount_paid']} $cur)'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (item['member_phone'] != null && item['member_phone'].toString().isNotEmpty)
                                  IconButton(icon: const Icon(Icons.phone, color: Colors.blue), onPressed: () => _callMember(item['member_phone'])),
                                IconButton(icon: const Icon(Icons.share, color: Colors.green), onPressed: () => _sendLateReminder(item)),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
    );
  }

  Widget _buildMetricCard(String title, String value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 8),
          Text(title, style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }
}
