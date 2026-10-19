import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../database/db_helper.dart';

class MemberInput {
  String name;
  String phone;
  int turnIndex;
  double memberPayment;

  MemberInput({
    required this.name,
    this.phone = '',
    required this.turnIndex,
    required this.memberPayment,
  });
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
  late TextEditingController _totalCyclesController;

  String _cycleType = 'daily';
  DateTime _startDate = DateTime.now();
  late DateTime _endDate;

  final List<MemberInput> _members = [];
  final _memberNameController = TextEditingController();
  final _memberPhoneController = TextEditingController();
  final _memberTurnController = TextEditingController(text: '1');
  final _memberAmountController = TextEditingController(text: '100');

  bool get isEditing => widget.existingCircle != null;

  @override
  void initState() {
    super.initState();
    final item = widget.existingCircle;
    _nameController = TextEditingController(text: item != null ? item['name'] : '');
    _shareAmountController = TextEditingController(
      text: item != null ? item['share_amount'].toString() : '100',
    );
    _totalCyclesController = TextEditingController(
      text: item != null ? item['total_months'].toString() : '100',
    );

    if (item != null) {
      _cycleType = item['cycle_type'] ?? 'daily';
      _startDate = DateTime.tryParse(item['start_date'] ?? '') ?? DateTime.now();
      _endDate = DateTime.tryParse(item['end_date'] ?? '') ?? _calcEndDate(_startDate, int.tryParse(_totalCyclesController.text) ?? 100, _cycleType);
    } else {
      _endDate = _calcEndDate(_startDate, 100, _cycleType);
    }
  }

  DateTime _calcEndDate(DateTime start, int count, String cycle) {
    final steps = count > 0 ? count - 1 : 0;
    switch (cycle) {
      case 'daily':
        return start.add(Duration(days: steps));
      case 'yearly':
        return DateTime(start.year + steps, start.month, start.day);
      case 'monthly':
      default:
        return DateTime(start.year, start.month + steps, start.day);
    }
  }

  void _addMember() {
    if (_memberNameController.text.trim().isEmpty) return;

    final double memAmount = double.tryParse(_memberAmountController.text) ?? 100.0;
    final int turn = int.tryParse(_memberTurnController.text) ?? 1;

    setState(() {
      _members.add(MemberInput(
        name: _memberNameController.text.trim(),
        phone: _memberPhoneController.text.trim(),
        turnIndex: turn,
        memberPayment: memAmount,
      ));

      _memberNameController.clear();
      _memberPhoneController.clear();
      _memberTurnController.text = (turn + 1).toString();
      _memberAmountController.text = _shareAmountController.text;
    });
  }

