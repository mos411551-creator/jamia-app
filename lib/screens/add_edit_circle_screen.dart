import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../database/db_helper.dart';
import '../services/notification_service.dart';

class MemberInput {
  String name;
  String phone;
  double shares;

  MemberInput({required this.name, this.phone = '', this.shares = 1.0});
}

class AddEditCircleScreen extends StatefulWidget {
  final Map<String, dynamic>? existingCircle;
  const AddEditCircleScreen({super.key, this.existingCircle});

  @override
  State<AddEditCircleScreen> createState() => _AddEditCircleScreenState();
}

class _AddEditCircleScreenState extends State<AddEditCircleScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _shareAmountController;

  String _cycleType = 'monthly';
  String _paymentMethod = 'cash';
  DateTime _startDate = DateTime.now();

  final List<MemberInput> _members = [];
  final _memberNameController = TextEditingController();
  final _memberPhoneController = TextEditingController();

  bool get isEditing => widget.existingCircle != null;

  @override
  void initState() {
    super.initState();
    final item = widget.existingCircle;
    _nameController = TextEditingController(text: item != null ? item['name'] : '');
    _shareAmountController = TextEditingController(
      text: item != null ? item['share_amount'].toString() : '',
    );
    if (item != null) {
      _cycleType = item['cycle_type'] ?? 'monthly';
      _paymentMethod = item['payment_method'] ?? 'cash';
      _startDate = DateTime.tryParse(item['start_date']) ?? DateTime.now();
    }
  }

  void _addMember() {
    if (_memberNameController.text.trim().isEmpty) return;
    setState(() {
      _members.add(
        MemberInput(
          name: _memberNameController.text.trim(),
          phone: _memberPhoneController.text.trim(),
        ),
      );
      _memberNameController.clear();
      _memberPhoneController.clear();
    });
  }

  DateTime _calculateDate(DateTime start, int index, String cycle) {
    switch (cycle) {
      case 'daily':
        return start.add(Duration(days: index));
      case 'weekly':
        return start.add(Duration(days: index * 7));
      case 'monthly':
      default:
        return DateTime(start.year, start.month + index, start.day);
    }
  }

  Future<void> _saveCircle() async {
    if (!_formKey.currentState!.validate()) return;
    if (!isEditing && _members.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('برجاء إضافة الأعضاء المشتركين')),
      );
      return;
    }

    final db = await DBHelper.instance.database;
    final shareAmount = double.parse(_shareAmountController.text);

    if (isEditing) {
      final circleId = widget.existingCircle!['id'];
      await db.update(
        'circles',
        {
          'name': _nameController.text.trim(),
          'share_amount': shareAmount,
          'cycle_type': _cycleType,
          'payment_method': _paymentMethod,
          'start_date': DateFormat('yyyy-MM-dd').format(_startDate),
        },
        where: 'id = ?',
        whereArgs: [circleId],
      );
    } else {
      final totalMonths = _members.length;
      await db.transaction((txn) async {
        final circleId = await txn.insert('circles', {
          'name': _nameController.text.trim(),
          'share_amount': shareAmount,
          'total_months': totalMonths,
          'start_date': DateFormat('yyyy-MM-dd').format(_startDate),
          'cycle_type': _cycleType,
          'payment_method': _paymentMethod,
          'status': 'active',
        });

        List<int> memberIds = [];
        for (var m in _members) {
          final mId = await txn.insert('members', {
            'circle_id': circleId,
            'name': m.name,
            'phone': m.phone,
            'shares_count': m.shares,
          });
          memberIds.add(mId);
        }

        for (int i = 0; i < memberIds.length; i++) {
          final payoutDate = _calculateDate(_startDate, i, _cycleType);
          final payoutId = await txn.insert('payouts', {
            'circle_id': circleId,
            'member_id': memberIds[i],
            'month_index': i + 1,
            'payout_date': DateFormat('yyyy-MM-dd').format(payoutDate),
            'is_received': 0,
          });

          NotificationService().scheduleCircleReminder(
            notificationId: payoutId,
            circleName: _nameController.text.trim(),
            receiverName: _members[i].name,
            dueDate: payoutDate,
          );
        }

        for (int month = 1; month <= totalMonths; month++) {
          for (int memberId in memberIds) {
            await txn.insert('payments', {
              'circle_id': circleId,
              'member_id': memberId,
              'month_index': month,
              'amount_paid': shareAmount,
              'is_paid': 0,
              'payment_method': _paymentMethod,
              'payment_date': null,
            });
          }
        }
      });
    }

    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'تعديل الجمعية' : 'إنشاء جمعية جديدة'),
        centerTitle: true,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'اسم الجمعية',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.group_work_outlined),
              ),
              validator: (v) => v!.isEmpty ? 'مطلوب' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _shareAmountController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'قيمة السهم الواحد (ج.م)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.attach_money),
              ),
              validator: (v) => v!.isEmpty ? 'مطلوب' : null,
            ),
            const SizedBox(height: 14),
            const Text('دورية الجمعية:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'daily', label: Text('يومية')),
                ButtonSegment(value: 'weekly', label: Text('أسبوعية')),
                ButtonSegment(value: 'monthly', label: Text('شهرية')),
              ],
              selected: {_cycleType},
              onSelectionChanged: (val) => setState(() => _cycleType = val.first),
            ),
            const SizedBox(height: 14),
            ListTile(
              shape: RoundedRectangleBorder(
                side: BorderSide(color: Colors.grey.shade400),
                borderRadius: BorderRadius.circular(6),
              ),
              leading: const Icon(Icons.event),
              title: const Text('تاريخ أول قسط'),
              trailing: Text(
                DateFormat('yyyy-MM-dd').format(_startDate),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _startDate,
                  firstDate: DateTime(2024),
                  lastDate: DateTime(2035),
                );
                if (picked != null) setState(() => _startDate = picked);
              },
            ),
            const SizedBox(height: 18),

            if (!isEditing) ...[
              const Text('إضافة المشتركين وترتيب الأدوار:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: _memberNameController,
                      decoration: const InputDecoration(hintText: 'اسم المشترك', isDense: true, border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _memberPhoneController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(hintText: 'الهاتف', isDense: true, border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(onPressed: _addMember, icon: const Icon(Icons.add)),
                ],
              ),
              const SizedBox(height: 12),
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _members.length,
                onReorder: (oldIdx, newIdx) {
                  setState(() {
                    if (newIdx > oldIdx) newIdx -= 1;
                    final item = _members.removeAt(oldIdx);
                    _members.insert(newIdx, item);
                  });
                },
                itemBuilder: (context, index) {
                  final member = _members[index];
                  final pDate = _calculateDate(_startDate, index, _cycleType);
                  return Card(
                    key: ValueKey(member),
                    child: ListTile(
                      leading: CircleAvatar(child: Text('${index + 1}')),
                      title: Text(member.name),
                      subtitle: Text('قبض: ${DateFormat('yyyy-MM-dd').format(pDate)}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => setState(() => _members.removeAt(index)),
                          ),
                          const Icon(Icons.drag_handle),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],

            const SizedBox(height: 24),
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
              onPressed: _saveCircle,
              icon: const Icon(Icons.check_circle_outline),
              label: Text(isEditing ? 'حفظ التعديلات' : 'حفظ وبدء الجمعية'),
            ),
          ],
        ),
      ),
    );
  }
}
