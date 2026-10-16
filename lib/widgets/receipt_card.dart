import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class PaymentReceiptCard extends StatelessWidget {
  final GlobalKey boundaryKey;
  final String circleName;
  final String memberName;
  final double amount;
  final String paymentMethod;
  final String paymentDate;
  final int monthIndex;

  const PaymentReceiptCard({
    super.key,
    required this.boundaryKey,
    required this.circleName,
    required this.memberName,
    required this.amount,
    required this.paymentMethod,
    required this.paymentDate,
    required this.monthIndex,
  });

  String _getMethodText(String method) {
    switch (method) {
      case 'wallet':
        return 'محفظة إلكترونية';
      case 'bank':
        return 'تحويل إنستاباي / بنكي';
      case 'cash':
      default:
        return 'نقداً (كاش)';
    }
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      key: boundaryKey,
      child: Container(
        width: 320,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 15,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_rounded, color: Colors.green, size: 42),
            ),
            const SizedBox(height: 10),
            const Text(
              'إيصال سداد إلكتروني',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.black87),
            ),
            Text(circleName, style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 20),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Text(
                '${amount.toStringAsFixed(0)} ج.م',
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.black),
              ),
            ),
            const SizedBox(height: 16),
            Divider(color: Colors.grey.shade300, height: 1),
            const SizedBox(height: 12),
            _buildRow('المشترك:', memberName),
            _buildRow('الدور / القسط:', 'رقم $monthIndex'),
            _buildRow('طريقة التوريد:', _getMethodText(paymentMethod)),
            _buildRow('التوقيت:', paymentDate),
            _buildRow('الحالة:', 'تم السداد بنجاح', valColor: Colors.green.shade700),
            const SizedBox(height: 12),
            Divider(color: Colors.grey.shade300, height: 1),
            const SizedBox(height: 8),
            Text('معتمد عبر تطبيق إدارة الجمعيات الذكي', style: TextStyle(fontSize: 9, color: Colors.grey.shade500)),
          ],
        ),
      ),
    );
  }

  Widget _buildRow(String label, String val, {Color? valColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          Text(val, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: valColor ?? Colors.black87)),
        ],
      ),
    );
  }
}

class ReceiptHelper {
  static Future<void> shareReceipt(GlobalKey key, String name, String circle) async {
    try {
      final boundary = key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final pngBytes = byteData!.buffer.asUint8List();

      final tempDir = await getTemporaryDirectory();
      final filePath = '${tempDir.path}/receipt_${DateTime.now().millisecondsSinceEpoch}.png';
      final file = await File(filePath).writeAsBytes(pngBytes);

      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'إيصال سداد - جمعية $circle للمشترك $name',
      );
    } catch (_) {}
  }
}
