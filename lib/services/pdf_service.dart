import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';

class PdfService {
  static String _translateMethod(String? method) {
    switch (method) {
      case 'wallet':
        return 'محفظة إلكترونية';
      case 'bank':
        return 'إنستاباي / بنكي';
      case 'cash':
      default:
        return 'كاش';
    }
  }

  static Future<Uint8List> generateCircleReport({
    required String circleName,
    required String cycleType,
    required int currentCycleIndex,
    required double shareAmount,
    required String receiverName,
    required String payoutDate,
    required bool isReceived,
    required List<Map<String, dynamic>> payments,
  }) async {
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.cairoRegular();
    final fontBold = await PdfGoogleFonts.cairoBold();

    final paidCount = payments.where((p) => p['is_paid'] == 1).length;
    final totalMembers = payments.length;
    final totalCollected = paidCount * shareAmount;
    final totalExpected = totalMembers * shareAmount;

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        textDirection: pw.TextDirection.rtl,
        theme: pw.ThemeData.withFont(base: font, bold: fontBold),
        build: (context) {
          return pw.Padding(
            padding: const pw.EdgeInsets.all(16),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.teal800,
                    borderRadius: pw.BorderRadius.circular(8),
                  ),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'كشف حساب رسمي للجمعية',
                        style: pw.TextStyle(font: fontBold, fontSize: 18, color: PdfColors.white),
                      ),
                      pw.Text(
                        DateFormat('yyyy-MM-dd').format(DateTime.now()),
                        style: const pw.TextStyle(color: PdfColors.white, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 16),
                pw.Container(
                  padding: const pw.EdgeInsets.all(12),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.grey100,
                    border: pw.Border.all(color: PdfColors.grey300),
                    borderRadius: pw.BorderRadius.circular(6),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text('اسم الجمعية: $circleName', style: pw.TextStyle(font: fontBold, fontSize: 14)),
                          pw.Text('الدورة: $cycleType | الدور: $currentCycleIndex', style: pw.TextStyle(font: fontBold, fontSize: 13)),
                        ],
                      ),
                      pw.Divider(color: PdfColors.grey300),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text('المستحق للقبض: $receiverName', style: pw.TextStyle(font: fontBold, fontSize: 13, color: PdfColors.teal900)),
                          pw.Text('موعد الاستحقاق: $payoutDate'),
                          pw.Text(
                            'الحالة: ${isReceived ? "تم القبض" : "لم يقبض بعد"}',
                            style: pw.TextStyle(font: fontBold, color: isReceived ? PdfColors.green800 : PdfColors.red800),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 16),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                  children: [
                    _buildBox('المحصل', '${totalCollected.toStringAsFixed(0)}', fontBold, PdfColors.green700),
                    _buildBox('المطلوب', '${totalExpected.toStringAsFixed(0)}', fontBold, PdfColors.blueGrey800),
                    _buildBox('نسبة التحصيل', '${((paidCount / (totalMembers == 0 ? 1 : totalMembers)) * 100).toStringAsFixed(0)}%', fontBold, PdfColors.teal700),
                    _buildBox('المسددين', '$paidCount من $totalMembers', fontBold, PdfColors.orange800),
                  ],
                ),
                pw.SizedBox(height: 20),
                pw.Text('تفاصيل سداد الأعضاء ووسائل التوريد:', style: pw.TextStyle(font: fontBold, fontSize: 14)),
                pw.SizedBox(height: 8),
                pw.TableHelper.fromTextArray(
                  border: pw.TableBorder.all(color: PdfColors.grey300),
                  headerStyle: pw.TextStyle(font: fontBold, color: PdfColors.white, fontSize: 11),
                  headerDecoration: const pw.BoxDecoration(color: PdfColors.teal700),
                  cellHeight: 26,
                  cellAlignments: {
                    0: pw.Alignment.centerRight,
                    1: pw.Alignment.center,
                    2: pw.Alignment.center,
                    3: pw.Alignment.center,
                    4: pw.Alignment.center,
                  },
                  headers: ['اسم العضو', 'المبلغ', 'حالة السداد', 'طريقة الدفع', 'تاريخ وتوقيت الدفع'],
                  data: payments.map((item) {
                    final isPaid = item['is_paid'] == 1;
                    return [
                      item['member_name'] ?? '',
                      '${shareAmount.toStringAsFixed(0)}',
                      isPaid ? 'تم السداد' : 'معلّق',
                      isPaid ? _translateMethod(item['payment_method']) : '-',
                      item['payment_date'] ?? '-',
                    ];
                  }).toList(),
                ),
                pw.Spacer(),
                pw.Divider(color: PdfColors.grey400),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('تم إنشاء هذا التقرير تلقائياً عبر تطبيق إدارة الجمعيات', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
                    pw.Text('توقيع المسؤول: ...........................', style: pw.TextStyle(font: fontBold, fontSize: 10)),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );

    return pdf.save();
  }

  static pw.Widget _buildBox(String title, String value, pw.Font fontBold, PdfColor color) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: color),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Column(
        children: [
          pw.Text(title, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
          pw.SizedBox(height: 4),
          pw.Text(value, style: pw.TextStyle(font: fontBold, fontSize: 13, color: color)),
        ],
      ),
    );
  }

  static Future<void> sharePdfReport({
    required String circleName,
    required int cycleIndex,
    required Uint8List pdfBytes,
  }) async {
    await Printing.sharePdf(
      bytes: pdfBytes,
      filename: 'تقرير_جمعية_${circleName}_الدور_$cycleIndex.pdf',
    );
  }
}