  Future<void> _saveCircle() async {
    if (!_formKey.currentState!.validate()) return;
    if (!isEditing && _members.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('برجاء إضافة المشتركين أولاً')),
      );
      return;
    }

    final db = await DBHelper.instance.database;
    final double fullShareAmount = double.parse(_shareAmountController.text);
    final int totalCycles = int.parse(_totalCyclesController.text);
    final startDateStr = DateFormat('yyyy-MM-dd').format(_startDate);
    final endDateStr = DateFormat('yyyy-MM-dd').format(_endDate);

    if (isEditing) {
      await DBHelper.instance.updateCircleDetails(
        circleId: widget.existingCircle!['id'],
        name: _nameController.text.trim(),
        shareAmount: fullShareAmount,
        cycleType: _cycleType,
        startDate: startDateStr,
        endDate: endDateStr,
      );
    } else {
      await db.transaction((txn) async {
        final circleId = await txn.insert('circles', {
          'name': _nameController.text.trim(),
          'share_amount': fullShareAmount,
          'total_months': totalCycles,
          'start_date': startDateStr,
          'end_date': endDateStr,
          'cycle_type': _cycleType,
          'status': 'active',
        });

        final double totalCirclePot = fullShareAmount * totalCycles;

        for (var m in _members) {
          final double fraction = m.memberPayment / (fullShareAmount == 0 ? 1 : fullShareAmount);
          final double memberPayout = totalCirclePot * fraction;

          final memberId = await txn.insert('members', {
            'circle_id': circleId,
            'name': m.name,
            'phone': m.phone,
            'shares_count': fraction,
            'turn_index': m.turnIndex,
          });

          final payoutDate = _calcEndDate(_startDate, m.turnIndex, _cycleType);

          await txn.insert('payouts', {
            'circle_id': circleId,
            'member_id': memberId,
            'month_index': m.turnIndex,
            'expected_amount': memberPayout,
            'payout_date': DateFormat('yyyy-MM-dd').format(payoutDate),
            'is_received': 0,
          });

          for (int cycle = 1; cycle <= totalCycles; cycle++) {
            await txn.insert('payments', {
              'circle_id': circleId,
              'member_id': memberId,
              'month_index': cycle,
              'amount_paid': m.memberPayment,
              'is_paid': 0,
            });
          }
        }
      });
    }

    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final double fullShare = double.tryParse(_shareAmountController.text) ?? 100.0;
    final int cycles = int.tryParse(_totalCyclesController.text) ?? 100;
    final double totalPot = fullShare * cycles;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'تعديل الجمعية' : 'إنشاء جمعية بأسهم مرنة'),
        centerTitle: true,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'اسم الجمعية', border: OutlineInputBorder()),
              validator: (v) => v!.isEmpty ? 'مطلوب' : null,
            ),
            const SizedBox(height: 14),

            const Text('دورية الجمعية:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'daily', label: Text('يومية')),
                ButtonSegment(value: 'monthly', label: Text('شهرية')),
                ButtonSegment(value: 'yearly', label: Text('سنوية')),
              ],
              selected: {_cycleType},
              onSelectionChanged: (val) {
                setState(() {
                  _cycleType = val.first;
                  _endDate = _calcEndDate(_startDate, int.tryParse(_totalCyclesController.text) ?? 100, _cycleType);
                });
              },
            ),
            const SizedBox(height: 14),

            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _shareAmountController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'قسط السهم الكامل (ج.م)',
                      hintText: '100',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) {
                      _memberAmountController.text = v;
                      setState(() {});
                    },
                    validator: (v) => v!.isEmpty ? 'مطلوب' : null,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: _totalCyclesController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'المدة (عدد الأدوار/الأيام)',
                      hintText: '100',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) {
                      final c = int.tryParse(v) ?? 1;
                      setState(() => _endDate = _calcEndDate(_startDate, c, _cycleType));
                    },
                    validator: (v) => v!.isEmpty ? 'مطلوب' : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.teal.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.teal.shade200),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('مبلغ السهم الكامل عند القبض:', style: TextStyle(fontWeight: FontWeight.bold)),
                  Text(
                    '${totalPot.toStringAsFixed(0)} ج.م',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.teal),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            Row(
              children: [
                Expanded(
                  child: ListTile(
                    shape: RoundedRectangleBorder(
                      side: BorderSide(color: Colors.grey.shade400),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    title: const Text('البداية', style: TextStyle(fontSize: 12)),
                    subtitle: Text(DateFormat('yyyy-MM-dd').format(_startDate)),
                    onTap: () async {
                      final p = await showDatePicker(
                        context: context,
                        initialDate: _startDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2045),
                      );
                      if (p != null) {
                        setState(() {
                          _startDate = p;
                          _endDate = _calcEndDate(_startDate, int.tryParse(_totalCyclesController.text) ?? 100, _cycleType);
                        });
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ListTile(
                    shape: RoundedRectangleBorder(
                      side: BorderSide(color: Colors.grey.shade400),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    title: const Text('النهاية', style: TextStyle(fontSize: 12)),
                    subtitle: Text(DateFormat('yyyy-MM-dd').format(_endDate)),
                    onTap: () async {
                      final p = await showDatePicker(
                        context: context,
                        initialDate: _endDate,
                        firstDate: _startDate,
                        lastDate: DateTime(2045),
                      );
                      if (p != null) setState(() => _endDate = p);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            if (!isEditing) ...[
              const Text(
                'إضافة المشتركين (وتوزيع الأسهم المشتركة):',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              const SizedBox(height: 4),
              Text(
                'ملاحظة: لدمج عدة أعضاء في سهم واحد، اجعل رقم الدور متطابقاً لكل منهم.',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
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
                  const SizedBox(width: 6),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _memberPhoneController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(hintText: 'الهاتف', isDense: true, border: OutlineInputBorder()),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _memberTurnController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'رقم الدور/السهم', isDense: true, border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _memberAmountController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'يدفع (ج.م)', isDense: true, border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _addMember,
                    icon: const Icon(Icons.person_add),
                    tooltip: 'إضافة المشترك',
                  ),
                ],
              ),
              const SizedBox(height: 12),

              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _members.length,
                itemBuilder: (context, index) {
                  final member = _members[index];
                  final fraction = member.memberPayment / (fullShare == 0 ? 1 : fullShare);
                  final payoutVal = totalPot * fraction;
                  final pDate = _calcEndDate(_startDate, member.turnIndex, _cycleType);

                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.teal.shade100,
                        child: Text('${member.turnIndex}'),
                      ),
                      title: Text(member.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(
                        'يدفع: ${member.memberPayment.toStringAsFixed(0)} ج.م • يستلم: ${payoutVal.toStringAsFixed(0)} ج.م\nتاريخ القبض: ${DateFormat('yyyy-MM-dd').format(pDate)}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => setState(() => _members.removeAt(index)),
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
              label: Text(isEditing ? 'حفظ التعديلات' : 'بدء الجمعية بالأسهم المحددة'),
            ),
          ],
        ),
      ),
    );
  }
}
