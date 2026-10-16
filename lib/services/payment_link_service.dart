import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'settings_controller.dart';

class PaymentLinkService {
  static String generateInstaPayLink({
    required String instapayAddress,
    required double amount,
  }) {
    return 'https://ipn.eg/p/$instapayAddress?amount=${amount.toStringAsFixed(0)}';
  }

  static Future<void> sendPaymentReminder({
    required String memberPhone,
    required String memberName,
    required String circleName,
    required double amount,
    required int turnIndex,
  }) async {
    final currency = SettingsController.currencyNotifier.value;
    final ipa = SettingsController.adminInstapayAddress;
    final wallet = SettingsController.adminWalletNumber;
    final link = generateInstaPayLink(instapayAddress: ipa, amount: amount);

    final msg = '''
السلام عليكم أ/ $memberName،
نذكركم بسداد قسط جمعية: "$circleName" (دور رقم $turnIndex).
المبلغ المطلوب: ${amount.toStringAsFixed(0)} $currency

طرق السداد الفوري:
1. رابط InstaPay مباشر:
$link

2. محفظة إلكترونية (فودافون كاش / إنستاباي):
$wallet

شكراً لالتزامك وتواصلك.
''';

    final cleanPhone = memberPhone.replaceAll(RegExp(r'\D'), '');
    final uri = Uri.parse('whatsapp://send?phone=$cleanPhone&text=${Uri.encodeComponent(msg)}');

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      await Share.share(msg);
    }
  }
}
